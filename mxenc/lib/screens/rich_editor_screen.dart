import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'cover_editor_screen.dart';
import '../rust_bridge.dart';
import '../utils/mxenc_dart.dart';
import '../utils/user_service.dart';
import '../utils/auth_service.dart';
import '../utils/keyboard_utils.dart';

class RichEditorScreen extends StatefulWidget {
  final RustBridge? rustBridge;
  const RichEditorScreen({super.key, this.rustBridge});

  @override
  State<RichEditorScreen> createState() => _RichEditorScreenState();
}

class _RichEditorScreenState extends State<RichEditorScreen> {
  final List<Map<String, dynamic>> _blocks = [];
  final TextEditingController _titleController = TextEditingController();
  final List<Map<String, dynamic>> _chapters = [];
  int _currentChapterIndex = -1;
  double _exportProgress = 0.0;
  String _exportLabel = '';

  void _addText() {
    setState(() {
      _blocks.add({
        'type': 'text',
        'content': '',
        'chapterId': _currentChapterIndex >= 0
            ? _chapters[_currentChapterIndex]['id']
            : null,
      });
    });
  }

  Future<void> _addImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _blocks.add({
          'type': 'image',
          'path': result.files.single.path,
          'chapterId': _currentChapterIndex >= 0
              ? _chapters[_currentChapterIndex]['id']
              : null,
        });
      });
    }
  }

  void _addChapter() {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _chapters.add({'id': id, 'title': '未命名章节'});
      _currentChapterIndex = _chapters.length - 1;
    });
  }

  void _manageChapters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final scrollController = ScrollController();
        return StatefulBuilder(
          builder: (context, setSheet) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Column(
                children: [
                  const Text(
                    '章节管理',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Scrollbar(
                      controller: scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: _chapters.length,
                        itemBuilder: (context, i) {
                          return Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  initialValue: (_chapters[i]['title'] ?? '')
                                      .toString(),
                                  onChanged: (v) {
                                    _chapters[i]['title'] = v;
                                  },
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  final removedId = _chapters[i]['id'];
                                  setSheet(() {
                                    _chapters.removeAt(i);
                                  });
                                  setState(() {
                                    _blocks.removeWhere(
                                      (b) => b['chapterId'] == removedId,
                                    );
                                    if (_currentChapterIndex >=
                                        _chapters.length) {
                                      _currentChapterIndex = _chapters.isEmpty
                                          ? -1
                                          : _chapters.length - 1;
                                    }
                                  });
                                },
                                icon: const Icon(Icons.delete),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
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

  // 封面选择目前在保存流程中处理，移除此方法以避免未使用警告

  Future<void> _exportEncrypted() async {
    String title = _titleController.text.trim().isEmpty
        ? '富文本小说'
        : _titleController.text.trim();
    List<String> tags = [];
    Uint8List? tmpCoverBytes;
    String? tmpCover;
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
    _exportProgress = 0.2;
    _exportLabel = '收集资源';
    setState(() {});
    final images = <Uint8List>[];
    final imageIdMap = <String, int>{};
    for (final b in _blocks) {
      if (b['type'] == 'image') {
        final p = (b['path']?.toString() ?? '');
        if (p.isNotEmpty && !imageIdMap.containsKey(p)) {
          try {
            final bytes = await File(p).readAsBytes();
            imageIdMap[p] = images.length;
            images.add(bytes);
          } catch (_) {}
        }
      }
    }
    final blocks = _blocks.map((b) {
      if (b['type'] == 'text') {
        return {
          'type': 'text',
          'content': b['content'] ?? '',
          'chapterId': b['chapterId'],
        };
      } else {
        final p = (b['path']?.toString() ?? '');
        final id = imageIdMap[p] ?? 0;
        return {
          'type': 'image',
          'ref': id,
          'name': p.split('/').last,
          'chapterId': b['chapterId'],
        };
      }
    }).toList();
    final manifest = {
      'title': title,
      'blocks': blocks,
      'resourcesIndex': [],
      'chapters': _chapters,
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
    _exportProgress = 0.5;
    _exportLabel = '打包容器';
    setState(() {});
    final payload = MxencDart.packRichNovelContainer(
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
        dialogTitle: '保存加密小说',
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
      originalFilename: '$title.rich',
      fileType: MxEncFileType.richNovel,
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导出至: $finalPath')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('富文本编辑器'),
        actions: [
          IconButton(onPressed: _addText, icon: const Icon(Icons.text_fields)),
          IconButton(onPressed: _addImage, icon: const Icon(Icons.image)),
          IconButton(onPressed: _manageChapters, icon: const Icon(Icons.list)),
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
            itemCount: _blocks.length,
            itemBuilder: (context, index) {
              final b = _blocks[index];
              if (_currentChapterIndex >= 0) {
                final id = _chapters[_currentChapterIndex]['id'];
                if (b['chapterId'] != id) return const SizedBox.shrink();
              }
              if (b['type'] == 'text') {
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          initialValue: b['content'],
                          maxLines: null,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: '文本块',
                          ),
                          onChanged: (v) => b['content'] = v,
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.text_fields),
                              tooltip: '在上方插入文本',
                              onPressed: () {
                                setState(() {
                                  _blocks.insert(index, {
                                    'type': 'text',
                                    'content': '',
                                    'chapterId': b['chapterId'],
                                  });
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.image),
                              tooltip: '在上方插入图片',
                              onPressed: () async {
                                final res = await FilePicker.platform.pickFiles(
                                  type: FileType.image,
                                );
                                if (res != null &&
                                    res.files.single.path != null) {
                                  setState(() {
                                    _blocks.insert(index, {
                                      'type': 'image',
                                      'path': res.files.single.path,
                                      'chapterId': b['chapterId'],
                                    });
                                  });
                                }
                              },
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: '删除此块',
                              onPressed: () {
                                setState(() {
                                  _blocks.removeAt(index);
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              } else {
                return Card(
                  margin: const EdgeInsets.all(12),
                  child: ListTile(
                    leading: const Icon(Icons.image),
                    title: Text(
                      (b['path']?.toString() ?? '图片').split('/').last,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.text_fields),
                          tooltip: '在上方插入文本',
                          onPressed: () {
                            setState(() {
                              _blocks.insert(index, {
                                'type': 'text',
                                'content': '',
                                'chapterId': b['chapterId'],
                              });
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.image),
                          tooltip: '在上方插入图片',
                          onPressed: () async {
                            final res = await FilePicker.platform.pickFiles(
                              type: FileType.image,
                            );
                            if (res != null && res.files.single.path != null) {
                              setState(() {
                                _blocks.insert(index, {
                                  'type': 'image',
                                  'path': res.files.single.path,
                                  'chapterId': b['chapterId'],
                                });
                              });
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete),
                          tooltip: '删除此块',
                          onPressed: () {
                            setState(() {
                              _blocks.removeAt(index);
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.12),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  value: _currentChapterIndex >= 0
                      ? _currentChapterIndex
                      : null,
                  hint: const Text('选择章节'),
                  items: [
                    for (int i = 0; i < _chapters.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text((_chapters[i]['title'] ?? '章节').toString()),
                      ),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _currentChapterIndex = v ?? -1;
                    });
                  },
                ),
              ),
              IconButton(onPressed: _addChapter, icon: const Icon(Icons.add)),
              IconButton(
                onPressed: _addText,
                icon: const Icon(Icons.text_fields),
              ),
              IconButton(onPressed: _addImage, icon: const Icon(Icons.image)),
              FilledButton(
                onPressed: _exportEncrypted,
                child: const Text('保存'),
              ),
            ],
          ),
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
