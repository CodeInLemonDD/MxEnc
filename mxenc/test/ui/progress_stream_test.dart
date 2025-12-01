import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxenc/rust_bridge.dart';
import 'package:mxenc/utils/mxenc_dart.dart';
import 'package:mxenc/utils/progress.dart';

void main() {
  test('decrypt progress stream emits done with data', () async {
    final plaintext = Uint8List.fromList(List<int>.generate(1024, (i) => i % 256));
    final encrypted = MxencDart.encrypt(
      plaintext: plaintext,
      password: 'p@ss',
      originalFilename: 'demo.txt',
    );
    final bridge = RustBridge.mock();
    final events = <ProgressEvent>[];
    await for (final ev in bridge.decryptFileProgress(mxencData: encrypted, password: 'p@ss')) {
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
