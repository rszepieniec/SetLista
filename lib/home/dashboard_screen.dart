import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../debug_log.dart';
import '../grammar.dart';
import '../messages.dart';
import '../models.dart';
import '../setlists/setlists_screen.dart';
import '../song.dart';
import '../teams/join_dialog.dart';
import '../preferences.dart';
import '../widgets.dart';
import 'songbook_screen.dart';
import 'team_home_screen.dart';

/// Ekran startowy: kafelki "Mój śpiewnik", "Moje setlisty" i zespoły.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.repository,
    required this.user,
  });

  final Repository repository;
  final User user;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final StreamSubscription<List<Team>> _teamsSubscription;
  late final _personalId = Repository.personalTeamId(widget.user.uid);
  late final _personalSongs = _repo.songs(_personalId);
  late final _personalSetlists = _repo.playlists(_personalId);
  late final _lastSeen = _repo.lastSeen();
  // Nasłuch ostatniej wiadomości osobno dla każdego zespołu, tworzony raz.
  final _latest = <String, Stream<ChatMessage?>>{};

  Repository get _repo => widget.repository;

  // Obecność: "w aplikacji" przy otwarciu i co 2 minuty, póki aplikacja jest
  // na ekranie; po zminimalizowaniu - "nieaktywny". Lista członków pokazuje
  // na tej podstawie zieloną/szarą kropkę.
  late final AppLifecycleListener _lifecycle;
  Timer? _heartbeat;

  @override
  void initState() {
    super.initState();
    _teamsSubscription = _repo.watchTeams().listen(
      (_) {},
      onError: (Object e) => logFirebase('teams: ${describeError(e)}'),
    );
    _lifecycle = AppLifecycleListener(
      onShow: _startPresence,
      onResume: _startPresence,
      onHide: _stopPresence,
    );
    _startPresence();
  }

  void _startPresence() {
    if (_heartbeat?.isActive ?? false) return;
    _sendPresence(online: true);
    _heartbeat = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _sendPresence(online: true),
    );
  }

  void _stopPresence() {
    if (!(_heartbeat?.isActive ?? false)) return;
    _heartbeat?.cancel();
    _sendPresence(online: false);
  }

  void _sendPresence({required bool online}) {
    if (FirebaseAuth.instance.currentUser == null) return;
    _repo.setPresence(online: online).catchError((Object _) {});
  }

  Future<void> _signOut() async {
    _heartbeat?.cancel();
    // Najpierw "nieaktywny" - po wylogowaniu nie mamy już prawa zapisu.
    await _repo
        .setPresence(online: false)
        .timeout(const Duration(seconds: 3))
        .catchError((Object _) {});
    await FirebaseAuth.instance.signOut();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _lifecycle.dispose();
    _teamsSubscription.cancel();
    super.dispose();
  }

  void _push(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _openTeam(String teamId) =>
      _push(TeamHomeScreen(repository: _repo, teamId: teamId));

  Future<void> _createTeam() async {
    final name = await askForText(
      context,
      title: 'Nowy zespół',
      label: 'Nazwa zespołu',
      confirmLabel: 'Utwórz',
    );
    if (name == null) return;
    try {
      final id = await _repo.createTeam(name);
      showMessage(
        youDid('utworzył', 'zespół „$name” - zaproś członków ikoną 👥'),
      );
      if (mounted) _openTeam(id);
    } catch (e) {
      showMessage('Nie udało się utworzyć zespołu: $e');
    }
  }

  Future<void> _changeName() async {
    final current = FirebaseAuth.instance.currentUser?.displayName ?? '';
    final name = await askForText(
      context,
      title: 'Twoje imię',
      label: 'Imię widoczne w zespołach',
      confirmLabel: 'Zapisz',
      initialValue: current,
    );
    if (name == null || name == current) return;
    try {
      await _repo.updateMyName(name);
      if (mounted) setState(() {});
      showMessage('Zmieniono imię na „$name”');
    } catch (e) {
      showMessage('Nie udało się zmienić imienia: $e');
    }
  }

  Future<void> _chooseTheme() async {
    final mode = await showDialog<ThemeMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Motyw'),
        children: [
          RadioGroup<ThemeMode>(
            groupValue: themeMode.value,
            onChanged: (m) => Navigator.pop(context, m),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in ThemeMode.values)
                  RadioListTile<ThemeMode>(
                    value: m,
                    title: Text(themeModeLabel(m)),
                    secondary: Icon(themeModeIcon(m)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (mode != null) await setThemeMode(mode);
  }

  Future<void> _joinTeam() async {
    final teamId = await showJoinTeamDialog(context, _repo);
    if (teamId == null || !mounted) return;
    showMessage(youDid('dołączył', 'do zespołu'));
    _openTeam(teamId);
  }

  @override
  Widget build(BuildContext context) {
    // Aktualne imię (po zmianie w menu konta), nie to z chwili logowania.
    final name = FirebaseAuth.instance.currentUser?.displayName ?? '';
    return Scaffold(
      appBar: AppBar(
        title: const Text('SetLista'),
        actions: [
          PopupMenuButton<void>(
            tooltip: 'Konto',
            icon: CircleAvatar(
              radius: 16,
              child: Text(
                name.isEmpty ? '?' : name.characters.first.toUpperCase(),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                enabled: false,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(name.isEmpty ? 'Zalogowano' : name),
                  subtitle: Text(widget.user.email ?? ''),
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                onTap: _changeName,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Zmień imię'),
                ),
              ),
              PopupMenuItem(
                onTap: _chooseTheme,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(themeModeIcon(themeMode.value)),
                  title: const Text('Motyw'),
                  subtitle: Text(themeModeLabel(themeMode.value)),
                ),
              ),
              PopupMenuItem(
                onTap: _signOut,
                child: const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout),
                  title: Text('Wyloguj'),
                ),
              ),
            ],
          ),
          // Odstęp, żeby awatar nie przylegał do krawędzi ekranu.
          const SizedBox(width: 12),
        ],
      ),
      body: ValueListenableBuilder<List<Team>>(
        valueListenable: _repo.teams,
        builder: (context, teams, _) {
          final bands = [
            for (final t in teams)
              if (!t.personal) t,
          ];
          return StreamBuilder<Map<String, DateTime>>(
            stream: _lastSeen,
            builder: (context, seenSnapshot) {
              final seen = seenSnapshot.data ?? const {};
              return CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverGrid.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                      children: [
                        StreamBuilder<List<Song>>(
                          stream: _personalSongs,
                          builder: (context, s) => _Tile(
                            icon: Icons.library_music,
                            title: 'Mój śpiewnik',
                            subtitle: s.hasData
                                ? songsCount(s.data!.length)
                                : 'Twoje piosenki',
                            onTap: () =>
                                _push(SongbookScreen(repository: _repo)),
                          ),
                        ),
                        StreamBuilder<List<Playlist>>(
                          stream: _personalSetlists,
                          builder: (context, s) => _Tile(
                            icon: Icons.queue_music,
                            title: 'Moje setlisty',
                            subtitle: s.hasData
                                ? _setlistsCount(s.data!.length)
                                : 'Kolejność na mszę i próbę',
                            tone: _Tone.tertiary,
                            onTap: () =>
                                _push(SetlistsScreen(repository: _repo)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                      child: Text(
                        'Zespoły',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      0,
                      16,
                      MediaQuery.paddingOf(context).bottom + 24,
                    ),
                    sliver: SliverGrid.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                      children: [
                        for (final team in bands)
                          StreamBuilder<ChatMessage?>(
                            stream: _latest[team.id] ??= _repo.latestMessage(
                              team.id,
                            ),
                            builder: (context, s) {
                              final last = s.data;
                              return _Tile(
                                icon: Icons.groups,
                                title: team.name,
                                subtitle: last == null
                                    ? _membersCount(team.memberIds.length)
                                    : _preview(last),
                                unread: _isUnread(last, seen[team.id]),
                                tone: _Tone.secondary,
                                onTap: () => _openTeam(team.id),
                              );
                            },
                          ),
                        _Tile(
                          icon: Icons.group_add_outlined,
                          title: 'Nowy zespół',
                          subtitle: 'Załóż i zaproś innych',
                          outlined: true,
                          onTap: _createTeam,
                        ),
                        _Tile(
                          icon: Icons.vpn_key_outlined,
                          title: 'Dołącz kodem',
                          subtitle: 'Masz kod zaproszenia?',
                          outlined: true,
                          onTap: _joinTeam,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  bool _isUnread(ChatMessage? last, DateTime? seen) {
    if (last == null || last.authorId == _repo.uid) return false;
    final at = last.createdAt;
    return at != null && (seen == null || at.isAfter(seen));
  }

  String _preview(ChatMessage m) {
    final mine = m.authorId == _repo.uid;
    final who = mine
        ? 'Ty'
        : (m.authorName.isEmpty ? 'Ktoś' : m.authorName.split(' ').first);
    return m.isEvent
        ? '$who ${describeEvent(m, mine: mine)}'
        : '$who: ${m.text}';
  }
}

String _setlistsCount(int n) => switch (n) {
  0 => 'Brak setlist',
  1 => '1 setlista',
  _ when n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) =>
    '$n setlisty',
  _ => '$n setlist',
};

String _membersCount(int n) => switch (n) {
  1 => '1 osoba',
  _ when n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14) =>
    '$n osoby',
  _ => '$n osób',
};

enum _Tone { primary, secondary, tertiary }

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = _Tone.primary,
    this.unread = false,
    this.outlined = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final _Tone tone;
  final bool unread;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      _Tone.primary => (colors.primaryContainer, colors.onPrimaryContainer),
      _Tone.secondary => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      _Tone.tertiary => (colors.tertiaryContainer, colors.onTertiaryContainer),
    };

    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 32,
                color: outlined ? colors.primary : foreground,
              ),
              const Spacer(),
              if (unread)
                Badge(label: const Text('nowe'), backgroundColor: colors.error),
            ],
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: outlined ? null : foreground,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: outlined
                  ? colors.onSurfaceVariant
                  : foreground.withValues(alpha: 0.8),
              fontWeight: unread ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );

    return outlined
        ? Card.outlined(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: content),
          )
        : Card.filled(
            margin: EdgeInsets.zero,
            color: background,
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onTap, child: content),
          );
  }
}
