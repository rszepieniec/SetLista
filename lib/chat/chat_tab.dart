import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../grammar.dart';
import '../messages.dart';
import '../models.dart';
import '../setlists/setlists_screen.dart';
import '../song_screen.dart';
import '../widgets.dart';

/// Czat zespołu. Najnowsze wiadomości na dole, jak w komunikatorach.
/// Oprócz wiadomości są tu zdarzenia: udostępnione setlisty, nowe i zmienione
/// piosenki, import, komentarze - każde z przyciskiem "Otwórz".
class ChatTab extends StatefulWidget {
  const ChatTab({
    super.key,
    required this.repository,
    required this.team,
    required this.active,
    required this.onShowSongs,
  });

  final Repository repository;
  final Team team;

  /// Czy zakładka jest widoczna - wtedy nowe wiadomości są od razu "przeczytane".
  final bool active;

  /// Przejście do zakładki "Piosenki" (np. po imporcie wielu piosenek).
  final VoidCallback onShowSongs;

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  late final _messages = widget.repository.messages(widget.team.id);
  final _input = TextEditingController();
  DateTime? _lastMarked;
  // Nasłuch setlist z kart na czacie - żeby oznaczyć usunięte. Tworzony raz.
  final _setlistStreams = <String, Stream<Playlist?>>{};

  Stream<Playlist?> _setlistOf(String id) =>
      _setlistStreams[id] ??= _repo.playlist(widget.team.id, id);

  Repository get _repo => widget.repository;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _repo
        .sendMessage(widget.team.id, text)
        .catchError((Object e) => showMessage('Nie udało się wysłać: $e'));
  }

  /// Zapisuje "przeczytane" - raz na nową wiadomość, tylko gdy czat jest widoczny.
  void _markSeen(List<ChatMessage> messages) {
    if (!widget.active || messages.isEmpty) return;
    final newest = messages.first.createdAt;
    if (newest == null || newest == _lastMarked) return;
    _lastMarked = newest;
    _repo.markSeen(widget.team.id).catchError((Object _) {});
  }

  Future<void> _newSetlist() async {
    final id = await createSetlist(context, _repo, widget.team.id);
    if (id != null && mounted) openSetlist(context, _repo, widget.team.id, id);
  }

  Future<void> _delete(ChatMessage message) async {
    final ok = await confirm(
      context,
      title: 'Usunąć wiadomość?',
      message: 'Zniknie u wszystkich w zespole.',
      confirmLabel: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    _repo
        .deleteMessage(widget.team.id, message.id)
        .catchError((Object e) => showMessage('Nie udało się usunąć: $e'));
  }

  /// Przytrzymanie wiadomości/karty: otwórz, usuń setlistę, usuń wiadomość.
  Future<void> _eventActions(
    ChatMessage message, {
    required bool exists,
  }) async {
    final mine = message.authorId == _repo.uid;
    final isSetlist =
        message.type == MessageType.setlist && message.playlistId != null;
    final canDeleteSetlist =
        isSetlist && exists && widget.team.canEdit(_repo.uid);
    if (!mine && !canDeleteSetlist) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canDeleteSetlist)
              ListTile(
                leading: const Icon(Icons.playlist_remove),
                title: const Text('Usuń setlistę'),
                subtitle: const Text('Zniknie dla całego zespołu'),
                onTap: () => Navigator.pop(context, 'setlist'),
              ),
            if (mine)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Usuń wiadomość'),
                onTap: () => Navigator.pop(context, 'message'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'message') {
      await _delete(message);
    } else if (action == 'setlist') {
      final ok = await confirm(
        context,
        title: 'Usunąć setlistę?',
        message:
            'Setlista zniknie dla całego zespołu. Piosenki zostaną w śpiewniku.',
        confirmLabel: 'Usuń setlistę',
        destructive: true,
      );
      if (!ok) return;
      _repo
          .deletePlaylist(widget.team.id, message.playlistId!)
          .catchError((Object e) => showMessage('Nie udało się usunąć: $e'));
      // Własną wiadomość o setliście usuwamy razem z nią.
      if (mine) {
        _repo
            .deleteMessage(widget.team.id, message.id)
            .catchError((Object _) {});
      }
    }
  }

  void _openEvent(ChatMessage message) {
    switch (message.type) {
      case MessageType.setlist when message.playlistId != null:
        openSetlist(context, _repo, widget.team.id, message.playlistId!);
      case MessageType.songsImported:
        widget.onShowSongs();
      case _ when message.songId != null:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SongScreen.team(
              repository: _repo,
              teamId: widget.team.id,
              songIds: [message.songId!],
              initialIndex: 0,
              openComments: message.type == MessageType.comment,
            ),
          ),
        );
      case _:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _messages,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return InfoState(
                    icon: Icons.cloud_off_outlined,
                    error: true,
                    title: 'Nie udało się wczytać czatu',
                    text: 'Sprawdź połączenie z internetem.',
                    details: '${snapshot.error}',
                  );
                }
                final messages = snapshot.data;
                if (messages == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _markSeen(messages),
                );
                if (messages.isEmpty) {
                  return const InfoState(
                    icon: Icons.forum_outlined,
                    title: 'Napisz pierwszą wiadomość',
                    text:
                        'Tu pojawiają się wiadomości, setlisty i zmiany '
                        'w śpiewniku zespołu. Setlistę utworzysz przyciskiem + '
                        'obok pola wiadomości.',
                  );
                }
                return ListView.builder(
                  reverse: true,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final message = messages[i];
                    // Lista jest odwrócona: i+1 to wiadomość wcześniejsza.
                    final older = i + 1 < messages.length
                        ? messages[i + 1]
                        : null;
                    final newDay =
                        older == null ||
                        !_sameDay(older.createdAt, message.createdAt);
                    final sameAuthor =
                        !newDay && older.authorId == message.authorId;
                    final mine = message.authorId == _repo.uid;
                    return Column(
                      children: [
                        if (newDay) _DayHeader(date: message.createdAt),
                        if (message.type == MessageType.setlist &&
                            message.playlistId != null)
                          StreamBuilder<Playlist?>(
                            stream: _setlistOf(message.playlistId!),
                            builder: (context, s) {
                              // Dopóki nie wiadomo, zakładamy że istnieje.
                              final exists =
                                  !s.hasData &&
                                      s.connectionState ==
                                          ConnectionState.waiting ||
                                  s.data != null;
                              return _EventCard(
                                message: message,
                                mine: mine,
                                showAuthor: !sameAuthor,
                                deleted: !exists,
                                onOpen: () => _openEvent(message),
                                onLongPress: () =>
                                    _eventActions(message, exists: exists),
                              );
                            },
                          )
                        else if (message.isEvent)
                          _EventCard(
                            message: message,
                            mine: mine,
                            showAuthor: !sameAuthor,
                            onOpen: () => _openEvent(message),
                            onLongPress: () =>
                                _eventActions(message, exists: true),
                          )
                        else
                          _Bubble(
                            message: message,
                            mine: mine,
                            showAuthor: !sameAuthor,
                            onLongPress: mine ? () => _delete(message) : null,
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          _Composer(
            controller: _input,
            onSend: _send,
            onNewSetlist: widget.team.canEdit(_repo.uid) ? _newSetlist : null,
          ),
        ],
      ),
    );
  }
}

bool _sameDay(DateTime? a, DateTime? b) {
  a ??= DateTime.now();
  b ??= DateTime.now();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _time(BuildContext context, DateTime date) => MaterialLocalizations.of(
  context,
).formatTimeOfDay(TimeOfDay.fromDateTime(date));

/// Nagłówek nowego dnia: data i godzina pierwszej wiadomości tego dnia.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime? date;

  @override
  Widget build(BuildContext context) {
    final day = date ?? DateTime.now();
    final now = DateTime.now();
    final label = _sameDay(day, now)
        ? 'Dzisiaj'
        : _sameDay(day, now.subtract(const Duration(days: 1)))
        ? 'Wczoraj'
        : MaterialLocalizations.of(context).formatFullDate(day);
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            '$label, ${_time(context, day)}',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// Zdarzenie: "Adam Kowalski udostępnia setlistę „Niedziela”" + przycisk.
/// Wyrównane jak dymki: moje po prawej, cudze po lewej (z imieniem nad kartą).
class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.message,
    required this.mine,
    required this.showAuthor,
    required this.onOpen,
    required this.onLongPress,
    this.deleted = false,
  });

  final ChatMessage message;
  final bool mine;
  final bool showAuthor;
  final VoidCallback onOpen;
  final VoidCallback onLongPress;

  /// Setlista z tej karty została usunięta.
  final bool deleted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (icon, action) = switch (message.type) {
      MessageType.setlist => (Icons.queue_music, 'Otwórz setlistę'),
      MessageType.songAdded => (Icons.library_add_outlined, 'Otwórz piosenkę'),
      MessageType.songUpdated => (Icons.edit_note, 'Otwórz piosenkę'),
      MessageType.songsImported => (Icons.upload_file, 'Zobacz śpiewnik'),
      MessageType.comment => (Icons.chat_bubble_outline, 'Pokaż komentarze'),
      // Zdarzenia zespołu - nie ma czego otwierać.
      MessageType.joined => (Icons.person_add_alt_1_outlined, null),
      MessageType.left => (Icons.person_remove_outlined, null),
      MessageType.teamCreated => (Icons.groups_outlined, null),
      MessageType.teamRenamed => (Icons.drive_file_rename_outline, null),
      MessageType.text => (Icons.info_outline, null),
    };
    final name = message.authorName.isEmpty ? 'Ktoś' : message.authorName;
    final highlighted = message.type == MessageType.setlist && !deleted;
    final (background, foreground) = highlighted
        ? (colors.tertiaryContainer, colors.onTertiaryContainer)
        : mine
        ? (colors.primaryContainer, colors.onPrimaryContainer)
        : (colors.surfaceContainerHighest, colors.onSurface);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Imię jest w treści karty ("Adam Kowalski udostępnia…"),
            // więc nad kartą tylko odstęp, gdy zmienia się autor.
            if (showAuthor) const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: background,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: deleted || action == null ? null : onOpen,
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 6, 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 20, color: foreground),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: mine ? 'Ty ' : '$name ',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      // Czas przeszły, odmieniony: "dodałeś",
                                      // "dodała", "dodał(a)".
                                      TextSpan(
                                        text: describeEvent(
                                          message,
                                          mine: mine,
                                        ),
                                      ),
                                    ],
                                  ),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: foreground,
                                    decoration: deleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 30),
                            Text(
                              message.createdAt == null
                                  ? 'wysyłanie…'
                                  : _time(context, message.createdAt!),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: foreground.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (deleted)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 12,
                                ),
                                child: Text(
                                  'Setlista usunięta',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: foreground.withValues(alpha: 0.6),
                                  ),
                                ),
                              )
                            else if (action != null)
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: foreground,
                                ),
                                onPressed: onOpen,
                                child: Text(action),
                              )
                            else
                              const SizedBox(height: 40),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showAuthor,
    this.onLongPress,
  });

  final ChatMessage message;
  final bool mine;
  final bool showAuthor;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final background = mine
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final foreground = mine ? colors.onPrimaryContainer : colors.onSurface;
    final time = message.createdAt == null
        ? 'wysyłanie…'
        : _time(context, message.createdAt!);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (showAuthor && !mine)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 6, bottom: 2),
                child: Text(
                  message.authorName.isEmpty ? 'Ktoś' : message.authorName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Material(
                color: background,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onLongPress: onLongPress,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          message.text,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          time,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: foreground.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    this.onNewSetlist,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onNewSetlist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (onNewSetlist != null)
              IconButton(
                tooltip: 'Nowa setlista',
                icon: const Icon(Icons.playlist_add),
                onPressed: onNewSetlist,
              )
            else
              const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Wiadomość do zespołu',
                  counterText: '',
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => IconButton.filled(
                tooltip: 'Wyślij',
                onPressed: controller.text.trim().isEmpty ? null : onSend,
                icon: const Icon(Icons.send),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
