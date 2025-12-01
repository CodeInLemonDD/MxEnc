import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:pointycastle/export.dart';

class MxencDart {
  static const magic = [77, 88, 69, 78, 67, 50, 48];
  static Uint8List _rand(int n) {
    final r = Random.secure();
    final b = Uint8List(n);
    for (var i = 0; i < n; i++) { b[i] = r.nextInt(256); }
    return b;
  }
  static Uint8List _pbkdf2(String password, Uint8List salt, int length) {
    final params = Pbkdf2Parameters(salt, 100000, length);
    final gen = KeyDerivator('SHA-256/HMAC/PBKDF2')..init(params);
    return gen.process(Uint8List.fromList(password.codeUnits));
  }
  static Uint8List _aesGcmEncrypt(Uint8List key, Uint8List nonce, Uint8List data) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(true, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(data);
  }
  static Uint8List _aesGcmDecrypt(Uint8List key, Uint8List nonce, Uint8List data) {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(false, AEADParameters(KeyParameter(key), 128, nonce, Uint8List(0)));
    return cipher.process(data);
  }
  static Uint8List _u32(int v) {
    final b = ByteData(4);
    b.setUint32(0, v, Endian.big);
    return b.buffer.asUint8List();
  }
  static Map<String, dynamic> parseHeader(Uint8List mxenc) {
    var offset = 0;
    for (var i = 0; i < magic.length; i++) { if (mxenc[i] != magic[i]) { throw ArgumentError('invalid magic'); } }
    offset += magic.length;
    final nameLen = ByteData.sublistView(mxenc, offset, offset + 4).getUint32(0, Endian.big); offset += 4;
    final nameBytes = mxenc.sublist(offset, offset + nameLen); offset += nameLen;
    final fileType = mxenc[offset]; offset += 1;
    final metaLen = ByteData.sublistView(mxenc, offset, offset + 4).getUint32(0, Endian.big); offset += 4;
    final meta = mxenc.sublist(offset, offset + metaLen); offset += metaLen;
    final salt = mxenc.sublist(offset, offset + 32); offset += 32;
    final nonce = mxenc.sublist(offset, offset + 12); offset += 12;
    final ciphertext = mxenc.sublist(offset);
    return {
      'filename': utf8.decode(nameBytes, allowMalformed: true),
      'fileType': fileType,
      'metadata': meta,
      'salt': salt,
      'nonce': nonce,
      'ciphertext': ciphertext,
    };
  }
  static Uint8List encrypt({required Uint8List plaintext, required String password, required String originalFilename, int fileType = 0, Uint8List? metadata}) {
    final salt = _rand(32);
    final nonce = _rand(12);
    final key = _pbkdf2(password, salt, 32);
    final ct = _aesGcmEncrypt(key, nonce, plaintext);
    final nameBytes = Uint8List.fromList(utf8.encode(originalFilename));
    final meta = metadata ?? Uint8List(0);
    final out = BytesBuilder();
    out.add(magic);
    out.add(_u32(nameBytes.length));
    out.add(nameBytes);
    out.add(Uint8List.fromList([fileType]));
    out.add(_u32(meta.length));
    out.add(meta);
    out.add(salt);
    out.add(nonce);
    out.add(ct);
    return out.toBytes();
  }
  static (String, Uint8List) decrypt({required Uint8List mxencData, required String password}) {
    final h = parseHeader(mxencData);
    final key = _pbkdf2(password, h['salt'], 32);
    final pt = _aesGcmDecrypt(key, h['nonce'], h['ciphertext']);
    return (h['filename'] as String, pt);
  }

  static Uint8List packComicContainer({required Map<String, dynamic> manifest, required List<Uint8List> images}) {
    final out = BytesBuilder();
    final idx = <Map<String, dynamic>>[];
    var offset = 0;
    for (var i = 0; i < images.length; i++) {
      final bytes = images[i];
      idx.add({'id': i, 'byteOffset': offset, 'length': bytes.length});
      offset += bytes.length;
    }
    manifest['imagesIndex'] = idx;
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    final jsonLen = _u32(jsonBytes.length);
    out.add(jsonLen);
    out.add(jsonBytes);
    for (final img in images) { out.add(img); }
    return out.toBytes();
  }

  static Uint8List packRichNovelContainer({required Map<String, dynamic> manifest, required List<Uint8List> images}) {
    final out = BytesBuilder();
    final idx = <Map<String, dynamic>>[];
    var offset = 0;
    for (var i = 0; i < images.length; i++) {
      final bytes = images[i];
      idx.add({'id': i, 'byteOffset': offset, 'length': bytes.length});
      offset += bytes.length;
    }
    manifest['resourcesIndex'] = idx;
    final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    final jsonLen = _u32(jsonBytes.length);
    out.add(jsonLen);
    out.add(jsonBytes);
    for (final img in images) { out.add(img); }
    return out.toBytes();
  }

  static Map<String, dynamic> unpackComicContainer(Uint8List payload) {
    final len = ByteData.sublistView(payload, 0, 4).getUint32(0, Endian.big);
    final manifestBytes = payload.sublist(4, 4 + len);
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final start = 4 + len;
    return {
      'manifest': manifest,
      'start': start,
      'payload': payload,
    };
  }

  static Map<String, dynamic> unpackRichNovelContainer(Uint8List payload) {
    final len = ByteData.sublistView(payload, 0, 4).getUint32(0, Endian.big);
    final manifestBytes = payload.sublist(4, 4 + len);
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    final start = 4 + len;
    return {
      'manifest': manifest,
      'start': start,
      'payload': payload,
    };
  }
}
