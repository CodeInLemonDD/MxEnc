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
  String _exportLabel = '';

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
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '章节管理',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  for (int i = 0; i < _chapters.length; i++)
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: (_chapters[i]['title'] ?? '')
                                .toString(),
                            onChanged: (v) {
                              setState(() {
                                _chapters[i]['title'] = v;
                              });
                              setSheet(() {});
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
                          icon: const Icon(Icons.delete),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      _addChapter();
                      setSheet(() {});
                    },
                    child: const Text('添加章节'),
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
    final images = <Uint8List>[];
    final imageIdMap = <String, int>{};
    for (final ch in _chapters) {
      final list = (ch['images'] as List<String>);
      for (final p in list) {
        if (!imageIdMap.containsKey(p)) {
          try {
            final bytes = await File(p).readAsBytes();
            imageIdMap[p] = images.length;
            images.add(bytes);
          } catch (_) {}
        }
      }
    }
    final chapters = _chapters.map((ch) {
      final arr = (ch['images'] as List<String>)
          .map((p) => {'id': imageIdMap[p] ?? 0, 'name': p.split('/').last})
          .toList();
      return {'id': ch['id'], 'title': ch['title'], 'images': arr};
    }).toList();
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
    _exportProgress = 0.7;
    _exportLabel = '加密中';
    setState(() {});
    final encrypted = await bridge.encryptFileWithMetadata(
      plaintext: payload,
      password: password,
      originalFilename: '$title.comic',
      fileType: MxEncFileType.comic,
      metadata: null,
    );
    _exportProgress = 0.9;
    _exportLabel = '保存文件';
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
      _exportLabel = '完成';
      setState(() {});
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('导出成功'),
          content: Text('已导出至:\n$finalPath'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('漫画编辑器'),
        actions: [
          IconButton(
            onPressed: _addChapter,
            icon: const Icon(Icons.add),
            tooltip: '新建章节',
          ),
          IconButton(
            onPressed: _manageChapters,
            icon: const Icon(Icons.list),
            tooltip: '管理章节',
          ),
          IconButton(
            onPressed: _exportEncrypted,
            icon: const Icon(Icons.lock),
            tooltip: '导出加密',
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
              child: Column(
                children: [
                  LinearProgressIndicator(value: _exportProgress),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_exportLabel),
                  ),
                ],
              ),
            ),
          ),
          ListView.builder(
            itemCount: _chapters.length,
            itemBuilder: (context, index) {
              final ch = _chapters[index];
              final images = (ch['images'] as List<String>);
              return Card(
                key: ValueKey(ch['id']),
                margin: const EdgeInsets.all(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: ch['title'],
                              decoration: const InputDecoration(
                                labelText: '章节标题',
                              ),
                              onChanged: (v) => ch['title'] = v,
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () => _importImages(index),
                            icon: const Icon(Icons.image),
                            label: const Text('导入图片'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 20,
                            ),
                            tooltip: '在开头插入图片',
                            onPressed: () async {
                              final res = await FilePicker.platform.pickFiles(
                                type: FileType.image,
                              );
                              if (res != null &&
                                  res.files.single.path != null) {
                                setState(() {
                                  images.insert(0, res.files.single.path!);
                                });
                              }
                            },
                          ),
                          for (int i = 0; i < images.length; i++) ...[
                            InputChip(
                              label: Text(images[i].split('/').last),
                              onDeleted: () {
                                setState(() {
                                  images.removeAt(i);
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.add, size: 18),
                              tooltip: '在此后插入图片',
                              onPressed: () async {
                                final res = await FilePicker.platform.pickFiles(
                                  type: FileType.image,
                                );
                                if (res != null &&
                                    res.files.single.path != null) {
                                  setState(() {
                                    images.insert(
                                      i + 1,
                                      res.files.single.path!,
                                    );
                                  });
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addChapter,
        child: const Icon(Icons.add),
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
