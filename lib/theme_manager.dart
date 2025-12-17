// Code ya: JEMBE TALK APP
// Dosiye: lib/theme_manager.dart
// IYI NI VERSION NSHASHA YA NYUMA IKEMURA IKIBazo CYA FONTSIZE BURUNDU

import 'package:flutter/material.dart';
import 'package:jembe_talk/language_provider.dart';
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

  String getFontSizeLabel(LanguageProvider lang) {
    if (_fontSizeMultiplier < 0.9) return lang.t('font_size_xsmall');
    if (_fontSizeMultiplier < 1.0) return lang.t('font_size_small');
    if (_fontSizeMultiplier == 1.0) return lang.t('font_size_medium');
    if (_fontSizeMultiplier < 1.15) return lang.t('font_size_large');
    return lang.t('font_size_xlarge');
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

  // << IMPINDUKA NYAMUKURU: Twahinduye iyi function kugira ikore neza kandi yizewe >>
  TextTheme _buildTextTheme(TextTheme baseTheme, Color textColor, Color subTextColor) {
    String? effectiveFontFamily = _fontFamily == 'SystemDefault' ? null : _fontFamily;
    
    // Ubu buryo bwo gukoresha .copyWith() ni bwo bwizewe kuruta .apply()
    return baseTheme.copyWith(
      displayLarge: baseTheme.displayLarge?.copyWith(fontSize: 96 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
      displayMedium: baseTheme.displayMedium?.copyWith(fontSize: 60 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
      displaySmall: baseTheme.displaySmall?.copyWith(fontSize: 48 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
      headlineMedium: baseTheme.headlineMedium?.copyWith(fontSize: 34 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: textColor),
      headlineSmall: baseTheme.headlineSmall?.copyWith(fontSize: 24 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: textColor),
      titleLarge: baseTheme.titleLarge?.copyWith(fontSize: 20 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: textColor),
      titleMedium: baseTheme.titleMedium?.copyWith(fontSize: 16 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
      titleSmall: baseTheme.titleSmall?.copyWith(fontSize: 14 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
      bodyLarge: baseTheme.bodyLarge?.copyWith(fontSize: 16 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: textColor),
      bodyMedium: baseTheme.bodyMedium?.copyWith(fontSize: 14 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
      bodySmall: baseTheme.bodySmall?.copyWith(fontSize: 12 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
      labelLarge: baseTheme.labelLarge?.copyWith(fontSize: 14 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: textColor),
      labelSmall: baseTheme.labelSmall?.copyWith(fontSize: 10 * _fontSizeMultiplier, fontFamily: effectiveFontFamily, color: subTextColor),
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
        primary: Color(0xFF1565C0),
        secondary: Color(0xFF1976D2),
        onSecondary: Colors.white,
        background: Color(0xFFF0F2F5),
        surface: Colors.white,
      ),
      dialogBackgroundColor: Colors.white,
      dividerColor: Colors.grey.shade300,
      textTheme: _buildTextTheme(base.textTheme, Colors.black87, Colors.black54),
    );
  }

  ThemeData get getDarkTheme {
    final base = ThemeData.dark();
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0D1B2A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1B263B),
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
      textTheme: _buildTextTheme(base.textTheme, Colors.white, Colors.white70),
    );
  }
}