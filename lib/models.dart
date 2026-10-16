import 'package:cloud_firestore/cloud_firestore.dart';

/// Zespół albo "Mój śpiewnik" (zespół z personal == true).
class Team {
  Team({
    required this.id,
    required this.name,
    required this.personal,
    required this.ownerId,
    required this.roles,
    required this.memberIds,
    required this.memberNames,
  });

  final String id;
  final String name;
  final bool personal;
  final String ownerId;
  final Map<String, String> roles;
  final List<String> memberIds;
  final Map<String, String> memberNames;

  factory Team.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Team(
      id: doc.id,
      name: d['name'] as String? ?? '',
      personal: d['personal'] as bool? ?? false,
      ownerId: d['ownerId'] as String? ?? '',
      roles: Map<String, String>.from(d['roles'] as Map? ?? const {}),
      memberIds: List<String>.from(d['memberIds'] as List? ?? const []),
      memberNames: Map<String, String>.from(
        d['memberNames'] as Map? ?? const {},
      ),
    );
  }

  String? roleOf(String uid) => roles[uid];
  bool isOwner(String uid) => roles[uid] == 'owner';
  bool canEdit(String uid) => const ['owner', 'editor'].contains(roles[uid]);
  String nameOf(String uid) => memberNames[uid] ?? 'Ktoś';
}

String roleLabel(String? role) => switch (role) {
  'owner' => 'Właściciel',
  'editor' => 'Edytor',
  'member' => 'Tylko odczyt',
  _ => '',
};

class Playlist {
  Playlist({
    required this.id,
    required this.name,
    required this.songIds,
    this.date,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String name;
  final List<String> songIds;
  final DateTime? date;
  final String? createdBy;
  final DateTime? createdAt;

  factory Playlist.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Playlist(
      id: doc.id,
      name: d['name'] as String? ?? '',
      songIds: List<String>.from(d['songIds'] as List? ?? const []),
      date: (d['date'] as Timestamp?)?.toDate(),
      createdBy: d['createdBy'] as String?,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Rodzaje wiadomości na czacie: zwykły tekst albo zdarzenie z odnośnikiem.
enum MessageType {
  text,
  setlist,
  songAdded,
  songUpdated,
  songsImported,
  comment,
  joined,
  left,
  teamCreated,
  teamRenamed;

  static const _ids = {
    text: 'text',
    setlist: 'setlist',
    songAdded: 'song_added',
    songUpdated: 'song_updated',
    songsImported: 'songs_imported',
    comment: 'comment',
    joined: 'joined',
    left: 'left',
    teamCreated: 'team_created',
    teamRenamed: 'team_renamed',
  };

  String get id => _ids[this]!;

  static MessageType fromId(String? id) => _ids.entries
      .firstWhere((e) => e.value == id, orElse: () => _ids.entries.first)
      .key;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.text,
    required this.authorId,
    required this.authorName,
    this.type = MessageType.text,
    this.createdAt,
    this.playlistId,
    this.songId,
    this.count,
    this.subject,
    this.legacy = false,
  });

  final String id;

  /// Zwykła wiadomość: jej treść. Zdarzenie: opis zapasowy w 3. osobie
  /// (dla komentarza - jego fragment). Pełne zdanie buduje [eventSentence].
  final String text;
  final String authorId;
  final String authorName;
  final MessageType type;

  /// null, dopóki serwer nie potwierdzi wiadomości (np. offline).
  final DateTime? createdAt;
  final String? playlistId;
  final String? songId;
  final int? count;

  /// Tytuł piosenki/setlisty/zespołu, którego dotyczy zdarzenie.
  final String? subject;

  /// Najstarsze wiadomości (z gotowym tekstem w czasie teraźniejszym),
  /// zapisane zanim zdarzenia dostały pola subject/count.
  final bool legacy;

  bool get isEvent => type != MessageType.text;

  factory ChatMessage.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return ChatMessage(
      id: doc.id,
      text: d['text'] as String? ?? '',
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      // Starsze wiadomości o udostępnionej playliście nie miały pola type.
      type: d['type'] == null && d['playlistId'] != null
          ? MessageType.setlist
          : MessageType.fromId(d['type'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      playlistId: d['playlistId'] as String?,
      songId: d['songId'] as String?,
      count: d['count'] as int?,
      subject: d['subject'] as String?,
      // Nowe zdarzenia mają pole authorForm (dziś zawsze "n" - forma neutralna).
      legacy: d['type'] != 'text' && d['authorForm'] == null,
    );
  }
}

class SongComment {
  SongComment({
    required this.id,
    required this.text,
    required this.authorId,
    required this.authorName,
    this.createdAt,
  });

  final String id;
  final String text;
  final String authorId;
  final String authorName;
  final DateTime? createdAt;

  factory SongComment.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SongComment(
      id: doc.id,
      text: d['text'] as String? ?? '',
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Kod zaproszenia: 8 znaków bez mylących (0/O, 1/I/L), wyświetlany jako XXXX-XXXX.
const inviteAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String formatInviteCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

/// "abcd-2345 " -> "ABCD2345"
String normalizeInviteCode(String input) =>
    input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

/// Czy ktoś ma teraz otwartą aplikację. Aplikacja na ekranie wysyła sygnał
/// co 2 minuty, a przy zminimalizowaniu zapisuje online = false.
class Presence {
  Presence({required this.online, this.lastActive});

  final bool online;
  final DateTime? lastActive;

  static const activeWindow = Duration(minutes: 3);

  /// Online i ostatni sygnał niedawno (na wypadek zamknięcia aplikacji bez
  /// pożegnania, np. przy braku zasięgu albo zabiciu procesu).
  bool get isActive =>
      online &&
      lastActive != null &&
      DateTime.now().difference(lastActive!) < activeWindow;

  factory Presence.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Presence(
      online: d['online'] as bool? ?? false,
      lastActive: (d['lastActive'] as Timestamp?)?.toDate(),
    );
  }
}
