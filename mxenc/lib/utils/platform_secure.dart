import 'dart:io';
import 'package:flutter/services.dart';

/// 平台特定的安全功能
class PlatformSecure {
  static const _methodChannel = MethodChannel('com.maoxiao.mxenc/secure');

  /// 启用防截图模式
  static Future<void> enableSecureScreen() async {
    try {
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('enableSecureScreen');
      } else if (Platform.isIOS) {
        await _methodChannel.invokeMethod('enableSecureScreen');
      }
      // 其他平台暂不支持
    } catch (e) {
      // 忽略错误，确保应用不会崩溃
      print('启用防截图模式失败: $e');
    }
  }

  /// 禁用防截图模式
  static Future<void> disableSecureScreen() async {
    try {
      if (Platform.isAndroid) {
        await _methodChannel.invokeMethod('disableSecureScreen');
      } else if (Platform.isIOS) {
        await _methodChannel.invokeMethod('disableSecureScreen');
      }
      // 其他平台暂不支持
    } catch (e) {
      // 忽略错误，确保应用不会崩溃
      print('禁用防截图模式失败: $e');
    }
  }
}