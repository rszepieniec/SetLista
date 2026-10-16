import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'data/repository.dart';
import 'import/add_songs.dart';
import 'models.dart';
import 'song.dart';
import 'song_screen.dart';
import 'widgets.dart';

/// Zakładka "Piosenki" na ekranie głównym: lista z wyszukiwarką.
class SongListScreen extends StatefulWidget {
  const SongListScreen({
    super.key,
    required this.repository,
    required this.team,
  });

  final Repository repository;
  final Team team;

  @override
  State<SongListScreen> createState() => _SongListScreenState();
}

class _SongListScreenState extends State<SongListScreen> {
  late Stream<List<Song>> _songs = widget.repository.songs(widget.team.id);
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  String _query = '';

  bool get _canEdit => widget.team.canEdit(widget.repository.uid);

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<Song> _filter(List<Song> songs) {
    final q = foldPolish(_query.trim());
    if (q.isEmpty) return songs;
    return songs.where((s) => s.searchKey.contains(q)).toList();
  }

  void _retry() {
    setState(() => _songs = widget.repository.songs(widget.team.id));
  }

  void _addSongs(List<Song> current) {
    showAddSongsSheet(
      context,
      repository: widget.repository,
      team: widget.team,
      currentSongs: current,
    );
  }

  void _openSong(List<Song> songs, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SongScreen.team(
          repository: widget.repository,
          teamId: widget.team.id,
          songIds: [for (final s in songs) s.id],
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Song>>(
      stream: _songs,
      builder: (context, snapshot) {
        final hasSongs = snapshot.data?.isNotEmpty ?? false;
        return Scaffold(
          // Klawiaturę obsługuje Scaffold ekranu głównego.
          resizeToAvoidBottomInset: false,
          // Przy pustym śpiewniku przycisk jest na środku ekranu - drugi byłby zbędny.
          floatingActionButton: hasSongs && _canEdit
              ? FloatingActionButton.extended(
                  heroTag: 'add-song',
                  onPressed: () => _addSongs(snapshot.data!),
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj'),
                )
              : null,
          body: _buildBody(snapshot),
        );
      },
    );
  }

  Widget _buildBody(AsyncSnapshot<List<Song>> snapshot) {
    if (snapshot.hasError) {
      return InfoState(
        icon: Icons.cloud_off_outlined,
        error: true,
        title: _loadErrorTitle(snapshot.error!),
        text: 'Sprawdź połączenie z internetem i spróbuj ponownie.',
        details: '${snapshot.error}',
        action: FilledButton.tonalIcon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh),
          label: const Text('Spróbuj ponownie'),
        ),
      );
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.data!.isEmpty) {
      final personal = widget.team.personal;
      return InfoState(
        icon: Icons.library_music_outlined,
        title: personal
            ? 'Twój śpiewnik jest pusty'
            : 'Śpiewnik zespołu jest pusty',
        text: !_canEdit
            ? 'Piosenki dodają tu właściciel i edytorzy zespołu.'
            : personal
            ? 'Wpisz piosenkę albo zaimportuj wiele naraz z plików '
                  '(telefon, Dysk Google, .zip, jWorship).'
            : 'Zaimportuj pliki (np. z Dysku Google) albo dodaj piosenki '
                  'z Mojego śpiewnika.',
        action: _canEdit
            ? FilledButton.icon(
                onPressed: () => _addSongs(const []),
                icon: const Icon(Icons.add),
                label: const Text('Dodaj piosenki'),
              )
            : null,
      );
    }

    final songs = _filter(snapshot.data!);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SearchBar(
            controller: _searchController,
            hintText: 'Szukaj tytułu lub tekstu',
            leading: const Icon(Icons.search),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: 'Wyczyść',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _query = '');
                  },
                ),
            ],
            onChanged: (value) => setState(() => _query = value),
            elevation: const WidgetStatePropertyAll(0),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              songsCount(songs.length),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Expanded(
          child: songs.isEmpty
              ? const InfoState(
                  icon: Icons.search_off,
                  title: 'Nic nie znaleziono',
                  text: 'Spróbuj innego słowa z tytułu lub tekstu.',
                )
              : Scrollbar(
                  controller: _scrollController,
                  interactive: true,
                  child: ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    // Miejsce na przycisk "Dodaj", żeby nie zasłaniał ostatniej piosenki.
                    padding: const EdgeInsets.only(bottom: 88),
                    itemCount: songs.length,
                    itemBuilder: (context, i) => SongTile(
                      song: songs[i],
                      onTap: () => _openSong(songs, i),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

String _loadErrorTitle(Object error) {
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Brak dostępu do tego śpiewnika';
  }
  return 'Nie udało się wczytać piosenek';
}

class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    this.leading,
    this.trailing = const Icon(Icons.chevron_right),
    this.labels = const [],
  });

  final Song song;
  final VoidCallback onTap;

  /// Domyślnie kółko z pierwszą literą tytułu.
  final Widget? leading;
  final Widget? trailing;

  /// Etykiety pod podglądem tekstu, np. zespoły, w których jest piosenka.
  final List<Widget> labels;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initial = song.sortKey.isEmpty
        ? '#'
        : song.title
              .replaceFirst(RegExp(r'^[^\p{L}\p{N}]+', unicode: true), '')
              .characters
              .first
              .toUpperCase();

    return ListTile(
      onTap: onTap,
      leading:
          leading ??
          CircleAvatar(
            backgroundColor: colors.secondaryContainer,
            foregroundColor: colors.onSecondaryContainer,
            child: Text(initial),
          ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: labels.isEmpty
          ? Text(
              song.author.isNotEmpty ? song.author : song.preview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  song.author.isNotEmpty ? song.author : song.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(spacing: 4, runSpacing: 4, children: labels),
              ],
            ),
      trailing: trailing,
    );
  }
}
