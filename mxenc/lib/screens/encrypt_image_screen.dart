import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../rust_bridge.dart';
import '../utils/auth_service.dart';
import '../utils/user_service.dart';
import 'dart:convert';
import 'dart:typed_data';

class EncryptImageScreen extends StatefulWidget {
  final RustBridge rustBridge;

  const EncryptImageScreen({super.key, required this.rustBridge});

  @override
  State<EncryptImageScreen> createState() => _EncryptImageScreenState();
}

class _EncryptImageScreenState extends State<EncryptImageScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  File? _selectedImage;
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
    if (!_hasPermission && mounted) {
      Navigator.pushReplacementNamed(context, '/permission');
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    if (result != null) {
      setState(() {
        _selectedImage = File(result.files.single.path!);
        _errorMessage = null;
      });
    }
  }

  Future<void> _encryptImage() async {
    if (!_hasPermission) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/permission');
      }
      return;
    }
    if (_selectedImage == null) {
      setState(() {
        _errorMessage = '请先选择图片';
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
      _progressLabel = '读取图片';
    });

    Uint8List encrypted;
    String filename;
    try {
      final bytes = await _selectedImage!.readAsBytes();
      filename = path.basename(_selectedImage!.path);

      // 组装作者元数据（用于头部存储）
      Uint8List? meta;
      try {
        final us = UserService();
        final auth = AuthService();
        final metaObj = {
          'authorNickname': await us.getNickname() ?? '',
          'authorSignature': await us.getSignature() ?? '',
          'authorAvatarPath': await us.getAvatarPath() ?? '',
          'authorDeviceId': await auth.getDeviceId(),
        };
        meta = Uint8List.fromList(utf8.encode(jsonEncode(metaObj)));
      } catch (_) {}

      setState(() {
        _progress = 0.4;
        _progressLabel = '加密中';
      });
      encrypted = await widget.rustBridge.encryptFileWithMetadata(
        plaintext: bytes,
        password: _passwordController.text,
        originalFilename: filename,
        fileType: MxEncFileType.image,
        metadata: meta,
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
      String savePath;
      final outName = '$filename.mxenc';
      setState(() {
        _progress = 0.8;
        _progressLabel = '保存文件';
      });
      if (Platform.isAndroid) {
        final dir = await FilePicker.platform.getDirectoryPath(dialogTitle: '选择保存位置');
        if (dir != null && dir.isNotEmpty) {
          savePath = path.join(dir, outName);
        } else {
          try {
            final downloads = await getExternalStorageDirectories(type: StorageDirectory.downloads);
            if (downloads != null && downloads.isNotEmpty) {
              savePath = path.join(downloads.first.path, outName);
            } else {
              final ext = await getExternalStorageDirectory();
              savePath = path.join((ext?.path ?? (await getTemporaryDirectory()).path), outName);
            }
          } catch (_) {
            final ext = await getExternalStorageDirectory();
            savePath = path.join((ext?.path ?? (await getTemporaryDirectory()).path), outName);
          }
        }
      } else {
        savePath = '${_selectedImage!.path}.mxenc';
      }
      await File(savePath).writeAsBytes(encrypted);

      if (mounted) {
        setState(() {
          _progress = 1.0;
          _progressLabel = '完成';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('图片已加密并保存到: $savePath')),
        );
        setState(() {
          _selectedImage = null;
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

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text('加密图片')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('加密图片')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('选择图片并设置密码', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _isEncrypting ? null : _pickImage,
                  icon: const Icon(Icons.image),
                  label: const Text('选择图片'),
                ), // <-- 修复点：添加了逗号
                const SizedBox(height: 8),
                if (_selectedImage != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(_selectedImage!, height: 200, fit: BoxFit.cover),
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: '设置密码',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() { _obscurePassword = !_obscurePassword; });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
                  enabled: !_isEncrypting,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: '确认密码',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                      onPressed: () {
                        setState(() { _obscureConfirmPassword = !_obscureConfirmPassword; });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  enabled: !_isEncrypting,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isEncrypting ? null : _encryptImage,
                  child: const Text('开始加密'),
                ),
                if (_isEncrypting)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(
                      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                if (_errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
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