import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'cover_editor_screen.dart';
import '../rust_bridge.dart';
import '../utils/mxenc_dart.dart';
import '../utils/user_service.dart';
import '../utils/auth_service.dart';
import '../utils/keyboard_utils.dart';
import '../utils/storage_service.dart';

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

  @override
  void initState() {
    super.initState();
    _addChapter(initial: true);
  }

  void _addText() {
    if (_chapters.isEmpty || _currentChapterIndex < 0) {
      _addChapter();
    }
    setState(() {
      _blocks.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(), // Unique ID
        'type': 'text',
        'content': '',
        'chapterId': _chapters[_currentChapterIndex]['id'],
      });
    });
  }

  Future<void> _addImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      if (_chapters.isEmpty || _currentChapterIndex < 0) {
        _addChapter();
      }
      setState(() {
        _blocks.add({
          'id': DateTime.now().microsecondsSinceEpoch.toString(), // Unique ID
          'type': 'image',
          'path': result.files.single.path,
          'chapterId': _chapters[_currentChapterIndex]['id'],
        });
      });
    }
  }

  void _addChapter({bool initial = false}) {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _chapters.add({'id': id, 'title': initial ? '第一章' : '未命名章节'});
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
                                    if (_chapters.isEmpty) {
                                      // 如果删除了所有章节，重置当前索引为 -1
                                      // 外部会处理索引越界，但这里需要确保状态一致
                                      // 实际上，我们应该避免无章节状态，所以这里可以自动添加一个新章节
                                      final id = DateTime.now()
                                          .microsecondsSinceEpoch
                                          .toString();
                                      _chapters.add({
                                        'id': id,
                                        'title': '未命名章节',
                                      });
                                    }
                                  });
                                  setState(() {
                                    _blocks.removeWhere(
                                      (b) => b['chapterId'] == removedId,
                                    );
                                    // 修正当前章节索引
                                    if (_currentChapterIndex >=
                                        _chapters.length) {
                                      _currentChapterIndex =
                                          _chapters.length - 1;
                                    }
                                    if (_currentChapterIndex < 0 &&
                                        _chapters.isNotEmpty) {
                                      _currentChapterIndex = 0;
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

    // 数据清洗：确保所有 Block 都有 chapterId
    if (_chapters.isEmpty) {
      _addChapter(initial: true);
    }
    final defaultChapterId = _chapters.first['id'].toString();
    for (final b in _blocks) {
      if (b['chapterId'] == null) {
        b['chapterId'] = defaultChapterId;
      }
    }

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
            final f = File(p);
            if (!await f.exists()) {
              throw Exception('文件不存在: ${path.basename(p)}');
            }
            final bytes = await f.readAsBytes();
            imageIdMap[p] = images.length;
            images.add(bytes);
          } catch (e) {
            if (mounted) {
              // Close 作品信息 dialog if open
              // Navigator.pop(context) might have already been called or need to be called
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
      }
    }
    final blocks = _blocks.map((b) {
      final cid = (b['chapterId'] ?? defaultChapterId).toString();
      if (b['type'] == 'text') {
        return {
          'type': 'text',
          'content': (b['content'] ?? '').toString(),
          'chapterId': cid,
        };
      } else {
        final p = (b['path']?.toString() ?? '');
        final id = imageIdMap[p] ?? 0;
        return {
          'type': 'image',
          'ref': id,
          'name': path.basename(p),
          'chapterId': cid,
        };
      }
    }).toList();

    // 强制清洗 chapters 中的 ID 为字符串
    final cleanChapters = _chapters
        .map(
          (c) => {
            'id': (c['id'] ?? '').toString(),
            'title': (c['title'] ?? '章节').toString(),
          },
        )
        .toList();

    final manifest = {
      'title': title,
      'blocks': blocks,
      'chapters': cleanChapters,
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
    } else if (Platform.isIOS) {
      final dir = await getApplicationDocumentsDirectory();
      savePath = path.join(dir.path, '$title.mxenc');
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
          'isNovel': false,
          'isRichNovel': true,
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

  @override
  Widget build(BuildContext context) {
    final currentBlocks = _chapters.isEmpty || _currentChapterIndex < 0
        ? <Map<String, dynamic>>[]
        : _blocks
              .where(
                (b) => b['chapterId'] == _chapters[_currentChapterIndex]['id'],
              )
              .toList();

    return GestureDetector(
      onTap: () => KeyboardUtils.hide(context),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('富文本编辑器'),
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
        body: Column(
          children: [
            // 导出进度条
            if (_exportProgress > 0 && _exportProgress < 1.0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: _exportProgress),
                    const SizedBox(height: 4),
                    Text(
                      _exportLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),

            // 主要内容列表
            Expanded(
              child: _chapters.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.library_books,
                            size: 64,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '暂无章节',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => _addChapter(initial: true),
                            child: const Text('创建新章节'),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: currentBlocks.length,
                      itemBuilder: (context, index) {
                        final block = currentBlocks[index];
                        // 确保每个 Block 都有 ID，如果没有（旧数据），临时生成一个
                        final keyId = block['id'] ??=
                            DateTime.now().microsecondsSinceEpoch.toString() +
                            index.toString();
                        return _buildBlockItem(block, keyId);
                      },
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _buildBottomToolbar(),
      ),
    );
  }

  Widget _buildBottomToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 章节切换
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _currentChapterIndex >= 0
                        ? _currentChapterIndex
                        : null,
                    hint: const Text('选择章节'),
                    items: List.generate(_chapters.length, (index) {
                      return DropdownMenuItem(
                        value: index,
                        child: Text(
                          (_chapters[index]['title'] ?? '章节').toString(),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _currentChapterIndex = v);
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 操作按钮
            IconButton.filledTonal(
              onPressed: _addText,
              icon: const Icon(Icons.text_fields),
              tooltip: '添加文本',
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _addImage,
              icon: const Icon(Icons.image),
              tooltip: '添加图片',
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _addChapter,
              icon: const Icon(Icons.add),
              tooltip: '新章节',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockItem(Map<String, dynamic> block, String keyId) {
    return Card(
      key: ValueKey(keyId),
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 内容区域
          if (block['type'] == 'text')
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextFormField(
                initialValue: block['content'],
                maxLines: null,
                minLines: 3,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '在此输入内容...',
                  isDense: true,
                ),
                onChanged: (v) => block['content'] = v,
              ),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: Image.file(
                    File(block['path'] ?? ''),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 200,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 150,
                      color: Colors.grey[200],
                      alignment: Alignment.center,
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      path.basename(block['path'] ?? ''),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ),
              ],
            ),

          // 底部操作栏（更紧凑）
          Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                ),
              ),
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerLow.withValues(alpha: 0.3),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionButton(
                  icon: Icons.vertical_align_top,
                  label: '插文',
                  onTap: () => _insertBlock(block, 'text', before: true),
                ),
                _buildActionButton(
                  icon: Icons.add_photo_alternate_outlined,
                  label: '插图',
                  onTap: () => _insertBlock(block, 'image', before: true),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red,
                  ),
                  onPressed: () => _deleteBlock(block),
                  tooltip: '删除',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteBlock(Map<String, dynamic> block) {
    setState(() {
      _blocks.remove(block);
    });
  }

  Future<void> _insertBlock(
    Map<String, dynamic> targetBlock,
    String type, {
    bool before = false,
  }) async {
    final index = _blocks.indexOf(targetBlock);
    if (index < 0) return;

    final newBlock = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'type': type,
      'chapterId': targetBlock['chapterId'],
    };

    if (type == 'text') {
      newBlock['content'] = '';
      setState(() {
        _blocks.insert(before ? index : index + 1, newBlock);
      });
    } else {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        newBlock['path'] = result.files.single.path;
        setState(() {
          _blocks.insert(before ? index : index + 1, newBlock);
        });
      }
    }
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
