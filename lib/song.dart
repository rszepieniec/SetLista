import 'package:cloud_firestore/cloud_firestore.dart';

class Song {
  Song({
    required this.id,
    required this.title,
    required this.lyrics,
    this.author = '',
    this.updatedAt,
    this.updatedBy,
  });

  final String id;
  final String title;
  final String author;
  final String lyrics;
  final DateTime? updatedAt;
  final String? updatedBy;

  factory Song.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      Song.fromMap(doc.id, doc.data() ?? const {});

  factory Song.fromMap(String id, Map<String, dynamic> data) => Song(
    id: id,
    title: data['title'] as String? ?? '',
    author: data['author'] as String? ?? '',
    lyrics: data['lyrics'] as String? ?? '',
    // Świeżo zapisana piosenka ma tu null, dopóki serwer nie nada czasu.
    updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    updatedBy: data['updatedBy'] as String?,
  );

  /// Tytuł + tekst bez polskich znaków, do wyszukiwania ("zmiluj" znajdzie "zmiłuj").
  late final String searchKey = foldPolish('$title\n$author\n$lyrics');
  late final String sortKey = polishSortKey(title);

  String get firstLine => lyrics
      .split('\n')
      .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
      .trim();

  /// Podgląd na liście: pierwsza linia tekstu, która nie powtarza tytułu.
  String get preview {
    final titleKey = _letters(title);
    return lyrics
        .split('\n')
        .map((l) => l.trim())
        .firstWhere(
          (l) => l.isNotEmpty && !_letters(l).startsWith(titleKey),
          orElse: () => firstLine,
        );
  }

  static String _letters(String s) =>
      foldPolish(s).replaceAll(RegExp(r'[^a-z0-9]'), '');
}

const _polish = 'ąćęłńóśźż';
const _latin = 'acelnoszz';

String foldPolish(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = _polish.indexOf(ch);
    out.write(i == -1 ? ch : _latin[i]);
  }
  return out.toString();
}

/// Klucz sortowania wg polskiego alfabetu: "ą" -> "a~" ląduje po wszystkich
/// "a..." a przed "b", bo '~' jest w ASCII za literami.
/// Pomija wiodące znaki interpunkcyjne (np. "! Części stałe", "\"Hosanna\"").
String polishSortKey(String title) {
  final trimmed = title.toLowerCase().replaceFirst(
    RegExp(r'^[^\p{L}\p{N}]+', unicode: true),
    '',
  );
  final out = StringBuffer();
  for (final ch in trimmed.split('')) {
    final i = _polish.indexOf(ch);
    out.write(i == -1 ? ch : '${_latin[i]}~');
  }
  return out.toString();
}
