# SetLista

Mobilny śpiewnik dla zespołów muzycznych, chórów i grup, które grają razem na próbach, koncertach czy zwykłych spotkaniach ze śpiewaniem.

> **Status:** propozycja projektu na przedmiot *Systemy mobilne*. To wstępna koncepcja z działającym prototypem części funkcji, a nie skończona aplikacja. Zakres może się jeszcze zmienić.

## Spis treści

- [Postęp prac](#postęp-prac)
- [Pomysł](#pomysł)
- [Funkcje](#funkcje)
- [Funkcje opcjonalne](#funkcje-opcjonalne)
- [Technologie](#technologie)
- [Uruchomienie](#uruchomienie)
- [Testy](#testy)
- [Struktura projektu](#struktura-projektu)

## Postęp prac

Dziennik prac, uzupełniany mniej więcej raz w miesiącu. Najnowsze wpisy są na górze.

### Październik 2026

- Projekt Flutter (iOS, Android, web) podłączony do Firebase: projekt `setlista-app`, Authentication, Cloud Firestore w regionie `europe-central2`.
- Logowanie i rejestracja e-mailem, reset hasła i komunikaty błędów po polsku.
- **Mój śpiewnik:** dodawanie, edycja i usuwanie piosenek z historią wersji. Polskie sortowanie i wyszukiwanie bez polskich znaków. Scalony widok piosenek z Mojego śpiewnika i ze wszystkich zespołów, bez duplikatów, z etykietami źródła i filtrami.
- **Import wielu piosenek naraz:** `.txt`, `.md`, `.zip` i pliki `.sng` starszego programu (sprawdzone na 286 prawdziwych plikach). Rozpoznawanie kodowań UTF-8, UTF-16 i Windows-1250, podgląd przed importem i pomijanie duplikatów.
- **Zespoły:** tworzenie, kody zaproszeń (tworzą je właściciel i edytorzy), role (właściciel, edytor, tylko odczyt), zmiana nazwy, opuszczanie i usuwanie zespołu, status „w aplikacji” przy członkach.
- **Setlisty:** tworzenie z datą, kolejność ustawiana przeciąganiem i udostępnianie zespołowi. Piosenki z innych śpiewników są dokopiowywane bez duplikatów. „Moje setlisty” są pogrupowane według zespołów.
- **Czat zespołu:** wiadomości, zdarzenia w czasie przeszłym („Ty dodałeś(-aś) piosenkę…”) z przyciskiem „Otwórz”, nagłówki dni z godziną i oznaczanie nieprzeczytanych wiadomości na ekranie startowym.
- Komentarze do piosenek.
- Ekran startowy z kafelkami: Mój śpiewnik, Moje setlisty i zespoły.
- Zapamiętywanie motywu jasnego/ciemnego i rozmiaru tekstu piosenek.
- Reguły bezpieczeństwa Firestore z 40 testami na emulatorze oraz 37 testów logiki aplikacji.

<!--
Szablon kolejnego wpisu:

### Miesiąc RRRR

- Co zostało zrobione.
- Co zmieniło się w założeniach.
- Co dalej.
-->

## Pomysł

Zespoły często korzystają z papierowych śpiewników, plików rozsyłanych na komunikatorach albo starszych programów desktopowych do wyświetlania tekstów. SetLista zbiera to w jednej aplikacji na telefon:

- każdy ma **własny śpiewnik** zawsze przy sobie, także bez internetu;
- zespół ma **wspólną bazę piosenek**, z której wszyscy korzystają;
- **setlisty** określają kolejność piosenek na konkretne wydarzenie;
- **czat zespołu** pokazuje ustalenia i wszystkie zmiany w jednym miejscu.

Przykładowe zastosowania: zespół grający covery, chór, grupa na próbach, ognisko z gitarą, nauczyciel muzyki z uczniami.

## Funkcje

| Obszar | Funkcja |
|---|---|
| Mój śpiewnik | Prywatne piosenki oraz piosenki ze wszystkich moich zespołów, bez powtórek, z oznaczeniem źródła |
| Zespoły | Dołączanie przez kod zaproszenia, role: właściciel, edytor, tylko odczyt |
| Zespoły | Status członków: kto ma teraz otwartą aplikację |
| Setlisty | Kolejność piosenek na próbę, koncert lub występ, udostępniana zespołowi jednym przyciskiem |
| Czat | Wiadomości i automatyczne zdarzenia: nowa setlista, dodana lub zmieniona piosenka, komentarz, dołączenie do zespołu |
| Import | Wiele plików naraz z telefonu lub Dysku Google, elastyczny format, polskie kodowania |
| Granie | Przewijanie tekstu, rozmiar czcionki, przechodzenie między piosenkami gestem, tryb jasny i ciemny |
| Offline | Lokalna kopia danych: teksty działają bez internetu, a zmiany wysyłają się po powrocie połączenia |

## Funkcje opcjonalne

Pomysły do rozważenia w dalszej części projektu:

- **Przekierowanie do iReal Pro:** przycisk „Otwórz w iReal Pro” przy piosence i wysłanie całej setlisty jako playlisty. iReal Pro nie ma publicznego API, ale obsługuje schemat linków `irealbook://`, który otwiera aplikację i importuje akordy ([dokumentacja formatu](https://irealpro.com/ireal-pro-file-format/)).
- **Synchronizacja z zewnętrznymi źródłami:**
  - automatyczny import i aktualizacja piosenek z folderu na Dysku Google;
  - eksport setlisty do PDF lub do kalendarza (data wydarzenia);
  - kopia zapasowa śpiewnika do pliku.
- **Oznaczanie części piosenki:** refren, zwrotka i bridge, z wyróżnieniem refrenu i automatycznym rozpoznawaniem przy imporcie.
- **Akordy nad tekstem** i transpozycja tonacji.
- **Powiadomienia push** o nowych wiadomościach i setlistach. Wymagają planu Firebase Blaze (Cloud Functions), a na iOS konta Apple Developer.
- **Tryb prezentacji:** wyświetlanie tekstu na drugim ekranie lub rzutniku.

## Technologie

- **[Flutter](https://flutter.dev/)** (Dart): jedna aplikacja na iOS, Androida i przeglądarkę.
- **[Firebase Authentication](https://firebase.google.com/docs/auth):** konta użytkowników (e-mail i hasło).
- **[Cloud Firestore](https://firebase.google.com/docs/firestore):** baza danych z synchronizacją na żywo i trybem offline.
- **Reguły bezpieczeństwa Firestore** ([`firestore.rules`](firestore.rules)) jako backend: kontrolują, kto może czytać i zmieniać dane zespołu, więc nie jest potrzebny własny serwer.
- Pakiety: `file_picker` (wybór plików), `archive` (zip), `share_plus` (udostępnianie kodu zaproszenia), `shared_preferences` (ustawienia na urządzeniu).

### Model danych

```
users/{uid}                      profil, ostatnio przeczytane czaty
presence/{uid}                   czy ktoś ma otwartą aplikację
invites/{kod}                    kod zaproszenia do zespołu (ważny 7 dni)
teams/{teamId}                   zespół albo "Mój śpiewnik" (personal_<uid>)
  ├ songs/{songId}               piosenki
  │   ├ revisions/{id}           historia zmian
  │   └ comments/{id}            komentarze
  ├ playlists/{id}               setlisty
  ├ messages/{id}                czat i zdarzenia
  └ joins/{uid}                  kod, którym ktoś dołączył (do weryfikacji w regułach)
```

## Uruchomienie

Wymagania: Flutter SDK, a do emulatora Firebase CLI i Java 21 lub nowsza.

Na prawdziwym projekcie Firebase:

```bash
flutter run
```

Na lokalnym emulatorze Firebase, bez zmieniania prawdziwych danych. W jednym terminalu:

```bash
firebase emulators:start --only auth,firestore
```

W drugim terminalu:

```bash
flutter run --dart-define=USE_EMULATOR=true
```

W VS Code gotowe konfiguracje są w `.vscode/launch.json`: wybierz je w panelu Run and Debug i naciśnij F5. Logi zapytań do Firebase (`[firebase] …`) pojawiają się w Debug Console.

## Testy

Logika aplikacji (bez sieci, na fałszywym Firestore):

```bash
flutter test
```

Reguły bezpieczeństwa (na emulatorze Firestore), w folderze `firestore_tests`:

```bash
npm test
```

Wgranie reguł do projektu Firebase:

```bash
firebase deploy --only firestore:rules
```

## Struktura projektu

```
lib/
  main.dart              start aplikacji, Firebase, motyw
  data/repository.dart   cała komunikacja z Firestore
  models.dart, song.dart modele danych
  auth/                  logowanie i rejestracja
  home/                  ekran startowy, Mój śpiewnik, ekran zespołu
  chat/                  czat zespołu
  setlists/              setlisty
  teams/                 członkowie, zaproszenia, dołączanie
  import/                import piosenek z plików
  grammar.dart           treść zdarzeń na czacie
  preferences.dart       ustawienia zapamiętywane na urządzeniu
firestore.rules          reguły bezpieczeństwa (backend)
firestore_tests/         testy reguł
test/                    testy aplikacji
```
