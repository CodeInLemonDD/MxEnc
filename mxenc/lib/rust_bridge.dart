import 'dart:typed_data';
import 'utils/mxenc_dart.dart';
import 'bridge_generated/frb_generated.dart';
import 'utils/progress.dart';

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

  Stream<ProgressEvent> decryptFileProgress({
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

  static RustBridge mock() {
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
    return MxencDart.encrypt(plaintext: plaintext, password: password, originalFilename: originalFilename);
  }

  @override
  Future<Uint8List> encryptFileWithMetadata({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
    required MxEncFileType fileType,
    Uint8List? metadata,
  }) async {
    return MxencDart.encrypt(
      plaintext: plaintext,
      password: password,
      originalFilename: originalFilename,
      fileType: fileType.value,
      metadata: metadata,
    );
  }

  @override
  Future<(String, Uint8List)> decryptFile({
    required Uint8List mxencData,
    required String password,
  }) async {
    return MxencDart.decrypt(mxencData: mxencData, password: password);
  }

  @override
  Stream<ProgressEvent> decryptFileProgress({
    required Uint8List mxencData,
    required String password,
  }) async* {
    yield const ProgressEvent(phase: ProgressPhase.readHeader, percent: 0.05, label: '读取文件');
    try {
      await parseMxencFullHeader(mxencData: mxencData);
      yield const ProgressEvent(phase: ProgressPhase.readHeader, percent: 0.10, label: '解析头部');
    } catch (_) {
      yield const ProgressEvent(phase: ProgressPhase.readHeader, percent: 0.10, label: '解析头部');
    }
    yield const ProgressEvent(phase: ProgressPhase.deriveKey, percent: 0.20, label: '派生密钥');

    double p = 0.20;
    while (p < 0.90) {
      await Future.delayed(const Duration(milliseconds: 200));
      p += 0.05;
      if (p > 0.90) p = 0.90;
      yield ProgressEvent(phase: ProgressPhase.decrypt, percent: p, label: '解密中');
    }

    (String, Uint8List) result;
    try {
      result = await decryptFile(mxencData: mxencData, password: password);
    } catch (e) {
      rethrow;
    }
    yield const ProgressEvent(phase: ProgressPhase.decode, percent: 0.98, label: '解码中');
    yield ProgressEvent(
      phase: ProgressPhase.done,
      percent: 1.0,
      label: '完成',
      filename: result.$1,
      data: result.$2,
    );
  }

  @override
  Future<String> parseMxencHeader({required Uint8List mxencData}) async {
    final h = MxencDart.parseHeader(mxencData);
    return h['filename'] as String;
  }

  @override
  Future<(String, MxEncFileType)> parseMxencHeaderExtended({
    required Uint8List mxencData,
  }) async {
    final h = MxencDart.parseHeader(mxencData);
    return (h['filename'] as String, _fromIntFileType(h['fileType'] as int));
  }

  @override
  Future<(String, MxEncFileType, Uint8List)> parseMxencFullHeader({
    required Uint8List mxencData,
  }) async {
    final h = MxencDart.parseHeader(mxencData);
    return (h['filename'] as String, _fromIntFileType(h['fileType'] as int), h['metadata'] as Uint8List);
  }

  @override
  Future<String> generateDeviceFingerprint() async {
    return 'DEV-${DateTime.now().microsecondsSinceEpoch}';
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
