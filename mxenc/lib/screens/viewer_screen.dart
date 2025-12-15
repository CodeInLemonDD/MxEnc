import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import '../rust_bridge.dart';
import '../utils/progress.dart';
import '../utils/dynamic_watermark.dart';
import '../models/novel.dart';
import 'novel_detail_screen.dart';
import 'bookshelf_screen.dart';
import '../utils/platform_secure.dart';
import '../utils/storage_service.dart';
import '../utils/user_service.dart';
import '../utils/auth_service.dart';
import '../utils/mxenc_dart.dart';
import '../utils/keyboard_utils.dart';
import '../widgets/loading_dialog.dart';
import 'comic_detail_screen.dart';
import 'rich_detail_screen.dart';

class ViewerScreen extends StatefulWidget {
  final RustBridge rustBridge;
  final File? initialFile;

  const ViewerScreen({super.key, required this.rustBridge, this.initialFile});

  @override
  State<ViewerScreen> createState() => _ViewerScreenState();
}

class _ViewerScreenState extends State<ViewerScreen> {
  final _passwordController = TextEditingController();
  File? _selectedFile;
  bool _isDecrypting = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  double _progress = 0.0;
  String _progressLabel = '';

  String? _originalFilename;
  Uint8List? _decryptedContent;
  String? _textContent;
  Uint8List? _previewImage; // 用于小说封面预览

  String? _deviceId; // 真实设备指纹（来自Rust）

  @override
  void initState() {
    super.initState();
    if (widget.initialFile != null) {
      _selectedFile = widget.initialFile;
      _parseHeader();
    }

    // 启用防截图
    PlatformSecure.enableSecureScreen();

    // 获取设备指纹（用于水印）
    _loadDeviceId();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    // 禁用防截图
    PlatformSecure.disableSecureScreen();
    super.dispose();
  }

  Future<void> _loadDeviceId() async {
    try {
      final id = await widget.rustBridge.generateDeviceFingerprint();
      if (mounted) {
        setState(() {
          _deviceId = id;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _deviceId = 'unknown-device';
        });
      }
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mxenc'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _decryptedContent = null;
        _textContent = null;
        _previewImage = null;
        _errorMessage = null;
      });

      _parseHeader();
    }
  }

  MxEncFileType? _fileType; // 文件类型

  Future<void> _parseHeader() async {
    if (_selectedFile == null) return;

    try {
      final fileBytes = await _selectedFile!.readAsBytes();
      final (filename, fileType) = await widget.rustBridge
          .parseMxencHeaderExtended(mxencData: fileBytes);

      final decoded = _decodeFilenameUnicode(filename);
      setState(() {
        _originalFilename = _normalizePreviewFilename(decoded);
        _fileType = fileType;
      });

      try {
        final saved = await StorageService.getItemPassword(_selectedFile!.path);
        if (saved != null && saved.isNotEmpty) {
          _passwordController.text = saved;
          await _decryptFile();
        }
      } catch (_) {}

      // 解析完整头部以尝试获取元数据（用于小说封面预览）
      if (fileType == MxEncFileType.novel) {
        try {
          final result = await widget.rustBridge.parseMxencFullHeader(
            mxencData: fileBytes,
          );
          final metadata = result.$3;
          if (metadata.isNotEmpty) {
            setState(() {
              _previewImage = metadata;
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      setState(() {
        _errorMessage = '无法解析文件: $e';
      });
    }
  }

  Future<void> _decryptFile() async {
    KeyboardUtils.hide(context);
    if (_selectedFile == null) {
      setState(() {
        _errorMessage = '请先选择文件';
      });
      return;
    }

    if (_passwordController.text.isEmpty) {
      setState(() {
        _errorMessage = '请输入密码';
      });
      return;
    }

    final loading = LoadingController(0);
    // 非阻塞显示加载对话框
    // ignore: discarded_futures
    showLoadingDialog(context, controller: loading, label: '解密中');
    setState(() {
      _isDecrypting = true;
      _errorMessage = null;
      _decryptedContent = null;
      _textContent = null;
      _previewImage = null;
      _progress = 0.1;
      _progressLabel = '读取文件';
    });
    loading.set(_progress);

    try {
      final fileBytes = await _selectedFile!.readAsBytes();

      final stream = widget.rustBridge.decryptFileProgress(
        mxencData: fileBytes,
        password: _passwordController.text,
      );
      await for (final ev in stream) {
        _progress = ev.percent;
        _progressLabel = ev.label;
        setState(() {});
        loading.set(_progress);
        if (ev.phase == ProgressPhase.done &&
            ev.data != null &&
            ev.filename != null) {
          final originalFilename = _normalizePreviewFilename(
            _decodeFilenameUnicode(ev.filename!),
          );
          final decryptedBytes = ev.data!;

          // 根据文件类型处理内容
          if (_fileType == MxEncFileType.novel) {
            final parsed = await compute(decodeNovelMeta, decryptedBytes);
            final novelTitle = parsed.$1.isEmpty ? originalFilename : parsed.$1;
            final author = parsed.$2.isEmpty ? '未知作者' : parsed.$2;

            if (mounted) {
              setState(() {
                _isDecrypting = false;
              });
              String coverPath = 'assets/placeholder.png';
              if (_previewImage != null) {
                final id = StorageService.newId();
                String masked = '';
                try {
                  final s = utf8.decode(decryptedBytes, allowMalformed: true);
                  final map = jsonDecode(s) as Map<String, dynamic>;
                  final dev = (map['authorDeviceId'] ?? '').toString();
                  if (dev.isNotEmpty) {
                    masked = dev.length > 8
                        ? '${dev.substring(0, 4)}****${dev.substring(dev.length - 4)}'
                        : dev;
                  }
                } catch (_) {}
                coverPath = await StorageService.storeCoverBytes(
                  id,
                  _previewImage!,
                  watermarkText: masked,
                );
              }
              final item = BookshelfItem(
                id: StorageService.newId(),
                title: novelTitle,
                author: author,
                coverPath: coverPath,
                filePath: _selectedFile?.path ?? '',
                isNovel: true,
                importTime: DateTime.now(),
                creationTime: null,
              );
              NovelData? novel;
              try {
                final obj = await compute(decodeNovelFull, decryptedBytes);
                novel = NovelData.fromJson(obj);
              } catch (_) {}
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      NovelDetailScreen(item: item, novel: novel),
                ),
              );
              return;
            }
          } else if (_fileType == MxEncFileType.comic) {
            try {
              final packed = await compute(unpackComicEntry, decryptedBytes);
              final manifest = packed['manifest'] as Map<String, dynamic>;
              final start = packed['start'] as int;
              if (mounted) {
                setState(() {
                  _isDecrypting = false;
                });
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ComicDetailScreen(
                      manifest: manifest,
                      payload: decryptedBytes,
                      start: start,
                      sourcePath: _selectedFile?.path ?? '',
                      password: _passwordController.text,
                    ),
                  ),
                );
                return;
              }
            } catch (_) {}
          } else if (_fileType == MxEncFileType.richNovel) {
            try {
              final packed = await compute(unpackRichEntry, decryptedBytes);
              final manifest = packed['manifest'] as Map<String, dynamic>;
              final start = packed['start'] as int;
              if (mounted) {
                setState(() {
                  _isDecrypting = false;
                });
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RichDetailScreen(
                      manifest: manifest,
                      payload: decryptedBytes,
                      start: start,
                      sourcePath: _selectedFile?.path ?? '',
                      password: _passwordController.text,
                    ),
                  ),
                );
                return;
              }
            } catch (_) {}
          } else if (_fileType == MxEncFileType.image ||
              _isImageFile(originalFilename)) {
            _previewImage = decryptedBytes;
          } else if (_isTextFile(originalFilename)) {
            try {
              final s = await compute(decodeUtf8Safe, decryptedBytes);
              if (mounted) {
                setState(() {
                  _textContent = s;
                });
              }
            } catch (_) {}
          }

          if (mounted) {
            setState(() {
              _originalFilename = originalFilename;
              _decryptedContent = decryptedBytes;
              _isDecrypting = false;
              _progress = 1.0;
              _progressLabel = '完成';
            });
            if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          }
          break;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '解密失败: $e';
          _isDecrypting = false;
        });
        if (Navigator.canPop(context)) {
          Navigator.of(context).pop();
        }
        KeyboardUtils.hide(context);
      }
    }
  }

  bool _isTextFile(String filename) {
    final ext = path.extension(filename).toLowerCase();
    return [
      '.txt',
      '.md',
      '.json',
      '.csv',
      '.xml',
      '.html',
      '.css',
      '.js',
    ].contains(ext);
  }

  bool _isImageFile(String filename) {
    final ext = path.extension(filename).toLowerCase();
    return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext);
  }

  Future<void> _saveToBookshelf() async {
    try {
      final id = StorageService.newId();
      String title = _originalFilename ?? '未命名';
      String author = '未知作者';
      bool isNovel = _fileType == MxEncFileType.novel;
      DateTime now = DateTime.now();
      String authorDeviceId = '';
      String authorSignature = '';
      String authorAvatarPath = '';

      String coverPath = 'assets/placeholder.png';
      if (isNovel) {
        if (_previewImage != null) {
          coverPath = await StorageService.storeCoverBytes(id, _previewImage!);
        }
        if (_decryptedContent != null) {
          try {
            final obj = String.fromCharCodes(_decryptedContent!);
            if (obj.isNotEmpty) {
              final map = jsonDecode(obj) as Map<String, dynamic>;
              title = (map['title'] ?? title).toString();
              author = (map['author'] ?? author).toString();
              authorSignature = (map['authorSignature'] ?? '').toString();
              authorAvatarPath = (map['authorAvatarPath'] ?? '').toString();
            }
          } catch (_) {}
        }
      } else {
        if (_decryptedContent != null) {
          String masked = '';
          if (authorDeviceId.isNotEmpty) {
            masked = authorDeviceId.length > 8
                ? '${authorDeviceId.substring(0, 4)}****${authorDeviceId.substring(authorDeviceId.length - 4)}'
                : authorDeviceId;
          }
          coverPath = await StorageService.storeCoverBytes(
            id,
            _decryptedContent!,
            watermarkText: masked,
          );
        }
        try {
          final us = UserService();
          final auth = AuthService();
          author = (await us.getNickname()) ?? author;
          authorDeviceId = await auth.getDeviceId();
          authorSignature = (await us.getSignature()) ?? '';
          authorAvatarPath = (await us.getAvatarPath()) ?? '';
        } catch (_) {}
      }

      final item = {
        'id': id,
        'title': title,
        'author': author,
        'coverPath': coverPath,
        'filePath': _selectedFile?.path ?? '',
        'isNovel': isNovel,
        'importTime': now.toIso8601String(),
        'creationTime': null,
        'authorDeviceId': (() {
          if (isNovel && _decryptedContent != null) {
            try {
              final obj =
                  jsonDecode(String.fromCharCodes(_decryptedContent!))
                      as Map<String, dynamic>;
              final v = (obj['authorDeviceId'] ?? '').toString();
              return v;
            } catch (_) {}
          }
          return authorDeviceId;
        })(),
        'authorSignature': authorSignature,
        'authorAvatarPath': authorAvatarPath,
        'workId': (() {
          final baseDev = (() {
            if (isNovel && _decryptedContent != null) {
              try {
                final s = String.fromCharCodes(_decryptedContent!);
                final map = jsonDecode(s) as Map<String, dynamic>;
                return (map['authorDeviceId'] ?? '').toString();
              } catch (_) {}
            }
            return authorDeviceId;
          })();
          return '$title|$baseDev';
        })(),
      };
      await StorageService.saveShelfItem(item);
      try {
        final fp = _selectedFile?.path ?? '';
        if (fp.isNotEmpty && _passwordController.text.isNotEmpty) {
          await StorageService.saveItemPassword(fp, _passwordController.text);
        }
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存到书架')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _decryptedContent != null
          ? AppBar(
              title: Text('查看: ${path.basename(_originalFilename!)}'),
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
              actions: [
                IconButton(
                  icon: const Icon(Icons.bookmark_add),
                  onPressed: _saveToBookshelf,
                  tooltip: '保存到书架',
                ),
              ],
            )
          : AppBar(title: const Text('文件解密')),
      body: _decryptedContent != null
          ? _buildContentViewer()
          : _buildDecryptionForm(),
    );
  }

  Widget _buildDecryptionForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (_isDecrypting)
            Column(
              children: [
                LinearProgressIndicator(
                  value: _progress == 0.0 ? null : _progress,
                ),
                const SizedBox(height: 8),
                Text(_progressLabel.isEmpty ? '正在处理...' : _progressLabel),
              ],
            ),
          // 星星眼表情包
          const Text('✨(✧∇✧)✨', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 20),

          const Text(
            '解密你的文件',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),

          // 文件选择
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isDecrypting ? null : _pickFile,
              icon: const Icon(Icons.file_open),
              label: const Text('选择.mxenc文件', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),

          // 预览区域
          if (_previewImage != null && _selectedFile != null) ...[
            const SizedBox(height: 20),
            const Text('预览:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                _previewImage!,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
          ],

          if (_selectedFile != null)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade800
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已选择: ${path.basename(_selectedFile!.path)}'),
                  if (_originalFilename != null)
                    Text('原始文件: ${path.basename(_originalFilename!)}'),
                ],
              ),
            ),

          const SizedBox(height: 20),

          // 密码输入
          SizedBox(
            width: double.infinity,
            child: TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: '输入密码',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              obscureText: _obscurePassword,
              enabled: !_isDecrypting,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => KeyboardUtils.hide(context),
            ),
          ),
          const SizedBox(height: 24),

          // 解密按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isDecrypting ? null : _decryptFile,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('解密查看', style: TextStyle(fontSize: 16)),
            ),
          ),
          if (_isDecrypting)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
              ),
            ),

          // 保存到书架按钮（仅在解密后显示在表单中）
          if (_decryptedContent != null)
            Column(
              children: [
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saveToBookshelf,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text('保存到书架', style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
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
        ],
      ),
    );
  }

  Widget _buildContentViewer() {
    if (_decryptedContent == null || _originalFilename == null) {
      return const Center(child: Text('无内容可显示'));
    }

    Widget contentWidget;

    if (_textContent != null) {
      // 文本查看器
      contentWidget = SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: SelectableText(
          _textContent!,
          enableInteractiveSelection: false, // 禁用选择
          style: const TextStyle(fontSize: 16, height: 1.6),
        ),
      );
    } else if (_isImageFile(_originalFilename!)) {
      // 图片查看器
      contentWidget = Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.memory(_decryptedContent!, fit: BoxFit.contain),
        ),
      );
    } else {
      // 其他文件类型
      contentWidget = const Center(child: Text('此文件类型不支持预览'));
    }

    // 添加动态水印
    return Stack(
      fit: StackFit.expand,
      children: [
        contentWidget,
        // 保存到书架悬浮按钮
        Positioned(
          bottom: 20,
          right: 20,
          child: FloatingActionButton(
            onPressed: _saveToBookshelf,
            backgroundColor: Theme.of(context).colorScheme.primary,
            tooltip: '保存到书架',
            child: const Icon(Icons.bookmark_add),
          ),
        ),
        // 动态水印层
        if (_deviceId != null)
          DynamicWatermark(
            receiverId: (() {
              final v = _deviceId!;
              return v.length > 8
                  ? '${v.substring(0, 4)}****${v.substring(v.length - 4)}'
                  : v;
            })(),
            opacity: 0.3,
          ),
      ],
    );
  }

  String _decodeFilenameUnicode(String input) {
    try {
      if (input.contains('%')) {
        final decoded = Uri.decodeComponent(input);
        if (decoded != input) return decoded;
      }
    } catch (_) {}
    try {
      final hasHigh = input.codeUnits.any((c) => c >= 0x80);
      if (hasHigh) {
        final decoded = utf8.decode(input.codeUnits, allowMalformed: true);
        if (decoded.isNotEmpty) return decoded;
      }
    } catch (_) {}
    return input;
  }

  String _normalizePreviewFilename(String input) {
    final base = path.basename(input);
    final bad = base.isEmpty || base.contains('�');
    if (bad && _selectedFile != null) {
      return path.basename(_selectedFile!.path);
    }
    return base;
  }
}

// isolate helpers must be top-level
Map<String, dynamic> unpackComicEntry(Uint8List payload) =>
    MxencDart.unpackComicContainer(payload);
Map<String, dynamic> unpackRichEntry(Uint8List payload) =>
    MxencDart.unpackRichNovelContainer(payload);
Map<String, dynamic> _decodeJson(Uint8List data) =>
    jsonDecode(utf8.decode(data, allowMalformed: true)) as Map<String, dynamic>;
String decodeUtf8Safe(Uint8List data) =>
    utf8.decode(data, allowMalformed: true);
Map<String, dynamic> decodeNovelFull(Uint8List data) => _decodeJson(data);
(String, String) decodeNovelMeta(Uint8List data) {
  try {
    final obj = _decodeJson(data);
    if (obj.containsKey('chapters')) {
      final title = (obj['title'] ?? '').toString();
      final author = (obj['author'] ?? '').toString();
      return (title, author);
    }
  } catch (_) {}
  return ('', '');
}
