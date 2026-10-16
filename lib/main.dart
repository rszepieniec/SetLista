import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'auth/auth_gate.dart';
import 'debug_log.dart';
import 'firebase_options.dart';
import 'messages.dart';
import 'preferences.dart';

/// `flutter run --dart-define=USE_EMULATOR=true` łączy z lokalnym emulatorem
/// Firebase (`firebase emulators:start`) zamiast z prawdziwym projektem.
const _useEmulator = bool.fromEnvironment('USE_EMULATOR');

/// `--dart-define=FIREBASE_VERBOSE=true` włącza dodatkowo bardzo szczegółowe
/// logi samego SDK Firestore (każda wiadomość wysłana/odebrana z serwera).
const _verboseFirestore = bool.fromEnvironment('FIREBASE_VERBOSE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  if (_useEmulator) {
    // Emulator Androida widzi komputer pod 10.0.2.2.
    final host = defaultTargetPlatform == TargetPlatform.android
        ? '10.0.2.2'
        : 'localhost';
    await FirebaseAuth.instance.useAuthEmulator(host, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  }
  await FirebaseAuth.instance.setLanguageCode('pl');
  await loadPreferences();
  if (_verboseFirestore) await FirebaseFirestore.setLoggingEnabled(true);

  final options = Firebase.app().options;
  logFirebase(
    'start: projekt=${options.projectId}, '
    '${_useEmulator ? 'EMULATOR (localhost)' : 'PRAWDZIWY Firebase'}, '
    'platforma=${kIsWeb ? 'web' : defaultTargetPlatform.name}',
  );
  FirebaseAuth.instance.authStateChanges().listen(
    (user) => logFirebase(
      user == null
          ? 'auth: wylogowany'
          : 'auth: zalogowany uid=${user.uid} (${user.email})',
    ),
  );
  runApp(const SongViewerApp());
}

class SongViewerApp extends StatelessWidget {
  const SongViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Colors.indigo;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeMode,
      builder: (context, mode, _) => MaterialApp(
        themeMode: mode,
        title: 'SetLista',
        debugShowCheckedModeBanner: false,
        // Komunikaty u góry ekranu korzystają z nakładki nawigatora.
        navigatorKey: navigatorKey,
        theme: ThemeData(colorSchemeSeed: seed),
        darkTheme: ThemeData(
          colorSchemeSeed: seed,
          brightness: Brightness.dark,
        ),
        // Polskie teksty we wbudowanych elementach (kalendarz, "Wklej", daty).
        locale: const Locale('pl'),
        supportedLocales: const [Locale('pl'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const AuthGate(),
      ),
    );
  }
}

// TODO:
// 1. Rozwinięcie wyswietlania tekstów - dodanie kolejnej opcji -
//    robienie tego w slajdach 3/4 kafelki na górze pierwsza wzrotka, kolejna wzrotka refren/ bridge?.
//    ogarnąć jakie dane są w formacie sng, czy jest tam refren itd.
// 2. integracja chwytów do tego? popytać moni/kacpra
// 3. rozwinięcie search engine, jak tanio i szybko zrobić wyszukiwanie po tekście,
//    tytule, vibe'ie ogólnym, tematyce, nastroju, - zreaserchować mądre rozwiązanie, 
// 4. integracja z worshipem, export - gotowy spiewnik wyeksportować do gotowego zipa
//   - folderu z plikami w sng (po słowacku?xd)
// 5. przetestować czy edycja udsotepnionej playlisty działa (równiez przez osoby,
//    które nie są jej autorami), np kolejności, itd. dodaj wiadomość (może być mała wiadomość w czacie)
// 6. IrealPro zobaczyć czy mozliwe jest przekierowanie do piosenki w tamtej apce, 
// 7. Dodać mozliwość customowania labelów do piosenek 
