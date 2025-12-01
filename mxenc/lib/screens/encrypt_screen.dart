import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../rust_bridge.dart';
import '../utils/auth_service.dart';

class EncryptScreen extends StatefulWidget {
  final RustBridge rustBridge;

  const EncryptScreen({super.key, required this.rustBridge});

  @override
  State<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends State<EncryptScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  File? _selectedFile;
  bool _isEncrypting = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final AuthService _authService = AuthService();
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  double _progress = 0.0;
  String _progressLabel = '';

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
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

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();

    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _errorMessage = null;
      });
    }
  }

  Future<void> _encryptFile() async {
    // 再次检查权限（以防在页面打开后权限发生变化）
    if (!_hasPermission) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/permission');
      }
      return;
    }

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

    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = '两次输入的密码不一致';
      });
      return;
    }

    setState(() {
      _isEncrypting = true;
      _errorMessage = null;
      _progress = 0.1;
      _progressLabel = '读取文件';
    });

    Uint8List encryptedBytes;
    try {
      final fileBytes = await _selectedFile!.readAsBytes();
      final originalFilename = path.basename(_selectedFile!.path);
      final fileType = _determineFileType(originalFilename);
      setState(() {
        _progress = 0.4;
        _progressLabel = '加密中';
      });
      encryptedBytes = await widget.rustBridge.encryptFileWithMetadata(
        plaintext: fileBytes,
        password: _passwordController.text,
        originalFilename: originalFilename,
        fileType: fileType,
        metadata: null,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加密失败: $e';
          _isEncrypting = false;
          _progress = 0.0;
          _progressLabel = '';
        });
      }
      return;
    }

    try {
      final originalFilename = path.basename(_selectedFile!.path);
      String encryptedFilePath;
      final outName = '$originalFilename.mxenc';
      setState(() {
        _progress = 0.8;
        _progressLabel = '保存文件';
      });
      if (Platform.isAndroid) {
        final dir = await FilePicker.platform.getDirectoryPath(
          dialogTitle: '选择保存位置',
        );
        if (dir != null && dir.isNotEmpty) {
          encryptedFilePath = path.join(dir, outName);
        } else {
          try {
            final downloads = await getExternalStorageDirectories(
              type: StorageDirectory.downloads,
            );
            if (downloads != null && downloads.isNotEmpty) {
              encryptedFilePath = path.join(downloads.first.path, outName);
            } else {
              final ext = await getExternalStorageDirectory();
              encryptedFilePath = path.join(
                (ext?.path ?? (await getTemporaryDirectory()).path),
                outName,
              );
            }
          } catch (_) {
            final ext = await getExternalStorageDirectory();
            encryptedFilePath = path.join(
              (ext?.path ?? (await getTemporaryDirectory()).path),
              outName,
            );
          }
        }
      } else {
        encryptedFilePath = '${_selectedFile!.path}.mxenc';
      }
      await File(encryptedFilePath).writeAsBytes(encryptedBytes);
      if (mounted) {
        setState(() {
          _progress = 1.0;
          _progressLabel = '完成';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件已加密并保存到: $encryptedFilePath')),
        );
        setState(() {
          _selectedFile = null;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '导出失败: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isEncrypting = false;
          _progress = 0.0;
          _progressLabel = '';
        });
      }
    }
  }

  // 根据文件名判断文件类型
  MxEncFileType _determineFileType(String filename) {
    final lower = filename.toLowerCase();
    // 图片文件
    if (lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.svg')) {
      return MxEncFileType.image;
    }
    // 小说文件
    if (lower.endsWith('.txt') ||
        lower.endsWith('.md') ||
        lower.endsWith('.novel') ||
        lower.endsWith('.epub') ||
        lower.endsWith('.mobi') ||
        lower.endsWith('.pdf')) {
      return MxEncFileType.novel;
    }
    return MxEncFileType.generic;
  }

  @override
  Widget build(BuildContext context) {
    // 显示权限检查加载状态
    if (_isCheckingPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('文件加密')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('文件加密')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '文件加密',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // 文件选择
                ElevatedButton.icon(
                  onPressed: _isEncrypting ? null : _pickFile,
                  icon: const Icon(Icons.file_upload),
                  label: const Text('选择要加密的文件'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                if (_selectedFile != null)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('已选择: ${path.basename(_selectedFile!.path)}'),
                  ),
                const SizedBox(height: 16),

                // 密码输入
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
                  enabled: !_isEncrypting,
                ),
                const SizedBox(height: 16),

                // 确认密码
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
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  enabled: !_isEncrypting,
                ),
                const SizedBox(height: 24),

                // 加密按钮
                ElevatedButton(
                  onPressed: _isEncrypting ? null : _encryptFile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _isEncrypting
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('开始加密', style: TextStyle(fontSize: 16)),
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

                // 提示信息
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '安全提示:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text('• 加密后的文件将保存为 "原文件名.mxenc"'),
                        Text('• 请妥善保管您的密码，密码丢失将无法恢复文件'),
                        Text('• 加密文件可在任何平台上使用猫鸮加密查看器打开'),
                      ],
                    ),
                  ),
                ),
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
