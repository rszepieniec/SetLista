import 'package:flutter/material.dart';

import '../chat/chat_tab.dart';
import '../data/repository.dart';
import '../models.dart';
import '../song_list_screen.dart';
import '../teams/team_screen.dart';

/// Zespół: zakładki Czat (setlisty i zmiany pojawiają się tutaj) i Piosenki.
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({
    super.key,
    required this.repository,
    required this.teamId,
  });

  final Repository repository;
  final String teamId;

  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  var _tab = 0;

  Repository get _repo => widget.repository;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Team>>(
      valueListenable: _repo.teams,
      builder: (context, _, _) {
        final team = _repo.team(widget.teamId);
        if (team == null) {
          // Zespół zniknął (opuszczony, usunięty, ktoś nas usunął) - wracamy.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(team.name),
            actions: [
              IconButton(
                tooltip: 'Członkowie i zaproszenia',
                icon: const Icon(Icons.group_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TeamScreen(repository: _repo, teamId: team.id),
                  ),
                ),
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              ChatTab(
                repository: _repo,
                team: team,
                active: _tab == 0,
                onShowSongs: () => setState(() => _tab = 1),
              ),
              SongListScreen(repository: _repo, team: team),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.forum_outlined),
                selectedIcon: Icon(Icons.forum),
                label: 'Czat',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music),
                label: 'Piosenki',
              ),
            ],
          ),
        );
      },
    );
  }
}
