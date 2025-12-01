import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:pointycastle/export.dart';

class StoragePaths {
  final Directory appDir;
  final Directory dataDir;
  final Directory coversDir;
  final File shelfIndex;
  final File passwordsIndex;
  const StoragePaths({
    required this.appDir,
    required this.dataDir,
    required this.coversDir,
    required this.shelfIndex,
    required this.passwordsIndex,
  });
}

class StorageService {
  static final _uuid = const Uuid();

  static Future<StoragePaths> _paths() async {
    final dir = await getApplicationSupportDirectory();
    final dataDir = Directory(p.join(dir.path, 'app_data'));
    final coversDir = Directory(p.join(dataDir.path, 'covers'));
    if (!dataDir.existsSync()) dataDir.createSync(recursive: true);
    if (!coversDir.existsSync()) coversDir.createSync(recursive: true);
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

  static Future<void> saveShelfItem(Map<String, dynamic> item) async {
    final sp = await _paths();
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
