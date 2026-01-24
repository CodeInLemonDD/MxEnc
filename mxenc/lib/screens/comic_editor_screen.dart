import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../rust_bridge.dart';
import '../utils/mxenc_dart.dart';
import '../utils/user_service.dart';
import '../utils/auth_service.dart';
import '../utils/keyboard_utils.dart';
import 'cover_editor_screen.dart';
import '../utils/storage_service.dart';

class ComicEditorScreen extends StatefulWidget {
  final RustBridge? rustBridge;
  const ComicEditorScreen({super.key, this.rustBridge});

  @override
  State<ComicEditorScreen> createState() => _ComicEditorScreenState();
}

class _ComicEditorScreenState extends State<ComicEditorScreen> {
  final List<Map<String, dynamic>> _chapters = [];
  final TextEditingController _titleController = TextEditingController();
  double _exportProgress = 0.0;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _addChapter() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _chapters.add({'id': id, 'title': '未命名章节', 'images': <String>[]});
    });
  }

  void _manageChapters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Container(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                children: [
                  const Text(
                    '章节管理',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _chapters.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              Text(
                                '${i + 1}.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  initialValue: (_chapters[i]['title'] ?? '')
                                      .toString(),
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                  onChanged: (v) {
                                    setState(() {
                                      _chapters[i]['title'] = v;
                                    });
                                    // setSheet(() {}); // No need to rebuild sheet for text change
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setSheet(() {
                                    _chapters.removeAt(i);
                                  });
                                  setState(() {});
                                },
                                icon: const Icon(Icons.delete_outline),
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        _addChapter();
                        setSheet(() {});
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('添加章节'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportEncrypted() async {
    String title = _titleController.text.trim().isEmpty
        ? '漫画作品'
        : _titleController.text.trim();
    List<String> tags = [];
    String? tmpCover;
    Uint8List? tmpCoverBytes;
    bool confirmExport = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final tCtrl = TextEditingController(text: title);
        final tagCtrl = TextEditingController();
        return StatefulBuilder(
          builder: (context, setSheet) {
            return AlertDialog(
              title: const Text('作品信息'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: tCtrl,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  TextField(
                    controller: tagCtrl,
                    decoration: const InputDecoration(labelText: '标签（逗号分隔）'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final res = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                          );
                          if (res != null && res.files.single.path != null) {
                            final path = res.files.single.path!;
                            if (!context.mounted) return;
                            final cropped = await Navigator.push<Uint8List>(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CoverEditorScreen(sourceFile: File(path)),
                              ),
                            );
                            if (cropped != null) {
                              tmpCover = path;
                              tmpCoverBytes = cropped;
                              setSheet(() {});
                            }
                          }
                        },
                        icon: const Icon(Icons.photo),
                        label: const Text('选择封面（可跳过）'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tmpCover == null ? '未选择' : tmpCover!.split('/').last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    title = tCtrl.text.trim().isEmpty
                        ? title
                        : tCtrl.text.trim();
                    tags = tagCtrl.text
                        .split(',')
                        .map((e) => e.trim())
                        .where((e) => e.isNotEmpty)
                        .toList();
                    confirmExport = true;
                    Navigator.pop(context);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!confirmExport) return;
    // 封面路径仅用于对话框展示，裁剪后的字节用于容器封面
    final imageIdMap = <String, int>{};
    final images = <Uint8List>[];
    final chapters = <Map<String, dynamic>>[];

    for (var ch in _chapters) {
      final chImages = <Map<String, dynamic>>[];
      for (var p in (ch['images'] as List<String>)) {
        int id;
        if (imageIdMap.containsKey(p)) {
          id = imageIdMap[p]!;
        } else {
          try {
            final f = File(p);
            if (!await f.exists()) {
              throw Exception('文件不存在: ${path.basename(p)}');
            }
            final bytes = await f.readAsBytes();
            id = images.length;
            imageIdMap[p] = id;
            images.add(bytes);
          } catch (e) {
            if (mounted) {
              if (Navigator.canPop(context)) {
                Navigator.pop(context); // Close any potential info dialog
              }
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('导出失败'),
                  content: Text('读取图片失败: $e\n\n请检查图片文件是否已被移动或删除。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            }
            return;
          }
        }
        chImages.add({'id': id, 'name': path.basename(p)});
      }
      chapters.add({'id': ch['id'], 'title': ch['title'], 'images': chImages});
    }
    final manifest = {
      'title': title,
      'chapters': chapters,
      'tags': tags,
      'authorNickname': await (UserService().getNickname()) ?? '',
      'authorSignature': await (UserService().getSignature()) ?? '',
      'authorAvatarPath': await (UserService().getAvatarPath()) ?? '',
      'authorDeviceId': await AuthService().getDeviceId(),
      'creationTime': DateTime.now().toIso8601String(),
    };
    if (tmpCoverBytes != null) {
      imageIdMap['__cover__'] = images.length;
      images.add(tmpCoverBytes!);
      manifest['coverRef'] = imageIdMap['__cover__'] ?? 0;
    } else {
      final bd = await rootBundle.load('assets/logo.jpg');
      final def = bd.buffer.asUint8List();
      imageIdMap['__default_cover__'] = images.length;
      images.add(def);
      manifest['coverRef'] = imageIdMap['__default_cover__'] ?? 0;
    }
    final payload = MxencDart.packComicContainer(
      manifest: manifest,
      images: images,
    );
    String? savePath;
    if (Platform.isAndroid) {
      if (!await _requestPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('需要存储权限才能保存文件')));
        }
        return;
      }
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择保存位置',
      );
      if (dir == null || dir.isEmpty) return;
      savePath = path.join(dir, '$title.mxenc');
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      savePath = path.join(dir.path, '$title.mxenc');
    } else {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: '保存加密漫画',
        fileName: '$title.mxenc',
      );
      if (savePath == null) return;
    }
    String password = '';
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('设置密码'),
          content: TextField(
            controller: ctrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => KeyboardUtils.hide(context),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                password = ctrl.text;
                KeyboardUtils.hide(context);
                Navigator.pop(context);
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (password.isEmpty) return;
    final bridge = widget.rustBridge ?? await RustBridge.init();
    if (bridge == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加密组件初始化失败，请重启应用')));
      }
      return;
    }
    _exportProgress = 0.7;
    setState(() {});
    final encrypted = await bridge.encryptFileWithMetadata(
      plaintext: payload,
      password: password,
      originalFilename: '$title.comic',
      fileType: MxEncFileType.comic,
      metadata: null,
    );
    _exportProgress = 0.9;
    setState(() {});

    String finalPath = savePath;
    try {
      await File(savePath).writeAsBytes(encrypted, flush: true);
    } catch (e) {
      debugPrint('Save failed at $savePath: $e');
      bool saved = false;

      // 尝试保存到下载目录 (Android)
      if (!saved && Platform.isAndroid) {
        try {
          final downloadsDir = Directory('/storage/emulated/0/Download');
          if (await downloadsDir.exists()) {
            final fallbackPath = path.join(downloadsDir.path, '$title.mxenc');
            await File(fallbackPath).writeAsBytes(encrypted, flush: true);
            finalPath = fallbackPath;
            saved = true;
          }
        } catch (_) {}
      }

      // 尝试保存到应用外部存储
      if (!saved) {
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            final fallbackPath = path.join(extDir.path, '$title.mxenc');
            await File(fallbackPath).writeAsBytes(encrypted, flush: true);
            finalPath = fallbackPath;
            saved = true;
          }
        } catch (_) {}
      }

      // 尝试保存到临时目录
      if (!saved) {
        try {
          final tempDir = await getTemporaryDirectory();
          final fallbackPath = path.join(tempDir.path, '$title.mxenc');
          await File(fallbackPath).writeAsBytes(encrypted, flush: true);
          finalPath = fallbackPath;
          saved = true;
        } catch (_) {}
      }

      if (!saved) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
        }
        return;
      }
    }

    if (mounted) {
      _exportProgress = 1.0;
      setState(() {});

      // 自动添加到书架
      try {
        final authorNickname = await UserService().getNickname() ?? '未知作者';
        final authorAvatarPath = await UserService().getAvatarPath() ?? '';
        final authorSignature = await UserService().getSignature() ?? '';
        final authorDeviceId = await AuthService().getDeviceId();

        final itemId = StorageService.newId();
        // 生成封面路径（如果选择了封面）
        String coverPath = 'assets/placeholder.png';
        if (tmpCoverBytes != null) {
          // 简单加水印
          String masked = '';
          if (authorDeviceId.isNotEmpty) {
            masked = authorDeviceId.length > 8
                ? '${authorDeviceId.substring(0, 4)}****${authorDeviceId.substring(authorDeviceId.length - 4)}'
                : authorDeviceId;
          }
          coverPath = await StorageService.storeCoverBytes(
            itemId,
            tmpCoverBytes!,
            watermarkText: masked,
          );
        }

        final shelfItem = {
          'id': itemId,
          'title': title,
          'author': authorNickname,
          'coverPath': coverPath,
          'filePath': finalPath,
          'isNovel': false, // 对于书架 UI，漫画和富文本小说是独立类型
          'isComic': true,
          'importTime': DateTime.now().toIso8601String(),
          'creationTime': DateTime.now().toIso8601String(),
          'authorDeviceId': authorDeviceId,
          'authorSignature': authorSignature,
          'authorAvatarPath': authorAvatarPath,
          'tags': tags,
          'workId': '$title|$authorDeviceId',
        };

        await StorageService.saveShelfItem(shelfItem, password: password);
      } catch (e) {
        debugPrint('Auto add to bookshelf failed: $e');
      }

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出成功'),
          content: Text('已导出至:\n$finalPath\n\n同时已自动添加到您的书架。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                SharePlus.instance.share(
                  ShareParams(files: [XFile(finalPath)]),
                );
              },
              child: const Text('分享'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _importImages(int chapterIndex) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result != null) {
      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      setState(() {
        _chapters[chapterIndex]['images'].addAll(paths);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => KeyboardUtils.hide(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('漫画编辑器'),
          actions: [
            IconButton(
              onPressed: _manageChapters,
              icon: const Icon(Icons.format_list_bulleted),
              tooltip: '章节管理',
            ),
            IconButton(
              onPressed: _exportEncrypted,
              icon: const Icon(Icons.save_alt),
              tooltip: '保存导出',
            ),
          ],
        ),
        body: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Offstage(
                offstage: !(_exportProgress > 0 && _exportProgress < 1.0),
                child: LinearProgressIndicator(value: _exportProgress),
              ),
            ),
            if (_chapters.isEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.menu_book, size: 64, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text(
                      '暂无章节',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _addChapter,
                      icon: const Icon(Icons.add),
                      label: const Text('创建第一章'),
                    ),
                  ],
                ),
              )
            else
              ListView.builder(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom + 80,
                  top: 8,
                  left: 12,
                  right: 12,
                ),
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final ch = _chapters[index];
                  final images = (ch['images'] as List<String>);
                  return Card(
                    key: ValueKey(ch['id']),
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 章节头部
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.bookmark,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  initialValue: ch['title'],
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: '输入章节标题',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  onChanged: (v) => ch['title'] = v,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _importImages(index),
                                icon: const Icon(Icons.add_photo_alternate),
                                tooltip: '批量导入',
                                style: IconButton.styleFrom(
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 图片列表
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: images.isEmpty
                              ? Container(
                                  height: 100,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.grey.withValues(alpha: 0.3),
                                      style: BorderStyle.solid,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: TextButton.icon(
                                      onPressed: () => _importImages(index),
                                      icon: const Icon(Icons.add),
                                      label: const Text('添加图片'),
                                    ),
                                  ),
                                )
                              : ReorderableListView(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  onReorder: (oldIndex, newIndex) {
                                    setState(() {
                                      if (oldIndex < newIndex) {
                                        newIndex -= 1;
                                      }
                                      final item = images.removeAt(oldIndex);
                                      images.insert(newIndex, item);
                                    });
                                  },
                                  children: [
                                    for (int i = 0; i < images.length; i++)
                                      ListTile(
                                        key: ValueKey('${ch['id']}_$i'),
                                        contentPadding: EdgeInsets.zero,
                                        leading: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: Image.file(
                                            File(images[i]),
                                            width: 40,
                                            height: 40,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    Container(
                                                      width: 40,
                                                      height: 40,
                                                      color: Colors.grey[200],
                                                      child: const Icon(
                                                        Icons.broken_image,
                                                        size: 20,
                                                      ),
                                                    ),
                                          ),
                                        ),
                                        title: Text(
                                          path.basename(images[i]),
                                          style: const TextStyle(fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                Icons.add_circle_outline,
                                                size: 20,
                                              ),
                                              tooltip: '在此后插入',
                                              onPressed: () async {
                                                final res = await FilePicker
                                                    .platform
                                                    .pickFiles(
                                                      type: FileType.image,
                                                    );
                                                if (res != null &&
                                                    res.files.single.path !=
                                                        null) {
                                                  setState(() {
                                                    images.insert(
                                                      i + 1,
                                                      res.files.single.path!,
                                                    );
                                                  });
                                                }
                                              },
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.close,
                                                size: 20,
                                              ),
                                              color: Colors.grey,
                                              onPressed: () {
                                                setState(() {
                                                  images.removeAt(i);
                                                });
                                              },
                                            ),
                                            const Icon(
                                              Icons.drag_handle,
                                              color: Colors.grey,
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            // 底部FAB
            Positioned(
              bottom: 24,
              right: 24,
              child: FloatingActionButton.extended(
                onPressed: _addChapter,
                icon: const Icon(Icons.add),
                label: const Text('新章节'),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _requestPermission() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.status.isGranted) {
      return true;
    }

    if (await Permission.storage.status.isGranted) {
      return true;
    }

    if (await Permission.manageExternalStorage.request().isGranted) {
      return true;
    }

    if (await Permission.storage.request().isGranted) {
      return true;
    }

    return false;
  }
}
