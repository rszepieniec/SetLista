import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ustawienia zapamiętywane na tym urządzeniu: motyw i rozmiar tekstu piosenek.
/// (Na telefonie i tablecie można mieć inny rozmiar - dlatego nie w koncie.)

/// Jasny / ciemny / jak w systemie.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Rozmiar tekstu piosenki (przyciski A− / A+).
final lyricsFontSize = ValueNotifier<double>(20);
const minLyricsFontSize = 14.0;
const maxLyricsFontSize = 40.0;

const _themeKey = 'themeMode';
const _fontSizeKey = 'lyricsFontSize';

Future<void> loadPreferences() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    themeMode.value = ThemeMode.values.firstWhere(
      (m) => m.name == prefs.getString(_themeKey),
      orElse: () => ThemeMode.system,
    );
    lyricsFontSize.value = (prefs.getDouble(_fontSizeKey) ?? 20).clamp(
      minLyricsFontSize,
      maxLyricsFontSize,
    );
  } catch (_) {
    // Brak dostępu do pamięci urządzenia - zostają wartości domyślne.
  }
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeMode.value = mode;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  } catch (_) {}
}

Future<void> changeLyricsFontSize(double delta) async {
  final size = (lyricsFontSize.value + delta).clamp(
    minLyricsFontSize,
    maxLyricsFontSize,
  );
  lyricsFontSize.value = size;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, size);
  } catch (_) {}
}

String themeModeLabel(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'Jak w systemie',
  ThemeMode.light => 'Jasny',
  ThemeMode.dark => 'Ciemny',
};

IconData themeModeIcon(ThemeMode mode) => switch (mode) {
  ThemeMode.system => Icons.brightness_auto_outlined,
  ThemeMode.light => Icons.light_mode_outlined,
  ThemeMode.dark => Icons.dark_mode_outlined,
};
