import 'data/repository.dart' show songsCount;
import 'models.dart';

/// Czas przeszły, zawsze w formie neutralnej: od formy męskiej 3. osoby
/// ("dodał") robi "dodał(a)", a do zalogowanej osoby ([you]) "dodałeś(-aś)".
String pastTense(String masculine, {required bool you}) =>
    you ? '${masculine}eś(-aś)' : '$masculine(a)';

/// "Dołączyłeś(-aś) do zespołu" - komunikat do zalogowanej osoby, z wielkiej litery.
String youDid(String masculine, String rest) {
  final verb = pastTense(masculine, you: true);
  return '${verb[0].toUpperCase()}${verb.substring(1)} $rest';
}

/// Treść zdarzenia bez podmiotu, np. "dodał(a) piosenkę „Barka”" albo - gdy to
/// moje zdarzenie - "dodałeś(-aś) piosenkę „Barka”". Podmiot ("Adam", "Ty")
/// dokleja wywołujący.
String describeEvent(ChatMessage m, {required bool mine}) {
  if (m.type == MessageType.text) return m.text;
  String v(String verb) => pastTense(verb, you: mine);
  // Najstarsze wiadomości mają gotowy tekst w czasie teraźniejszym
  // ("dodaje piosenkę „Barka”") - tytuł i liczbę wyciągamy z tego tekstu.
  final subject =
      m.subject ?? RegExp('„([^”]*)”').firstMatch(m.text)?.group(1) ?? '';
  final count =
      m.count ??
      int.tryParse(RegExp(r'\((\d+) ').firstMatch(m.text)?.group(1) ?? '');
  // Komentarz: nowe wiadomości mają w text sam fragment, stare całe zdanie.
  final commentText = m.legacy && m.text.contains('”: ')
      ? m.text.substring(m.text.indexOf('”: ') + 3)
      : m.text;
  return switch (m.type) {
    MessageType.setlist =>
      '${v('udostępnił')} setlistę „$subject”'
          '${count == null ? '' : ' (${songsCount(count)})'}',
    MessageType.songAdded => '${v('dodał')} piosenkę „$subject”',
    MessageType.songUpdated => '${v('zmienił')} piosenkę „$subject”',
    MessageType.songsImported =>
      '${v('dodał')} ${songsCount(count ?? 0)} do śpiewnika zespołu',
    MessageType.comment => '${v('skomentował')} „$subject”: $commentText',
    MessageType.joined => '${v('dołączył')} do zespołu',
    MessageType.left => '${v('opuścił')} zespół',
    MessageType.teamCreated => '${v('utworzył')} zespół „$subject”',
    MessageType.teamRenamed => '${v('zmienił')} nazwę zespołu na „$subject”',
    MessageType.text => m.text,
  };
}

/// Pełne zdanie: "Ty dodałeś(-aś) piosenkę „Barka”" / "Adam dodał(a) piosenkę „Barka”".
String eventSentence(ChatMessage m, {required bool mine}) {
  final who = mine ? 'Ty' : (m.authorName.isEmpty ? 'Ktoś' : m.authorName);
  return '$who ${describeEvent(m, mine: mine)}';
}
