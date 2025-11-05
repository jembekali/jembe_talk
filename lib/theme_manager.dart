// Code ya: JEMBE TALK APP
// Dosiye: lib/theme_manager.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager with ChangeNotifier {
  final SharedPreferences _prefs;
  ThemeMode _themeMode;
  double _fontSizeMultiplier;
  String _fontFamily;

  ThemeManager(this._prefs)
      : _themeMode = _loadThemeFromPrefs(_prefs),
        _fontSizeMultiplier = _prefs.getDouble('fontSizeMultiplier') ?? 1.0,
        _fontFamily = _prefs.getString('fontFamily') ?? 'SystemDefault';

  // Getters
  ThemeMode get themeMode => _themeMode;
  double get fontSizeMultiplier => _fontSizeMultiplier;
  String get fontFamily => _fontFamily;

  String get fontSizeLabel {
    if (_fontSizeMultiplier < 0.7) return "Ntoya cane";
    if (_fontSizeMultiplier < 1.0) return "Ntoya";
    if (_fontSizeMultiplier == 1.5) return "Iringaniye";
    if (_fontSizeMultiplier < 1.20) return "Nini";
    return "Nini cane";
  }

  // Setters
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setString('themeMode', mode.name);
    notifyListeners();
  }

  Future<void> setFontSize(double multiplier) async {
    _fontSizeMultiplier = multiplier;
    await _prefs.setDouble('fontSizeMultiplier', multiplier);
    notifyListeners();
  }

  Future<void> setFontFamily(String family) async {
    _fontFamily = family;
    await _prefs.setString('fontFamily', family);
    notifyListeners();
  }

  static ThemeMode _loadThemeFromPrefs(SharedPreferences prefs) {
    final themeString = prefs.getString('themeMode');
    return ThemeMode.values.firstWhere((e) => e.name == themeString, orElse: () => ThemeMode.system);
  }

  TextTheme _buildTextTheme(TextTheme baseTheme) {
    return baseTheme.apply(
      fontFamily: _fontFamily == 'SystemDefault' ? null : _fontFamily,
      fontSizeFactor: _fontSizeMultiplier,
    );
  }

  ThemeData get getLightTheme {
    final base = ThemeData.light();
    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF0F2F5),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF1565C0), // Ubururu bwerurutse
        secondary: Color(0xFF1976D2), // Ubururu bwimbitse
        onSecondary: Colors.white,
        background: Color(0xFFF0F2F5),
        surface: Colors.white,
      ),
      dialogBackgroundColor: Colors.white,
      dividerColor: Colors.grey.shade300,
      textTheme: _buildTextTheme(base.textTheme).copyWith(
        bodyLarge: const TextStyle(color: Colors.black87),
        bodyMedium: const TextStyle(color: Colors.black54),
      ),
    );
  }

  ThemeData get getDarkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      brightness: Brightness.dark,
      // <<-- NZOKWIBUKA KO AHA NAKORESHEJE IBARA RISHASHA RY'UBURURU BWIJIMYE -->>
      scaffoldBackgroundColor: const Color(0xFF0D1B2A), // Ubururu bwijimye cane
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1B263B), // Ubururu bwijimye bukeye gato
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF415A77),
        secondary: Color(0xFF778DA9),
        onSecondary: Colors.white,
        background: Color(0xFF0D1B2A),
        surface: Color(0xFF1B263B),
      ),
      dialogBackgroundColor: const Color(0xFF1B263B),
      dividerColor: Colors.white24,
      textTheme: _buildTextTheme(base.textTheme).copyWith(
        bodyLarge: const TextStyle(color: Colors.white),
        bodyMedium: const TextStyle(color: Colors.white70),
      ),
    );
  }
}