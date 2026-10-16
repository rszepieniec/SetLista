import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../messages.dart';
import '../models.dart';
import '../song.dart';
import '../song_list_screen.dart';
import '../song_picker_screen.dart';
import '../song_screen.dart';
import '../widgets.dart';
import 'setlist_dialog.dart';

/// Setlista: kolejność ustawia się przeciąganiem, usuwa przesunięciem w lewo.
class SetlistScreen extends StatefulWidget {
  const SetlistScreen({
    super.key,
    required this.repository,
    required this.teamId,
    required this.setlistId,
  });

  final Repository repository;
  final String teamId;
  final String setlistId;

  @override
  State<SetlistScreen> createState() => _SetlistScreenState();
}

class _SetlistScreenState extends State<SetlistScreen> {
  late final _setlist = widget.repository.playlist(
    widget.teamId,
    widget.setlistId,
  );
  late final _songs = widget.repository.songs(widget.teamId);

  Repository get _repo => widget.repository;
  bool get _canEdit => _repo.canEdit(widget.teamId);
  bool get _isPersonal => widget.teamId == Repository.personalTeamId(_repo.uid);

  void _setSongs(List<String> songIds) {
    _repo
        .updatePlaylist(widget.teamId, widget.setlistId, songIds: songIds)
        .catchError((Object e) => showMessage('Nie udało się zapisać: $e'));
  }

  /// Do setlisty można wybierać piosenki ze wszystkich moich śpiewników.
  /// Te spoza śpiewnika setlisty są najpierw do niego kopiowane (bez duplikatów).
  Future<void> _addSongs(Playlist setlist, List<Song> ownSongs) async {
    final inSetlist = setlist.songIds.toSet();
    final known = {for (final s in ownSongs) Repository.titleKey(s.title)};
    final personalId = Repository.personalTeamId(_repo.uid);
    // Mój śpiewnik najpierw, potem zespoły alfabetycznie.
    final others = [
      for (final t in _repo.teams.value)
        if (t.id != widget.teamId) t,
    ]..sort((a, b) => a.personal == b.personal ? 0 : (a.personal ? -1 : 1));

    final otherSections = <({String teamId, String name, List<Song> songs})>[];
    for (final team in others) {
      final songs = [
        for (final s in await _repo.songs(team.id).first)
          if (known.add(Repository.titleKey(s.title))) s,
      ];
      if (songs.isNotEmpty) {
        otherSections.add((teamId: team.id, name: team.name, songs: songs));
      }
    }
    if (!mounted) return;
    final ownName = _repo.team(widget.teamId)?.name ?? 'Mój śpiewnik';
    final target = _isPersonal ? 'Mojego śpiewnika' : 'śpiewnika „$ownName”';

    final picked = await Navigator.of(context).push<List<Song>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SongPickerScreen(
          title: 'Dodaj do setlisty',
          sections: [
            PickerSection(
              title: _isPersonal ? 'Mój śpiewnik' : 'Śpiewnik „$ownName”',
              icon: _isPersonal ? Icons.person_outline : Icons.groups_outlined,
              items: [
                for (final song in ownSongs)
                  inSetlist.contains(song.id)
                      ? PickerItem(song, locked: true, note: 'Już na setliście')
                      : PickerItem(song),
              ],
            ),
            for (final other in otherSections)
              PickerSection(
                title: other.teamId == personalId
                    ? 'Mój śpiewnik'
                    : 'Zespół „${other.name}”',
                subtitle: 'Zaznaczone zostaną najpierw dodane do $target',
                icon: other.teamId == personalId
                    ? Icons.person_outline
                    : Icons.groups_outlined,
                items: [
                  for (final song in other.songs)
                    PickerItem(song, note: 'Doda się do $target'),
                ],
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked.isEmpty) return;

    final ownIds = {for (final s in ownSongs) s.id};
    final foreign = [
      for (final s in picked)
        if (!ownIds.contains(s.id)) s,
    ];
    try {
      final copied = foreign.isEmpty
          ? const <String, String>{}
          : await _repo.copySongsToTeam(foreign, widget.teamId);
      _setSongs([
        ...setlist.songIds,
        for (final s in picked) copied[s.id] ?? s.id,
      ]);
      if (foreign.isNotEmpty) {
        showMessage(
          'Dodano ${songsCount(foreign.length)} do $target i do setlisty',
        );
      }
    } catch (e) {
      showMessage('Nie udało się dodać: $e');
    }
  }

  Future<void> _saveToMine(
    Playlist setlist,
    Map<String, Song> songsById,
  ) async {
    final personal = _repo.team(Repository.personalTeamId(_repo.uid));
    if (personal == null) return;
    try {
      await _repo.sharePlaylist(setlist, songsById, personal);
      showMessage('Zapisano kopię w Moich setlistach');
    } catch (e) {
      showMessage('Nie udało się zapisać: $e');
    }
  }

  void _remove(Playlist setlist, int index, String title) {
    final before = setlist.songIds;
    _setSongs([...before]..removeAt(index));
    showMessage(
      'Usunięto „$title” z setlisty',
      actionLabel: 'Cofnij',
      onAction: () => _setSongs(before),
    );
  }

  Future<void> _edit(Playlist setlist) async {
    final details = await showSetlistDialog(
      context,
      title: 'Edytuj setlistę',
      confirmLabel: 'Zapisz',
      initialName: setlist.name,
      initialDate: setlist.date,
    );
    if (details == null) return;
    _repo
        .updatePlaylist(
          widget.teamId,
          widget.setlistId,
          name: details.name,
          date: details.date,
          clearDate: details.date == null,
        )
        .catchError((Object e) => showMessage('Nie udało się zapisać: $e'));
  }

  Future<void> _delete(Playlist setlist) async {
    final ok = await confirm(
      context,
      title: 'Usunąć setlistę?',
      message: '„${setlist.name}” zniknie. Piosenki zostaną w śpiewniku.',
      confirmLabel: 'Usuń',
      destructive: true,
    );
    if (!ok || !mounted) return;
    _repo
        .deletePlaylist(widget.teamId, widget.setlistId)
        .catchError((Object e) => showMessage('Nie udało się usunąć: $e'));
    Navigator.of(context).pop();
  }

  Future<void> _share(Playlist setlist, Map<String, Song> songsById) async {
    final targets = [
      for (final t in _repo.teams.value)
        if (t.id != widget.teamId && t.canEdit(_repo.uid)) t,
    ];
    if (targets.isEmpty) {
      showMessage(
        'Nie należysz do żadnego zespołu, w którym możesz dodawać setlisty. '
        'Utwórz zespół albo dołącz do niego na ekranie startowym.',
      );
      return;
    }
    final target = await pickTeam(
      context,
      title: 'Udostępnij „${setlist.name}” w…',
      teams: targets,
    );
    if (target == null) return;
    try {
      final copied = await _repo.sharePlaylist(setlist, songsById, target);
      showMessage(
        'Udostępniono w „${target.name}”'
        '${copied > 0 ? ' (skopiowano ${songsCount(copied)})' : ''}',
      );
    } catch (e) {
      showMessage('Nie udało się udostępnić: $e');
    }
  }

  void _open(List<String> existingIds, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongScreen.team(
          repository: _repo,
          teamId: widget.teamId,
          songIds: existingIds,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Playlist?>(
      stream: _setlist,
      builder: (context, setlistSnapshot) {
        return StreamBuilder<List<Song>>(
          stream: _songs,
          builder: (context, songsSnapshot) {
            final setlist = setlistSnapshot.data;
            final songs = songsSnapshot.data;
            if (setlistSnapshot.hasError || songsSnapshot.hasError) {
              return Scaffold(
                appBar: AppBar(),
                body: InfoState(
                  icon: Icons.cloud_off_outlined,
                  error: true,
                  title: 'Nie udało się wczytać setlisty',
                  text: 'Sprawdź połączenie z internetem.',
                  details: '${setlistSnapshot.error ?? songsSnapshot.error}',
                ),
              );
            }
            if (setlistSnapshot.connectionState == ConnectionState.waiting ||
                songs == null) {
              return Scaffold(
                appBar: AppBar(),
                body: const Center(child: CircularProgressIndicator()),
              );
            }
            if (setlist == null) {
              return Scaffold(
                appBar: AppBar(),
                body: const InfoState(
                  icon: Icons.playlist_remove,
                  title: 'Setlista została usunięta',
                  text: 'Ktoś usunął tę setlistę.',
                ),
              );
            }
            return _buildSetlist(setlist, songs);
          },
        );
      },
    );
  }

  Widget _buildSetlist(Playlist setlist, List<Song> songs) {
    final songsById = {for (final s in songs) s.id: s};
    // Piosenki usunięte ze śpiewnika pomijamy przy przewijaniu tekstów.
    final existingIds = [
      for (final id in setlist.songIds)
        if (songsById.containsKey(id)) id,
    ];
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(setlist.name),
            Text(
              [
                if (setlist.date != null) formatDate(context, setlist.date!),
                songsCount(setlist.songIds.length),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          if (_isPersonal && setlist.songIds.isNotEmpty)
            IconButton(
              tooltip: 'Udostępnij w zespole',
              icon: const Icon(Icons.group_add_outlined),
              onPressed: () => _share(setlist, songsById),
            ),
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              if (!_isPersonal)
                PopupMenuItem(
                  onTap: () => _saveToMine(setlist, songsById),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.bookmark_add_outlined),
                    title: Text('Zapisz w Moich setlistach'),
                  ),
                ),
              if (_canEdit) ...[
                PopupMenuItem(
                  onTap: () => _edit(setlist),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Zmień nazwę i datę'),
                  ),
                ),
                PopupMenuItem(
                  onTap: () => _delete(setlist),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('Usuń setlistę'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      floatingActionButton: _canEdit && setlist.songIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _addSongs(setlist, songs),
              icon: const Icon(Icons.add),
              label: const Text('Dodaj piosenki'),
            )
          : null,
      body: setlist.songIds.isEmpty
          ? InfoState(
              icon: Icons.queue_music,
              title: 'Pusta setlista',
              text: _isPersonal
                  ? 'Dodaj piosenki z Mojego śpiewnika i ułóż je w kolejności.'
                  : 'Dodaj piosenki ze śpiewnika zespołu albo z Mojego '
                        'śpiewnika i ułóż je w kolejności.',
              action: _canEdit
                  ? FilledButton.icon(
                      onPressed: () => _addSongs(setlist, songs),
                      icon: const Icon(Icons.add),
                      label: const Text('Dodaj piosenki'),
                    )
                  : null,
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: EdgeInsets.only(
                top: 8,
                bottom: MediaQuery.paddingOf(context).bottom + 88,
              ),
              itemCount: setlist.songIds.length,
              // onReorderItem dostaje już poprawiony indeks docelowy.
              onReorderItem: (from, to) {
                final ids = [...setlist.songIds];
                ids.insert(to, ids.removeAt(from));
                _setSongs(ids);
              },
              itemBuilder: (context, i) {
                final id = setlist.songIds[i];
                final song = songsById[id];
                final number = CircleAvatar(
                  backgroundColor: colors.secondaryContainer,
                  foregroundColor: colors.onSecondaryContainer,
                  child: Text('${i + 1}'),
                );
                final handle = _canEdit
                    ? ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      )
                    : null;
                final tile = song == null
                    ? ListTile(
                        leading: number,
                        title: Text(
                          'Piosenka usunięta ze śpiewnika',
                          style: TextStyle(color: colors.outline),
                        ),
                        trailing: handle,
                      )
                    : SongTile(
                        song: song,
                        leading: number,
                        trailing: handle,
                        onTap: () =>
                            _open(existingIds, existingIds.indexOf(id)),
                      );
                if (!_canEdit) {
                  return KeyedSubtree(key: ValueKey(id), child: tile);
                }
                return Dismissible(
                  key: ValueKey(id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: colors.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: Icon(
                      Icons.playlist_remove,
                      color: colors.onErrorContainer,
                    ),
                  ),
                  onDismissed: (_) =>
                      _remove(setlist, i, song?.title ?? 'piosenkę'),
                  child: tile,
                );
              },
            ),
    );
  }
}
