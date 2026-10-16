import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../messages.dart';
import '../models.dart';
import '../widgets.dart';
import 'setlist_dialog.dart';
import 'setlist_screen.dart';

/// "Moje setlisty": moje setlisty, a niżej - posegregowane według zespołów -
/// setlisty udostępnione w moich zespołach.
class SetlistsScreen extends StatefulWidget {
  const SetlistsScreen({super.key, required this.repository});

  final Repository repository;

  @override
  State<SetlistsScreen> createState() => _SetlistsScreenState();
}

class _SetlistsScreenState extends State<SetlistsScreen> {
  Repository get _repo => widget.repository;
  late final _teamId = Repository.personalTeamId(_repo.uid);
  // Jeden nasłuch na każdy śpiewnik, tworzony raz - nie przy każdym przebudowaniu.
  final _streams = <String, Stream<List<Playlist>>>{};

  Stream<List<Playlist>> _setlistsOf(String teamId) =>
      _streams[teamId] ??= _repo.playlists(teamId);

  Future<void> _create() async {
    final id = await createSetlist(context, _repo, _teamId);
    if (id != null && mounted) openSetlist(context, _repo, _teamId, id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moje setlisty')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.playlist_add),
        label: const Text('Nowa setlista'),
      ),
      body: ValueListenableBuilder<List<Team>>(
        valueListenable: _repo.teams,
        builder: (context, teams, _) => CustomScrollView(
          slivers: [
            _section(
              teamId: _teamId,
              title: 'Moje',
              icon: Icons.person_outline,
              empty: InfoState(
                icon: Icons.queue_music,
                title: 'Brak setlist',
                text:
                    'Ułóż piosenki w kolejności na mszę, próbę czy koncert. '
                    'Gotową setlistę udostępnisz w zespole jednym przyciskiem.',
                action: FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.playlist_add),
                  label: const Text('Utwórz setlistę'),
                ),
              ),
            ),
            for (final team in teams)
              if (!team.personal)
                _section(
                  teamId: team.id,
                  title: 'Udostępnione w „${team.name}”',
                  icon: Icons.groups_outlined,
                ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: MediaQuery.paddingOf(context).bottom + 88,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sekcja setlist jednego śpiewnika; pusta sekcja zespołu się nie pokazuje.
  Widget _section({
    required String teamId,
    required String title,
    required IconData icon,
    Widget? empty,
  }) {
    final theme = Theme.of(context);
    return StreamBuilder<List<Playlist>>(
      stream: _setlistsOf(teamId),
      builder: (context, snapshot) {
        final setlists = snapshot.data;
        if (snapshot.hasError) {
          return SliverToBoxAdapter(
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(title),
              subtitle: Text('Nie udało się wczytać: ${snapshot.error}'),
            ),
          );
        }
        if (setlists == null) {
          return const SliverToBoxAdapter(child: LinearProgressIndicator());
        }
        if (setlists.isEmpty) {
          return SliverToBoxAdapter(child: empty ?? const SizedBox.shrink());
        }
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: setlists.length,
              itemBuilder: (context, i) => SetlistTile(
                setlist: setlists[i],
                onTap: () =>
                    openSetlist(context, _repo, teamId, setlists[i].id),
              ),
            ),
          ],
        );
      },
    );
  }
}

class SetlistTile extends StatelessWidget {
  const SetlistTile({super.key, required this.setlist, required this.onTap});

  final Playlist setlist;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colors.tertiaryContainer,
        foregroundColor: colors.onTertiaryContainer,
        child: const Icon(Icons.queue_music),
      ),
      title: Text(setlist.name),
      subtitle: Text(
        [
          if (setlist.date != null) formatDate(context, setlist.date!),
          songsCount(setlist.songIds.length),
        ].join(' · '),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

/// Pyta o nazwę i datę, tworzy setlistę (w zespole od razu pojawia się na
/// czacie) i zwraca jej id.
Future<String?> createSetlist(
  BuildContext context,
  Repository repository,
  String teamId,
) async {
  final details = await showSetlistDialog(
    context,
    title: 'Nowa setlista',
    confirmLabel: 'Utwórz',
  );
  if (details == null || !context.mounted) return null;
  // W zespole setlista od razu trafia na czat - zapytaj, czy na pewno.
  final team = repository.team(teamId);
  if (team != null && !team.personal) {
    final ok = await confirm(
      context,
      title: 'Udostępnić setlistę?',
      message:
          '„${details.name}” zostanie udostępniona zespołowi „${team.name}” - '
          'wszyscy członkowie zobaczą ją na czacie i będą mogli ją otworzyć.',
      confirmLabel: 'Utwórz i udostępnij',
    );
    if (!ok) return null;
  }
  final id = repository.newPlaylistId(teamId);
  repository
      .createPlaylist(teamId, id, name: details.name, date: details.date)
      .catchError((Object e) => showMessage('Nie udało się utworzyć: $e'));
  return id;
}

void openSetlist(
  BuildContext context,
  Repository repository,
  String teamId,
  String setlistId,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => SetlistScreen(
        repository: repository,
        teamId: teamId,
        setlistId: setlistId,
      ),
    ),
  );
}
