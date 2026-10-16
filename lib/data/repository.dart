import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../debug_log.dart';
import '../grammar.dart';
import '../import/song_import.dart';
import '../models.dart';
import '../song.dart';

/// Błąd, który można pokazać użytkownikowi wprost.
class UserFacingException implements Exception {
  UserFacingException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Dostęp do Firestore. Struktura danych i uprawnienia: firestore.rules.
///
/// Zapisy piosenek, playlist i wiadomości nie czekają na serwer - przy braku
/// internetu Firestore trzyma je w kolejce i wysyła później, a lokalna kopia
/// zmienia się od razu. Operacje na zespołach (tworzenie, zaproszenia,
/// dołączanie) wymagają internetu.
class Repository {
  Repository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Zespoły zalogowanej osoby, "Mój śpiewnik" na początku. Uzupełnia [watchTeams].
  final teams = ValueNotifier<List<Team>>(const []);

  static String personalTeamId(String uid) => 'personal_$uid';

  String get uid => _auth.currentUser!.uid;
  String get _displayName => _auth.currentUser?.displayName ?? '';

  Team? team(String teamId) {
    for (final t in teams.value) {
      if (t.id == teamId) return t;
    }
    return null;
  }

  bool canEdit(String teamId) => team(teamId)?.canEdit(uid) ?? false;

  DocumentReference<Map<String, dynamic>> _team(String teamId) =>
      _db.collection('teams').doc(teamId);

  CollectionReference<Map<String, dynamic>> _songs(String teamId) =>
      _team(teamId).collection('songs');

  CollectionReference<Map<String, dynamic>> _playlists(String teamId) =>
      _team(teamId).collection('playlists');

  CollectionReference<Map<String, dynamic>> _messages(String teamId) =>
      _team(teamId).collection('messages');

  // ---------------------------------------------------------------- konto

  /// Przy logowaniu: profil użytkownika i "Mój śpiewnik", jeśli go jeszcze nie ma.
  Future<void> ensureUserSetup(User user) async {
    final profile = _db.collection('users').doc(user.uid);
    unawaited(
      traced(
        'set ${profile.path} (merge)',
        () => profile.set({
          'displayName': user.displayName ?? '',
          'email': user.email ?? '',
        }, SetOptions(merge: true)),
      ).catchError((Object _) {}),
    );

    final team = _team(personalTeamId(user.uid));
    bool exists;
    try {
      final snapshot = await traced(
        'get ${team.path}',
        team.get,
        describe: (s) =>
            'exists=${s.exists}, fromCache=${s.metadata.isFromCache}',
      );
      exists = snapshot.exists;
    } on FirebaseException {
      // Offline i brak kopii w pamięci - zakładamy, że to pierwsze logowanie.
      exists = false;
    }
    if (exists) return;

    await _waitIfOnline(
      traced(
        'set ${team.path} (nowy "Mój śpiewnik")',
        () => team.set(
          _newTeamData('Mój śpiewnik', user.uid, user.displayName ?? '', true),
        ),
      ),
    );
  }

  Map<String, dynamic> _newTeamData(
    String name,
    String ownerId,
    String ownerName,
    bool personal,
  ) => {
    'name': name,
    'ownerId': ownerId,
    'personal': personal,
    'roles': {ownerId: 'owner'},
    'memberIds': [ownerId],
    if (ownerName.isNotEmpty) 'memberNames': {ownerId: ownerName},
    'createdAt': FieldValue.serverTimestamp(),
  };

  /// Czeka na potwierdzenie zapisu, ale najwyżej kilka sekund - offline zapis
  /// zostaje w kolejce i zostanie wysłany, gdy wróci internet.
  Future<void> _waitIfOnline(Future<void> write) async {
    try {
      // Online czekamy, bo reguły wpuszczą do podkolekcji dopiero po zapisie zespołu.
      await write.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      logFirebase('  (brak odpowiedzi po 8 s - zapis czeka w kolejce offline)');
    }
  }

  /// Operacje, które bez internetu nie mają sensu (zaproszenia, dołączanie).
  Future<T> _requireOnline<T>(Future<T> future) => future.timeout(
    const Duration(seconds: 12),
    onTimeout: () => throw UserFacingException(
      'Brak połączenia z serwerem. Sprawdź internet i spróbuj ponownie.',
    ),
  );

  // ---------------------------------------------------------------- zespoły

  /// Nasłuch zespołów, do których należy zalogowana osoba; aktualizuje [teams].
  Stream<List<Team>> watchTeams() {
    final query = _db
        .collection('teams')
        .where('memberIds', arrayContains: uid);
    return tracedStream(
      'teams (memberIds zawiera mnie)',
      query.snapshots(),
      describe: (s) =>
          '${s.docs.length} zespołów, fromCache=${s.metadata.isFromCache}',
    ).map((snapshot) {
      final list = snapshot.docs.map(Team.fromDoc).toList()
        ..sort((a, b) {
          if (a.personal != b.personal) return a.personal ? -1 : 1;
          return polishSortKey(a.name).compareTo(polishSortKey(b.name));
        });
      teams.value = list;
      return list;
    });
  }

  Future<String> createTeam(String name) async {
    final ref = _db.collection('teams').doc();
    final batch = _db.batch()
      ..set(ref, _newTeamData(name, uid, _displayName, false));
    _addEvent(batch, ref.id, MessageType.teamCreated, subject: name);
    await _waitIfOnline(traced('create ${ref.path} ("$name")', batch.commit));
    return ref.id;
  }

  Future<void> renameTeam(Team team, String name) {
    final batch = _db.batch()..update(_team(team.id), {'name': name});
    _addEvent(batch, team.id, MessageType.teamRenamed, subject: name);
    return traced('update ${_team(team.id).path} name="$name"', batch.commit);
  }

  /// Zmienia moje imię: w koncie, w profilu i na listach członków wszystkich
  /// moich zespołów. Stare wiadomości zostają z dawnym imieniem.
  Future<void> updateMyName(String name) async {
    final user = _auth.currentUser!;
    await _requireOnline(
      traced('auth: updateDisplayName("$name")', () async {
        await user.updateDisplayName(name);
        await user.reload();
      }),
    );
    final batch = _db.batch()
      ..set(_db.collection('users').doc(uid), {
        'displayName': name,
      }, SetOptions(merge: true));
    for (final team in teams.value) {
      batch.update(_team(team.id), {'memberNames.$uid': name});
    }
    await _waitIfOnline(
      traced(
        'update memberNames.$uid w ${teams.value.length} zespołach',
        batch.commit,
      ),
    );
  }

  Future<void> deleteTeam(Team team) => _requireOnline(
    traced('delete ${_team(team.id).path}', () => _team(team.id).delete()),
  );

  /// Tworzy kod zaproszenia ważny 7 dni.
  Future<String> createInvite(Team team) async {
    final random = Random.secure();
    final code = List.generate(
      8,
      (_) => inviteAlphabet[random.nextInt(inviteAlphabet.length)],
    ).join();
    final ref = _db.collection('invites').doc(code);
    await _requireOnline(
      traced(
        'create ${ref.path} (zespół ${team.id})',
        () => ref.set({
          'teamId': team.id,
          'teamName': team.name,
          'createdBy': uid,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(
            DateTime.now().add(const Duration(days: 7)),
          ),
        }),
      ),
    );
    return code;
  }

  /// Dołącza do zespołu z kodu zaproszenia; zwraca id zespołu.
  Future<String> joinTeam(String rawCode) async {
    final code = normalizeInviteCode(rawCode);
    if (code.length != 8) {
      throw UserFacingException('Kod ma 8 znaków, np. ABCD-2345.');
    }
    final invite = await _requireOnline(
      traced(
        'get invites/$code',
        () => _db
            .collection('invites')
            .doc(code)
            .get(const GetOptions(source: Source.server)),
        describe: (s) => 'exists=${s.exists}',
      ),
    );
    final data = invite.data();
    if (data == null) {
      throw UserFacingException('Nie ma zaproszenia z takim kodem.');
    }
    final teamId = data['teamId'] as String;
    final expiresAt = (data['expiresAt'] as Timestamp).toDate();
    if (expiresAt.isBefore(DateTime.now())) {
      throw UserFacingException('To zaproszenie wygasło - poproś o nowe.');
    }
    if (team(teamId) != null) return teamId;

    final name = _displayName;
    final batch = _db.batch()
      ..set(_team(teamId).collection('joins').doc(uid), {
        'code': code,
        'joinedAt': FieldValue.serverTimestamp(),
      })
      ..update(_team(teamId), {
        'memberIds': FieldValue.arrayUnion([uid]),
        'roles.$uid': 'editor',
        if (name.isNotEmpty) 'memberNames.$uid': name,
      });
    _addEvent(batch, teamId, MessageType.joined);
    await _requireOnline(traced('join teams/$teamId', batch.commit));
    return teamId;
  }

  Future<void> leaveTeam(Team team) async {
    // Najpierw pożegnanie na czacie - po wyjściu nie wolno już pisać.
    final batch = _db.batch();
    _addEvent(batch, team.id, MessageType.left);
    await _requireOnline(traced('left message ${team.id}', batch.commit));
    await _requireOnline(_removeFromTeam(team, uid, 'leave'));
  }

  Future<void> removeMember(Team team, String memberId) =>
      _requireOnline(_removeFromTeam(team, memberId, 'remove $memberId'));

  Future<void> _removeFromTeam(Team team, String memberId, String label) =>
      traced(
        '$label ${_team(team.id).path}',
        () => _team(team.id).update({
          'memberIds': FieldValue.arrayRemove([memberId]),
          'roles.$memberId': FieldValue.delete(),
          'memberNames.$memberId': FieldValue.delete(),
        }),
      );

  Future<void> setRole(Team team, String memberId, String role) => traced(
    'update ${_team(team.id).path} roles.$memberId=$role',
    () => _team(team.id).update({'roles.$memberId': role}),
  );

  // ---------------------------------------------------------------- piosenki

  Stream<List<Song>> songs(String teamId) {
    final query = _songs(teamId);
    return tracedStream(
      query.path,
      query.snapshots(),
      describe: (s) =>
          '${s.docs.length} piosenek, zmienionych ${s.docChanges.length}, '
          'fromCache=${s.metadata.isFromCache}, '
          'czeka na zapis=${s.metadata.hasPendingWrites}',
    ).map((snapshot) {
      final songs = snapshot.docs.map(Song.fromDoc).toList();
      songs.sort((a, b) => a.sortKey.compareTo(b.sortKey));
      return songs;
    });
  }

  Map<String, dynamic> _songData(String title, String author, String lyrics) =>
      {
        'title': title,
        'author': author,
        'lyrics': lyrics,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': uid,
      };

  /// Tworzy nową piosenkę (gdy [original] == null) albo zapisuje zmiany,
  /// odkładając poprzednią wersję do historii.
  Future<void> saveSong(
    String teamId, {
    Song? original,
    required String title,
    required String author,
    required String lyrics,
  }) {
    final ref = original == null
        ? _songs(teamId).doc()
        : _songs(teamId).doc(original.id);
    final batch = _db.batch();
    if (original != null) {
      batch.set(ref.collection('revisions').doc(), _revision(original));
    }
    batch.set(ref, _songData(title, author, lyrics));
    _addEvent(
      batch,
      teamId,
      original == null ? MessageType.songAdded : MessageType.songUpdated,
      subject: title,
      songId: ref.id,
    );
    return traced(
      '${original == null ? 'create' : 'update'} ${ref.path} '
      '("$title", ${lyrics.length} znaków)',
      batch.commit,
    );
  }

  /// Usuwa piosenkę; jej ostatnia wersja zostaje w historii.
  Future<void> deleteSong(String teamId, Song song) {
    final ref = _songs(teamId).doc(song.id);
    final batch = _db.batch()
      ..set(ref.collection('revisions').doc(), {
        ..._revision(song),
        'deleted': true,
      })
      ..delete(ref);
    return traced('delete ${ref.path} ("${song.title}")', batch.commit);
  }

  /// Kopiuje (albo przenosi) piosenkę do innego śpiewnika. Zwraca false, gdy
  /// piosenka o tym samym tytule już tam jest - wtedy nic nie zmienia.
  Future<bool> copySong(
    String fromTeamId,
    Song song,
    String toTeamId, {
    bool move = false,
  }) async {
    final existing = await _songIdsByTitle(toTeamId);
    if (existing.containsKey(titleKey(song.title))) return false;

    final target = _songs(toTeamId).doc();
    final batch = _db.batch()
      ..set(target, _songData(song.title, song.author, song.lyrics));
    _addEvent(
      batch,
      toTeamId,
      MessageType.songAdded,
      subject: song.title,
      songId: target.id,
    );
    if (move) {
      final source = _songs(fromTeamId).doc(song.id);
      batch
        ..set(source.collection('revisions').doc(), {
          ..._revision(song),
          'deleted': true,
        })
        ..delete(source);
    }
    unawaited(
      traced(
        '${move ? 'move' : 'copy'} ${song.id} -> ${target.path}',
        batch.commit,
      ).catchError((Object _) {}),
    );
    return true;
  }

  /// Kopiuje piosenki (np. z Mojego śpiewnika) do śpiewnika zespołu. Piosenki,
  /// które już tam są (ten sam tytuł), nie są dublowane. Zwraca mapę
  /// id źródłowe -> id w docelowym śpiewniku.
  Future<Map<String, String>> copySongsToTeam(
    List<Song> songs,
    String toTeamId,
  ) async {
    final existing = await _songIdsByTitle(toTeamId);
    final ids = <String, String>{};
    final toCopy = <({String sourceId, ImportedSong song})>[];
    for (final song in songs) {
      final key = titleKey(song.title);
      final existingId = existing[key];
      if (existingId != null) {
        ids[song.id] = existingId;
      } else {
        toCopy.add((
          sourceId: song.id,
          song: ImportedSong(
            title: song.title,
            author: song.author,
            lyrics: song.lyrics,
            source: song.id,
          ),
        ));
        existing[key] = song.id; // ten sam tytuł dwa razy na liście
      }
    }
    final newIds = await _writeSongs(toTeamId, [
      for (final c in toCopy) c.song,
    ]);
    for (var i = 0; i < toCopy.length; i++) {
      ids[toCopy[i].sourceId] = newIds[i];
    }
    return ids;
  }

  /// Zapisuje zaimportowane piosenki (paczkami - Firestore przyjmuje do 500
  /// zapisów naraz). Zwraca id nowych piosenek.
  Future<List<String>> importSongs(String teamId, List<ImportedSong> songs) =>
      _writeSongs(teamId, songs);

  Future<List<String>> _writeSongs(
    String teamId,
    List<ImportedSong> songs,
  ) async {
    final ids = <String>[];
    const chunk = 400;
    for (var start = 0; start < songs.length; start += chunk) {
      final part = songs.skip(start).take(chunk).toList();
      final batch = _db.batch();
      for (final song in part) {
        final ref = _songs(teamId).doc();
        batch.set(ref, _songData(song.title, song.author, song.lyrics));
        ids.add(ref.id);
      }
      final last = start + chunk >= songs.length;
      if (last) {
        if (songs.length == 1) {
          _addEvent(
            batch,
            teamId,
            MessageType.songAdded,
            subject: songs.single.title,
            songId: ids.single,
          );
        } else {
          _addEvent(
            batch,
            teamId,
            MessageType.songsImported,
            count: songs.length,
          );
        }
      }
      await _waitIfOnline(
        traced(
          'import ${part.length} piosenek -> ${_songs(teamId).path}',
          batch.commit,
        ),
      );
    }
    return ids;
  }

  /// Klucz do porównywania tytułów: bez wielkości liter, polskich znaków i interpunkcji.
  static String titleKey(String title) =>
      foldPolish(title).replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<Map<String, String>> _songIdsByTitle(String teamId) async {
    final snapshot = await traced(
      'get ${_songs(teamId).path}',
      () => _songs(teamId).get(),
      describe: (s) => '${s.docs.length} piosenek',
    );
    return {
      for (final doc in snapshot.docs)
        titleKey(doc.data()['title'] as String? ?? ''): doc.id,
    };
  }

  Map<String, dynamic> _revision(Song song) => {
    'title': song.title,
    'author': song.author,
    'lyrics': song.lyrics,
    'updatedAt': song.updatedAt,
    'updatedBy': song.updatedBy,
    'replacedAt': FieldValue.serverTimestamp(),
    'replacedBy': uid,
  };

  // ---------------------------------------------------------------- playlisty

  Stream<List<Playlist>> playlists(String teamId) {
    final query = _playlists(teamId);
    return tracedStream(
      query.path,
      query.snapshots(),
      describe: (s) => '${s.docs.length} playlist',
    ).map((snapshot) {
      final list = snapshot.docs.map(Playlist.fromDoc).toList()
        // Najnowsze daty na górze, playlisty bez daty na końcu.
        ..sort((a, b) {
          final ad = a.date ?? a.createdAt, bd = b.date ?? b.createdAt;
          if (a.date != null && b.date == null) return -1;
          if (a.date == null && b.date != null) return 1;
          if (ad == null || bd == null) return 0;
          return bd.compareTo(ad);
        });
      return list;
    });
  }

  Stream<Playlist?> playlist(String teamId, String playlistId) {
    final ref = _playlists(teamId).doc(playlistId);
    return tracedStream(
      ref.path,
      ref.snapshots(),
      describe: (s) => s.exists
          ? '${(s.data()?['songIds'] as List?)?.length ?? 0} piosenek'
          : 'nie istnieje',
    ).map((s) => s.exists ? Playlist.fromDoc(s) : null);
  }

  String newPlaylistId(String teamId) => _playlists(teamId).doc().id;

  Future<void> createPlaylist(
    String teamId,
    String playlistId, {
    required String name,
    DateTime? date,
    List<String> songIds = const [],
  }) {
    final ref = _playlists(teamId).doc(playlistId);
    final batch = _db.batch()
      ..set(ref, {
        'name': name,
        'date': date == null ? null : Timestamp.fromDate(date),
        'songIds': songIds,
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    _addEvent(
      batch,
      teamId,
      MessageType.setlist,
      subject: name,
      playlistId: playlistId,
    );
    return traced('create ${ref.path} ("$name")', batch.commit);
  }

  Future<void> updatePlaylist(
    String teamId,
    String playlistId, {
    String? name,
    DateTime? date,
    bool clearDate = false,
    List<String>? songIds,
  }) {
    final ref = _playlists(teamId).doc(playlistId);
    return traced(
      'update ${ref.path}',
      () => ref.update({
        'name': ?name,
        if (date != null || clearDate)
          'date': date == null ? null : Timestamp.fromDate(date),
        'songIds': ?songIds,
        'updatedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  Future<void> deletePlaylist(String teamId, String playlistId) {
    final ref = _playlists(teamId).doc(playlistId);
    return traced('delete ${ref.path}', ref.delete);
  }

  /// Kopiuje playlistę do innego śpiewnika razem z piosenkami, których tam
  /// brakuje (te, które już są - po tytule - zostają użyte bez kopiowania).
  /// W zespole wysyła też wiadomość na czat. Zwraca liczbę skopiowanych piosenek.
  Future<int> sharePlaylist(
    Playlist playlist,
    Map<String, Song> sourceSongs,
    Team target,
  ) async {
    final existing = await _songIdsByTitle(target.id);
    final batch = _db.batch();
    final songIds = <String>[];
    var copied = 0;
    for (final id in playlist.songIds) {
      final song = sourceSongs[id];
      if (song == null) continue;
      final key = titleKey(song.title);
      var targetId = existing[key];
      if (targetId == null) {
        final ref = _songs(target.id).doc();
        batch.set(ref, _songData(song.title, song.author, song.lyrics));
        existing[key] = targetId = ref.id;
        copied++;
      }
      songIds.add(targetId);
    }

    final playlistRef = _playlists(target.id).doc();
    batch.set(playlistRef, {
      'name': playlist.name,
      'date': playlist.date == null ? null : Timestamp.fromDate(playlist.date!),
      'songIds': songIds,
      'createdBy': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _addEvent(
      batch,
      target.id,
      MessageType.setlist,
      subject: playlist.name,
      count: songIds.length,
      playlistId: playlistRef.id,
    );
    await _waitIfOnline(
      traced(
        'share playlist ${playlist.id} -> ${playlistRef.path} '
        '($copied nowych piosenek)',
        batch.commit,
      ),
    );
    return copied;
  }

  // ---------------------------------------------------------------- czat

  Stream<List<ChatMessage>> messages(String teamId) {
    final query = _messages(
      teamId,
    ).orderBy('createdAt', descending: true).limit(200);
    return tracedStream(
      _messages(teamId).path,
      query.snapshots(),
      describe: (s) =>
          '${s.docs.length} wiadomości, nowych ${s.docChanges.length}',
    ).map((s) => s.docs.map(ChatMessage.fromDoc).toList());
  }

  Future<void> sendMessage(String teamId, String text) {
    final ref = _messages(teamId).doc();
    return traced(
      'create ${ref.path} (${text.length} znaków)',
      () => ref.set(_messageData(MessageType.text, text)),
    );
  }

  Map<String, dynamic> _messageData(
    MessageType type,
    String text, {
    String? subject,
    String? songId,
    String? playlistId,
    int? count,
  }) => {
    'type': type.id,
    'text': text,
    'authorId': uid,
    'authorName': _displayName,
    'createdAt': FieldValue.serverTimestamp(),
    // Znacznik nowego formatu zdarzeń (zdanie składa się przy wyświetlaniu);
    // forma zawsze neutralna: "dodał(a)".
    if (type != MessageType.text) 'authorForm': 'n',
    'subject': ?subject,
    'songId': ?songId,
    'playlistId': ?playlistId,
    'count': ?count,
  };

  /// Dopisuje do operacji wiadomość-zdarzenie na czacie zespołu
  /// (w "Moim śpiewniku" nie ma czatu, więc tam nic nie robi). Zdanie
  /// ("Adam dodał…", "Ty dodałeś…") składa się przy wyświetlaniu, a w polu
  /// text zostaje wersja zapasowa w 3. osobie.
  void _addEvent(
    WriteBatch batch,
    String teamId,
    MessageType type, {
    String? subject,
    String? comment,
    String? songId,
    String? playlistId,
    int? count,
  }) {
    if (teamId == personalTeamId(uid)) return;
    if (team(teamId)?.personal ?? false) return;
    final fallback =
        comment ??
        describeEvent(
          ChatMessage(
            id: '',
            text: '',
            authorId: uid,
            authorName: _displayName,
            type: type,
            subject: subject,
            count: count,
          ),
          mine: false,
        );
    batch.set(
      _messages(teamId).doc(),
      _messageData(
        type,
        fallback.length > 2000 ? '${fallback.substring(0, 1997)}...' : fallback,
        subject: subject == null || subject.length <= 300
            ? subject
            : subject.substring(0, 300),
        songId: songId,
        playlistId: playlistId,
        count: count,
      ),
    );
  }

  Future<void> deleteMessage(String teamId, String messageId) {
    final ref = _messages(teamId).doc(messageId);
    return traced('delete ${ref.path}', ref.delete);
  }

  /// Najnowsza wiadomość zespołu - do kafelka na ekranie startowym.
  Stream<ChatMessage?> latestMessage(String teamId) {
    final query = _messages(
      teamId,
    ).orderBy('createdAt', descending: true).limit(1);
    return tracedStream(
      '${_messages(teamId).path} (ostatnia)',
      query.snapshots(),
      describe: (s) => s.docs.isEmpty ? 'brak' : 'jest',
    ).map((s) => s.docs.isEmpty ? null : ChatMessage.fromDoc(s.docs.first));
  }

  /// Kiedy zalogowana osoba ostatnio czytała czat każdego zespołu.
  Stream<Map<String, DateTime>> lastSeen() {
    final ref = _db.collection('users').doc(uid);
    return tracedStream(
      '${ref.path} (lastSeen)',
      ref.snapshots(),
      describe: (s) => 'exists=${s.exists}',
    ).map((s) {
      final raw = s.data()?['lastSeen'] as Map? ?? const {};
      return {
        for (final e in raw.entries)
          if (e.value is Timestamp)
            e.key as String: (e.value as Timestamp).toDate(),
      };
    });
  }

  Future<void> markSeen(String teamId) {
    final ref = _db.collection('users').doc(uid);
    return traced(
      'update ${ref.path} lastSeen.$teamId',
      () => ref.set({
        'lastSeen': {teamId: FieldValue.serverTimestamp()},
      }, SetOptions(merge: true)),
    );
  }

  // ---------------------------------------------------------------- obecność

  /// "Mam otwartą aplikację" (true) albo "zminimalizowałem" (false).
  Future<void> setPresence({required bool online}) {
    final ref = _db.collection('presence').doc(uid);
    return traced(
      'set ${ref.path} online=$online',
      () => ref.set({
        'online': online,
        'lastActive': FieldValue.serverTimestamp(),
      }),
    );
  }

  /// Status członków zespołu - nasłuch tylko na czas otwartej listy członków.
  Stream<Map<String, Presence>> presence(List<String> uids) {
    if (uids.isEmpty) return Stream.value(const {});
    // whereIn przyjmuje do 30 wartości - zespoły są mniejsze.
    final query = _db
        .collection('presence')
        .where(FieldPath.documentId, whereIn: uids.take(30).toList());
    return tracedStream(
      'presence (${uids.length} osób)',
      query.snapshots(),
      describe: (s) => '${s.docs.length} statusów',
    ).map((s) => {for (final d in s.docs) d.id: Presence.fromDoc(d)});
  }

  // ---------------------------------------------------------------- komentarze

  CollectionReference<Map<String, dynamic>> _comments(
    String teamId,
    String songId,
  ) => _songs(teamId).doc(songId).collection('comments');

  Stream<List<SongComment>> comments(String teamId, String songId) {
    final query = _comments(teamId, songId).orderBy('createdAt');
    return tracedStream(
      _comments(teamId, songId).path,
      query.snapshots(),
      describe: (s) => '${s.docs.length} komentarzy',
    ).map((s) => s.docs.map(SongComment.fromDoc).toList());
  }

  Future<void> addComment(String teamId, Song song, String text) {
    final ref = _comments(teamId, song.id).doc();
    final batch = _db.batch()
      ..set(ref, {
        'text': text,
        'authorId': uid,
        'authorName': _displayName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    final excerpt = text.length > 120 ? '${text.substring(0, 117)}...' : text;
    _addEvent(
      batch,
      teamId,
      MessageType.comment,
      subject: song.title,
      comment: excerpt,
      songId: song.id,
    );
    return traced('create ${ref.path}', batch.commit);
  }

  Future<void> deleteComment(String teamId, String songId, String commentId) {
    final ref = _comments(teamId, songId).doc(commentId);
    return traced('delete ${ref.path}', ref.delete);
  }
}

/// "1 piosenka", "3 piosenki", "25 piosenek".
String songsCount(int n) {
  if (n == 1) return '1 piosenka';
  final last = n % 10, lastTwo = n % 100;
  if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) {
    return '$n piosenki';
  }
  return '$n piosenek';
}
