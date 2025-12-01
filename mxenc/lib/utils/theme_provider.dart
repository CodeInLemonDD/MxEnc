import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode_dark';
  static const _seedKey = 'theme_seed_color';
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  Color? _seedColor;
  Color? get seedColor => _seedColor;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool(_key);
    final seed = prefs.getInt(_seedKey);
    if (isDark == null) {
      _mode = ThemeMode.system;
    } else {
      _mode = isDark ? ThemeMode.dark : ThemeMode.light;
    }
    _seedColor = seed != null ? Color(seed) : null;
    notifyListeners();
  }

  Future<void> setDarkMode(bool dark) async {
    _mode = dark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, dark);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedKey, color.toARGB32());
    notifyListeners();
  }
}
