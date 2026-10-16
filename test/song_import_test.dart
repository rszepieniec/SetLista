import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:song_viewer/import/song_import.dart';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  test('format SetListy: tytuł, autor, zwrotki', () {
    final song = parseSongText(
      'Barka\nAutor: ks. S. Gabarain\n\nPan kiedyś stanął\n\n\n\nO Panie',
      fileName: 'cokolwiek.txt',
    )!;
    expect(song.title, 'Barka');
    expect(song.author, 'ks. S. Gabarain');
    expect(song.lyrics, 'Pan kiedyś stanął\n\nO Panie');
  });

  test('sam tekst bez tytułu - tytuł z nazwy pliku', () {
    final song = parseSongText(
      'Zawsze wierny byłeś mi\nKiedy zawodziłem ja\nNiepojęty w miłości\nTyś jest dobry',
      fileName: 'Bo_jestes_dobry.txt',
    )!;
    expect(song.title, 'Bo jestes dobry');
    expect(song.lyrics, startsWith('Zawsze wierny'));
  });

  test('techniczna nazwa pliku - tytuł z pierwszej linii', () {
    final song = parseSongText(
      'Abba Ojcze\nTy wyzwoliłeś nas Panie\nz kajdan i samych siebie\na Chrystus stał się bratem',
      fileName: 'piosenka3.txt',
    )!;
    expect(song.title, 'Abba Ojcze');
  });

  test('Markdown i pusty plik', () {
    expect(
      parseSongText('# Cicha noc\n\nŚwięta noc', fileName: 'a.md')!.title,
      'Cicha noc',
    );
    expect(parseSongText('  \n\n ', fileName: 'pusty.txt'), isNull);
  });

  test('kodowania: UTF-8 z BOM, Windows-1250, UTF-16', () {
    expect(
      decodeText(
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Łąka')]),
      ),
      'Łąka',
    );
    // "Zażółć" w Windows-1250
    expect(
      decodeText(Uint8List.fromList([0x5A, 0x61, 0xBF, 0xF3, 0xB3, 0xE6])),
      'Zażółć',
    );
    expect(
      decodeText(Uint8List.fromList([0xFF, 0xFE, 0x41, 0x00, 0x05, 0x01])),
      'Aą',
    );
  });

  test('zip z folderem: pomija śmieci, zgłasza nieobsługiwane pliki', () {
    final archive = Archive()
      ..add(
        ArchiveFile.bytes('piosenki/Barka.txt', bytes('Barka\n\nPan kiedyś')),
      )
      ..add(ArchiveFile.bytes('piosenki/.DS_Store', bytes('x')))
      ..add(ArchiveFile.bytes('__MACOSX/piosenki/._Barka.txt', bytes('x')))
      ..add(ArchiveFile.bytes('piosenki/okladka.jpg', bytes('x')));
    final zip = Uint8List.fromList(ZipEncoder().encode(archive));
    final result = parseFiles([(name: 'spiewnik.zip', bytes: zip)]);
    expect(result.songs.map((s) => s.title), ['Barka']);
    expect(result.skipped, ['okladka.jpg']);
  });

  // Prawdziwe pliki z jWorship (jeśli są na dysku obok projektu).
  final jworship = Directory('../jWorship_calosc/songs');
  test('wszystkie pliki .sng z jWorship', () {
    final files = jworship
        .listSync()
        .whereType<File>()
        // Pliki zaczynające się od kropki (np. ".sng") import pomija jak systemowe.
        .where(
          (f) =>
              f.path.endsWith('.sng') &&
              !f.uri.pathSegments.last.startsWith('.'),
        )
        .toList();
    final result = parseFiles([
      for (final f in files)
        (name: f.uri.pathSegments.last, bytes: f.readAsBytesSync()),
    ]);
    // _9.sng to całkiem pusta piosenka (bez tytułu i zwrotek) - słusznie pominięta.
    expect(result.skipped, ['_9.sng']);
    expect(result.songs, hasLength(files.length - 1));
    final silentNight = result.songs.firstWhere((s) => s.title == 'Cicha noc');
    expect(silentNight.lyrics, contains('Cicha noc, święta noc'));
    final barka = result.songs.where(
      (s) => s.title.toLowerCase().contains('bo jesteś dobry'),
    );
    expect(barka.single.lyrics, contains('Zawsze wierny byłeś mi'));
  }, skip: jworship.existsSync() ? false : 'brak folderu jWorship_calosc');
}
