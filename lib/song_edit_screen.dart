import 'package:flutter/material.dart';

import 'data/repository.dart';
import 'messages.dart';
import 'song.dart';

/// Dodawanie nowej piosenki (gdy [song] == null) albo edycja istniejącej.
class SongEditScreen extends StatefulWidget {
  const SongEditScreen({
    super.key,
    required this.repository,
    required this.teamId,
    this.song,
  });

  final Repository repository;
  final String teamId;
  final Song? song;

  @override
  State<SongEditScreen> createState() => _SongEditScreenState();
}

class _SongEditScreenState extends State<SongEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.song?.title);
  late final _author = TextEditingController(text: widget.song?.author);
  late final _lyrics = TextEditingController(text: widget.song?.lyrics);

  bool get _isNew => widget.song == null;

  bool get _dirty =>
      _title.text != (widget.song?.title ?? '') ||
      _author.text != (widget.song?.author ?? '') ||
      _lyrics.text != (widget.song?.lyrics ?? '');

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _lyrics.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    if (!_dirty) {
      Navigator.of(context).pop();
      return;
    }
    // Bez czekania na serwer: offline zapis trafi do kolejki, a lista
    // i tak od razu pokaże zmiany z lokalnej kopii.
    widget.repository
        .saveSong(
          widget.teamId,
          original: widget.song,
          title: _title.text.trim(),
          author: _author.text.trim(),
          lyrics: _lyrics.text.trim(),
        )
        .catchError((Object e) => showMessage('Nie udało się zapisać: $e'));
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Odrzucić zmiany?'),
        content: const Text('Niezapisane zmiany zostaną utracone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Edytuj dalej'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Odrzuć'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!_dirty || await _confirmDiscard()) {
          if (context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'Nowa piosenka' : 'Edycja'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton(
                onPressed: _save,
                child: const Text('Zapisz'),
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              MediaQuery.paddingOf(context).bottom + 24,
            ),
            children: [
              TextFormField(
                controller: _title,
                autofocus: _isNew,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Tytuł',
                  counterText: '',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Tytuł jest wymagany' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _author,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Autor (opcjonalnie)',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lyrics,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                minLines: 14,
                maxLines: null,
                maxLength: 50000,
                style: const TextStyle(height: 1.5),
                decoration: const InputDecoration(
                  labelText: 'Tekst',
                  hintText: 'Zwrotki oddzielaj pustą linią',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
