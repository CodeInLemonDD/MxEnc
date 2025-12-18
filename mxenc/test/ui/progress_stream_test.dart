import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxenc/rust_bridge.dart';
import 'package:mxenc/utils/mxenc_dart.dart';

class MockRustBridge implements RustBridge {
  @override
  Stream<ProgressEvent> decryptFileWithProgress({
    required Uint8List mxencData,
    required String password,
  }) async* {
    yield ProgressEvent(
      phase: ProgressPhase.readHeader,
      percent: 0.1,
      label: 'Reading header',
    );
    yield ProgressEvent(
      phase: ProgressPhase.deriveKey,
      percent: 0.2,
      label: 'Deriving key',
    );
    yield ProgressEvent(
      phase: ProgressPhase.decrypt,
      percent: 0.5,
      label: 'Decrypting',
    );
    yield ProgressEvent(
      phase: ProgressPhase.done,
      percent: 1.0,
      label: 'Done',
      filename: 'demo.txt',
      data: Uint8List.fromList([1, 2, 3]),
    );
  }

  @override
  Future<(String, Uint8List)> decryptFile({
    required Uint8List mxencData,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> encryptFile({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
  }) {
    throw UnimplementedError();
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
    throw UnimplementedError();
  }

  @override
  Future<Uint8List> encryptFileWithMetadata({
    required Uint8List plaintext,
    required String password,
    required String originalFilename,
    required MxEncFileType fileType,
    Uint8List? metadata,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<ProgressEvent> decryptFileByPathWithProgress({
    required String inputPath,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> generateDeviceFingerprint() {
    throw UnimplementedError();
  }

  @override
  Future<(String, int, Uint8List)> parseMxencFullHeader({
    required Uint8List mxencData,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<(String, int, Uint8List)> parseMxencFullHeaderByPath({
    required String inputPath,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> parseMxencHeader({required Uint8List mxencData}) {
    throw UnimplementedError();
  }

  @override
  Future<(String, int)> parseMxencHeaderByPath({required String inputPath}) {
    throw UnimplementedError();
  }

  @override
  Future<(String, int)> parseMxencHeaderExtended({
    required Uint8List mxencData,
  }) {
    throw UnimplementedError();
  }
}

void main() {
  test('decrypt progress stream emits done with data', () async {
    final plaintext = Uint8List.fromList(
      List<int>.generate(1024, (i) => i % 256),
    );
    final encrypted = MxencDart.encrypt(
      plaintext: plaintext,
      password: 'p@ss',
      originalFilename: 'demo.txt',
    );
    final bridge = MockRustBridge();
    final events = <ProgressEvent>[];
    await for (final ev in bridge.decryptFileWithProgress(
      mxencData: encrypted,
      password: 'p@ss',
    )) {
      events.add(ev);
      if (ev.phase == ProgressPhase.done) break;
    }
    expect(events.isNotEmpty, true);
    final last = events.last;
    expect(last.phase, ProgressPhase.done);
    expect(last.percent, 1.0);
    expect(last.data != null, true);
    expect(last.filename != null, true);
  });
}
