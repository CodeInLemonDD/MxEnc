import 'dart:typed_data';
import 'bridge_generated/lib.dart' as api;
import 'utils/mxenc_dart.dart';
import 'bridge_generated/frb_generated.dart';

// 文件类型枚举
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

  Future<String> parseMxencHeader({required Uint8List mxencData});

  Future<(String, MxEncFileType)> parseMxencHeaderExtended({
    required Uint8List mxencData,
  });

  Future<(String, MxEncFileType, Uint8List)> parseMxencFullHeader({
    required Uint8List mxencData,
  });

  Future<String> generateDeviceFingerprint();

  static Future<RustBridge> init() async {
    await RustLib.init(forceSameCodegenVersion: false);
    return _RustBridgeFrb();
  }
}

class _RustBridgeFrb implements RustBridge {
  @override
  Future<Uint8List> encryptFile({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
  }) async {
    try {
      return api.encryptFile(
        plaintext: plaintext,
        password: password,
        originalFilename: originalFilename,
      );
    } catch (_) {
      return MxencDart.encrypt(plaintext: plaintext, password: password, originalFilename: originalFilename);
    }
  }

  @override
  Future<Uint8List> encryptFileWithMetadata({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
    required MxEncFileType fileType,
    Uint8List? metadata,
  }) async {
    try {
      return api.encryptFileWithMetadata(
        plaintext: plaintext,
        password: password,
        originalFilename: originalFilename,
        fileType: fileType.value,
        metadata: metadata,
      );
    } catch (_) {
      return MxencDart.encrypt(
        plaintext: plaintext,
        password: password,
        originalFilename: originalFilename,
        fileType: fileType.value,
        metadata: metadata,
      );
    }
  }

  @override
  Future<(String, Uint8List)> decryptFile({
    required Uint8List mxencData,
    required String password,
  }) async {
    try {
      return api.decryptFile(
        mxencData: mxencData,
        password: password,
      );
    } catch (_) {
      return MxencDart.decrypt(mxencData: mxencData, password: password);
    }
  }

  @override
  Future<String> parseMxencHeader({required Uint8List mxencData}) async {
    try {
      return api.parseMxencHeader(mxencData: mxencData);
    } catch (_) {
      final h = MxencDart.parseHeader(mxencData);
      return h['filename'] as String;
    }
  }

  @override
  Future<(String, MxEncFileType)> parseMxencHeaderExtended({
    required Uint8List mxencData,
  }) async {
    try {
      final result = api.parseMxencHeaderExtended(mxencData: mxencData);
      final filename = result.$1;
      final fileType = _fromIntFileType(result.$2);
      return (filename, fileType);
    } catch (_) {
      final h = MxencDart.parseHeader(mxencData);
      return (h['filename'] as String, _fromIntFileType(h['fileType'] as int));
    }
  }

  @override
  Future<(String, MxEncFileType, Uint8List)> parseMxencFullHeader({
    required Uint8List mxencData,
  }) async {
    try {
      final result = api.parseMxencFullHeader(mxencData: mxencData);
      final filename = result.$1;
      final fileType = _fromIntFileType(result.$2);
      final metadata = result.$3;
      return (filename, fileType, metadata);
    } catch (_) {
      final h = MxencDart.parseHeader(mxencData);
      return (h['filename'] as String, _fromIntFileType(h['fileType'] as int), h['metadata'] as Uint8List);
    }
  }

  @override
  Future<String> generateDeviceFingerprint() async {
    try {
      return api.generateDeviceFingerprint();
    } catch (_) {
      return 'DEV-${DateTime.now().microsecondsSinceEpoch}';
    }
  }

  MxEncFileType _fromIntFileType(int v) {
    switch (v) {
      case 1:
        return MxEncFileType.image;
      case 2:
        return MxEncFileType.novel;
      case 3:
        return MxEncFileType.comic;
      case 4:
        return MxEncFileType.richNovel;
      case 255:
        return MxEncFileType.other;
      default:
        return MxEncFileType.generic;
    }
  }
}
