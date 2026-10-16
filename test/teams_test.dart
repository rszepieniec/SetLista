import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:song_viewer/data/repository.dart';
import 'package:song_viewer/grammar.dart';
import 'package:song_viewer/import/song_import.dart';
import 'package:song_viewer/models.dart';

/// Dwie osoby (Ala i Bartek) na tej samej, wspólnej bazie.
void main() {
  late FakeFirebaseFirestore db;
  late Repository ala;
  late Repository bartek;

  Repository signedIn(String uid, String name) => Repository(
    firestore: db,
    auth: MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(
        uid: uid,
        displayName: name,
        email: '$uid@example.test',
      ),
    ),
  );

  setUp(() async {
    db = FakeFirebaseFirestore();
    ala = signedIn('ala', 'Ala');
    bartek = signedIn('bartek', 'Bartek');
  });

  /// Wiadomości zespołu bez początkowego "utworzył zespół".
  Future<List<ChatMessage>> chat(Repository repo, String teamId) async => [
    for (final m in await repo.messages(teamId).first)
      if (m.type != MessageType.teamCreated) m,
  ];

  Future<Team> createBand() async {
    final id = await ala.createTeam('Schola');
    await ala.watchTeams().first;
    return ala.team(id)!;
  }

  test('nowy zespół: Ala jest właścicielem', () async {
    final team = await createBand();
    expect(team.name, 'Schola');
    expect(team.personal, isFalse);
    expect(team.isOwner('ala'), isTrue);
    expect(team.nameOf('ala'), 'Ala');
  });

  test(
    'zaproszenie i dołączenie kodem (z myślnikiem i małymi literami)',
    () async {
      final team = await createBand();
      final code = await ala.createInvite(team);
      expect(code, hasLength(8));
      expect(code.split('').every(inviteAlphabet.contains), isTrue);

      final joined = await bartek.joinTeam(
        formatInviteCode(code).toLowerCase(),
      );
      expect(joined, team.id);

      final teams = await bartek.watchTeams().first;
      final band = teams.single;
      expect(band.roleOf('bartek'), 'editor');
      expect(band.nameOf('bartek'), 'Bartek');
      final join = await db.doc('teams/${team.id}/joins/bartek').get();
      expect(join.data()!['code'], code);
    },
  );

  test('zły i wygasły kod dają czytelny błąd', () async {
    final team = await createBand();
    await expectLater(
      bartek.joinTeam('ZZZZ-ZZZZ'),
      throwsA(isA<UserFacingException>()),
    );
    await expectLater(
      bartek.joinTeam('ABC'),
      throwsA(isA<UserFacingException>()),
    );

    final code = await ala.createInvite(team);
    await db.doc('invites/$code').update({
      'expiresAt': DateTime.now().subtract(const Duration(days: 1)),
    });
    await expectLater(
      bartek.joinTeam(code),
      throwsA(
        isA<UserFacingException>().having(
          (e) => e.message,
          'message',
          contains('wygasło'),
        ),
      ),
    );
  });

  test('opuszczenie zespołu i zmiana roli przez właściciela', () async {
    final team = await createBand();
    await bartek.joinTeam(await ala.createInvite(team));
    await ala.watchTeams().first;

    await ala.setRole(ala.team(team.id)!, 'bartek', 'member');
    await ala.watchTeams().first;
    expect(ala.team(team.id)!.canEdit('bartek'), isFalse);

    await bartek.watchTeams().first;
    await bartek.leaveTeam(bartek.team(team.id)!);
    expect(await bartek.watchTeams().first, isEmpty);
    final after = (await ala.watchTeams().first).single;
    expect(after.memberIds, ['ala']);
    expect(after.roles.containsKey('bartek'), isFalse);
  });

  test('playlista: tworzenie, kolejność, data', () async {
    const team = 'personal_ala';
    final id = ala.newPlaylistId(team);
    await ala.createPlaylist(team, id, name: 'Niedziela', songIds: ['a', 'b']);
    await ala.updatePlaylist(
      team,
      id,
      songIds: ['b', 'a'],
      date: DateTime(2026, 10, 12),
    );

    final playlist = (await ala.playlist(team, id).first)!;
    expect(playlist.name, 'Niedziela');
    expect(playlist.songIds, ['b', 'a']);
    expect(playlist.date, DateTime(2026, 10, 12));
    expect(playlist.createdBy, 'ala');

    await ala.updatePlaylist(team, id, clearDate: true);
    expect((await ala.playlist(team, id).first)!.date, isNull);
  });

  test(
    'udostępnienie playlisty kopiuje tylko brakujące piosenki i pisze na czacie',
    () async {
      final band = await createBand();
      const mine = 'personal_ala';
      await ala.saveSong(
        mine,
        title: 'Barka',
        author: '',
        lyrics: 'Pan kiedyś',
      );
      await ala.saveSong(
        mine,
        title: 'Abba Ojcze',
        author: '',
        lyrics: 'Ty wyzwoliłeś',
      );
      // "barka!" w zespole to ta sama piosenka co "Barka" (porównanie bez wielkości liter i znaków).
      await ala.saveSong(
        band.id,
        title: 'barka!',
        author: '',
        lyrics: 'wersja zespołu',
      );

      final songs = {for (final s in await ala.songs(mine).first) s.id: s};
      final id = ala.newPlaylistId(mine);
      await ala.createPlaylist(
        mine,
        id,
        name: 'Próba',
        songIds: songs.keys.toList(),
      );
      final playlist = (await ala.playlist(mine, id).first)!;

      final copied = await ala.sharePlaylist(playlist, songs, band);
      expect(copied, 1);

      final bandSongs = await ala.songs(band.id).first;
      expect(bandSongs.map((s) => s.title), ['Abba Ojcze', 'barka!']);
      final shared = (await ala.playlists(band.id).first).single;
      expect(shared.name, 'Próba');
      expect(shared.songIds.toSet(), bandSongs.map((s) => s.id).toSet());

      final messages = await chat(ala, band.id);
      final message = messages.firstWhere((m) => m.type == MessageType.setlist);
      expect(message.playlistId, shared.id);
      expect(message.text, contains('Próba'));
    },
  );

  test('kopiowanie i przenoszenie piosenki między śpiewnikami', () async {
    final band = await createBand();
    const mine = 'personal_ala';
    await ala.saveSong(mine, title: 'Barka', author: '', lyrics: 'Pan kiedyś');
    final song = (await ala.songs(mine).first).single;

    expect(await ala.copySong(mine, song, band.id), isTrue);
    await pumpEventQueue();
    expect((await ala.songs(band.id).first).single.title, 'Barka');
    expect(await ala.songs(mine).first, hasLength(1));
    // Druga kopia tej samej piosenki nie powstaje.
    expect(await ala.copySong(mine, song, band.id), isFalse);

    await ala.saveSong(mine, title: 'Cicha noc', author: '', lyrics: '');
    final silentNight = (await ala.songs(mine).first).firstWhere(
      (s) => s.title == 'Cicha noc',
    );
    expect(await ala.copySong(mine, silentNight, band.id, move: true), isTrue);
    await pumpEventQueue();
    expect((await ala.songs(mine).first).map((s) => s.title), ['Barka']);
    expect(await ala.songs(band.id).first, hasLength(2));
  });

  test('czat: najnowsze wiadomości pierwsze, autor z imieniem', () async {
    final band = await createBand();
    await ala.sendMessage(band.id, 'Próba o 18');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await ala.sendMessage(band.id, 'Weźcie śpiewniki');

    final messages = await chat(ala, band.id);
    expect(messages.map((m) => m.text), ['Weźcie śpiewniki', 'Próba o 18']);
    expect(messages.first.authorName, 'Ala');

    await ala.deleteMessage(band.id, messages.first.id);
    expect((await chat(ala, band.id)).single.text, 'Próba o 18');
  });

  test('kod zaproszenia: formatowanie i normalizacja', () {
    expect(formatInviteCode('ABCD2345'), 'ABCD-2345');
    expect(normalizeInviteCode(' abcd-2345 '), 'ABCD2345');
  });

  group('zdarzenia na czacie', () {
    test(
      'nowa i zmieniona piosenka w zespole; w Moim śpiewniku bez czatu',
      () async {
        final band = await createBand();
        await ala.saveSong(band.id, title: 'Barka', author: '', lyrics: 'a');
        final song = (await ala.songs(band.id).first).single;
        await ala.saveSong(
          band.id,
          original: song,
          title: 'Barka',
          author: 'X',
          lyrics: 'b',
        );
        await ala.saveSong(
          'personal_ala',
          title: 'Prywatna',
          author: '',
          lyrics: '',
        );

        final events = await chat(ala, band.id);
        expect(events.map((m) => m.type), [
          MessageType.songUpdated,
          MessageType.songAdded,
        ]);
        expect(events.every((m) => m.songId == song.id), isTrue);
        expect(events.first.text, 'zmienił(a) piosenkę „Barka”');
        expect(events.first.subject, 'Barka');
        expect(
          await db
              .collection('teams/personal_ala/messages')
              .get()
              .then((s) => s.docs),
          isEmpty,
        );
      },
    );

    test('import wielu piosenek to jedna wiadomość', () async {
      final band = await createBand();
      final ids = await ala.importSongs(band.id, [
        for (var i = 1; i <= 25; i++)
          ImportedSong(title: 'Piosenka $i', lyrics: 'tekst', source: '$i.txt'),
      ]);
      expect(ids, hasLength(25));
      expect(await ala.songs(band.id).first, hasLength(25));
      final event = (await chat(ala, band.id)).single;
      expect(event.type, MessageType.songsImported);
      expect(event.count, 25);
      expect(event.text, 'dodał(a) 25 piosenek do śpiewnika zespołu');
    });

    test('nowa setlista w zespole pojawia się na czacie', () async {
      final band = await createBand();
      final id = ala.newPlaylistId(band.id);
      await ala.createPlaylist(band.id, id, name: 'Niedziela');
      final event = (await chat(ala, band.id)).single;
      expect(event.type, MessageType.setlist);
      expect(event.playlistId, id);
      expect(event.text, 'udostępnił(a) setlistę „Niedziela”');
    });
  });

  test('kopiowanie z Mojego śpiewnika: bez duplikatów, mapa id', () async {
    final band = await createBand();
    const mine = 'personal_ala';
    await ala.saveSong(mine, title: 'Barka', author: '', lyrics: 'moja');
    await ala.saveSong(mine, title: 'Cicha noc', author: '', lyrics: '');
    await ala.saveSong(band.id, title: 'BARKA', author: '', lyrics: 'zespołu');
    final personal = await ala.songs(mine).first;
    final bandBarka = (await ala.songs(band.id).first).single;

    final ids = await ala.copySongsToTeam(personal, band.id);
    final bandSongs = await ala.songs(band.id).first;
    expect(bandSongs.map((s) => s.title), ['BARKA', 'Cicha noc']);
    final barka = personal.firstWhere((s) => s.title == 'Barka');
    final silentNight = personal.firstWhere((s) => s.title == 'Cicha noc');
    expect(ids[barka.id], bandBarka.id);
    expect(ids[silentNight.id], bandSongs.last.id);
  });

  test('komentarze: dodanie, wiadomość na czacie, usunięcie', () async {
    final band = await createBand();
    await ala.saveSong(band.id, title: 'Barka', author: '', lyrics: '');
    final song = (await ala.songs(band.id).first).single;

    await ala.addComment(band.id, song, 'Zaczynamy od refrenu');
    final comments = await ala.comments(band.id, song.id).first;
    expect(comments.single.text, 'Zaczynamy od refrenu');
    expect(comments.single.authorName, 'Ala');
    final event = (await ala.messages(band.id).first).first;
    expect(event.type, MessageType.comment);
    expect(event.text, 'Zaczynamy od refrenu');
    expect(
      describeEvent(event, mine: true),
      'skomentowałeś(-aś) „Barka”: Zaczynamy od refrenu',
    );

    await ala.deleteComment(band.id, song.id, comments.single.id);
    expect(await ala.comments(band.id, song.id).first, isEmpty);
  });

  test('przeczytane wiadomości (lastSeen)', () async {
    final band = await createBand();
    expect(await ala.lastSeen().first, isEmpty);
    await ala.markSeen(band.id);
    final seen = await ala.lastSeen().first;
    expect(seen.keys, [band.id]);
  });

  group('odmiana (zawsze neutralna)', () {
    test('czas przeszły: "dodał(a)", do mnie "dodałeś(-aś)"', () {
      expect(pastTense('dodał', you: false), 'dodał(a)');
      expect(pastTense('dodał', you: true), 'dodałeś(-aś)');
      expect(youDid('dołączył', 'do zespołu'), 'Dołączyłeś(-aś) do zespołu');
    });

    test('zdarzenie: Ty dodałeś(-aś) / Ala dodał(a)', () async {
      final band = await createBand();
      await ala.saveSong(band.id, title: 'Barka', author: '', lyrics: '');
      final event = (await chat(ala, band.id)).single;
      expect(event.legacy, isFalse);
      expect(
        eventSentence(event, mine: false),
        'Ala dodał(a) piosenkę „Barka”',
      );
      expect(
        eventSentence(event, mine: true),
        'Ty dodałeś(-aś) piosenkę „Barka”',
      );
    });

    test('utworzenie, dołączenie i wyjście są na czacie', () async {
      final team = await createBand();
      await bartek.joinTeam(await ala.createInvite(team));
      await bartek.watchTeams().first;
      await bartek.leaveTeam(bartek.team(team.id)!);

      final all = (await ala.messages(team.id).first).reversed.toList();
      expect(all.map((m) => eventSentence(m, mine: false)), [
        'Ala utworzył(a) zespół „Schola”',
        'Bartek dołączył(a) do zespołu',
        'Bartek opuścił(a) zespół',
      ]);
    });

    test('stare wiadomości (bez formy) też w czasie przeszłym', () {
      final old = ChatMessage(
        id: 'x',
        text: 'dodaje piosenkę „Barka”',
        authorId: 'a',
        authorName: 'Adam',
        type: MessageType.songAdded,
        legacy: true,
      );
      expect(eventSentence(old, mine: false), 'Adam dodał(a) piosenkę „Barka”');
      final oldComment = ChatMessage(
        id: 'y',
        text: 'komentuje „Barka”: Od refrenu',
        authorId: 'a',
        authorName: 'Adam',
        type: MessageType.comment,
        legacy: true,
      );
      expect(
        eventSentence(oldComment, mine: false),
        'Adam skomentował(a) „Barka”: Od refrenu',
      );
      final oldSetlist = ChatMessage(
        id: 'z',
        text: 'udostępnia setlistę „Niedziela” (3 piosenki)',
        authorId: 'a',
        authorName: 'Adam',
        type: MessageType.setlist,
        legacy: true,
      );
      expect(
        eventSentence(oldSetlist, mine: true),
        'Ty udostępniłeś(-aś) setlistę „Niedziela” (3 piosenki)',
      );
    });
  });

  test('zmiana nazwy zespołu - też na czacie', () async {
    final team = await createBand();
    await ala.renameTeam(team, 'Schola Cantorum');
    final renamed = (await ala.watchTeams().first).firstWhere(
      (t) => t.id == team.id,
    );
    expect(renamed.name, 'Schola Cantorum');
    final event = (await chat(ala, team.id)).single;
    expect(event.type, MessageType.teamRenamed);
    expect(
      eventSentence(event, mine: true),
      'Ty zmieniłeś(-aś) nazwę zespołu na „Schola Cantorum”',
    );
  });

  test(
    'zmiana imienia: konto, profil i listy członków wszystkich zespołów',
    () async {
      final team = await createBand();
      await bartek.joinTeam(await ala.createInvite(team));
      await bartek.watchTeams().first;

      await bartek.updateMyName('Bartosz');
      final updated = (await ala.watchTeams().first).firstWhere(
        (t) => t.id == team.id,
      );
      expect(updated.nameOf('bartek'), 'Bartosz');
      expect(updated.nameOf('ala'), 'Ala');
      expect(
        (await db.doc('users/bartek').get()).data()!['displayName'],
        'Bartosz',
      );
      // Nowe wiadomości są już z nowym imieniem.
      await bartek.sendMessage(team.id, 'Cześć');
      expect(
        (await bartek.messages(team.id).first).first.authorName,
        'Bartosz',
      );
    },
  );
}
