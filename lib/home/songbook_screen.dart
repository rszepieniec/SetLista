import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../import/add_songs.dart';
import '../song.dart';
import '../song_list_screen.dart';
import '../song_screen.dart';
import '../widgets.dart';
import 'all_songs.dart';

/// "Mój śpiewnik": moje piosenki i piosenki ze wszystkich moich zespołów,
/// bez powtórek. Filtry u góry zawężają do jednego źródła.
class SongbookScreen extends StatefulWidget {
  const SongbookScreen({super.key, required this.repository});

  final Repository repository;

  @override
  State<SongbookScreen> createState() => _SongbookScreenState();
}

/// null = wszystkie piosenki, personalId = tylko moje, inne id = zespół.
typedef _Filter = String?;

class _SongbookScreenState extends State<SongbookScreen> {
  late final _all = AllSongs(widget.repository);
  final _scrollController = ScrollController();
  _Filter _filter;
  String _query = '';

  Repository get _repo => widget.repository;

  @override
  void dispose() {
    _all.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<SongEntry> _visible() {
    final List<SongEntry> source;
    if (_filter == null) {
      source = _all.entries;
    } else if (_filter == _all.personalId) {
      source = [
        for (final e in _all.entries)
          if (e.teamId == _all.personalId) e,
      ];
    } else {
      // Zespół: jego własne piosenki (to one się otworzą i będą edytowane).
      source = [
        for (final s in _all.songsOf(_filter!))
          SongEntry(song: s, teamId: _filter!, teamIds: [_filter!]),
      ];
    }
    final q = foldPolish(_query.trim());
    if (q.isEmpty) return source;
    return [
      for (final e in source)
        if (e.song.searchKey.contains(q)) e,
    ];
  }

  void _add() {
    final personal = _repo.team(_all.personalId);
    if (personal == null) return;
    showAddSongsSheet(
      context,
      repository: _repo,
      team: personal,
      currentSongs: _all.personalSongs,
    );
  }

  void _open(List<SongEntry> entries, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongScreen(
          repository: _repo,
          songs: [
            for (final e in entries) (teamId: e.teamId, songId: e.song.id),
          ],
          initialIndex: index,
        ),
      ),
    );
  }

  List<Widget> _labels(SongEntry entry) {
    if (entry.teamIds.isEmpty) return const [];
    return [
      if (entry.teamId == _all.personalId)
        const SourceChip(label: 'Moje', personal: true),
      for (final id in entry.teamIds)
        if (_all.team(id) case final team?) SourceChip(label: team.name),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _all,
      builder: (context, _) {
        final teams = [
          for (final t in _repo.teams.value)
            if (!t.personal) t,
        ];
        final entries = _visible();
        return Scaffold(
          appBar: AppBar(title: const Text('Mój śpiewnik')),
          floatingActionButton: _all.entries.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _add,
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj'),
                )
              : null,
          body: !_all.loaded
              ? const Center(child: CircularProgressIndicator())
              : _all.entries.isEmpty
              ? InfoState(
                  icon: Icons.library_music_outlined,
                  title: 'Twój śpiewnik jest pusty',
                  text:
                      'Wpisz piosenkę albo zaimportuj wiele naraz z plików '
                      '(telefon, Dysk Google, .zip, jWorship). Piosenki '
                      'z Twoich zespołów też pojawią się tutaj.',
                  action: FilledButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add),
                    label: const Text('Dodaj piosenki'),
                  ),
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: SearchBar(
                        hintText: 'Szukaj tytułu lub tekstu',
                        leading: const Icon(Icons.search),
                        elevation: const WidgetStatePropertyAll(0),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    if (teams.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            for (final (id, label, icon) in [
                              (null, 'Wszystkie', Icons.library_music_outlined),
                              (_all.personalId, 'Moje', Icons.person_outline),
                              for (final t in teams)
                                (t.id, t.name, Icons.groups_outlined),
                            ])
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  avatar: Icon(icon, size: 18),
                                  label: Text(label),
                                  selected: _filter == id,
                                  showCheckmark: false,
                                  onSelected: (_) =>
                                      setState(() => _filter = id),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          songsCount(entries.length),
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: entries.isEmpty
                          ? const InfoState(
                              icon: Icons.search_off,
                              title: 'Nic nie znaleziono',
                              text: 'Spróbuj innego słowa albo filtra.',
                            )
                          : Scrollbar(
                              controller: _scrollController,
                              interactive: true,
                              child: ListView.builder(
                                controller: _scrollController,
                                keyboardDismissBehavior:
                                    ScrollViewKeyboardDismissBehavior.onDrag,
                                padding: const EdgeInsets.only(bottom: 88),
                                itemCount: entries.length,
                                itemBuilder: (context, i) => SongTile(
                                  song: entries[i].song,
                                  labels: _filter == null
                                      ? _labels(entries[i])
                                      : const [],
                                  onTap: () => _open(entries, i),
                                ),
                              ),
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
