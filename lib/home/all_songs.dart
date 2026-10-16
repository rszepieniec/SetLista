import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repository.dart';
import '../debug_log.dart';
import '../models.dart';
import '../song.dart';

/// Piosenka na scalonej liście "Mój śpiewnik".
class SongEntry {
  SongEntry({required this.song, required this.teamId, required this.teamIds});

  final Song song;

  /// Śpiewnik, z którego pochodzi pokazywana wersja (mój albo zespołu).
  final String teamId;

  /// Zespoły, w których jest piosenka o tym tytule (bez Mojego śpiewnika).
  final List<String> teamIds;
}

/// Wszystkie piosenki z Mojego śpiewnika i ze wszystkich zespołów - bez
/// powtórek. Piosenki o tym samym tytule (np. skopiowana z Mojego śpiewnika
/// do zespołu) są pokazane raz: moja wersja, jeśli jest, a obok etykiety zespołów.
class AllSongs extends ChangeNotifier {
  AllSongs(this._repo) {
    _repo.teams.addListener(_syncTeams);
    _syncTeams();
  }

  final Repository _repo;
  final _subscriptions = <String, StreamSubscription<List<Song>>>{};
  final _songs = <String, List<Song>>{};

  List<SongEntry> entries = const [];

  String get personalId => Repository.personalTeamId(_repo.uid);

  /// Mój śpiewnik już się wczytał (zespoły mogą jeszcze dochodzić).
  bool get loaded => _songs.containsKey(personalId);

  List<Song> get personalSongs => _songs[personalId] ?? const [];

  List<Song> songsOf(String teamId) => _songs[teamId] ?? const [];

  void _syncTeams() {
    final ids = {for (final t in _repo.teams.value) t.id};
    for (final id in ids.difference(_subscriptions.keys.toSet())) {
      _subscriptions[id] = _repo.songs(id).listen((songs) {
        _songs[id] = songs;
        _rebuild();
      }, onError: (Object e) => logFirebase('songs $id: ${describeError(e)}'));
    }
    for (final id in _subscriptions.keys.toSet().difference(ids)) {
      _subscriptions.remove(id)?.cancel();
      _songs.remove(id);
    }
    _rebuild();
  }

  void _rebuild() {
    final byTitle = <String, SongEntry>{};
    for (final song in personalSongs) {
      byTitle.putIfAbsent(
        Repository.titleKey(song.title),
        () => SongEntry(song: song, teamId: personalId, teamIds: []),
      );
    }
    final teams = [
      for (final t in _repo.teams.value)
        if (!t.personal) t,
    ];
    for (final team in teams) {
      for (final song in songsOf(team.id)) {
        final key = Repository.titleKey(song.title);
        final entry = byTitle[key];
        if (entry == null) {
          byTitle[key] = SongEntry(
            song: song,
            teamId: team.id,
            teamIds: [team.id],
          );
        } else if (!entry.teamIds.contains(team.id)) {
          entry.teamIds.add(team.id);
        }
      }
    }
    entries = byTitle.values.toList()
      ..sort((a, b) => a.song.sortKey.compareTo(b.song.sortKey));
    notifyListeners();
  }

  Team? team(String id) => _repo.team(id);

  @override
  void dispose() {
    _repo.teams.removeListener(_syncTeams);
    for (final s in _subscriptions.values) {
      s.cancel();
    }
    super.dispose();
  }
}
