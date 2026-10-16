import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:song_viewer/data/repository.dart';
import 'package:song_viewer/messages.dart';
import 'package:song_viewer/song.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:song_viewer/song_edit_screen.dart';
import 'package:song_viewer/preferences.dart';

void main() {
  test('Song.fromMap and preview skipping the title line', () {
    final song = Song.fromMap('s1', {
      'title': 'Cicha noc',
      'lyrics':
          'Cicha noc, święta noc,\nPokój niesie ludziom wszem\n\nZwrotka 2',
    });
    expect(song.id, 's1');
    expect(song.author, '');
    expect(song.updatedAt, isNull);
    expect(song.firstLine, 'Cicha noc, święta noc,');
    expect(song.preview, 'Pokój niesie ludziom wszem');
  });

  test('Polish sort order and search folding', () {
    final titles = [
      'Bóg',
      'Ą',
      'Azz',
      'Łaska',
      'Lud',
      '! Części',
      'Cud',
      'Ćma',
    ];
    titles.sort((a, b) => polishSortKey(a).compareTo(polishSortKey(b)));
    expect(titles, [
      'Azz',
      'Ą',
      'Bóg',
      'Cud',
      '! Części',
      'Ćma',
      'Lud',
      'Łaska',
    ]);
    expect(foldPolish('Zmiłuj SIĘ'), 'zmiluj sie');
  });

  group('Repository', () {
    late FakeFirebaseFirestore db;
    late MockUser user;
    late Repository repo;

    setUp(() async {
      db = FakeFirebaseFirestore();
      user = MockUser(uid: 'ala', email: 'ala@example.com', displayName: 'Ala');
      final auth = MockFirebaseAuth(mockUser: user, signedIn: true);
      repo = Repository(firestore: db, auth: auth);
    });

    test('creates "Mój śpiewnik" once', () async {
      await repo.ensureUserSetup(user);
      await repo.ensureUserSetup(user);
      final team = await db.doc('teams/personal_ala').get();
      expect(team.data()!['name'], 'Mój śpiewnik');
      expect(team.data()!['personal'], true);
      expect(team.data()!['roles'], {'ala': 'owner'});
      expect(team.data()!['memberIds'], ['ala']);
      expect((await db.collection('teams').get()).docs, hasLength(1));
      expect((await db.doc('users/ala').get()).data()!['displayName'], 'Ala');
    });

    test('save, edit with history, delete', () async {
      const team = 'personal_ala';
      await repo.saveSong(
        team,
        title: 'Barka',
        author: '',
        lyrics: 'Pan kiedyś',
      );
      var songs = await repo.songs(team).first;
      expect(songs.single.title, 'Barka');
      expect(songs.single.updatedBy, 'ala');

      await repo.saveSong(
        team,
        original: songs.single,
        title: 'Barka',
        author: 'ks. S. Gabarain',
        lyrics: 'Pan kiedyś stanął nad brzegiem',
      );
      songs = await repo.songs(team).first;
      expect(songs.single.author, 'ks. S. Gabarain');
      final history = await db
          .collection('teams/$team/songs/${songs.single.id}/revisions')
          .get();
      expect(history.docs.single.data()['lyrics'], 'Pan kiedyś');

      await repo.deleteSong(team, songs.single);
      expect(await repo.songs(team).first, isEmpty);
    });

    test('songs are sorted by Polish alphabet', () async {
      for (final t in ['Łaska', 'Lud', 'Ćma', 'Cud']) {
        await repo.saveSong('t', title: t, author: '', lyrics: '');
      }
      final songs = await repo.songs('t').first;
      expect(songs.map((s) => s.title), ['Cud', 'Ćma', 'Lud', 'Łaska']);
    });

    testWidgets('edit screen validates title and saves a new song', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SongEditScreen(repository: repo, teamId: 't'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Zapisz'));
      await tester.pump();
      expect(find.text('Tytuł jest wymagany'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tytuł'),
        'Abba Ojcze',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Tekst'),
        'Ty wyzwoliłeś nas Panie',
      );
      await tester.tap(find.text('Zapisz'));
      await tester.pumpAndSettle();

      expect(
        find.text('open'),
        findsOneWidget,
        reason: 'ekran edycji się zamknął',
      );
      final songs = await repo.songs('t').first;
      expect(songs.single.title, 'Abba Ojcze');
      expect(songs.single.lyrics, 'Ty wyzwoliłeś nas Panie');
    });
  });

  testWidgets('motyw i rozmiar tekstu są zapamiętywane', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await setThemeMode(ThemeMode.dark);
    await changeLyricsFontSize(4);
    await changeLyricsFontSize(100); // nie więcej niż maksimum
    // "Ponowne uruchomienie": wartości w pamięci wracają do domyślnych...
    themeMode.value = ThemeMode.system;
    lyricsFontSize.value = 20;
    // ...i są wczytywane z urządzenia.
    await loadPreferences();
    expect(themeMode.value, ThemeMode.dark);
    expect(lyricsFontSize.value, maxLyricsFontSize);

    SharedPreferences.setMockInitialValues({});
    await loadPreferences();
    expect(themeMode.value, ThemeMode.system);
    expect(lyricsFontSize.value, 20);
  });
}
