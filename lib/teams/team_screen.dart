import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../data/repository.dart';
import '../messages.dart';
import '../models.dart';
import '../widgets.dart';

/// Ustawienia zespołu: zaproszenia, członkowie i role, opuszczenie/usunięcie.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key, required this.repository, required this.teamId});

  final Repository repository;
  final String teamId;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Team>>(
      valueListenable: repository.teams,
      builder: (context, _, _) {
        final team = repository.team(teamId);
        // Zespół zniknął z listy (opuszczony/usunięty) - ekran zaraz się zamknie.
        if (team == null) return Scaffold(appBar: AppBar());
        return _TeamView(repository: repository, team: team);
      },
    );
  }
}

class _TeamView extends StatelessWidget {
  const _TeamView({required this.repository, required this.team});

  final Repository repository;
  final Team team;

  String get _uid => repository.uid;

  Future<void> _invite(BuildContext context) async {
    try {
      final code = await repository.createInvite(team);
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _InviteDialog(team: team, code: code),
      );
    } catch (e) {
      showMessage('Nie udało się utworzyć zaproszenia: $e');
    }
  }

  Future<void> _rename(BuildContext context) async {
    final name = await askForText(
      context,
      title: 'Nazwa zespołu',
      label: 'Nazwa',
      confirmLabel: 'Zapisz',
      initialValue: team.name,
    );
    if (name == null) return;
    repository
        .renameTeam(team, name)
        .catchError((Object e) => showMessage('Nie udało się: $e'));
  }

  Future<void> _memberAction(
    BuildContext context,
    String memberId,
    String action,
  ) async {
    try {
      if (action == 'remove') {
        final ok = await confirm(
          context,
          title: 'Usunąć z zespołu?',
          message:
              '${team.nameOf(memberId)} straci dostęp do piosenek, '
              'playlist i czatu zespołu.',
          confirmLabel: 'Usuń',
          destructive: true,
        );
        if (ok) await repository.removeMember(team, memberId);
      } else {
        await repository.setRole(team, memberId, action);
      }
    } catch (e) {
      showMessage('Nie udało się: $e');
    }
  }

  Future<void> _leave(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Opuścić zespół?',
      message:
          'Stracisz dostęp do piosenek, playlist i czatu „${team.name}”. '
          'Wrócić możesz tylko z nowym zaproszeniem.',
      confirmLabel: 'Opuść',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await repository.leaveTeam(team);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      showMessage('Nie udało się: $e');
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirm(
      context,
      title: 'Usunąć zespół?',
      message:
          'Zespół „${team.name}” zniknie dla wszystkich członków razem '
          'z piosenkami, playlistami i czatem. Tego nie da się cofnąć.',
      confirmLabel: 'Usuń zespół',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await repository.deleteTeam(team);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      showMessage('Nie udało się: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOwner = team.isOwner(_uid);
    final canInvite = team.canEdit(_uid);
    final members = [...team.memberIds]
      ..sort((a, b) {
        // Właściciel pierwszy, potem alfabetycznie.
        if (team.isOwner(a) != team.isOwner(b)) return team.isOwner(a) ? -1 : 1;
        return team.nameOf(a).compareTo(team.nameOf(b));
      });

    return Scaffold(
      appBar: AppBar(title: Text(team.name)),
      body: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom + 24,
        ),
        children: [
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: Text(team.name, style: theme.textTheme.titleMedium),
            subtitle: const Text('Nazwa zespołu'),
            trailing: team.canEdit(_uid)
                ? IconButton(
                    tooltip: 'Zmień nazwę',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _rename(context),
                  )
                : null,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card.filled(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Zaproś do zespołu',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      canInvite
                          ? 'Wyślij kod np. przez Messengera. Osoba wpisuje go '
                                'na ekranie startowym: „Dołącz kodem”. Kod działa 7 dni.'
                          : 'Kody zaproszeń tworzą właściciel i edytorzy zespołu.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (canInvite) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _invite(context),
                        icon: const Icon(Icons.person_add_alt_1),
                        label: const Text('Utwórz kod zaproszenia'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'Członkowie (${members.length})',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          _PresenceBuilder(
            repository: repository,
            uids: members,
            builder: (presence) => Column(
              children: [
                for (final memberId in members)
                  ListTile(
                    leading: _PresenceAvatar(
                      name: team.nameOf(memberId),
                      presence: presence[memberId],
                    ),
                    title: Text(
                      memberId == _uid
                          ? '${team.nameOf(memberId)} (Ty)'
                          : team.nameOf(memberId),
                    ),
                    subtitle: Text(
                      [
                        roleLabel(team.roleOf(memberId)),
                        _presenceLabel(
                          presence[memberId],
                          isMe: memberId == _uid,
                        ),
                      ].where((s) => s.isNotEmpty).join(' · '),
                    ),
                    trailing: isOwner && memberId != _uid
                        ? PopupMenuButton<String>(
                            tooltip: 'Zmień rolę',
                            onSelected: (action) =>
                                _memberAction(context, memberId, action),
                            itemBuilder: (context) => [
                              CheckedPopupMenuItem(
                                value: 'editor',
                                checked: team.roleOf(memberId) == 'editor',
                                child: const Text('Edytor - dodaje i zmienia'),
                              ),
                              CheckedPopupMenuItem(
                                value: 'member',
                                checked: team.roleOf(memberId) == 'member',
                                child: const Text('Tylko odczyt'),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'remove',
                                child: Text('Usuń z zespołu'),
                              ),
                            ],
                          )
                        : null,
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          ListTile(
            leading: Icon(
              isOwner ? Icons.delete_forever_outlined : Icons.logout,
              color: theme.colorScheme.error,
            ),
            title: Text(
              isOwner ? 'Usuń zespół' : 'Opuść zespół',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => isOwner ? _delete(context) : _leave(context),
          ),
        ],
      ),
    );
  }
}

class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.team, required this.code});

  final Team team;
  final String code;

  String get _message =>
      'Dołącz do zespołu „${team.name}” w aplikacji SetLista: '
      'menu boczne, „Dołącz do zespołu”, kod ${formatInviteCode(code)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Kod zaproszenia'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SelectableText(
            formatInviteCode(code),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Ważny 7 dni. Każdy, kto go zna, może dołączyć jako edytor.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: formatInviteCode(code)));
            showMessage('Skopiowano kod');
          },
          icon: const Icon(Icons.copy),
          label: const Text('Kopiuj'),
        ),
        FilledButton.icon(
          onPressed: () {
            final box = context.findRenderObject() as RenderBox?;
            SharePlus.instance.share(
              ShareParams(
                text: _message,
                subject: 'Zaproszenie do zespołu ${team.name}',
                // Wymagane na iPadzie - skąd ma "wyskoczyć" okno udostępniania.
                sharePositionOrigin: box == null
                    ? null
                    : box.localToGlobal(Offset.zero) & box.size,
              ),
            );
          },
          icon: const Icon(Icons.share),
          label: const Text('Udostępnij'),
        ),
      ],
    );
  }
}

/// Statusy obecności członków: nasłuch tylko na czas otwartego ekranu
/// i odświeżanie co 30 s (żeby "teraz" zmieniło się w "5 min temu").
class _PresenceBuilder extends StatefulWidget {
  const _PresenceBuilder({
    required this.repository,
    required this.uids,
    required this.builder,
  });

  final Repository repository;
  final List<String> uids;
  final Widget Function(Map<String, Presence> presence) builder;

  @override
  State<_PresenceBuilder> createState() => _PresenceBuilderState();
}

class _PresenceBuilderState extends State<_PresenceBuilder> {
  late Stream<Map<String, Presence>> _stream = widget.repository.presence(
    widget.uids,
  );
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 30),
      (_) => setState(() {}),
    );
  }

  @override
  void didUpdateWidget(_PresenceBuilder old) {
    super.didUpdateWidget(old);
    if (!listEquals(old.uids, widget.uids)) {
      _stream = widget.repository.presence(widget.uids);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, Presence>>(
    stream: _stream,
    builder: (context, snapshot) => widget.builder(snapshot.data ?? const {}),
  );
}

/// Awatar z kropką: zielona - ma teraz otwartą aplikację, szara - nie.
class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({required this.name, required this.presence});

  final String name;
  final Presence? presence;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final active = presence?.isActive ?? false;
    return Badge(
      smallSize: 12,
      backgroundColor: active ? Colors.green.shade600 : colors.outlineVariant,
      alignment: AlignmentDirectional.bottomEnd,
      child: CircleAvatar(child: Text(name.characters.first.toUpperCase())),
    );
  }
}

String _presenceLabel(Presence? presence, {required bool isMe}) {
  if (isMe) return 'w aplikacji';
  if (presence == null || presence.lastActive == null) return '';
  if (presence.isActive) return 'w aplikacji';
  final ago = DateTime.now().difference(presence.lastActive!);
  if (ago.inMinutes < 60) return 'ostatnio ${ago.inMinutes} min temu';
  if (ago.inHours < 24) return 'ostatnio ${ago.inHours} godz. temu';
  if (ago.inDays == 1) return 'ostatnio wczoraj';
  return 'ostatnio ${ago.inDays} dni temu';
}
