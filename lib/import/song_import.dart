import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Piosenka odczytana z pliku, przed zapisem do bazy.
class ImportedSong {
  ImportedSong({
    required this.title,
    required this.lyrics,
    required this.source,
    this.author = '',
  });

  final String title;
  final String author;
  final String lyrics;

  /// Nazwa pliku (do pokazania przy podglądzie importu).
  final String source;
}

/// Wynik odczytu plików: piosenki i pliki, których nie dało się użyć.
class ImportResult {
  ImportResult(this.songs, this.skipped);

  final List<ImportedSong> songs;
  final List<String> skipped;
}

const supportedExtensions = ['txt', 'md', 'sng', 'zip'];

/// Odczytuje pliki wybrane przez użytkownika (także z wnętrza archiwów .zip).
ImportResult parseFiles(List<({String name, Uint8List bytes})> files) {
  final songs = <ImportedSong>[];
  final skipped = <String>[];

  void handle(String path, Uint8List bytes) {
    final name = path.split('/').last;
    if (name.startsWith('.') || path.contains('__MACOSX/')) return;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    try {
      switch (ext) {
        case 'zip':
          for (final entry in ZipDecoder().decodeBytes(bytes)) {
            if (entry.isFile) handle(entry.name, entry.content);
          }
        case 'sng':
          final song = parseSng(bytes, fileName: name);
          song == null ? skipped.add(name) : songs.add(song);
        case 'txt' || 'md' || '':
          final song = parseSongText(decodeText(bytes), fileName: name);
          song == null ? skipped.add(name) : songs.add(song);
        default:
          skipped.add(name);
      }
    } catch (_) {
      skipped.add(name);
    }
  }

  for (final file in files) {
    handle(file.name, file.bytes);
  }
  return ImportResult(songs, skipped);
}

/// Tekst z pliku: UTF-8 (z BOM lub bez), UTF-16 albo polskie Windows-1250.
String decodeText(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), littleEndian: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), littleEndian: false);
  }
  var data = bytes;
  if (data.length >= 3 &&
      data[0] == 0xEF &&
      data[1] == 0xBB &&
      data[2] == 0xBF) {
    data = data.sublist(3);
  }
  try {
    return utf8.decode(data);
  } on FormatException {
    return _cp1250(data);
  }
}

String _utf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

/// Windows-1250 (polskie pliki z Notatnika). Znaki 0x80-0xFF.
const _cp1250Table =
    '€\u0081‚\u0083„…†‡\u0088‰Š‹ŚŤŽŹ\u0090‘’“”•–—\u0098™š›śťžź'
    ' ˇ˘Ł¤Ą¦§¨©Ş«¬­®Ż°±˛ł´µ¶·¸ąş»Ľ˝ľż'
    'ŔÁÂĂÄĹĆÇČÉĘËĚÍÎĎĐŃŇÓÔŐÖ×ŘŮÚŰÜÝŢß'
    'ŕáâăäĺćçčéęëěíîďđńňóôőö÷řůúűüýţ˙';

String _cp1250(Uint8List bytes) => String.fromCharCodes([
  for (final b in bytes) b < 0x80 ? b : _cp1250Table.codeUnitAt(b - 0x80),
]);

/// Elastyczny odczyt tekstu piosenki:
/// - format SetListy (tytuł, opcjonalnie "Autor: ...", pusta linia, zwrotki),
/// - sam tekst bez tytułu - tytuł z nazwy pliku (albo z pierwszej linii),
/// - Markdown z "# Tytuł".
ImportedSong? parseSongText(String text, {required String fileName}) {
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((l) => l.trimRight())
      .toList();
  while (lines.isNotEmpty && lines.first.trim().isEmpty) {
    lines.removeAt(0);
  }
  if (lines.isEmpty) return null;

  final blank = lines.indexWhere((l) => l.trim().isEmpty);
  final header = blank == -1 ? lines : lines.sublist(0, blank);
  final looksLikeHeader =
      blank != -1 &&
      header.length <= 3 &&
      header.every((l) => l.trim().length <= 100);

  String title;
  var author = '';
  List<String> body;
  if (looksLikeHeader) {
    title = header.first.trim();
    for (final line in header.skip(1)) {
      final match = RegExp(
        r'^(autor|author|słowa|muzyka)\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line.trim());
      if (match != null) author = match.group(2)!.trim();
    }
    body = lines.sublist(blank + 1);
  } else {
    title = _titleFromFileName(fileName) ?? lines.first.trim();
    body = lines;
  }
  title = title.replaceFirst(RegExp(r'^#+\s*'), '').trim();
  if (title.length > 200) title = title.substring(0, 200);
  if (title.isEmpty) return null;

  return ImportedSong(
    title: title,
    author: author,
    lyrics: _cleanLyrics(body),
    source: fileName,
  );
}

/// "Bo_jestes_dobry.txt" -> "Bo jestes dobry". Nazwy techniczne
/// ("_10.txt", "piosenka3.txt", "IMG_2024") nie nadają się na tytuł.
String? _titleFromFileName(String fileName) {
  var name = fileName.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot > 0) name = name.substring(0, dot);
  name = name.replaceAll(RegExp(r'[_]+'), ' ').trim();
  final letters = RegExp(r'\p{L}', unicode: true).allMatches(name).length;
  if (letters < 3 ||
      RegExp(
        r'^(piosenka|song|nowy|new|img|scan)\s*\d*$',
        caseSensitive: false,
      ).hasMatch(name)) {
    return null;
  }
  return name;
}

/// Najwyżej jedna pusta linia między zwrotkami, bez pustych linii na brzegach.
String _cleanLyrics(List<String> lines) {
  final out = <String>[];
  for (final line in lines) {
    if (line.trim().isEmpty && (out.isEmpty || out.last.isEmpty)) continue;
    out.add(line.trim().isEmpty ? '' : line);
  }
  while (out.isNotEmpty && out.last.isEmpty) {
    out.removeLast();
  }
  return out.join('\n');
}

/// Plik .sng z programu jWorship: zserializowany obiekt Javy sk.asc.worship.Song
/// z polami author, title, title2 i verses (java.util.Vector zwrotek).
ImportedSong? parseSng(Uint8List bytes, {required String fileName}) {
  final Object? root;
  try {
    root = _JavaReader(bytes).readRoot();
  } catch (_) {
    return null;
  }
  if (root is! _JavaObject) return null;
  final song = root;

  String text(String field) => (song.fields[field] as String? ?? '').trim();
  final verses = song.fields['verses'];
  final verseList = verses is _JavaObject
      ? (verses.fields['elementData'] as List<Object?>? ?? const []).take(
          verses.fields['elementCount'] as int? ?? 0,
        )
      : const <Object?>[];
  final lyrics = verseList
      .whereType<String>()
      .map((v) => v.trim())
      .where((v) => v.isNotEmpty)
      .join('\n\n');

  final title = text('title').isNotEmpty
      ? text('title')
      : _titleFromFileName(fileName) ??
            (lyrics.isEmpty ? '' : lyrics.split('\n').first.trim());
  if (title.isEmpty) return null;
  return ImportedSong(
    title: title.length > 200 ? title.substring(0, 200) : title,
    author: [
      text('author'),
      text('title2'),
    ].where((s) => s.isNotEmpty).join(' · '),
    lyrics: lyrics,
    source: fileName,
  );
}

class _JavaObject {
  _JavaObject(this.className);
  final String className;
  final fields = <String, Object?>{};
}

class _ClassDesc {
  _ClassDesc(this.name, this.flags, this.fields, this.superClass);
  final String name;
  final int flags;
  final List<({String type, String name})> fields;
  final _ClassDesc? superClass;
}

/// Minimalny czytnik formatu Java Object Serialization (wersja 5) -
/// wystarczający dla obiektów z napisami, liczbami, tablicami i Vectorem.
class _JavaReader {
  _JavaReader(this._bytes);

  final Uint8List _bytes;
  var _pos = 0;
  final _handles = <Object?>[];

  Object? readRoot() {
    if (_u16() != 0xACED || _u16() != 5) {
      throw const FormatException('nie .sng');
    }
    return _readContent();
  }

  int _u8() => _bytes[_pos++];
  int _u16() => (_u8() << 8) | _u8();
  int _i32() => (_u16() << 16) | _u16();
  String _utf(int length) {
    final s = utf8.decode(
      _bytes.sublist(_pos, _pos + length),
      allowMalformed: true,
    );
    _pos += length;
    return s;
  }

  Object? _readContent() {
    final tag = _u8();
    switch (tag) {
      case 0x70: // TC_NULL
        return null;
      case 0x71: // TC_REFERENCE
        return _handles[_i32() - 0x7E0000];
      case 0x74: // TC_STRING
        final s = _utf(_u16());
        _handles.add(s);
        return s;
      case 0x7C: // TC_LONGSTRING
        final high = _i32(), low = _i32();
        final s = _utf((high << 32) | low);
        _handles.add(s);
        return s;
      case 0x72: // TC_CLASSDESC
        _pos--;
        return _readClassDesc();
      case 0x73: // TC_OBJECT
        return _readObject();
      case 0x75: // TC_ARRAY
        return _readArray();
      default:
        throw FormatException(
          'nieobsługiwany znacznik 0x${tag.toRadixString(16)}',
        );
    }
  }

  _ClassDesc? _readClassDesc() {
    final tag = _u8();
    if (tag == 0x70) return null;
    if (tag == 0x71) return _handles[_i32() - 0x7E0000] as _ClassDesc?;
    if (tag != 0x72) throw const FormatException('oczekiwano opisu klasy');
    final name = _utf(_u16());
    _pos += 8; // serialVersionUID
    final handle = _handles.length;
    _handles.add(null);
    final flags = _u8();
    final fields = <({String type, String name})>[];
    for (var n = _u16(); n > 0; n--) {
      final type = String.fromCharCode(_u8());
      final fieldName = _utf(_u16());
      if (type == 'L' || type == '[') _readContent(); // sygnatura typu
      fields.add((type: type, name: fieldName));
    }
    _skipAnnotations();
    final desc = _ClassDesc(name, flags, fields, _readClassDesc());
    _handles[handle] = desc;
    return desc;
  }

  void _skipAnnotations() {
    while (true) {
      final tag = _bytes[_pos];
      if (tag == 0x78) {
        _pos++;
        return;
      }
      if (tag == 0x77) {
        _pos++;
        _pos += _u8();
      } else if (tag == 0x7A) {
        _pos++;
        _pos += _i32();
      } else {
        _readContent();
      }
    }
  }

  _JavaObject _readObject() {
    final desc = _readClassDesc()!;
    final object = _JavaObject(desc.name);
    _handles.add(object);
    // Najpierw pola klas nadrzędnych.
    final chain = <_ClassDesc>[];
    for (_ClassDesc? d = desc; d != null; d = d.superClass) {
      chain.insert(0, d);
    }
    for (final d in chain) {
      for (final field in d.fields) {
        object.fields[field.name] = _readValue(field.type);
      }
      if (d.flags & 0x01 != 0) _skipAnnotations(); // SC_WRITE_METHOD
    }
    return object;
  }

  List<Object?> _readArray() {
    final desc = _readClassDesc()!;
    final list = <Object?>[];
    _handles.add(list);
    final type = desc.name.length > 1 ? desc.name[1] : 'L';
    for (var n = _i32(); n > 0; n--) {
      list.add(_readValue(type));
    }
    return list;
  }

  Object? _readValue(String type) {
    switch (type) {
      case 'B' || 'Z':
        return _u8();
      case 'C' || 'S':
        return _u16();
      case 'I' || 'F':
        return _i32();
      case 'J' || 'D':
        final high = _i32(), low = _i32();
        return (high << 32) | low;
      default:
        return _readContent();
    }
  }
}
