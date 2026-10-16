import 'package:flutter/material.dart';

import '../widgets.dart';

typedef SetlistDetails = ({String name, DateTime? date});

/// Nazwa i (opcjonalnie) data setlisty, np. "Niedziela 12.10".
Future<SetlistDetails?> showSetlistDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  DateTime? initialDate,
}) {
  return showDialog<SetlistDetails>(
    context: context,
    builder: (context) => _SetlistDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialDate: initialDate,
    ),
  );
}

class _SetlistDialog extends StatefulWidget {
  const _SetlistDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialDate,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final DateTime? initialDate;

  @override
  State<_SetlistDialog> createState() => _SetlistDialogState();
}

class _SetlistDialogState extends State<_SetlistDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late DateTime? _date = widget.initialDate;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop<SetlistDetails>(context, (name: name, date: _date));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.initialName.isEmpty,
            maxLength: 100,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Nazwa',
              hintText: 'np. Niedziela, Próba, Ślub Ani',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _date == null ? 'Dodaj datę' : formatDate(context, _date!),
                  ),
                ),
              ),
              if (_date != null)
                IconButton(
                  tooltip: 'Usuń datę',
                  onPressed: () => setState(() => _date = null),
                  icon: const Icon(Icons.close),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            onPressed: _name.text.trim().isEmpty ? null : _submit,
            child: Text(widget.confirmLabel),
          ),
        ),
      ],
    );
  }
}
