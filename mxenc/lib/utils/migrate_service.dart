import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart' show Digest;
import 'package:shared_preferences/shared_preferences.dart';

import '../rust_bridge.dart';
import 'storage_service.dart';

/// 换机迁移过程中可能出现的错误。
/// code: not_package / invalid_package / newer_version / package_missing / empty
class MigrateException implements Exception {
  final String code;
  MigrateException(this.code);
  @override
  String toString() => 'MigrateException: $code';
}

/// 进度回调：message 为当前阶段的描述，progress 为 0.0 ~ 1.0。
typedef MigrateProgress = void Function(String message, double progress);

class MigrateExportResult {
  final String path;
  final int bytes;
  final int itemCount;
  final DateTime createdAt;
  MigrateExportResult({
    required this.path,
    required this.bytes,
    required this.itemCount,
    required this.createdAt,
  });
}

class MigrateImportResult {
  final int importedItems;
  final int skippedItems;
  final int totalItems;
  final String? nickname;
  final String? signature;
  final String? avatarPath;
  final String appVersion;
  final String platform;
  MigrateImportResult({
    required this.importedItems,
    required this.skippedItems,
    required this.totalItems,
    required this.nickname,
    required this.signature,
    required this.avatarPath,
    required this.appVersion,
    required this.platform,
  });
}

class MigratePackage {
  /// 已加密的 .mxbak 临时文件路径（局域网发送与离线导出复用）
  final String path;
  final Map<String, dynamic> manifest;
  final int itemCount;
  final int size;
  MigratePackage({
    required this.path,
    required this.manifest,
    required this.itemCount,
    required this.size,
  });
}

/// 换手机传输：把书架 / 密码表 / 个人资料打包带走。
///
/// 包体结构（固定密钥加密后的 .mxbak）：
///   manifest.json   迁移元信息（只追加字段，不改旧字段）
///   bookshelf.json  原书架索引（绝对路径，导入时重写）
///   passwords.json  密码表（key 为文件绝对路径，导入时重写）
///   files/ covers/ user/ ...  app_data 下的实际内容
class MigrateService {
  /// 外观像普通备份文件的扩展名（实质是加密后的 zip）
  static const String packageExtension = 'mxbak';

  /// 固定密钥，必须保持 ASCII（MxencDart 内部按 codeUnits 取字节）
  static const String _packageKey = 'MxEnc.DeviceTransfer.v1';
  static const String _keyId = 'dt-v1';
  static const String _manifestMagic = 'MXENC_MIGRATE';

  /// 包格式版本：导入时只接受 <= 当前版本，保证旧包能在新版本里导入
  static const int formatVersion = 1;

  /// 换机包文件类型（Rust 侧非标准类型统一落成 Other=255）
  static const int _fileType = 255;

  /// 早期纯 Dart 版本写出的包类型，保留兼容
  static const int _legacyFileType = 9;

  /// 这些顶层目录属于临时产物，不随包迁移
  static const Set<String> _skipTopDirs = {'exports', 'tmp', 'temp', 'cache'};

  static Future<Directory> _appDataDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'app_data'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ---------------------------------------------------------------------------
  // 导出
  // ---------------------------------------------------------------------------

  /// 生成迁移包（.mxbak 临时文件），局域网发送也复用它。
  ///
  /// 压缩在后台 isolate 里流式写 zip，加密交给 Rust（[RustBridge.encryptFileByPath]），
  /// 全程不在 UI isolate 上做重计算。
  static Future<MigratePackage> buildPackage({
    required RustBridge bridge,
    MigrateProgress? onProgress,
  }) async {
    onProgress?.call('正在整理数据…', 0.0);

    final dataDir = await _appDataDir();
    final shelf = await StorageService.loadShelf();
    final prefs = await SharedPreferences.getInstance();

    final rels = <String>[];
    var totalBytes = 0;
    await for (final entity
        in dataDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final rel = _posix(p.relative(entity.path, from: dataDir.path));
      if (_shouldSkip(rel)) continue;
      rels.add(rel);
      try {
        totalBytes += await entity.length();
      } catch (_) {}
    }
    if (rels.isEmpty &&
        shelf.isEmpty &&
        (prefs.getString('user_nickname') ?? '').isEmpty &&
        (prefs.getString('user_signature') ?? '').isEmpty) {
      throw MigrateException('empty');
    }

    final avatarPath = prefs.getString('user_avatar_path') ?? '';
    String? avatarRel;
    if (avatarPath.isNotEmpty && !_isAsset(avatarPath)) {
      final norm = _posix(avatarPath);
      if (p.isWithin(dataDir.path, avatarPath)) {
        avatarRel = _posix(p.relative(avatarPath, from: dataDir.path));
      } else {
        final idx = norm.lastIndexOf('/app_data/');
        if (idx >= 0) avatarRel = norm.substring(idx + '/app_data/'.length);
      }
    }

    final info = await PackageInfo.fromPlatform();
    final manifest = <String, dynamic>{
      'magic': _manifestMagic,
      'formatVersion': formatVersion,
      'keyId': _keyId,
      'appVersion': '${info.version}+${info.buildNumber}',
      'platform': Platform.operatingSystem,
      'createdAt': DateTime.now().toIso8601String(),
      'nickname': prefs.getString('user_nickname') ?? '',
      'signature': prefs.getString('user_signature') ?? '',
      'avatarRel': avatarRel ?? '',
      'itemCount': shelf.length,
      'fileCount': rels.length,
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final zipPath = p.join(tempDir.path, 'mxpack_$stamp.zip');
    final packagePath =
        p.join(tempDir.path, 'mxpack_$stamp.$packageExtension');

    final progressPort = ReceivePort();
    final subscription = progressPort.listen((message) {
      if (message is! List || message.length != 2) return;
      final ratio = (message[1] as num).toDouble();
      onProgress?.call(
        '正在打包 ${message[0]}',
        (0.05 + 0.80 * ratio).clamp(0.0, 0.85),
      );
    });

    try {
      onProgress?.call('正在压缩…', 0.05);
      await _runZipIsolate(
        zipPath: zipPath,
        dataDirPath: dataDir.path,
        rels: rels,
        manifestBytes: manifestBytes,
        totalBytes: totalBytes,
        progressPort: progressPort.sendPort,
      );

      onProgress?.call('正在加密…', 0.90);
      await bridge.encryptFileByPath(
        inputPath: zipPath,
        outputPath: packagePath,
        password: _packageKey,
        originalFilename: 'MxBackup',
        fileType: _fileType,
      );
    } on MigrateException {
      rethrow;
    } catch (e, st) {
      debugPrint('MigrateService.buildPackage failed: $e\n$st');
      await _deleteQuietly(packagePath);
      throw MigrateException('export_failed');
    } finally {
      subscription.cancel();
      progressPort.close();
      await _deleteQuietly(zipPath);
    }

    final size = await File(packagePath).length();
    onProgress?.call('打包完成', 1.0);
    return MigratePackage(
      path: packagePath,
      manifest: manifest,
      itemCount: shelf.length,
      size: size,
    );
  }

  /// 导出为 .mxbak 文件，返回文件路径。
  static Future<MigrateExportResult> exportPackage({
    required RustBridge bridge,
    MigrateProgress? onProgress,
  }) async {
    final pkg = await buildPackage(bridge: bridge, onProgress: onProgress);
    return savePackage(pkg);
  }

  /// 把已经生成好的包体落盘到 exports/（局域网发送时复用它，避免重复打包）。
  static Future<MigrateExportResult> savePackage(MigratePackage pkg) async {
    final docs = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(docs.path, 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    final now = DateTime.now();
    final stamp =
        '${now.year}${_pad2(now.month)}${_pad2(now.day)}_${_pad2(now.hour)}${_pad2(now.minute)}';
    final path = p.join(exportDir.path, 'MxBackup_$stamp.$packageExtension');
    try {
      await File(pkg.path).copy(path);
    } catch (_) {
      throw MigrateException('export_failed');
    }
    return MigrateExportResult(
      path: path,
      bytes: pkg.size,
      itemCount: pkg.itemCount,
      createdAt: now,
    );
  }

  /// 清掉 buildPackage 产生的临时包体。
  static Future<void> discardPackage(MigratePackage? pkg) async {
    if (pkg == null) return;
    await _deleteQuietly(pkg.path);
  }

  // ---------------------------------------------------------------------------
  // 导入
  // ---------------------------------------------------------------------------

  /// 导入 .mxbak 文件：解密交给 Rust，解压在后台 isolate 里完成。
  static Future<MigrateImportResult> importPackageFile(
    String path, {
    required RustBridge bridge,
    MigrateProgress? onProgress,
  }) async {
    final file = File(path);
    if (!await file.exists()) throw MigrateException('package_missing');

    onProgress?.call('正在校验迁移包…', 0.02);

    int fileType;
    try {
      final (_, type, _) =
          await bridge.parseMxencFullHeaderByPath(inputPath: path);
      fileType = type;
    } catch (_) {
      throw MigrateException('invalid_package');
    }
    if (fileType != _fileType && fileType != _legacyFileType) {
      throw MigrateException('not_package');
    }

    final dataDir = await _appDataDir();
    final docs = await getApplicationDocumentsDirectory();
    final staging = Directory(
      p.join(docs.path, 'migrate_tmp_${DateTime.now().millisecondsSinceEpoch}'),
    );
    final tempDir = await getTemporaryDirectory();
    final zipPath = p.join(
      tempDir.path,
      'mxunpack_${DateTime.now().millisecondsSinceEpoch}.zip',
    );

    try {
      onProgress?.call('正在解密…', 0.05);
      Uint8List? plain;
      try {
        await for (final event in bridge.decryptFileByPathWithProgress(
          inputPath: path,
          password: _packageKey,
        )) {
          if (event.data != null) plain = event.data;
          onProgress?.call(
            '正在解密…',
            (0.05 + 0.30 * event.percent).clamp(0.0, 0.35),
          );
        }
      } catch (e, st) {
        debugPrint('MigrateService.decrypt failed: $e\n$st');
        throw MigrateException('invalid_package');
      }
      if (plain == null) throw MigrateException('invalid_package');

      onProgress?.call('正在解压…', 0.38);
      await File(zipPath).writeAsBytes(plain, flush: false);
      plain = null; // 明文已落盘，尽快释放内存

      try {
        await _runExtractIsolate(zipPath, staging.path);
      } catch (e, st) {
        debugPrint('MigrateService.extract failed: $e\n$st');
        throw MigrateException('invalid_package');
      }

      onProgress?.call('正在读取迁移信息…', 0.42);

      final manifestFile = File(p.join(staging.path, 'manifest.json'));
      if (!await manifestFile.exists()) throw MigrateException('not_package');
      Map<String, dynamic> manifest;
      try {
        manifest =
            jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        throw MigrateException('invalid_package');
      }
      if ((manifest['magic'] ?? '') != _manifestMagic) {
        throw MigrateException('not_package');
      }
      final version = (manifest['formatVersion'] as num?)?.toInt() ?? 0;
      if (version > formatVersion) throw MigrateException('newer_version');

      final incoming = await _readShelf(staging);
      final incomingPasswords = await _readPasswords(staging);

      final existingItems = await StorageService.loadShelf();
      final existingIds =
          existingItems.map((e) => (e['id'] ?? '').toString()).toSet();
      final existingWorkIds = existingItems
          .map((e) => (e['workId'] ?? '').toString())
          .where((e) => e.isNotEmpty)
          .toSet();

      final placement = _Placement(staging, dataDir);
      final planned = <Map<String, dynamic>>[];
      final seenWorkIds = <String>{};
      var skipped = 0;

      // 先去重，确定要导入的条目
      final accepted = <Map<String, dynamic>>[];
      for (final raw in incoming) {
        final item = Map<String, dynamic>.from(raw);
        var workId = (item['workId'] ?? '').toString();
        if (workId.isNotEmpty &&
            (existingWorkIds.contains(workId) || seenWorkIds.contains(workId))) {
          skipped++;
          continue;
        }
        if (workId.isEmpty) {
          workId = _computeWorkId(item);
          item['workId'] = workId;
        }
        seenWorkIds.add(workId);
        accepted.add(item);
      }

      // 系列条目指向整个目录：必须先整体搬运，否则目录里的单本先落盘会让系列目录被迫改名
      for (final item in accepted) {
        if (item['isSeries'] != true) continue;
        final seriesPath = (item['filePath'] ?? '').toString();
        if (seriesPath.isEmpty || _isAsset(seriesPath)) continue;
        final rel = _relSuffix(seriesPath);
        if (rel != null) await placement.placeRel(rel);
      }

      for (var i = 0; i < accepted.length; i++) {
        final item = accepted[i];

        // id 冲突时换新 id，避免覆盖新手机上同名条目
        var id = (item['id'] ?? '').toString();
        if (id.isEmpty ||
            existingIds.contains(id) ||
            planned.any((e) => e['id'] == id)) {
          id = StorageService.newId();
          item['id'] = id;
        }

        final oldFilePath = (item['filePath'] ?? '').toString();
        var newFilePath = oldFilePath;
        if (oldFilePath.isNotEmpty && !_isAsset(oldFilePath)) {
          final rel = _relSuffix(oldFilePath);
          if (rel != null) {
            final placed = await placement.placeRel(rel) ??
                placement.resolveRel(rel) ??
                p.joinAll([dataDir.path, ...rel.split('/')]);
            final type = await FileSystemEntity.type(
              placed,
              followLinks: false,
            );
            if (type == FileSystemEntityType.notFound) {
              // 内容没有随包带来，跳过这条，避免书架出现打不开的条目
              skipped++;
              continue;
            }
            newFilePath = placed;
          }
        }
        item['filePath'] = newFilePath;

        // 封面：系列封面在系列目录内，需要跟随目录改名前缀
        final oldCover = (item['coverPath'] ?? '').toString();
        if (oldCover.isEmpty || _isAsset(oldCover)) {
          if (oldCover.isEmpty) item['coverPath'] = 'assets/folder_cover.png';
        } else {
          String? relocated;
          if (oldFilePath.isNotEmpty && _isSameOrChild(oldCover, oldFilePath)) {
            relocated = _replacePrefix(oldCover, oldFilePath, newFilePath);
          } else {
            final rel = _relSuffix(oldCover);
            if (rel != null) {
              final placed = await placement.placeRel(rel) ??
                  placement.resolveRel(rel) ??
                  p.joinAll([dataDir.path, ...rel.split('/')]);
              relocated = placed;
            }
          }
          if (relocated == null ||
              relocated.isEmpty ||
              !await File(relocated).exists()) {
            relocated = 'assets/folder_cover.png';
          }
          item['coverPath'] = relocated;
        }

        // 头像
        final oldAvatar = (item['authorAvatarPath'] ?? '').toString();
        if (oldAvatar.isEmpty || _isAsset(oldAvatar)) {
          if (oldAvatar.isEmpty) {
            item['authorAvatarPath'] = 'assets/default_avatar.jpg';
          }
        } else {
          final rel = _relSuffix(oldAvatar);
          String? relocated;
          if (rel != null) {
            relocated = await placement.placeRel(rel) ??
                placement.resolveRel(rel) ??
                p.joinAll([dataDir.path, ...rel.split('/')]);
          }
          if (relocated == null || !await File(relocated).exists()) {
            relocated = 'assets/default_avatar.jpg';
          }
          item['authorAvatarPath'] = relocated;
        }

        planned.add(item);
        onProgress?.call(
          '正在迁移 ${item['title'] ?? ''}',
          (0.25 + 0.55 * (i + 1) / (accepted.isEmpty ? 1 : accepted.length))
              .clamp(0.0, 0.80),
        );
      }

      onProgress?.call('正在写入书架…', 0.86);

      final shelfFile = File(p.join(dataDir.path, 'bookshelf.json'));
      final merged = <Map<String, dynamic>>[...existingItems, ...planned];
      await shelfFile.writeAsString(jsonEncode({'items': merged}), flush: true);

      final pwFile = File(p.join(dataDir.path, 'passwords.json'));
      final mergedPasswords = <String, dynamic>{};
      if (await pwFile.exists()) {
        try {
          final obj = jsonDecode(await pwFile.readAsString());
          if (obj is Map && obj['items'] is Map) {
            mergedPasswords.addAll(
              Map<String, dynamic>.from(obj['items'] as Map),
            );
          }
        } catch (_) {}
      }
      for (final entry in incomingPasswords.entries) {
        if (entry.key.isEmpty) continue;
        var newKey = entry.key;
        if (!_isAsset(entry.key)) {
          final rel = _relSuffix(entry.key);
          if (rel != null) {
            final resolved = placement.resolveRel(rel) ??
                p.joinAll([dataDir.path, ...rel.split('/')]);
            // 对应条目被跳过（新机已有）或未迁移时，不留下悬空密码
            final type = await FileSystemEntity.type(resolved, followLinks: false);
            if (type == FileSystemEntityType.notFound) continue;
            newKey = resolved;
          }
        }
        mergedPasswords[newKey] = entry.value;
      }
      await pwFile.writeAsString(
        jsonEncode({'items': mergedPasswords}),
        flush: true,
      );

      onProgress?.call('正在恢复个人资料…', 0.94);

      final prefs = await SharedPreferences.getInstance();
      final nickname = (manifest['nickname'] ?? '').toString();
      if (nickname.isNotEmpty) {
        await prefs.setString('user_nickname', nickname);
      }
      final signature = (manifest['signature'] ?? '').toString();
      if (signature.isNotEmpty) {
        await prefs.setString('user_signature', signature);
      }
      String? restoredAvatar;
      final avatarRel = (manifest['avatarRel'] ?? '').toString();
      if (avatarRel.isNotEmpty) {
        final rel = _safeRel(avatarRel);
        if (rel != null) {
          final placed = await placement.placeRel(rel);
          final resolved = placed ??
              placement.resolveRel(rel) ??
              p.joinAll([dataDir.path, ...rel.split('/')]);
          if (await File(resolved).exists()) {
            restoredAvatar = resolved;
            await prefs.setString('user_avatar_path', resolved);
          }
        }
      }

      StorageService.notifyShelfChanged();
      onProgress?.call('迁移完成', 1.0);

      return MigrateImportResult(
        importedItems: planned.length,
        skippedItems: skipped,
        totalItems: merged.length,
        nickname: nickname.isEmpty ? null : nickname,
        signature: signature.isEmpty ? null : signature,
        avatarPath: restoredAvatar,
        appVersion: (manifest['appVersion'] ?? '').toString(),
        platform: (manifest['platform'] ?? '').toString(),
      );
    } finally {
      try {
        if (await staging.exists()) {
          await staging.delete(recursive: true);
        }
      } catch (_) {}
      await _deleteQuietly(zipPath);
    }
  }

  // ---------------------------------------------------------------------------
  // 内部工具
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> _readShelf(
    Directory staging,
  ) async {
    final file = File(p.join(staging.path, 'bookshelf.json'));
    if (!await file.exists()) return [];
    try {
      final text = await file.readAsString();
      if (text.trim().isEmpty) return [];
      final obj = jsonDecode(text);
      if (obj is Map && obj['items'] is List) {
        return (obj['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Map<String, String>> _readPasswords(Directory staging) async {
    final file = File(p.join(staging.path, 'passwords.json'));
    if (!await file.exists()) return {};
    try {
      final obj = jsonDecode(await file.readAsString());
      if (obj is Map && obj['items'] is Map) {
        return (obj['items'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }
    } catch (_) {}
    return {};
  }

  static String _computeWorkId(Map<String, dynamic> item) {
    final title = (item['title'] ?? '').toString();
    final authorDeviceId = (item['authorDeviceId'] ?? '').toString();
    final data = utf8.encode('$title|$authorDeviceId');
    final hash = Digest('SHA-256').process(Uint8List.fromList(data));
    return base64Url.encode(hash).substring(0, 24);
  }

  static bool _shouldSkip(String rel) {
    final first = rel.split('/').first;
    if (_skipTopDirs.contains(first)) return true;
    if (first.startsWith('migrate_tmp')) return true;
    return false;
  }

  static bool _isAsset(String path) =>
      path.startsWith('assets/') || path.startsWith('assets\\');

  static String _posix(String path) => path.replaceAll('\\', '/');

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 把压缩放进后台 isolate。参数全部是可发送对象，
  /// 避免闭包把外层（含 Widget State / Completer）一起带进 isolate。
  static Future<void> _runZipIsolate({
    required String zipPath,
    required String dataDirPath,
    required List<String> rels,
    required Uint8List manifestBytes,
    required int totalBytes,
    required SendPort progressPort,
  }) {
    return Isolate.run(
      () => _writeZipFile(
        zipPath: zipPath,
        dataDirPath: dataDirPath,
        rels: rels,
        manifestBytes: manifestBytes,
        totalBytes: totalBytes,
        progressPort: progressPort,
      ),
    );
  }

  /// 后台 isolate 解压，同样只捕获两个字符串。
  static Future<void> _runExtractIsolate(String zipPath, String targetDir) {
    return Isolate.run(() => extractFileToDisk(zipPath, targetDir));
  }

  /// 在后台 isolate 里流式写 zip（不把整个 app_data 读进内存）。
  static Future<void> _writeZipFile({
    required String zipPath,
    required String dataDirPath,
    required List<String> rels,
    required Uint8List manifestBytes,
    required int totalBytes,
    required SendPort progressPort,
  }) async {
    final encoder = ZipFileEncoder();
    encoder.create(zipPath, level: ZipFileEncoder.gzip);
    encoder.addArchiveFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
    var done = 0;
    final total = totalBytes <= 0 ? 1 : totalBytes;
    for (final rel in rels) {
      final source = File(p.joinAll([dataDirPath, ...rel.split('/')]));
      int len;
      try {
        len = await source.length();
      } catch (_) {
        continue;
      }
      await encoder.addFile(source, rel);
      done += len;
      progressPort.send([rel, (done / total).clamp(0.0, 1.0)]);
    }
    await encoder.close();
  }

  /// 把 "…/app_data/files/x" 之类的旧绝对路径，取出相对 app_data 的部分
  static String? _relSuffix(String path) {
    if (path.isEmpty || _isAsset(path)) return null;
    final norm = _posix(path);
    const marker = '/app_data/';
    final idx = norm.lastIndexOf(marker);
    if (idx >= 0) return norm.substring(idx + marker.length);
    const prefix = 'app_data/';
    if (norm.startsWith(prefix)) return norm.substring(prefix.length);
    return null;
  }

  /// 校验 zip 内条目名，禁止绝对路径与 .. 穿越
  static String? _safeRel(String name) {
    var rel = _posix(name);
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    if (rel.isEmpty) return null;
    final parts = rel.split('/');
    if (parts.any((e) => e.isEmpty || e == '.' || e == '..')) return null;
    return rel;
  }

  static bool _isSameOrChild(String path, String parent) {
    final a = _posix(path);
    final b = _posix(parent);
    if (b.isEmpty) return false;
    return a == b || a.startsWith('$b/');
  }

  static String _replacePrefix(String path, String oldPrefix, String newPrefix) {
    final a = _posix(path);
    final b = _posix(oldPrefix);
    if (a == b) return newPrefix;
    final rest = a
        .substring(b.length + 1)
        .split('/')
        .where((e) => e.isNotEmpty)
        .toList();
    return p.joinAll([newPrefix, ...rest]);
  }
}

/// 负责把 staging 里的条目搬到 app_data 下，并处理重名。
class _Placement {
  final Directory staging;
  final Directory dataDir;
  final Set<String> _reserved = {};
  final Map<String, String> _placed = {};

  _Placement(this.staging, this.dataDir);

  /// 搬运 rel（相对 app_data 的 posix 路径），返回新的绝对路径。
  Future<String?> placeRel(String rel) async {
    final cached = _placed[rel];
    if (cached != null) return cached;

    final srcPath = p.joinAll([staging.path, ...rel.split('/')]);
    final type = await FileSystemEntity.type(srcPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    final isDir = type == FileSystemEntityType.directory;

    final parts = rel.split('/');
    final name = parts.removeLast();
    final parent = Directory(p.joinAll([dataDir.path, ...parts]));
    if (!await parent.exists()) await parent.create(recursive: true);

    var candidate = p.join(parent.path, name);
    var i = 2;
    while (await FileSystemEntity.type(candidate, followLinks: false) !=
            FileSystemEntityType.notFound ||
        _reserved.contains(candidate)) {
      final nextName = isDir ? '${name}_$i' : _renamed(name, i);
      candidate = p.join(parent.path, nextName);
      i++;
    }
    _reserved.add(candidate);

    try {
      if (isDir) {
        await Directory(srcPath).rename(candidate);
      } else {
        await File(srcPath).rename(candidate);
      }
    } catch (_) {
      if (isDir) {
        await _copyDir(Directory(srcPath), Directory(candidate));
      } else {
        await File(srcPath).copy(candidate);
      }
    }

    _placed[rel] = candidate;
    return candidate;
  }

  /// 把 rel 映射成新机器上的路径（不负责搬运）。返回 null 表示无法映射。
  String? resolveRel(String rel) {
    final exact = _placed[rel];
    if (exact != null) return exact;
    for (final entry in _placed.entries) {
      if (rel.startsWith('${entry.key}/')) {
        final rest = rel
            .substring(entry.key.length + 1)
            .split('/')
            .where((e) => e.isNotEmpty)
            .toList();
        return p.joinAll([entry.value, ...rest]);
      }
    }
    return null;
  }

  static String _renamed(String name, int i) {
    final ext = p.extension(name);
    if (ext.isEmpty) return '${name}_$i';
    final base = p.basenameWithoutExtension(name);
    return '$base' '_' '$i' '$ext';
  }

  static Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final target = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDir(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }
}
