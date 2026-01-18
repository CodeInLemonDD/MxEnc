import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/foundation.dart';

class TtsService {
  static final TtsService _instance = TtsService._internal();
  factory TtsService() => _instance;

  final FlutterTts _flutterTts = FlutterTts();
  double _speechRate = 1.0;
  bool _isPlaying = false;
  Function()? _onCompletion;
  Function()? _onStart;
  Function(String)? _onError;

  TtsService._internal() {
    _initTts();
  }

  Future<void> _initTts() async {
    try {
      final engines = await _flutterTts.getEngines;
      if (engines == null || engines.isEmpty) {
        debugPrint("No TTS engines found on this device.");
        if (_onError != null) {
          _onError!("未检测到系统 TTS 引擎。请安装 Google 文字转语音或其他 TTS 引擎后重试。");
        }
        return;
      }

      if (kDebugMode) {
        debugPrint("Available TTS Engines: $engines");
        final defaultEngine = await _flutterTts.getDefaultEngine;
        debugPrint("Default TTS Engine: $defaultEngine");
      }

      final langResult = await _flutterTts.setLanguage("zh-CN");
      // Result 0: Not supported/available, Result 1: Success
      if (langResult == 0) {
        debugPrint("Language zh-CN not supported.");
        if (_onError != null) _onError!("当前 TTS 引擎不支持中文。请在系统设置中切换引擎或下载中文语音包。");
      }

      await _flutterTts.setSpeechRate(_speechRate);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      _flutterTts.setCompletionHandler(() {
        debugPrint("TTS Playback Completed");
        _isPlaying = false;
        if (_onCompletion != null) {
          _onCompletion!();
        }
      });

      _flutterTts.setErrorHandler((msg) {
        debugPrint("TTS Error Handler Triggered: $msg");
        _isPlaying = false;
        if (_onError != null) {
          _onError!(msg.toString());
        }
      });

      _flutterTts.setStartHandler(() {
        debugPrint("TTS Playback Started");
        if (_onStart != null) {
          _onStart!();
        }
      });
    } catch (e) {
      debugPrint("TTS Initialization Failed: $e");
      if (_onError != null) _onError!("初始化失败: $e");
    }
  }

  Future<void> speak(String text, {bool isQueued = false}) async {
    if (text.isEmpty) return;

    // Check if language is actually available before speaking
    bool isAvailable = await _flutterTts.isLanguageAvailable("zh-CN");
    if (!isAvailable) {
      debugPrint("Language zh-CN is NOT available on this device.");
    }

    debugPrint(
      "TTS Attempting to speak (${isQueued ? 'Queued' : 'Immediate'}): \"$text\"",
    );

    if (!isQueued) {
      await _flutterTts.stop();
      await _flutterTts.setQueueMode(0); // 0 = Flush
    } else {
      await _flutterTts.setQueueMode(1); // 1 = Add
    }

    _isPlaying = true;
    final result = await _flutterTts.speak(text);
    if (result == 1) {
      debugPrint("TTS Speak call successful");
    } else {
      debugPrint("TTS Speak call failed (result: $result)");
      if (_onError != null)
        _onError!("播放指令执行失败 (Result Code: $result)。请确认 TTS 引擎是否正在运行。");
    }
  }

  Future<void> pause() async {
    await _flutterTts.pause();
    _isPlaying = false;
  }

  Future<void> stop() async {
    await _flutterTts.stop();
    _isPlaying = false;
  }

  Future<void> setSpeechRate(double rate) async {
    _speechRate = rate;
    await _flutterTts.setSpeechRate(rate);
  }

  void setCompletionHandler(Function() handler) {
    _onCompletion = handler;
  }

  void setStartHandler(Function() handler) {
    _onStart = handler;
  }

  void setErrorHandler(Function(String) handler) {
    _onError = handler;
  }

  bool get isPlaying => _isPlaying;
  double get speechRate => _speechRate;
}
