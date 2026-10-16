import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Logi komunikacji z Firebase. Widać je w terminalu `flutter run`,
/// w Debug Console w VS Code i w konsoli przeglądarki (wersja webowa).
/// W wersji release (`flutter build ... --release`) są wyłączone.
///
/// Nigdy nie logujemy haseł ani tokenów.
void logFirebase(String message) {
  if (kDebugMode) debugPrint('[firebase] $message');
}

String describeError(Object error) => error is FirebaseException
    ? '[${error.plugin}/${error.code}] ${error.message}'
    : '$error';

/// Loguje zapytanie, a potem odpowiedź albo błąd, razem z czasem trwania.
Future<T> traced<T>(
  String request,
  Future<T> Function() call, {
  String Function(T result)? describe,
}) async {
  logFirebase('→ $request');
  final stopwatch = Stopwatch()..start();
  try {
    final result = await call();
    final details = describe == null ? '' : ': ${describe(result)}';
    logFirebase('← $request OK (${stopwatch.elapsedMilliseconds} ms)$details');
    return result;
  } catch (e) {
    logFirebase(
      '← $request BŁĄD (${stopwatch.elapsedMilliseconds} ms): ${describeError(e)}',
    );
    rethrow;
  }
}

/// Loguje start nasłuchu, każdą paczkę danych z serwera i błędy strumienia.
Stream<T> tracedStream<T>(
  String request,
  Stream<T> stream, {
  required String Function(T event) describe,
}) {
  logFirebase('→ nasłuch: $request');
  return stream.transform(
    StreamTransformer.fromHandlers(
      handleData: (event, sink) {
        logFirebase('← $request: ${describe(event)}');
        sink.add(event);
      },
      handleError: (error, stackTrace, sink) {
        logFirebase('← $request BŁĄD: ${describeError(error)}');
        sink.addError(error, stackTrace);
      },
    ),
  );
}
