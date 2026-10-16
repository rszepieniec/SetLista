import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../data/repository.dart';
import '../home/dashboard_screen.dart';
import 'login_screen.dart';

/// Pokazuje logowanie albo śpiewnik, zależnie od tego, czy ktoś jest zalogowany.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return _SignedIn(key: ValueKey(user.uid), user: user);
      },
    );
  }
}

class _SignedIn extends StatefulWidget {
  const _SignedIn({super.key, required this.user});

  final User user;

  @override
  State<_SignedIn> createState() => _SignedInState();
}

class _SignedInState extends State<_SignedIn> {
  final _repository = Repository();
  late final Future<void> _setup = _repository.ensureUserSetup(widget.user);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _setup,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nie udało się przygotować konta\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: FirebaseAuth.instance.signOut,
                      child: const Text('Wyloguj'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return DashboardScreen(repository: _repository, user: widget.user);
      },
    );
  }
}
