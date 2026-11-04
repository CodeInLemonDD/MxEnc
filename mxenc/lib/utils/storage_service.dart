import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pointycastle/export.dart';
import 'package:archive/archive_io.dart';
import 'package:mxenc/utils/mxenc_dart.dart';
import '../models/series.dart';
import 'user_service.dart';

class SeriesImportException implements Exception {
  final String type; // 'password_required', 'invalid_password'
  SeriesImportException(this.type);
  @override
  String toString() => 'SeriesImportException: $type';
}

class StoragePaths {
  final Directory appDir;
  final Directory dataDir;
  final Directory coversDir;
  final Directory filesDir;
  final Directory userDir;
  final File shelfIndex;
  final File passwordsIndex;
  const StoragePaths({
    required this.appDir,
    required this.dataDir,
    required this.coversDir,
    required this.filesDir,
    required this.userDir,
    required this.shelfIndex,
    required this.passwordsIndex,
  });
}

class StorageService {
  static final _uuid = const Uuid();

  // Event bus for shelf updates
  static final _shelfUpdateController = StreamController<void>.broadcast();
  static Stream<void> get onShelfChanged => _shelfUpdateController.stream;

  /// 外部直接改写 bookshelf.json 后（如换机迁移），通知书架刷新
  static void notifyShelfChanged() => _shelfUpdateController.add(null);

  static Future<StoragePaths> _paths() async {
    final dir = await getApplicationDocumentsDirectory();
    final dataDir = Directory(p.join(dir.path, 'app_data'));
    final coversDir = Directory(p.join(dataDir.path, 'covers'));
    final filesDir = Directory(p.join(dataDir.path, 'files'));
    final userDir = Directory(p.join(dataDir.path, 'user'));

    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
    if (!coversDir.existsSync()) coversDir.createSync(recursive: true);
    if (!filesDir.existsSync()) filesDir.createSync(recursive: true);
    if (!userDir.existsSync()) userDir.createSync(recursive: true);

    final shelfIndex = File(p.join(dataDir.path, 'bookshelf.json'));
    if (!shelfIndex.existsSync()) {
      shelfIndex.writeAsStringSync(jsonEncode({'items': []}));
    }
    final passwordsIndex = File(p.join(dataDir.path, 'passwords.json'));
    if (!passwordsIndex.existsSync()) {
      passwordsIndex.writeAsStringSync(jsonEncode({'items': {}}));
    }
    return StoragePaths(
      appDir: dir,
      dataDir: dataDir,
      coversDir: coversDir,
      filesDir: filesDir,
      userDir: userDir,
      shelfIndex: shelfIndex,
      passwordsIndex: passwordsIndex,
    );
  }

  static Future<List<Map<String, dynamic>>> loadShelf() async {
    final sp = await _paths();
    final text = await sp.shelfIndex.readAsString();
    if (text.isEmpty) return [];
    final obj = jsonDecode(text) as Map<String, dynamic>;
    final items = (obj['items'] as List<dynamic>).cast<Map<String, dynamic>>();

    // 自动扫描 files 目录下的文件夹（识别系列）
    // 这部分逻辑可以在这里，或者专门的 scan 方法里
    // 为了简单起见，我们在每次加载时简单检查一下目录结构

    return items;
  }

  // 创建系列文件夹
  static Future<void> createSeries(String title) async {
    final sp = await _paths();
    final id = newId();
    final seriesDir = Directory(p.join(sp.filesDir.path, title));

    // 如果文件夹已存在，尝试加后缀
    if (seriesDir.existsSync()) {
      throw Exception('系列 "$title" 已存在');
    }

    await seriesDir.create();

    // 创建 series.json
    final meta = SeriesMetadata(
      id: id,
      title: title,
      author: (await UserService().getNickname()) ?? '未知作者',
      coverPath: '', // 初始无封面
      volumes: [],
      passwords: {},
    );

    final metaFile = File(p.join(seriesDir.path, 'series.json'));
    await metaFile.writeAsString(jsonEncode(meta.toJson()));

    // 添加到书架索引
    final item = {
      'id': id,
      'title': title,
      'author': meta.author,
      'coverPath': 'assets/folder_cover.png', // 默认文件夹封面
      'filePath': seriesDir.path, // 指向文件夹
      'isNovel': false,
      'isSeries': true, // 标记为系列
      'importTime': DateTime.now().toIso8601String(),
      'creationTime': DateTime.now().toIso8601String(),
      'tags': ['系列'],
      'authorAvatarPath': await UserService().getAvatarPath(),
    };

    await saveShelfItem(item);
  }

  // 移动文件到系列
  static Future<void> moveItemToSeries(String itemId, String seriesId) async {
    // final sp = await _paths();
    final items = await loadShelf();

    final itemToMove = items.firstWhere(
      (e) => e['id'] == itemId,
      orElse: () => {},
    );
    final seriesItem = items.firstWhere(
      (e) => e['id'] == seriesId,
      orElse: () => {},
    );

    if (itemToMove.isEmpty || seriesItem.isEmpty) return;
    if (seriesItem['isSeries'] != true) return;

    final sourcePath = itemToMove['filePath'] as String;
    final seriesPath = seriesItem['filePath'] as String;

    if (sourcePath.isEmpty || seriesPath.isEmpty) return;

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    final fileName = p.basename(sourcePath);
    final targetPath = p.join(seriesPath, fileName);

    // 移动文件
    await sourceFile.rename(targetPath);

    // 更新 series.json
    final metaFile = File(p.join(seriesPath, 'series.json'));
    if (await metaFile.exists()) {
      final json = jsonDecode(await metaFile.readAsString());
      final meta = SeriesMetadata.fromJson(json);

      // 添加分卷
      final newVol = SeriesVolume(
        id: itemId, // 复用原来的 ID
        title: itemToMove['title'] ?? fileName,
        filename: fileName, // 存储相对文件名
        size: await File(targetPath).length(),
      );
      meta.volumes.add(newVol);

      // 迁移密码
      final oldPwd = await getItemPassword(sourcePath);
      if (oldPwd != null) {
        meta.passwords[itemId] = oldPwd; // 简单迁移，暂不加密存储内部密码
        await removeItemPassword(sourcePath); // 移除旧索引密码
      }

      await metaFile.writeAsString(jsonEncode(meta.toJson()));

      // Update aggregated tags
      await updateSeriesTags(seriesId);
    }

    // 从书架移除原单个文件
    await removeShelfItem(itemId);
  }

  // 复制文件到系列
  static Future<void> copyItemToSeries(String itemId, String seriesId) async {
    final items = await loadShelf();

    final itemToCopy = items.firstWhere(
      (e) => e['id'] == itemId,
      orElse: () => {},
    );
    final seriesItem = items.firstWhere(
      (e) => e['id'] == seriesId,
      orElse: () => {},
    );

    if (itemToCopy.isEmpty || seriesItem.isEmpty) return;
    if (seriesItem['isSeries'] != true) return;

    final sourcePath = itemToCopy['filePath'] as String;
    final seriesPath = seriesItem['filePath'] as String;

    if (sourcePath.isEmpty || seriesPath.isEmpty) return;

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    final fileName = p.basename(sourcePath);
    // Handle duplicate filename in series
    var targetName = fileName;
    var targetPath = p.join(seriesPath, targetName);
    var counter = 1;
    while (await File(targetPath).exists()) {
      final name = p.basenameWithoutExtension(fileName);
      final ext = p.extension(fileName);
      targetName = '${name}_copy$counter$ext';
      targetPath = p.join(seriesPath, targetName);
      counter++;
    }

    // 复制文件
    await sourceFile.copy(targetPath);

    // 更新 series.json
    final metaFile = File(p.join(seriesPath, 'series.json'));
    if (await metaFile.exists()) {
      final json = jsonDecode(await metaFile.readAsString());
      final meta = SeriesMetadata.fromJson(json);

      // 添加分卷
      final newVol = SeriesVolume(
        id: newId(), // 生成新 ID
        title: itemToCopy['title'] ?? fileName,
        filename: targetName,
        size: await File(targetPath).length(),
      );
      meta.volumes.add(newVol);

      // 复制密码
      final oldPwd = await getItemPassword(sourcePath);
      if (oldPwd != null) {
        meta.passwords[newVol.id] = oldPwd;
      }

      await metaFile.writeAsString(jsonEncode(meta.toJson()));

      // Update aggregated tags
      await updateSeriesTags(seriesId);
    }
  }

  // 移出文件到书架
  static Future<void> moveVolumeOutOfSeries(
    String seriesId,
    String volumeId,
  ) async {
    final sp = await _paths();
    final items = await loadShelf();
    final seriesItem = items.firstWhere(
      (e) => e['id'] == seriesId,
      orElse: () => {},
    );

    if (seriesItem.isEmpty || seriesItem['isSeries'] != true) return;

    final seriesPath = seriesItem['filePath'] as String;
    final metaFile = File(p.join(seriesPath, 'series.json'));

    if (!await metaFile.exists()) return;

    final json = jsonDecode(await metaFile.readAsString());
    final meta = SeriesMetadata.fromJson(json);

    final volIndex = meta.volumes.indexWhere((v) => v.id == volumeId);
    if (volIndex == -1) return;

    final vol = meta.volumes[volIndex];
    final sourcePath = p.join(seriesPath, vol.filename);
    final sourceFile = File(sourcePath);

    if (!await sourceFile.exists()) return;

    // Prepare target path in global filesDir
    final fileName = vol.filename; // e.g. "abc.mxenc"
    var targetName = fileName;
    var targetPath = p.join(sp.filesDir.path, targetName);
    var counter = 1;
    // Ensure unique filename in global storage
    while (await File(targetPath).exists()) {
      final name = p.basenameWithoutExtension(fileName);
      final ext = p.extension(fileName);
      targetName = '${name}_out$counter$ext';
      targetPath = p.join(sp.filesDir.path, targetName);
      counter++;
    }

    // Move file
    await sourceFile.rename(targetPath);

    // Handle Password: Move from Series Meta to Global Password Store
    final pwd = meta.passwords[volumeId];
    if (pwd != null) {
      await saveItemPassword(targetPath, pwd);
    }

    // Add to Bookshelf
    final ext = p.extension(targetName).toLowerCase();
    final isComic = ext == '.comic';
    final isNovel = !isComic; // Default to Novel (includes RichNovel)

    final newItem = {
      'id': vol
          .id, // Reuse volume ID (or generate new? Reuse is fine if unique in shelf)
      // Note: Volume ID is UUID, so likely unique.
      // But if user copied item INTO series, it got new ID.
      // If we reuse, we must ensure it's not already in shelf (unlikely unless bug)
      'title': vol.title,
      'author':
          seriesItem['author'], // Inherit author from Series? Or 'unknown'?
      // Since Series has author, maybe good to inherit.
      'coverPath': '', // No cover for now, unless we extract it?
      'filePath': targetPath,
      'isNovel': isNovel,
      'isComic': isComic,
      'isSeries': false,
      'importTime': DateTime.now().toIso8601String(),
      'creationTime': DateTime.now().toIso8601String(),
      'tags': vol.tags, // Keep volume tags
      'authorAvatarPath': seriesItem['authorAvatarPath'],
    };

    // Ensure ID uniqueness in shelf just in case
    if (items.any((e) => e['id'] == newItem['id'])) {
      newItem['id'] = newId();
    }

    await saveShelfItem(
      newItem,
      password: pwd,
    ); // This saves item and potentially password again

    // Attempt to extract cover in background
    if (pwd != null) {
      final coversPath = sp.coversDir.path;
      final itemId = newItem['id'].toString();
      compute(_extractCoverAndSave, {
        'filePath': targetPath,
        'password': pwd,
        'coverPath': p.join(coversPath, '$itemId.jpg'),
      });
    }

    // Update Series Metadata (Remove volume)
    meta.volumes.removeAt(volIndex);
    meta.passwords.remove(volumeId);
    await metaFile.writeAsString(jsonEncode(meta.toJson()));

    // Update Series Tags
    await updateSeriesTags(seriesId);
  }

  static Future<void> deleteVolumeFromSeries(
    String seriesId,
    String volumeId,
  ) async {
    // final sp = await _paths();
    final items = await loadShelf();
    final seriesItem = items.firstWhere(
      (e) => e['id'] == seriesId,
      orElse: () => {},
    );

    if (seriesItem.isEmpty || seriesItem['isSeries'] != true) return;

    final seriesPath = seriesItem['filePath'] as String;
    final metaFile = File(p.join(seriesPath, 'series.json'));

    if (await metaFile.exists()) {
      final json = jsonDecode(await metaFile.readAsString());
      final meta = SeriesMetadata.fromJson(json);

      final volIndex = meta.volumes.indexWhere((v) => v.id == volumeId);
      if (volIndex != -1) {
        final vol = meta.volumes[volIndex];
        // Delete file
        final file = File(p.join(seriesPath, vol.filename));
        if (await file.exists()) {
          await file.delete();
        }

        // Remove from meta
        meta.volumes.removeAt(volIndex);
        meta.passwords.remove(volumeId);

        await metaFile.writeAsString(jsonEncode(meta.toJson()));

        // Update tags
        await updateSeriesTags(seriesId);
      }
    }
  }

  static Future<void> updateSeriesTags(String seriesId) async {
    final items = await loadShelf();
    final index = items.indexWhere((e) => e['id'] == seriesId);
    if (index == -1) return;

    final seriesItem = items[index];
    if (seriesItem['isSeries'] != true) return;

    final seriesPath = seriesItem['filePath'] as String;
    final metaFile = File(p.join(seriesPath, 'series.json'));

    final Set<String> allTags = {'系列'};

    if (await metaFile.exists()) {
      try {
        final json = jsonDecode(await metaFile.readAsString());
        final meta = SeriesMetadata.fromJson(json);
        for (final vol in meta.volumes) {
          allTags.addAll(vol.tags);
        }
      } catch (_) {}
    }

    // Update bookshelf item
    seriesItem['tags'] = allTags.toList();

    // Write back to shelf index
    final sp = await _paths();
    await sp.shelfIndex.writeAsString(jsonEncode({'items': items}));
    _shelfUpdateController.add(null);
  }

  // 更新系列分卷顺序
  static Future<void> updateSeriesVolumes(
    String seriesId,
    List<SeriesVolume> newVolumes,
  ) async {
    final items = await loadShelf();
    final seriesItem = items.firstWhere(
      (e) => e['id'] == seriesId,
      orElse: () => {},
    );
    if (seriesItem.isEmpty || seriesItem['isSeries'] != true) return;

    final seriesPath = seriesItem['filePath'] as String;
    final metaFile = File(p.join(seriesPath, 'series.json'));

    if (await metaFile.exists()) {
      final json = jsonDecode(await metaFile.readAsString());
      var meta = SeriesMetadata.fromJson(json);

      // 更新分卷列表
      meta = meta.copyWith(volumes: newVolumes);

      await metaFile.writeAsString(jsonEncode(meta.toJson()));
    }
  }

  static Future<void> updateReadProgress(
    String id,
    Map<String, dynamic> progress,
  ) async {
    final sp = await _paths();
    final items = await loadShelf();
    final index = items.indexWhere((e) => e['id'] == id);
    if (index != -1) {
      items[index]['lastReadTime'] = DateTime.now().toIso8601String();
      items[index]['readProgress'] = progress;
      await sp.shelfIndex.writeAsString(jsonEncode({'items': items}));
      _shelfUpdateController.add(null);
    }
  }

  static Future<Map<String, dynamic>?> getLastReadItem() async {
    final items = await loadShelf();
    if (items.isEmpty) return null;

    // Filter items that have lastReadTime
    final readItems = items.where((e) => e['lastReadTime'] != null).toList();
    if (readItems.isEmpty) return null;

    // Sort by lastReadTime desc
    readItems.sort((a, b) {
      final tA = DateTime.tryParse(a['lastReadTime']) ?? DateTime(1970);
      final tB = DateTime.tryParse(b['lastReadTime']) ?? DateTime(1970);
      return tB.compareTo(tA);
    });

    return readItems.first;
  }

  static Future<void> saveShelfItem(
    Map<String, dynamic> item, {
    String? password,
  }) async {
    final sp = await _paths();

    // Ensure ID exists
    if (item['id'] == null) {
      item['id'] = newId();
    }

    // --- Persistence Fix: Copy file to app storage if needed ---
    String filePath = (item['filePath'] ?? '').toString();
    if (filePath.isNotEmpty) {
      final file = File(filePath);
      if (await file.exists()) {
        // Check if file is already in our managed 'files' directory
        final isManaged = p.isWithin(sp.filesDir.path, filePath);

        if (!isManaged) {
          // It's an external or cache file. Copy it to our storage.
          try {
            final ext = p.extension(filePath);
            // Use ID to name the file to ensure uniqueness and link to the item
            final newFileName = '${item['id']}$ext';
            final newPath = p.join(sp.filesDir.path, newFileName);

            // Perform copy
            await file.copy(newPath);

            // Update item path to the persistent location
            item['filePath'] = newPath;
            // Update local var for password saving
            filePath = newPath;
          } catch (e) {
            // If copy fails (e.g. space), we fall back to original path but log it?
            // For now, proceed with original path, but it might not persist.
            debugPrint('Error copying file to storage: $e');
          }
        }
      }
    }
    // ---------------------------------------------------------

    // Save password if provided (using the potentially updated filePath)
    if (password != null && password.isNotEmpty && filePath.isNotEmpty) {
      await saveItemPassword(filePath, password);
    }

    final items = await loadShelf();
    final isNovel = item['isNovel'] == true;
    if (item['workId'] == null || (item['workId'] as String).isEmpty) {
      final title = (item['title'] ?? '').toString();
      final authorDeviceId = (item['authorDeviceId'] ?? '').toString();
      final data = utf8.encode('$title|$authorDeviceId');
      final d = Digest('SHA-256');
      final hash = d.process(Uint8List.fromList(data));
      item['workId'] = base64Url.encode(hash).substring(0, 24);
    }
    final workId = (item['workId'] ?? '').toString();
    if (isNovel) {
      items.removeWhere(
        (e) => e['isNovel'] == true && (e['workId'] ?? '') == workId,
      );
    } else {
      final filePath = (item['filePath'] ?? '').toString();
      items.removeWhere(
        (e) =>
            (e['isNovel'] != true) &&
            ((e['workId'] ?? '') == workId ||
                (e['filePath'] ?? '') == filePath),
      );
    }
    items.removeWhere((e) => e['id'] == item['id']);
    items.add(item);
    await sp.shelfIndex.writeAsString(jsonEncode({'items': items}));
    _shelfUpdateController.add(null);
  }

  static Future<void> removeShelfItem(String id) async {
    final sp = await _paths();
    final items = await loadShelf();

    // Find item to delete related file
    final itemToRemove = items.firstWhere(
      (e) => e['id'] == id,
      orElse: () => {},
    );

    if (itemToRemove.isNotEmpty) {
      final filePath = (itemToRemove['filePath'] ?? '').toString();
      final isSeries = itemToRemove['isSeries'] == true;

      if (isSeries) {
        // 如果是系列，删除整个文件夹
        final dir = Directory(filePath);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } else {
        // 如果是单文件
        if (filePath.isNotEmpty && p.isWithin(sp.filesDir.path, filePath)) {
          try {
            final file = File(filePath);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (_) {
            // Ignore delete errors
          }
        }
        // Also delete cover
        try {
          final coverPath = p.join(sp.coversDir.path, '$id.jpg');
          final coverFile = File(coverPath);
          if (await coverFile.exists()) {
            await coverFile.delete();
          }
        } catch (_) {}
      }
    }

    items.removeWhere((e) => e['id'] == id);
    await sp.shelfIndex.writeAsString(jsonEncode({'items': items}));
    _shelfUpdateController.add(null);
  }

  static Future<String> storeCoverBytes(
    String id,
    Uint8List bytes, {
    String? watermarkText,
  }) async {
    final sp = await _paths();
    final path = p.join(sp.coversDir.path, '$id.jpg');
    final f = File(path);
    await f.writeAsBytes(bytes, flush: true);
    return path;
  }

  // --- New User Avatar Logic ---
  static Future<String?> saveUserAvatar(String sourcePath) async {
    if (sourcePath.isEmpty || sourcePath.startsWith('assets/')) {
      return sourcePath;
    }
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final userDir = Directory('${appDir.path}/app_data/user');
      if (!userDir.existsSync()) {
        userDir.createSync(recursive: true);
      }
      final ext = sourcePath.split('.').last;
      final fileName = 'avatar_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final targetPath = '${userDir.path}/$fileName';
      final sourceFile = File(sourcePath);

      if (sourceFile.existsSync()) {
        // Delete old avatars? Maybe not necessary if we just overwrite ref
        // But good hygiene:
        try {
          userDir.listSync().forEach((f) {
            if (f is File && f.path.contains('avatar_')) {
              f.deleteSync();
            }
          });
        } catch (_) {}

        await sourceFile.copy(targetPath);
        return targetPath;
      }
      return sourcePath;
    } catch (e) {
      debugPrint('StorageService: Error saving user avatar: $e');
      return null;
    }
  }
  // -----------------------------

  static String newId() => _uuid.v4();

  static Future<void> saveItemPassword(String filePath, String password) async {
    final sp = await _paths();
    try {
      final text = await sp.passwordsIndex.readAsString();
      final obj = jsonDecode(text) as Map<String, dynamic>;
      final items = (obj['items'] as Map<String, dynamic>);
      items[filePath] = password;
      await sp.passwordsIndex.writeAsString(
        jsonEncode({'items': items}),
        flush: true,
      );
    } catch (e) {
      debugPrint('StorageService: Error saving password for $filePath: $e');
    }
  }

  static Future<String?> getItemPassword(String filePath) async {
    final sp = await _paths();
    try {
      final text = await sp.passwordsIndex.readAsString();
      final obj = jsonDecode(text) as Map<String, dynamic>;
      final items = (obj['items'] as Map<String, dynamic>);
      final v = items[filePath];
      if (v is String && v.isNotEmpty) return v;
    } catch (e) {
      debugPrint('StorageService: Error getting password for $filePath: $e');
    }
    return null;
  }

  static Future<void> removeItemPassword(String filePath) async {
    final sp = await _paths();
    try {
      final text = await sp.passwordsIndex.readAsString();
      final obj = jsonDecode(text) as Map<String, dynamic>;
      final items = (obj['items'] as Map<String, dynamic>);
      items.remove(filePath);
      await sp.passwordsIndex.writeAsString(jsonEncode({'items': items}));
    } catch (_) {}
  }

  // ... (exportSeriesToZip and importSeriesFromZip omitted for brevity if unchanged,
  // but since we are appending to the file, we can just add the helper at the end
  // or after the class if it's top-level.
  // Since multi_replace targets existing blocks, I will add it at the end of the file or class.)
  // Actually, let's keep it inside the class as static or ensure we don't break strict position.
  // The file view shows `exportSeriesToZip` starts around line 589.
  // `StorageService` likely ends before `importSeriesFromZip`? No, wait.
  // I'll add the helper function at the very end of the file, outside the class.
  // Top-level helper for compute (now static inside class)
  static Future<void> _extractCoverAndSave(Map<String, String> args) async {
    final filePath = args['filePath']!;
    final password = args['password']!;
    final coverPath = args['coverPath']!;

    try {
      final file = File(filePath);
      if (!file.existsSync()) return;

      final bytes = await file.readAsBytes();
      // Decrypt
      final (_, decrypted) = MxencDart.decrypt(
        mxencData: bytes,
        password: password,
      );

      // Try to unpack as Comic or Rich
      Map<String, dynamic>? manifest;
      Uint8List? payload;
      int? start;

      // Try Comic
      try {
        final res = MxencDart.unpackComicContainer(decrypted);
        manifest = res['manifest'];
        payload = decrypted; // payload in res is just reference
        start = res['start'];
      } catch (_) {
        // Try Rich
        try {
          final res = MxencDart.unpackRichNovelContainer(decrypted);
          manifest = res['manifest'];
          payload = decrypted;
          start = res['start'];
        } catch (_) {}
      }

      if (manifest != null && payload != null && start != null) {
        // Find cover image
        final indexList =
            (manifest['imagesIndex'] ?? manifest['resourcesIndex']) as List?;

        if (indexList != null && indexList.isNotEmpty) {
          Map<String, dynamic>? targetEntry;

          // Check for explicit coverRef
          final coverRef = manifest['coverRef'];
          if (coverRef is int && coverRef >= 0 && coverRef < indexList.length) {
            targetEntry = indexList[coverRef];
          } else {
            // Fallback to first image
            targetEntry = indexList[0];
          }

          if (targetEntry != null) {
            final offset = (targetEntry['byteOffset'] as int);
            final length = (targetEntry['length'] as int);

            final imgBytes = payload.sublist(
              start + offset,
              start + offset + length,
            );

            await File(coverPath).writeAsBytes(imgBytes);
          }
        }
      }
    } catch (e) {
      debugPrint('Error extracting cover: $e');
    }
  }

  static Future<String> exportSeriesToZip(
    String seriesId, {
    String? password,
  }) async {
    final sp = await _paths();
    final items = await loadShelf();
    final seriesItem = items.firstWhere(
      (e) => e['id'] == seriesId,
      orElse: () => {},
    );
    if (seriesItem.isEmpty || seriesItem['isSeries'] != true) {
      throw Exception('Not a valid series');
    }

    final seriesPath = seriesItem['filePath'] as String;
    final seriesDir = Directory(seriesPath);
    if (!seriesDir.existsSync()) throw Exception('Series directory not found');

    final metaFile = File(p.join(seriesPath, 'series.json'));
    if (!metaFile.existsSync()) throw Exception('Metadata not found');

    final metaJson = jsonDecode(await metaFile.readAsString());
    final meta = SeriesMetadata.fromJson(metaJson);

    // Create temp dir for zip preparation
    final tempDir = await getTemporaryDirectory();
    final zipWorkDir = Directory(
      p.join(tempDir.path, 'mxenc_export_${_uuid.v4()}'),
    );
    await zipWorkDir.create();

    try {
      // 1. Handle Metadata & Passwords
      var exportMeta = SeriesMetadata.fromJson(meta.toJson()); // clone

      if (password != null && password.isNotEmpty) {
        // Encrypt passwords to key.enc
        final keyEncBytes = MxencDart.encryptKeyStore(meta.passwords, password);
        File(p.join(zipWorkDir.path, 'key.enc')).writeAsBytesSync(keyEncBytes);

        // Clear passwords in exported metadata
        exportMeta = exportMeta.copyWith(passwords: {});
      } else {
        // If no zip password, strip passwords (secure by default)
        // User must know volume passwords or input them manually
        exportMeta = exportMeta.copyWith(passwords: {});
      }

      // Write modified series.json
      File(
        p.join(zipWorkDir.path, 'series.json'),
      ).writeAsStringSync(jsonEncode(exportMeta.toJson()));

      // 2. Copy Volumes and Cover
      // Volumes
      for (final vol in meta.volumes) {
        final srcVol = File(p.join(seriesPath, vol.filename));
        if (srcVol.existsSync()) {
          srcVol.copySync(p.join(zipWorkDir.path, vol.filename));
        }
      }

      // Cover
      // 优先检查标准封面文件名
      final standardCover = File(p.join(seriesPath, 'cover.jpg'));
      if (standardCover.existsSync()) {
        standardCover.copySync(p.join(zipWorkDir.path, 'cover.jpg'));
      } else if (meta.coverPath.isNotEmpty) {
        // 如果元数据中有封面路径，且不是 cover.jpg，尝试复制
        // 注意：meta.coverPath 在本地可能是绝对路径或相对路径，但在 zip 中应该是相对的
        // 这里我们假设如果它存在，我们将其复制为 'cover.jpg' 并更新 meta（如果需要）
        // 但通常 series 的 coverPath 是空的或者指向 assets。
        // 如果它是本地文件路径：
        try {
          final f = File(meta.coverPath);
          if (f.existsSync()) {
            f.copySync(p.join(zipWorkDir.path, 'cover.jpg'));
          }
        } catch (_) {}
      }

      // 3. Create Zip
      // Sanitize title for filename
      final safeTitle = meta.title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final zipFileName = '$safeTitle.mxzip';
      final exportDir = Directory(p.join(sp.appDir.path, 'exports'));
      if (!exportDir.existsSync()) exportDir.createSync();
      final zipPath = p.join(exportDir.path, zipFileName);

      // Use in-memory Archive to ensure correctness and avoid stream/lock issues
      final archive = Archive();
      final files = zipWorkDir.listSync();
      if (files.isEmpty) {
        throw Exception('导出失败：没有文件被打包 (空文件夹?)');
      }

      for (final file in files) {
        if (file is File) {
          final filename = p.basename(file.path);
          final bytes = await file.readAsBytes();
          final archiveFile = ArchiveFile(filename, bytes.length, bytes);
          archive.addFile(archiveFile);
        }
      }

      final encoder = ZipEncoder();
      final encodedBytes = encoder.encode(archive);

      final zipFile = File(zipPath);
      await zipFile.writeAsBytes(encodedBytes, flush: true);

      // 验证文件大小
      if (await zipFile.length() < 100) {
        throw Exception('导出失败：生成的文件过小 (${await zipFile.length()} bytes)');
      }

      return zipPath;
    } finally {
      // Cleanup
      if (await zipWorkDir.exists()) {
        await zipWorkDir.delete(recursive: true);
      }
    }
  }

  static Future<void> importSeriesFromZip(
    String zipPath, {
    String? password,
  }) async {
    final sp = await _paths();
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Analyze content (look for series.json and key.enc)
    ArchiveFile? seriesJsonFile;
    ArchiveFile? keyEncFile;

    for (final file in archive) {
      if (file.name == 'series.json') seriesJsonFile = file;
      if (file.name == 'key.enc') keyEncFile = file;
    }

    if (seriesJsonFile == null) {
      throw Exception('Invalid mxzip: series.json missing');
    }

    // 2. Handle Encryption
    Map<String, String> importedPasswords = {};
    if (keyEncFile != null) {
      if (password == null) {
        throw SeriesImportException('password_required');
      }
      try {
        final keyData = keyEncFile.content as List<int>;
        importedPasswords = MxencDart.decryptKeyStore(
          Uint8List.fromList(keyData),
          password,
        );
      } catch (e) {
        throw SeriesImportException('invalid_password');
      }
    }

    // 3. Prepare Destination
    final seriesJsonContent = utf8.decode(seriesJsonFile.content as List<int>);
    final metaJson = jsonDecode(seriesJsonContent);
    var meta = SeriesMetadata.fromJson(metaJson);

    // Merge passwords
    if (importedPasswords.isNotEmpty) {
      // Create new map to ensure mutability and merge
      final newPasswords = Map<String, String>.from(meta.passwords);
      newPasswords.addAll(importedPasswords);
      meta = meta.copyWith(passwords: newPasswords);
    }

    // Ensure unique folder name
    var folderName = meta.title;
    // Sanitize folder name
    folderName = folderName.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');

    var destDir = Directory(p.join(sp.filesDir.path, folderName));
    var counter = 1;
    while (destDir.existsSync()) {
      folderName = '${meta.title}_$counter';
      destDir = Directory(p.join(sp.filesDir.path, folderName));
      counter++;
    }
    await destDir.create();

    // 4. Extract Files
    for (final file in archive) {
      if (file.isFile) {
        if (file.name == 'key.enc') {
          continue; // Skip key.enc
        }
        if (file.name == 'series.json') {
          continue; // Skip, we write modified one later
        }

        final filename = file.name;
        // Basic sanitization
        if (filename.contains('..') ||
            filename.contains('/') ||
            filename.contains('\\')) {
          // simple flat extract to avoid path traversal
          final name = p.basename(filename);
          File(
            p.join(destDir.path, name),
          ).writeAsBytesSync(file.content as List<int>);
        } else {
          File(
            p.join(destDir.path, filename),
          ).writeAsBytesSync(file.content as List<int>);
        }
      }
    }

    // 5. Save Metadata
    // Update title if folder name changed
    if (folderName != meta.title) {
      meta = meta.copyWith(title: folderName);
    }
    // Check for cover
    var coverPath = 'assets/folder_cover.png';
    if (File(p.join(destDir.path, 'cover.jpg')).existsSync()) {
      // We don't really use coverPath in meta for local files, but good to have consistency
      // But for bookshelf item, we need to know.
      // Let's assume cover.jpg in folder is the cover.
      coverPath = p.join(destDir.path, 'cover.jpg');
    }

    final metaFile = File(p.join(destDir.path, 'series.json'));
    await metaFile.writeAsString(jsonEncode(meta.toJson()));

    // 6. Add to Bookshelf
    // Generate NEW ID for imported series to avoid conflicts
    final newId = StorageService.newId();
    meta = meta.copyWith(id: newId);
    await metaFile.writeAsString(
      jsonEncode(meta.toJson()),
    ); // Update meta with new ID

    final item = {
      'id': newId,
      'title': meta.title,
      'author': meta.author,
      'coverPath': coverPath,
      'filePath': destDir.path,
      'isNovel': false,
      'isSeries': true,
      'importTime': DateTime.now().toIso8601String(),
      'creationTime': DateTime.now()
          .toIso8601String(), // Reset creation time to now? Or keep original?
      // Keep original if available, but meta doesn't have it.
      'tags': ['系列'],
    };

    await saveShelfItem(item);
  }
}
