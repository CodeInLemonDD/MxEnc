import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pointycastle/export.dart';

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
    final obj = jsonDecode(text) as Map<String, dynamic>;
    final items = (obj['items'] as List<dynamic>).cast<Map<String, dynamic>>();
    return items;
  }

  static Future<void> saveShelfItem(Map<String, dynamic> item, {String? password}) async {
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

    items.removeWhere((e) => e['id'] == id);
    await sp.shelfIndex.writeAsString(jsonEncode({'items': items}));
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
      await sp.passwordsIndex.writeAsString(jsonEncode({'items': items}));
    } catch (_) {}
  }

  static Future<String?> getItemPassword(String filePath) async {
    final sp = await _paths();
    try {
      final text = await sp.passwordsIndex.readAsString();
      final obj = jsonDecode(text) as Map<String, dynamic>;
      final items = (obj['items'] as Map<String, dynamic>);
      final v = items[filePath];
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {}
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
}
