import 'package:flutter/material.dart';

import 'song.dart';
import 'widgets.dart';

class PickerItem {
  const PickerItem(this.song, {this.locked = false, this.note});

  final Song song;

  /// Już dodana (zaznaczona na stałe, nie da się odznaczyć).
  final bool locked;

  /// Dopisek pod tytułem, np. "już w zespole".
  final String? note;
}

class PickerSection {
  const PickerSection({
    required this.title,
    required this.items,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<PickerItem> items;
}

/// Wybór wielu piosenek, w sekcjach (np. "Śpiewnik zespołu" i "Mój śpiewnik").
/// Zwraca zaznaczone piosenki w kolejności zaznaczania.
class SongPickerScreen extends StatefulWidget {
  const SongPickerScreen({
    super.key,
    required this.title,
    required this.sections,
    this.confirmLabel = 'Dodaj',
    this.emptyText = 'Najpierw dodaj piosenki do śpiewnika.',
  });

  final String title;
  final List<PickerSection> sections;
  final String confirmLabel;
  final String emptyText;

  @override
  State<SongPickerScreen> createState() => _SongPickerScreenState();
}

class _SongPickerScreenState extends State<SongPickerScreen> {
  final _selected = <Song>[];
  String _query = '';

  void _toggle(Song song) {
    setState(() {
      if (!_selected.remove(song)) _selected.add(song);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = foldPolish(_query.trim());
    final sections = [
      for (final section in widget.sections)
        (
          section: section,
          items: [
            for (final item in section.items)
              if (q.isEmpty || item.song.searchKey.contains(q)) item,
          ],
        ),
    ];
    final total = widget.sections.fold<int>(0, (n, s) => n + s.items.length);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, _selected),
              child: Text(
                _selected.isEmpty
                    ? widget.confirmLabel
                    : '${widget.confirmLabel} (${_selected.length})',
              ),
            ),
          ),
        ],
      ),
      body: total == 0
          ? InfoState(
              icon: Icons.library_music_outlined,
              title: 'Brak piosenek',
              text: widget.emptyText,
            )
          : CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SearchBar(
                      hintText: 'Szukaj tytułu lub tekstu',
                      leading: const Icon(Icons.search),
                      elevation: const WidgetStatePropertyAll(0),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                  ),
                ),
                for (final (:section, :items) in sections)
                  if (items.isNotEmpty) ...[
                    if (widget.sections.length > 1)
                      SliverToBoxAdapter(
                        child: ListTile(
                          leading: section.icon == null
                              ? null
                              : Icon(
                                  section.icon,
                                  color: theme.colorScheme.primary,
                                ),
                          title: Text(
                            section.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          subtitle: section.subtitle == null
                              ? null
                              : Text(section.subtitle!),
                        ),
                      ),
                    SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final item = items[i];
                        final order = _selected.indexOf(item.song);
                        return CheckboxListTile(
                          value: item.locked || order != -1,
                          onChanged: item.locked
                              ? null
                              : (_) => _toggle(item.song),
                          title: Text(
                            item.song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            order != -1
                                ? 'Pozycja ${order + 1}'
                                : item.note ?? item.song.preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
                  ],
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
    );
  }
}
