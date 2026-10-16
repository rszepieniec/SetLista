import 'dart:async';

import 'package:flutter/material.dart';

import 'comments_sheet.dart';
import 'data/repository.dart';
import 'debug_log.dart';
import 'messages.dart';
import 'models.dart';
import 'preferences.dart';
import 'song.dart';
import 'song_edit_screen.dart';
import 'widgets.dart';

/// Piosenka w konkretnym śpiewniku (mój albo zespołu).
typedef SongRef = ({String teamId, String songId});

/// Ekran z tekstem piosenki. Przesuwanie w lewo/prawo zmienia piosenkę
/// (w kolejności z listy, z uwzględnieniem wyszukiwania). Piosenki mogą być
/// z różnych śpiewników (scalony "Mój śpiewnik").
///
/// Treść jest na żywo z Firestore, więc zmiany (własne i innych osób)
/// pojawiają się od razu.
class SongScreen extends StatefulWidget {
  const SongScreen({
    super.key,
    required this.repository,
    required this.songs,
    required this.initialIndex,
    this.openComments = false,
  });

  /// Wszystkie piosenki z jednego śpiewnika.
  SongScreen.team({
    super.key,
    required this.repository,
    required String teamId,
    required List<String> songIds,
    required this.initialIndex,
    this.openComments = false,
  }) : songs = [for (final id in songIds) (teamId: teamId, songId: id)];

  final Repository repository;
  final List<SongRef> songs;
  final int initialIndex;

  /// Od razu pokaż komentarze (wejście z wiadomości o komentarzu na czacie).
  final bool openComments;

  @override
  State<SongScreen> createState() => _SongScreenState();
}

class _SongScreenState extends State<SongScreen> {
  late final _pageController = PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;
  // Jeden nasłuch na każdy śpiewnik, z którego są piosenki na tej liście.
  final _subscriptions = <StreamSubscription<List<Song>>>[];
  final _songsByTeam = <String, Map<String, Song>>{};
  // Nasłuch komentarzy osobno dla każdej piosenki, tworzony raz.
  final _commentStreams = <String, Stream<List<SongComment>>>{};
  var _openedComments = false;

  Repository get _repo => widget.repository;
  SongRef get _ref => widget.songs[_index];
  bool get _loaded =>
      widget.songs.every((r) => _songsByTeam.containsKey(r.teamId));

  Song? _songAt(SongRef ref) => _songsByTeam[ref.teamId]?[ref.songId];

  @override
  void initState() {
    super.initState();
    for (final teamId in {for (final r in widget.songs) r.teamId}) {
      _subscriptions.add(
        _repo
            .songs(teamId)
            .listen(
              (songs) => setState(
                () => _songsByTeam[teamId] = {for (final s in songs) s.id: s},
              ),
              onError: (Object e) =>
                  logFirebase('songs $teamId: ${describeError(e)}'),
            ),
      );
    }
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    _pageController.dispose();
    super.dispose();
  }

  Stream<List<SongComment>> _commentsOf(SongRef ref) =>
      _commentStreams['${ref.teamId}/${ref.songId}'] ??= _repo.comments(
        ref.teamId,
        ref.songId,
      );

  void _showComments(SongRef ref, Song song) =>
      showComments(context, repository: _repo, teamId: ref.teamId, song: song);

  void _changeFontSize(double delta) {
    // Zapamiętywany na urządzeniu - po ponownym uruchomieniu zostaje.
    changeLyricsFontSize(delta);
  }

  void _edit(SongRef ref, Song song) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            SongEditScreen(repository: _repo, teamId: ref.teamId, song: song),
      ),
    );
  }

  Future<void> _delete(SongRef ref, Song song) async {
    final where = _repo.team(ref.teamId)?.name ?? 'śpiewnika';
    final confirmed = await confirm(
      context,
      title: 'Usunąć piosenkę?',
      message: '„${song.title}” zniknie z „$where” i z jego setlist.',
      confirmLabel: 'Usuń',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    _repo
        .deleteSong(ref.teamId, song)
        .catchError((Object e) => showMessage('Nie udało się usunąć: $e'));
    showMessage('Usunięto „${song.title}”');
    Navigator.of(context).pop();
  }

  /// Kopiuje albo przenosi piosenkę do innego śpiewnika, w którym można edytować.
  Future<void> _copyTo(SongRef ref, Song song, {required bool move}) async {
    final targets = [
      for (final t in _repo.teams.value)
        if (t.id != ref.teamId && t.canEdit(_repo.uid)) t,
    ];
    if (targets.isEmpty) {
      showMessage(
        'Nie masz innego śpiewnika, do którego możesz dodawać piosenki - '
        'utwórz zespół albo dołącz do niego.',
      );
      return;
    }
    final target = await pickTeam(
      context,
      title: move
          ? 'Przenieś „${song.title}” do…'
          : 'Kopiuj „${song.title}” do…',
      teams: targets,
    );
    if (target == null || !mounted) return;
    if (move) {
      final ok = await confirm(
        context,
        title: 'Przenieść piosenkę?',
        message:
            '„${song.title}” trafi do „${target.name}” i zniknie z tego '
            'śpiewnika oraz jego setlist.',
        confirmLabel: 'Przenieś',
      );
      if (!ok || !mounted) return;
    }
    try {
      final done = await _repo.copySong(
        ref.teamId,
        song,
        target.id,
        move: move,
      );
      if (!done) {
        showMessage('W „${target.name}” jest już piosenka „${song.title}”.');
        return;
      }
      showMessage(
        move
            ? 'Przeniesiono do „${target.name}”'
            : 'Skopiowano do „${target.name}”',
      );
      if (move && mounted) Navigator.of(context).pop();
    } catch (e) {
      showMessage('Nie udało się: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = _ref;
    final current = _songAt(ref);
    final canEdit = _repo.canEdit(ref.teamId);
    if (widget.openComments && !_openedComments && current != null) {
      _openedComments = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showComments(ref, current),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.songs.length > 1
              ? '${_index + 1} / ${widget.songs.length}'
              : '',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        actions: [
          IconButton(
            tooltip: 'Mniejszy tekst',
            icon: const Icon(Icons.text_decrease),
            onPressed: () => _changeFontSize(-2),
          ),
          IconButton(
            tooltip: 'Większy tekst',
            icon: const Icon(Icons.text_increase),
            onPressed: () => _changeFontSize(2),
          ),
          if (current != null)
            StreamBuilder<List<SongComment>>(
              stream: _commentsOf(ref),
              builder: (context, snapshot) {
                final count = snapshot.data?.length ?? 0;
                return IconButton(
                  tooltip: 'Komentarze',
                  onPressed: () => _showComments(ref, current),
                  icon: Badge(
                    isLabelVisible: count > 0,
                    label: Text('$count'),
                    child: const Icon(Icons.chat_bubble_outline),
                  ),
                );
              },
            ),
          if (canEdit)
            IconButton(
              tooltip: 'Edytuj',
              icon: const Icon(Icons.edit_outlined),
              onPressed: current == null ? null : () => _edit(ref, current),
            ),
          PopupMenuButton<void>(
            enabled: current != null,
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => _copyTo(ref, current!, move: false),
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.copy_outlined),
                  title: Text('Kopiuj do…'),
                ),
              ),
              if (canEdit) ...[
                PopupMenuItem(
                  onTap: () => _copyTo(ref, current!, move: true),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.drive_file_move_outline),
                    title: Text('Przenieś do…'),
                  ),
                ),
                PopupMenuItem(
                  onTap: () => _delete(ref, current!),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_outline),
                    title: Text('Usuń piosenkę'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pageController,
              itemCount: widget.songs.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final pageRef = widget.songs[i];
                final song = _songAt(pageRef);
                final team = _repo.team(pageRef.teamId);
                return song == null
                    ? const Center(child: Text('Ta piosenka została usunięta'))
                    : _SongView(
                        song: song,
                        // Skąd jest piosenka - ważne w scalonym Moim śpiewniku.
                        source: team == null || team.personal
                            ? null
                            : team.name,
                      );
              },
            ),
    );
  }
}

class _SongView extends StatefulWidget {
  const _SongView({required this.song, this.source});

  final Song song;

  /// Nazwa zespołu, z którego śpiewnika jest piosenka (null = Mój śpiewnik).
  final String? source;

  @override
  State<_SongView> createState() => _SongViewState();
}

class _SongViewState extends State<_SongView> {
  // Własny kontroler na stronę - w PageView kilka stron żyje naraz,
  // więc wspólny PrimaryScrollController się nie nada.
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Scrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.paddingOf(context).bottom + 32,
        ),
        child: ValueListenableBuilder<double>(
          valueListenable: lyricsFontSize,
          builder: (context, fontSize, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                song.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.source != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SourceChip(label: widget.source!),
                ),
              if (song.author.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    song.author,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ),
              const SizedBox(height: 20),
              SelectableText(
                song.lyrics.isEmpty ? 'Brak tekstu' : song.lyrics,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: fontSize,
                  height: 1.5,
                  color: song.lyrics.isEmpty ? muted : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
