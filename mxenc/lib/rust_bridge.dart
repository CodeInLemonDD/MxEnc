import 'dart:ffi' as ffi;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'bridge_generated/frb_generated.dart';
import 'bridge_generated/lib.dart' as rust_lib;
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'; // Correct import for ExternalLibrary
export 'bridge_generated/lib.dart' show ProgressEvent, ProgressPhase;

// 文件类型枚举 (保留以兼容现有UI代码)
enum MxEncFileType {
  generic(0),
  image(1),
  novel(2),
  comic(3),
  richNovel(4),
  other(255);

  final int value;
  const MxEncFileType(this.value);
}

abstract class RustBridge {
  // 原有方法 (部分保留用于兼容，但建议迁移)
  Future<Uint8List> encryptFile({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
  });

  Future<Uint8List> encryptFileWithMetadata({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
    required MxEncFileType fileType,
    Uint8List? metadata,
  });

  Future<(String, Uint8List)> decryptFile({
    required Uint8List mxencData,
    required String password,
  });

  // 新增基于路径的方法 (推荐使用)
  Future<void> encryptFileByPath({
    required String inputPath,
    required String outputPath,
    required String password,
    String? originalFilename,
    required int fileType,
    Uint8List? metadata,
  });

  Stream<rust_lib.ProgressEvent> decryptFileByPathWithProgress({
    required String inputPath,
    required String password,
  });

  Stream<rust_lib.ProgressEvent> decryptFileWithProgress({
    required Uint8List mxencData,
    required String password,
  });

  // Header Parsing
  Future<String> parseMxencHeader({required Uint8List mxencData});

  Future<(String, int)> parseMxencHeaderExtended({
    required Uint8List mxencData,
  });

  Future<(String, int)> parseMxencHeaderByPath({required String inputPath});

  Future<(String, int, Uint8List)> parseMxencFullHeader({
    required Uint8List mxencData,
  });

  Future<(String, int, Uint8List)> parseMxencFullHeaderByPath({
    required String inputPath,
  });

  Future<String> generateDeviceFingerprint();

  static final List<String> initLogs = [];

  static void _log(String message) {
    debugPrint(message);
    initLogs.add(
      '${DateTime.now().toIso8601String().substring(11, 19)}: $message',
    );
  }

  static Future<RustBridge?> init() async {
    try {
      _log('Initializing Rust library...');

      ExternalLibrary? lib;
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        // iOS Static Linking Diagnostic Block
        try {
          _log('iOS: Attempting to open process handle...');
          final dylib = ffi.DynamicLibrary.process();
          _log('iOS: Process handle opened. Checking for symbols...');

          const symbolTest = 'dummy_method_to_enforce_bundling';
          if (dylib.providesSymbol(symbolTest)) {
            _log('iOS: SUCCESS - Found symbol: $symbolTest');
          } else {
            _log(
              'iOS: CRITICAL FAILURE - Symbol $symbolTest NOT FOUND in process!',
            );
            // If this dummy symbol is missing, the linker stripped it.
          }

          // Use this dylib for FRB
          lib = ExternalLibrary.process(iKnowHowToUseIt: true);
          _log('Using DynamicLibrary.process() for iOS static linking');
        } catch (e) {
          _log('iOS Diagnostic Error: $e');
        }
      }

      await RustLib.init(externalLibrary: lib);
      _log('Rust library initialized successfully');
      return _RustBridgeFrb();
    } catch (e, stack) {
      _log('CRITICAL: Failed to initialize Rust library: $e');
      _log('Stack trace: $stack');
      // Return null so the UI knows initialization failed
      return null;
    }
  }
}

class _RustBridgeFrb implements RustBridge {
  @override
  Future<Uint8List> encryptFile({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
  }) {
    return rust_lib.encryptFile(
      plaintext: plaintext,
      password: password,
      originalFilename: originalFilename,
    );
  }

  @override
  Future<Uint8List> encryptFileWithMetadata({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
    required MxEncFileType fileType,
    Uint8List? metadata,
  }) {
    return rust_lib.encryptFileWithMetadata(
      plaintext: plaintext,
      password: password,
      originalFilename: originalFilename,
      fileType: fileType.value,
      metadata: metadata,
    );
  }

  @override
  Future<void> encryptFileByPath({
    required String inputPath,
    required String outputPath,
    required String password,
    String? originalFilename,
    required int fileType,
    Uint8List? metadata,
  }) {
    return rust_lib.encryptFileByPath(
      inputPath: inputPath,
      outputPath: outputPath,
      password: password,
      originalFilename: originalFilename,
      fileType: fileType,
      metadata: metadata,
    );
  }

  @override
  Future<(String, Uint8List)> decryptFile({
    required Uint8List mxencData,
    required String password,
  }) {
    return rust_lib.decryptFile(mxencData: mxencData, password: password);
  }

  @override
  Stream<rust_lib.ProgressEvent> decryptFileByPathWithProgress({
    required String inputPath,
    required String password,
  }) {
    return rust_lib.decryptFileByPathWithProgress(
      inputPath: inputPath,
      password: password,
    );
  }

  @override
  Stream<rust_lib.ProgressEvent> decryptFileWithProgress({
    required Uint8List mxencData,
    required String password,
  }) {
    return rust_lib.decryptFileWithProgress(
      mxencData: mxencData,
      password: password,
    );
  }

  @override
  Future<String> parseMxencHeader({required Uint8List mxencData}) async {
    return rust_lib.parseMxencHeader(mxencData: mxencData);
  }

  @override
  Future<(String, int)> parseMxencHeaderExtended({
    required Uint8List mxencData,
  }) async {
    return rust_lib.parseMxencHeaderExtended(mxencData: mxencData);
  }

  @override
  Future<(String, int)> parseMxencHeaderByPath({required String inputPath}) {
    return rust_lib.parseMxencHeaderByPath(inputPath: inputPath);
  }

  @override
  Future<(String, int, Uint8List)> parseMxencFullHeader({
    required Uint8List mxencData,
  }) async {
    return rust_lib.parseMxencFullHeader(mxencData: mxencData);
  }

  @override
  Future<(String, int, Uint8List)> parseMxencFullHeaderByPath({
    required String inputPath,
  }) {
    return rust_lib.parseMxencFullHeaderByPath(inputPath: inputPath);
  }

  @override
  Future<String> generateDeviceFingerprint() async {
    return rust_lib.generateDeviceFingerprint();
  }
}
