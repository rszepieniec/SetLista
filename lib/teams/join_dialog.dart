import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../models.dart';

/// Okno "Dołącz do zespołu": kod zaproszenia -> id zespołu (albo null).
Future<String?> showJoinTeamDialog(
  BuildContext context,
  Repository repository,
) => showDialog<String>(
  context: context,
  builder: (_) => JoinDialog(repository: repository),
);

class JoinDialog extends StatefulWidget {
  const JoinDialog({super.key, required this.repository});

  final Repository repository;

  @override
  State<JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<JoinDialog> {
  final _code = TextEditingController();
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final teamId = await widget.repository.joinTeam(_code.text);
      if (mounted) Navigator.pop(context, teamId);
    } on UserFacingException catch (e) {
      setState(() => _error = e.message);
    } on FirebaseException catch (e) {
      setState(
        () => _error = e.code == 'permission-denied'
            ? 'Nie udało się dołączyć - kod mógł wygasnąć.'
            : 'Coś poszło nie tak (${e.code}).',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Dołącz do zespołu'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Wpisz kod, który dostałeś od właściciela zespołu.'),
          const SizedBox(height: 16),
          TextField(
            controller: _code,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(letterSpacing: 3),
            decoration: InputDecoration(
              hintText: 'ABCD-2345',
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _busy ? null : _join(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        ListenableBuilder(
          listenable: _code,
          builder: (context, _) => FilledButton(
            onPressed: _busy || normalizeInviteCode(_code.text).length != 8
                ? null
                : _join,
            child: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Dołącz'),
          ),
        ),
      ],
    );
  }
}
