import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:song_viewer/data/repository.dart';
import 'package:song_viewer/home/all_songs.dart';
import 'package:song_viewer/models.dart';

void main() {
  late FakeFirebaseFirestore db;
  late Repository ala;

  setUp(() async {
    db = FakeFirebaseFirestore();
    final user = MockUser(
      uid: 'ala',
      displayName: 'Ala',
      email: 'ala@example.test',
    );
    ala = Repository(
      firestore: db,
      auth: MockFirebaseAuth(signedIn: true, mockUser: user),
    );
    await ala.ensureUserSetup(user);
  });

  test('Mój śpiewnik: moje + zespołów, bez powtórek, z etykietami', () async {
    final schola = await ala.createTeam('Schola');
    final zespol = await ala.createTeam('Zespół');
    await ala.saveSong(
      'personal_ala',
      title: 'Barka',
      author: '',
      lyrics: 'moja',
    );
    // Ta sama piosenka skopiowana do zespołu - nie może się powtórzyć.
    await ala.saveSong(schola, title: 'Barka', author: '', lyrics: 'zespołu');
    await ala.saveSong(schola, title: 'Cicha noc', author: '', lyrics: '');
    await ala.saveSong(zespol, title: 'cicha noc!', author: '', lyrics: '');
    await ala.saveSong(zespol, title: 'Abba Ojcze', author: '', lyrics: '');

    final subscription = ala.watchTeams().listen((_) {});
    final all = AllSongs(ala);
    await pumpEventQueue();

    final byTitle = {for (final e in all.entries) e.song.title: e};
    expect(byTitle.keys, ['Abba Ojcze', 'Barka', 'Cicha noc']);
    // Barka: moja wersja, z etykietą zespołu, w którym też jest.
    expect(byTitle['Barka']!.teamId, 'personal_ala');
    expect(byTitle['Barka']!.song.lyrics, 'moja');
    expect(byTitle['Barka']!.teamIds, [schola]);
    // Cicha noc tylko w zespołach - jedna pozycja, oba zespoły w etykietach.
    expect(byTitle['Cicha noc']!.teamIds.toSet(), {schola, zespol});
    expect(all.songsOf(zespol), hasLength(2));

    all.dispose();
    await subscription.cancel();
  });

  test('obecność: zapis i odczyt, aktywny tylko świeży i online', () async {
    await ala.setPresence(online: true);
    final presence = await ala.presence(['ala', 'nieznany']).first;
    expect(presence.keys, ['ala']);
    expect(presence['ala']!.online, isTrue);

    expect(Presence(online: true, lastActive: DateTime.now()).isActive, isTrue);
    expect(
      Presence(
        online: true,
        lastActive: DateTime.now().subtract(const Duration(minutes: 10)),
      ).isActive,
      isFalse,
      reason: 'aplikacja zamknięta bez pożegnania',
    );
    expect(
      Presence(online: false, lastActive: DateTime.now()).isActive,
      isFalse,
    );
  });
}
