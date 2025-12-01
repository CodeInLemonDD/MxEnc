import 'package:shared_preferences/shared_preferences.dart';

/// 设置服务，用于管理用户偏好设置
class SettingsService {
  static const String _nightModeKey = 'night_mode';
  static const String _appLockKey = 'app_lock';
  static const String _themeKey = 'theme';
  
  SharedPreferences? _prefs;
  
  /// 初始化 SharedPreferences
  Future<void> _initPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
  }
  
  /// 获取夜间模式状态
  Future<bool> getNightMode() async {
    await _initPrefs();
    return _prefs!.getBool(_nightModeKey) ?? false;
  }
  
  /// 设置夜间模式状态
  Future<void> setNightMode(bool value) async {
    await _initPrefs();
    await _prefs!.setBool(_nightModeKey, value);
  }
  
  /// 获取应用锁状态
  Future<bool> getAppLock() async {
    await _initPrefs();
    return _prefs!.getBool(_appLockKey) ?? false;
  }
  
  /// 设置应用锁状态
  Future<void> setAppLock(bool value) async {
    await _initPrefs();
    await _prefs!.setBool(_appLockKey, value);
  }
  
  /// 获取主题色
  Future<String> getTheme() async {
    await _initPrefs();
    return _prefs!.getString(_themeKey) ?? '默认';
  }
  
  /// 设置主题色
  Future<void> setTheme(String theme) async {
    await _initPrefs();
    await _prefs!.setString(_themeKey, theme);
  }
}

