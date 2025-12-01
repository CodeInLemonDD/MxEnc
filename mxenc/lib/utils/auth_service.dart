import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../rust_bridge.dart';

class AuthService {
  late SharedPreferences _prefs;
  static const String _premiumKey = 'premium_user';
  static const String _trialStartKey = 'trial_start_date';
  static const int _trialDays = 7;
  static const String _deviceIdKey = 'device_id';
  static const String _allowedDevicesKey = 'allowed_devices';
  
  // 模拟授权设备ID列表（实际应该从服务器获取）
  final List<String> _allowedDeviceIds = [];
  
  // 初始化SharedPreferences
  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // 检查是否是授权用户
  Future<bool> isPremiumUser() async {
    await _initPrefs();
    
    // 1. 检查是否直接设置为授权用户
    if (_prefs.getBool(_premiumKey) ?? false) {
      return true;
    }
    
    // 2. 检查是否在试用期内
    if (await isInTrialPeriod()) {
      return true;
    }
    
    // 3. 根据设备序列号判断权限
    try {
      final deviceId = await _getDeviceId();
      
      // 读取本地存储的允许设备列表
      final allowedDevices = _prefs.getStringList(_allowedDevicesKey) ?? [];
      
      // 检查当前设备是否在允许列表中
      return allowedDevices.contains(deviceId) || _allowedDeviceIds.contains(deviceId);
    } catch (e) {
      // 如果获取设备ID失败，返回false
      return false;
    }
  }

  // 获取设备ID（公共方法）
  Future<String> getDeviceId() async {
    return _getDeviceId();
  }

  // 获取设备ID（私有方法）
  Future<String> _getDeviceId() async {
    // 尝试从存储中获取
    await _initPrefs();
    String? deviceId = _prefs.getString(_deviceIdKey);
    
    if (deviceId == null) {
      // 如果没有存储，生成新的并保存
      String prefix = 'UNK-';
      if (Platform.isWindows) prefix = 'WIN-';
      else if (Platform.isAndroid) prefix = 'AND-';
      else if (Platform.isIOS) prefix = 'IOS-';
      else if (Platform.isMacOS) prefix = 'MAC-';
      else if (Platform.isLinux) prefix = 'LIN-';
      try {
        final rustBridge = await RustBridge.init();
        final fp = await rustBridge.generateDeviceFingerprint();
        deviceId = '$prefix$fp';
      } catch (_) {
        deviceId = '$prefix${DateTime.now().microsecondsSinceEpoch}';
      }
      _prefs.setString(_deviceIdKey, deviceId);
    }
    
    return deviceId;
  }

  // 检查是否在试用期内
  Future<bool> isInTrialPeriod() async {
    await _initPrefs();
    final trialStart = _prefs.getString(_trialStartKey);
    
    if (trialStart == null) {
      return false;
    }

    final startDate = DateTime.parse(trialStart);
    final now = DateTime.now();
    final difference = now.difference(startDate).inDays;

    return difference < _trialDays;
  }

  // 开始试用期
  Future<void> startTrial() async {
    await _initPrefs();
    _prefs.setString(_trialStartKey, DateTime.now().toIso8601String());
  }

  // 设置为授权用户
  Future<void> setPremiumUser(bool isPremium) async {
    await _initPrefs();
    _prefs.setBool(_premiumKey, isPremium);
  }
  
  // 添加授权设备
  Future<void> addAuthorizedDevice(String deviceId) async {
    await _initPrefs();
    final allowedDevices = _prefs.getStringList(_allowedDevicesKey) ?? [];
    if (!allowedDevices.contains(deviceId)) {
      allowedDevices.add(deviceId);
      _prefs.setStringList(_allowedDevicesKey, allowedDevices);
    }
  }
  
  // 移除授权设备
  Future<void> removeAuthorizedDevice(String deviceId) async {
    await _initPrefs();
    final allowedDevices = _prefs.getStringList(_allowedDevicesKey) ?? [];
    allowedDevices.remove(deviceId);
    _prefs.setStringList(_allowedDevicesKey, allowedDevices);
  }
}
