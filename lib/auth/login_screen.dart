import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../debug_log.dart';
import '../messages.dart';

enum _Mode { signIn, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _mode = _Mode.signIn;
  var _busy = false;
  var _obscure = true;
  String? _error;

  FirebaseAuth get _auth => FirebaseAuth.instance;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final email = _email.text.trim();
      if (_mode == _Mode.signIn) {
        await traced(
          'auth: signInWithEmailAndPassword($email)',
          () => _auth.signInWithEmailAndPassword(
            email: email,
            password: _password.text,
          ),
          describe: (c) => 'uid=${c.user?.uid}',
        );
      } else {
        final cred = await traced(
          'auth: createUserWithEmailAndPassword($email)',
          () => _auth.createUserWithEmailAndPassword(
            email: email,
            password: _password.text,
          ),
          describe: (c) => 'uid=${c.user?.uid}',
        );
        final name = _name.text.trim();
        await traced(
          'auth: updateDisplayName("$name")',
          () => cred.user!.updateDisplayName(name),
        );
      }
      // AuthGate sam przełączy ekran po zalogowaniu.
    } on FirebaseAuthException catch (e) {
      setState(() => _error = authErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Wpisz najpierw swój e-mail powyżej.');
      return;
    }
    try {
      await traced(
        'auth: sendPasswordResetEmail($email)',
        () => _auth.sendPasswordResetEmail(email: email),
      );
      showMessage('Wysłaliśmy link do zmiany hasła na $email');
    } on FirebaseAuthException catch (e) {
      setState(() => _error = authErrorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final register = _mode == _Mode.register;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.queue_music,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'SetLista',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Śpiewnik dla Ciebie i Twojego zespołu',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 32),
                      SegmentedButton<_Mode>(
                        segments: const [
                          ButtonSegment(
                            value: _Mode.signIn,
                            label: Text('Logowanie'),
                          ),
                          ButtonSegment(
                            value: _Mode.register,
                            label: Text('Rejestracja'),
                          ),
                        ],
                        selected: {_mode},
                        showSelectedIcon: false,
                        onSelectionChanged: (s) => setState(() {
                          _mode = s.first;
                          _error = null;
                        }),
                      ),
                      const SizedBox(height: 24),
                      if (register) ...[
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Imię',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Podaj imię - zobaczą je inni w zespole'
                              : null,
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (v) => (v ?? '').trim().contains('@')
                            ? null
                            : 'Podaj poprawny adres e-mail',
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        onFieldSubmitted: (_) => _busy ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Hasło',
                          helperText: register ? 'Co najmniej 6 znaków' : null,
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Pokaż hasło' : 'Ukryj hasło',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Podaj hasło';
                          if (register && v!.length < 6) {
                            return 'Hasło musi mieć co najmniej 6 znaków';
                          }
                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ],
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(register ? 'Załóż konto' : 'Zaloguj się'),
                      ),
                      if (!register)
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Nie pamiętam hasła'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String authErrorMessage(FirebaseAuthException e) => switch (e.code) {
  'invalid-email' => 'Niepoprawny adres e-mail.',
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' => 'Zły e-mail lub hasło.',
  'user-disabled' => 'To konto zostało zablokowane.',
  'email-already-in-use' => 'Konto z tym adresem już istnieje - zaloguj się.',
  'weak-password' => 'Hasło jest za słabe - użyj co najmniej 6 znaków.',
  'too-many-requests' => 'Za dużo prób. Spróbuj ponownie za chwilę.',
  'network-request-failed' => 'Brak połączenia z internetem.',
  'operation-not-allowed' =>
    'Logowanie e-mailem nie jest włączone w Firebase '
        '(konsola: Authentication, Sign-in method, Email/Password).',
  'configuration-not-found' =>
    'Logowanie nie jest jeszcze skonfigurowane w Firebase '
        '(konsola: Authentication, Get started, potem włącz Email/Password).',
  _ => 'Coś poszło nie tak (${e.code}): ${e.message ?? ''}',
};
