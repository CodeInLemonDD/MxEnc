import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/user_service.dart';
import '../utils/auth_service.dart';

class OobeScreen extends StatefulWidget {
  const OobeScreen({super.key});
  @override
  State<OobeScreen> createState() => _OobeScreenState();
}

class _OobeScreenState extends State<OobeScreen> {
  final _nicknameController = TextEditingController();
  final _signatureController = TextEditingController();
  final _userService = UserService();
  final _authService = AuthService();
  String? _avatarPath;
  bool _isPremium = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _isPremium = await _authService.isPremiumUser();
    final nick = await _userService.getNickname() ?? '';
    final sig = await _userService.getSignature() ?? '';
    final ava = await _userService.getAvatarPath();
    setState(() {
      _nicknameController.text = nick;
      _signatureController.text = sig;
      _avatarPath = ava ?? 'assets/default_avatar.jpg';
    });
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null) {
      setState(() { _avatarPath = result.files.single.path; });
    }
  }

  Future<void> _save() async {
    final nick = _nicknameController.text.trim();
    final sig = _signatureController.text.trim();
    final ava = _avatarPath ?? '';
    if (_isPremium) {
      if (nick.isEmpty || sig.isEmpty || ava.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请完善头像、昵称与个签')));
        return;
      }
    }
    setState(() { _isSaving = true; });
    await _userService.setNickname(nick);
    await _userService.setSignature(sig);
    if (ava.isNotEmpty) await _userService.setAvatarPath(ava);
    await _userService.setOobeDone(true);
    if (mounted) {
      setState(() { _isSaving = false; });
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('设置资料'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    '欢迎使用 猫鸮加密',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '请完善资料以开始使用。高级功能需完成激活。',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.12)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(40),
                      child: SizedBox(
                        width: 80,
                        height: 80,
                        child: _avatarPath != null && _avatarPath!.startsWith('assets/')
                            ? Image.asset(_avatarPath!, fit: BoxFit.cover)
                            : (_avatarPath != null && File(_avatarPath!).existsSync()
                                ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                                : Image.asset('assets/default_avatar.jpg', fit: BoxFit.cover)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _nicknameController,
                            decoration: const InputDecoration(labelText: '昵称'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _signatureController,
                            decoration: const InputDecoration(labelText: '个签'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(onPressed: _pickAvatar, icon: const Icon(Icons.photo_camera)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _isSaving ? null : _save,
              child: const Text('完成'),
            ),
            if (_isSaving)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
