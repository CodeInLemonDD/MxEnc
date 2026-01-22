import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import '../rust_bridge.dart';
import '../utils/auth_service.dart';
import '../utils/storage_service.dart';
import '../utils/user_service.dart';
import 'oobe_screen.dart';
import 'cover_editor_screen.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../utils/keyboard_utils.dart';

// 章节数据模型
class Chapter {
  String title;
  String content;

  Chapter({required this.title, this.content = ''});

  Map<String, dynamic> toJson() {
    return {'title': title, 'content': content};
  }

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(title: json['title'], content: json['content']);
  }
}

// 小说数据模型
class Novel {
  String title;
  String author;
  String description;
  List<Chapter> chapters;
  String? coverPath;

  Novel({
    this.title = '',
    this.author = '',
    this.description = '',
    List<Chapter>? chapters,
    this.coverPath,
  }) : chapters = chapters ?? [];

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      'description': description,
      'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    };
  }

  factory Novel.fromJson(Map<String, dynamic> json) {
    return Novel(
      title: json['title'] ?? '',
      author: json['author'] ?? '',
      description: json['description'] ?? '',
      chapters: (json['chapters'] as List)
          .map((item) => Chapter.fromJson(item))
          .toList(),
    );
  }
}

class NovelUploadScreen extends StatefulWidget {
  final RustBridge rustBridge;

  const NovelUploadScreen({super.key, required this.rustBridge});

  @override
  State<NovelUploadScreen> createState() => _NovelUploadScreenState();
}

class _NovelUploadScreenState extends State<NovelUploadScreen> {
  final Novel _novel = Novel();
  final _titleController = TextEditingController();
  final _authorController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  File? _selectedCover;
  Chapter? _editingChapter;
  bool _isExporting = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final AuthService _authService = AuthService();
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  String? _workspaceId;
  Timer? _autosaveTimer;
  final double _progress = 0.0;
  final String _progressLabel = '';

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _workspaceId = StorageService.newId();
    _setupAutosave();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _descriptionController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _setupAutosave() {
    void schedule() {
      _autosaveTimer?.cancel();
      _autosaveTimer = Timer(const Duration(seconds: 2), _autosaveNow);
    }

    _titleController.addListener(schedule);
    _authorController.addListener(schedule);
    _descriptionController.addListener(schedule);
  }

  Future<void> _autosaveNow() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final wsDir = Directory(p.join(dir.path, 'workspaces', _workspaceId!));
      if (!wsDir.existsSync()) wsDir.createSync(recursive: true);
      final novel = {
        'title': _titleController.text.trim(),
        'author': _authorController.text.trim(),
        'description': _descriptionController.text.trim(),
        'chapters': _novel.chapters.map((c) => c.toJson()).toList(),
      };
      final f = File(p.join(wsDir.path, 'novel.json'));
      await f.writeAsString(jsonEncode(novel));
      if (_selectedCover != null) {
        final coverFile = File(p.join(wsDir.path, 'cover.jpg'));
        await coverFile.writeAsBytes(await _selectedCover!.readAsBytes());
      }
    } catch (_) {}
  }

  Future<void> _checkPermission() async {
    _hasPermission = await _authService.isPremiumUser();
    setState(() {
      _isCheckingPermission = false;
    });

    // 如果没有权限，导航到权限页面
    if (!_hasPermission && mounted) {
      Navigator.pushReplacementNamed(context, '/permission');
    }
  }

  // 上传封面
  Future<void> _pickCover() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null) {
      final file = File(result.files.single.path!);
      if (!mounted) return;
      final cropped = await Navigator.push<Uint8List?>(
        context,
        MaterialPageRoute(builder: (_) => CoverEditorScreen(sourceFile: file)),
      );
      if (cropped != null) {
        final tmp = await getTemporaryDirectory();
        final path = p.join(
          tmp.path,
          'cover_${DateTime.now().microsecondsSinceEpoch}.jpg',
        );
        final f = File(path);
        await f.writeAsBytes(cropped);
        setState(() {
          _selectedCover = f;
          _errorMessage = null;
        });
      }
    }
  }

  // 添加新章节
  void _addChapter() {
    _editingChapter = Chapter(title: '新章节 ${_novel.chapters.length + 1}');
    _showChapterEditor();
  }

  // 编辑章节
  void _editChapter(Chapter chapter) {
    _editingChapter = chapter;
    _showChapterEditor();
  }

  // 删除章节
  void _deleteChapter(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除章节'),
        content: const Text('确定要删除这个章节吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _novel.chapters.removeAt(index);
              });
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // 显示章节编辑器
  void _showChapterEditor() {
    final titleController = TextEditingController(text: _editingChapter?.title);
    final contentController = TextEditingController(
      text: _editingChapter?.content,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_editingChapter!.title.isEmpty ? '新建章节' : '编辑章节'),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.6,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: '章节标题',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contentController,
                  decoration: const InputDecoration(
                    labelText: '章节内容',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: null,
                  minLines: 10,
                  keyboardType: TextInputType.multiline,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              if (titleController.text.trim().isEmpty) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('章节标题不能为空')));
                return;
              }

              setState(() {
                _editingChapter!.title = titleController.text.trim();
                _editingChapter!.content = contentController.text.trim();

                // 检查是否是新章节
                final index = _novel.chapters.indexOf(_editingChapter!);
                if (index == -1) {
                  _novel.chapters.add(_editingChapter!);
                }
              });
              Navigator.pop(context);
              _autosaveNow();
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  // 导出并加密小说
  Future<void> _exportAndEncrypt() async {
    // 再次检查权限
    if (!_hasPermission) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/permission');
      }
      return;
    }

    // 授权用户需先完善资料
    if (_hasPermission) {
      final complete = await UserService().isProfileComplete();
      if (!complete) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('请先完善资料')));
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const OobeScreen()),
          );
        }
        return;
      }
    }

    // 验证必填字段
    if (_titleController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = '请输入小说标题';
      });
      return;
    }

    if (_authorController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = '请输入作者姓名';
      });
      return;
    }

    if (_novel.chapters.isEmpty) {
      setState(() {
        _errorMessage = '请添加至少一个章节';
      });
      return;
    }

    // 验证密码
    if (_passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = '请输入加密密码';
      });
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = '两次输入的密码不一致';
      });
      return;
    }

    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      // 填充小说数据
      _novel.title = _titleController.text.trim();
      _novel.author = _authorController.text.trim();
      _novel.description = _descriptionController.text.trim();

      // 创建小说JSON数据并合并标签与作者资料
      final baseJson = _novel.toJson();
      baseJson['tags'] = _tagsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final us = UserService();
      baseJson['authorNickname'] = await us.getNickname() ?? '';
      baseJson['authorSignature'] = await us.getSignature() ?? '';
      baseJson['authorAvatarPath'] = await us.getAvatarPath() ?? '';
      try {
        baseJson['authorDeviceId'] = await _authService.getDeviceId();
      } catch (_) {
        baseJson['authorDeviceId'] = '';
      }
      final novelBytes = utf8.encode(jsonEncode(baseJson));

      // 准备小说元数据：用于预览的封面字节（若有）
      Uint8List? metadataBytes;
      if (_selectedCover != null) {
        metadataBytes = await _selectedCover!.readAsBytes();
      }

      // 加密小说数据（使用支持元数据的方法）
      final encryptedBytes = await widget.rustBridge.encryptFileWithMetadata(
        plaintext: novelBytes,
        password: _passwordController.text,
        originalFilename: '${_novel.title}.novel',
        fileType: MxEncFileType.novel,
        metadata: metadataBytes,
      );

      // 保存加密文件
      final filename = '${_novel.title}.novel.mxenc';
      String? initialSavePath;

      if (Platform.isAndroid) {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择保存位置',
        );
        if (dir != null && dir.isNotEmpty) {
          initialSavePath = path.join(dir, filename);
        }
      } else if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        initialSavePath = path.join(dir.path, filename);
      } else {
        final desktopPath = path.join(
          Platform.isWindows
              ? Platform.environment['USERPROFILE'] ?? ''
              : Platform.environment['HOME'] ?? '',
          'Desktop',
          filename,
        );
        initialSavePath = File(desktopPath).parent.existsSync()
            ? desktopPath
            : filename;
      }

      String finalPath = initialSavePath ?? '';
      bool saved = false;

      // Attempt 1: Selected path (if any)
      if (initialSavePath != null) {
        try {
          await File(initialSavePath).writeAsBytes(encryptedBytes);
          finalPath = initialSavePath;
          saved = true;
        } catch (e) {
          debugPrint('Initial save failed: $e');
        }
      }

      // Attempt 2: Downloads (Android)
      if (!saved && Platform.isAndroid) {
        try {
          final downloadsDir = Directory('/storage/emulated/0/Download');
          if (await downloadsDir.exists()) {
            final fallbackPath = path.join(downloadsDir.path, filename);
            await File(fallbackPath).writeAsBytes(encryptedBytes);
            finalPath = fallbackPath;
            saved = true;
          }
        } catch (_) {}
      }

      // Attempt 3: External Storage
      if (!saved) {
        try {
          final extDir = await getExternalStorageDirectory();
          if (extDir != null) {
            final fallbackPath = path.join(extDir.path, filename);
            await File(fallbackPath).writeAsBytes(encryptedBytes);
            finalPath = fallbackPath;
            saved = true;
          }
        } catch (_) {}
      }

      // Attempt 4: Temporary
      if (!saved) {
        try {
          final tempDir = await getTemporaryDirectory();
          final fallbackPath = path.join(tempDir.path, filename);
          await File(fallbackPath).writeAsBytes(encryptedBytes);
          finalPath = fallbackPath;
          saved = true;
        } catch (_) {}
      }

      if (!saved) {
        throw Exception('无法保存文件，请检查权限');
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('小说已加密导出: $finalPath')));

        // 重置表单
        _resetForm();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '导出加密失败: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  // 重置表单
  void _resetForm() {
    _titleController.clear();
    _authorController.clear();
    _descriptionController.clear();
    _passwordController.clear();
    _confirmPasswordController.clear();
    _selectedCover = null;
    _novel.chapters.clear();
  }

  @override
  Widget build(BuildContext context) {
    // 显示权限检查加载状态
    if (_isCheckingPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('小说上传')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('小说上传'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('使用帮助'),
                  content: const Text(
                    '1. 填写小说基本信息\n2. 上传封面图片（可选）\n3. 添加章节内容\n4. 设置加密密码\n5. 点击导出按钮生成加密文件',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('确定'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '小说上传加密',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // 封面上传
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _selectedCover != null
                        ? Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _selectedCover!,
                                  width: 150,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedCover = null;
                                    });
                                  },
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.black54,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Container(
                            width: 150,
                            height: 200,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.photo_camera,
                                  size: 48,
                                  color: Colors.grey,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '点击上传封面',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isExporting ? null : _pickCover,
                      icon: const Icon(Icons.upload),
                      label: const Text('上传封面'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 8,
                          horizontal: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 小说基本信息
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: '小说标题',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  enabled: !_isExporting,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _authorController,
                  decoration: InputDecoration(
                    labelText: '作者姓名',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  enabled: !_isExporting,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: '小说简介',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  maxLines: 3,
                  enabled: !_isExporting,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _tagsController,
                  decoration: InputDecoration(
                    labelText: '标签（逗号分隔）',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  enabled: !_isExporting,
                ),
                const SizedBox(height: 24),

                // 章节管理
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '章节管理',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _isExporting ? null : _addChapter,
                              icon: const Icon(Icons.add),
                              label: const Text('添加章节'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        if (_novel.chapters.isEmpty)
                          const Center(
                            child: Text(
                              '暂无章节，点击"添加章节"开始编辑',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        else
                          ListView.builder(
                            shrinkWrap: true,
                            itemCount: _novel.chapters.length,
                            itemBuilder: (context, index) {
                              final chapter = _novel.chapters[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: 1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListTile(
                                  title: Text(
                                    '${index + 1}. ${chapter.title}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${chapter.content.length} 字',
                                    style: TextStyle(color: Colors.grey[600]!),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: _isExporting
                                            ? null
                                            : () => _editChapter(chapter),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        onPressed: _isExporting
                                            ? null
                                            : () => _deleteChapter(index),
                                      ),
                                    ],
                                  ),
                                  onTap: _isExporting
                                      ? null
                                      : () => _editChapter(chapter),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 加密设置
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          '加密设置',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          decoration: InputDecoration(
                            labelText: '设置密码',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscurePassword,
                          enabled: !_isExporting,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => KeyboardUtils.hide(context),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _confirmPasswordController,
                          decoration: InputDecoration(
                            labelText: '确认密码',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                            ),
                          ),
                          obscureText: _obscureConfirmPassword,
                          enabled: !_isExporting,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => KeyboardUtils.hide(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 导出按钮
                ElevatedButton(
                  onPressed: _isExporting ? null : _exportAndEncrypt,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('导出并加密', style: TextStyle(fontSize: 16)),
                ),
                if (_isExporting)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                  ),

                // 错误信息
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),

                const SizedBox(height: 24),
              ],
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Offstage(
              offstage: !(_progress > 0 && _progress < 1.0),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _progress),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(_progressLabel),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
