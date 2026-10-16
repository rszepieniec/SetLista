import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../messages.dart';
import '../models.dart';
import '../song.dart';
import '../song_edit_screen.dart';
import '../song_picker_screen.dart';
import 'song_import.dart';

/// Arkusz "Dodaj piosenki": nowa, z plików (także Dysk Google), z folderu,
/// albo - w zespole - z Mojego śpiewnika.
Future<void> showAddSongsSheet(
  BuildContext context, {
  required Repository repository,
  required Team team,
  required List<Song> currentSongs,
}) {
  // Folder da się wybrać i odczytać na Androidzie i komputerze; na iPhonie
  // zaznacza się wszystkie pliki w folderze (albo wybiera .zip).
  final folderSupported =
      !kIsWeb && defaultTargetPlatform != TargetPlatform.iOS;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      void run(Future<void> Function() action) {
        Navigator.pop(sheetContext);
        action();
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: const Text('Nowa piosenka'),
              subtitle: const Text('Wpisz albo wklej tekst'),
              onTap: () => run(() async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    fullscreenDialog: true,
                    builder: (_) =>
                        SongEditScreen(repository: repository, teamId: team.id),
                  ),
                );
              }),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Importuj pliki'),
              subtitle: const Text(
                'Z telefonu lub Dysku Google: .txt, .zip, .sng (jWorship) - '
                'można zaznaczyć wiele naraz',
              ),
              onTap: () => run(
                () => _importFiles(context, repository, team, currentSongs),
              ),
            ),
            if (folderSupported)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Importuj folder'),
                subtitle: const Text('Wszystkie pasujące pliki z folderu'),
                onTap: () => run(
                  () => _importFolder(context, repository, team, currentSongs),
                ),
              ),
            if (!team.personal)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: const Text('Z Mojego śpiewnika'),
                subtitle: const Text('Skopiuj swoje piosenki do zespołu'),
                onTap: () => run(
                  () =>
                      addFromPersonal(context, repository, team, currentSongs),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}

Future<void> _importFiles(
  BuildContext context,
  Repository repository,
  Team team,
  List<Song> currentSongs,
) async {
  // FileType.any: rozszerzenia filtrujemy sami - .sng nie jest znane systemom.
  final picked = await FilePicker.pickFiles(dialogTitle: 'Wybierz piosenki');
  if (picked.isEmpty || !context.mounted) return;
  final files = [
    for (final file in picked)
      (name: file.name, bytes: await file.readAsBytes()),
  ];
  if (!context.mounted) return;
  await _preview(context, repository, team, currentSongs, parseFiles(files));
}

Future<void> _importFolder(
  BuildContext context,
  Repository repository,
  Team team,
  List<Song> currentSongs,
) async {
  final path = await FilePicker.getDirectoryPath(
    dialogTitle: 'Wybierz folder z piosenkami',
  );
  if (path == null || !context.mounted) return;
  final files = <({String name, Uint8List bytes})>[];
  await for (final entity in Directory(path).list(recursive: true)) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (supportedExtensions.contains(ext)) {
      files.add((name: name, bytes: await entity.readAsBytes()));
    }
  }
  if (!context.mounted) return;
  await _preview(context, repository, team, currentSongs, parseFiles(files));
}

Future<void> _preview(
  BuildContext context,
  Repository repository,
  Team team,
  List<Song> currentSongs,
  ImportResult result,
) async {
  if (result.songs.isEmpty) {
    showMessage(
      result.skipped.isEmpty
          ? 'Nie wybrano żadnych plików.'
          : 'Nie znaleziono piosenek w wybranych plikach '
                '(obsługiwane: .txt, .md, .zip, .sng).',
    );
    return;
  }
  final count = await Navigator.of(context).push<int>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImportPreviewScreen(
        repository: repository,
        team: team,
        result: result,
        existingTitles: {
          for (final s in currentSongs) Repository.titleKey(s.title),
        },
      ),
    ),
  );
  if (count != null) {
    showMessage('Dodano ${songsCount(count)} do „${team.name}”');
  }
}

/// Wybór piosenek z Mojego śpiewnika do zespołu. Te, które zespół już ma
/// (ten sam tytuł), są zaznaczone i nie da się ich wybrać drugi raz.
Future<void> addFromPersonal(
  BuildContext context,
  Repository repository,
  Team team,
  List<Song> currentSongs,
) async {
  final personal = await repository
      .songs(Repository.personalTeamId(repository.uid))
      .first;
  if (!context.mounted) return;
  final inTeam = {for (final s in currentSongs) Repository.titleKey(s.title)};
  final picked = await Navigator.of(context).push<List<Song>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SongPickerScreen(
        title: 'Z Mojego śpiewnika',
        confirmLabel: 'Dodaj do zespołu',
        emptyText: 'Twój śpiewnik jest pusty.',
        sections: [
          PickerSection(
            title: 'Mój śpiewnik',
            items: [
              for (final song in personal)
                inTeam.contains(Repository.titleKey(song.title))
                    ? PickerItem(song, locked: true, note: 'Już jest w zespole')
                    : PickerItem(song),
            ],
          ),
        ],
      ),
    ),
  );
  if (picked == null || picked.isEmpty) return;
  try {
    await repository.copySongsToTeam(picked, team.id);
    showMessage('Dodano ${songsCount(picked.length)} do „${team.name}”');
  } catch (e) {
    showMessage('Nie udało się dodać: $e');
  }
}

/// Podgląd importu: co zostanie dodane, co już jest, czego nie dało się odczytać.
class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({
    super.key,
    required this.repository,
    required this.team,
    required this.result,
    required this.existingTitles,
  });

  final Repository repository;
  final Team team;
  final ImportResult result;
  final Set<String> existingTitles;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  late final List<ImportedSong> _songs = widget.result.songs;
  late final List<String?> _notes = _duplicateNotes();
  late final Set<int> _selected = {
    for (var i = 0; i < _songs.length; i++)
      if (_notes[i] == null) i,
  };
  var _busy = false;

  /// Duplikaty (w śpiewniku albo kilka razy w imporcie) są domyślnie odznaczone.
  List<String?> _duplicateNotes() {
    final seen = <String>{};
    return [
      for (final song in _songs)
        if (widget.existingTitles.contains(Repository.titleKey(song.title)))
          'Już jest w śpiewniku'
        else if (!seen.add(Repository.titleKey(song.title)))
          'Powtórzona w imporcie'
        else
          null,
    ];
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final songs = [
        for (var i = 0; i < _songs.length; i++)
          if (_selected.contains(i)) _songs[i],
      ];
      await widget.repository.importSongs(widget.team.id, songs);
      if (mounted) Navigator.pop(context, songs.length);
    } catch (e) {
      showMessage('Import się nie udał: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(ImportedSong song) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(song.title),
        content: SingleChildScrollView(
          child: Text(
            [
              if (song.author.isNotEmpty) song.author,
              'Plik: ${song.source}',
              '',
              song.lyrics.isEmpty ? '(brak tekstu)' : song.lyrics,
            ].join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Zamknij'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final skipped = widget.result.skipped;
    final allSelected = _selected.length == _songs.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Import do „${widget.team.name}”'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _busy || _selected.isEmpty ? null : _import,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text('Importuj (${_selected.length})'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          ListTile(
            title: Text(
              'Znaleziono ${songsCount(_songs.length)}',
              style: theme.textTheme.titleMedium,
            ),
            subtitle: const Text(
              'Dotknij piosenki, żeby zobaczyć tekst. Te, które już są, '
              'są odznaczone.',
            ),
            trailing: TextButton(
              onPressed: () => setState(() {
                if (allSelected) {
                  _selected.clear();
                } else {
                  _selected.addAll(List.generate(_songs.length, (i) => i));
                }
              }),
              child: Text(allSelected ? 'Odznacz' : 'Zaznacz wszystkie'),
            ),
          ),
          if (skipped.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Card.filled(
                color: theme.colorScheme.errorContainer,
                child: ExpansionTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text('Pominięto plików: ${skipped.length}'),
                  subtitle: const Text('Puste albo nieobsługiwany format'),
                  children: [
                    for (final name in skipped)
                      ListTile(dense: true, title: Text(name)),
                  ],
                ),
              ),
            ),
          for (var i = 0; i < _songs.length; i++)
            CheckboxListTile(
              value: _selected.contains(i),
              onChanged: _busy
                  ? null
                  : (on) => setState(
                      () => on! ? _selected.add(i) : _selected.remove(i),
                    ),
              secondary: IconButton(
                tooltip: 'Podgląd',
                icon: const Icon(Icons.visibility_outlined),
                onPressed: () => _show(_songs[i]),
              ),
              title: Text(
                _songs[i].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                _notes[i] ??
                    (_songs[i].author.isNotEmpty
                        ? _songs[i].author
                        : _songs[i].source),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _notes[i] == null
                    ? null
                    : TextStyle(color: theme.colorScheme.error),
              ),
            ),
        ],
      ),
    );
  }
}
