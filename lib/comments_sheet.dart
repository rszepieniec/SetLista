import 'package:flutter/material.dart';

import 'data/repository.dart';
import 'messages.dart';
import 'models.dart';
import 'song.dart';
import 'widgets.dart';

/// Komentarze do piosenki ("zaczynamy od refrenu", "tonacja D").
/// W zespole każdy nowy komentarz pojawia się też na czacie.
Future<void> showComments(
  BuildContext context, {
  required Repository repository,
  required String teamId,
  required Song song,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) =>
        _CommentsSheet(repository: repository, teamId: teamId, song: song),
  );
}

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({
    required this.repository,
    required this.teamId,
    required this.song,
  });

  final Repository repository;
  final String teamId;
  final Song song;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late final _comments = widget.repository.comments(
    widget.teamId,
    widget.song.id,
  );
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    widget.repository
        .addComment(widget.teamId, widget.song, text)
        .catchError((Object e) => showMessage('Nie udało się dodać: $e'));
  }

  Future<void> _delete(SongComment comment) async {
    final ok = await confirm(
      context,
      title: 'Usunąć komentarz?',
      message: comment.text,
      confirmLabel: 'Usuń',
      destructive: true,
    );
    if (!ok) return;
    widget.repository
        .deleteComment(widget.teamId, widget.song.id, comment.id)
        .catchError((Object e) => showMessage('Nie udało się usunąć: $e'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final personal =
        widget.teamId == Repository.personalTeamId(widget.repository.uid);

    return Padding(
      // Pole tekstowe nad klawiaturą.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      personal ? 'Notatki' : 'Komentarze',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      widget.song.title,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<SongComment>>(
                stream: _comments,
                builder: (context, snapshot) {
                  final comments = snapshot.data;
                  if (snapshot.hasError) {
                    return InfoState(
                      icon: Icons.cloud_off_outlined,
                      error: true,
                      title: 'Nie udało się wczytać',
                      text: 'Sprawdź połączenie z internetem.',
                      details: '${snapshot.error}',
                    );
                  }
                  if (comments == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (comments.isEmpty) {
                    return InfoState(
                      icon: Icons.chat_bubble_outline,
                      title: personal ? 'Brak notatek' : 'Brak komentarzy',
                      text: personal
                          ? 'Zapisz np. tonację albo kto zaczyna.'
                          : 'Np. „zaczynamy od refrenu”, „tonacja D”. '
                                'Komentarz zobaczy cały zespół.',
                    );
                  }
                  return ListView.builder(
                    itemCount: comments.length,
                    itemBuilder: (context, i) {
                      final c = comments[i];
                      final mine = c.authorId == widget.repository.uid;
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            c.authorName.isEmpty
                                ? '?'
                                : c.authorName.characters.first.toUpperCase(),
                          ),
                        ),
                        title: Text(c.text),
                        subtitle: Text(
                          [
                            mine
                                ? 'Ty'
                                : (c.authorName.isEmpty
                                      ? 'Ktoś'
                                      : c.authorName),
                            if (c.createdAt != null)
                              '${formatDate(context, c.createdAt!)}, '
                                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(c.createdAt!))}',
                          ].join(' · '),
                        ),
                        trailing: mine
                            ? IconButton(
                                tooltip: 'Usuń',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => _delete(c),
                              )
                            : null,
                      );
                    },
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: personal
                              ? 'Dodaj notatkę'
                              : 'Dodaj komentarz',
                          counterText: '',
                          filled: true,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ListenableBuilder(
                      listenable: _input,
                      builder: (context, _) => IconButton.filled(
                        tooltip: 'Wyślij',
                        onPressed: _input.text.trim().isEmpty ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
