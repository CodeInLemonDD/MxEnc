import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/auth_service.dart';
import '../utils/settings_service.dart';
import 'package:provider/provider.dart';
import '../utils/theme_provider.dart';
import '../utils/user_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  // 用户信息
  String _deviceId = '';
  bool _isPremiumUser = false;
  bool _isNightMode = false;
  bool _isAppLocked = false;
  String _currentTheme = '默认';
  String? _nickname;
  String? _avatarPath;
  String _version = '';
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();
  final UserService _userService = UserService();

  @override
  void initState() {
    super.initState();
    // 加载用户信息
    _loadUserInfo();
  }

  // 加载用户信息
  void _loadUserInfo() async {
    try {
      // 获取版本信息
      final packageInfo = await PackageInfo.fromPlatform();
      _version = 'v${packageInfo.version}';

      // 获取设备ID
      _deviceId = await _authService.getDeviceId();
      // 检查是否为授权用户
      _isPremiumUser = await _authService.isPremiumUser();
      _nickname = await _userService.getNickname();
      _avatarPath = await _userService.getAvatarPath();
      // 加载设置
      _isNightMode = await _settingsService.getNightMode();
      _isAppLocked = await _settingsService.getAppLock();
      _currentTheme = await _settingsService.getTheme();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // 处理错误，避免崩溃
      if (mounted) {
        setState(() {
          _deviceId = '获取失败';
        });
      }
    }
  }

  // 切换夜间模式
  void _toggleNightMode() async {
    if (!mounted) return;
    setState(() {
      _isNightMode = !_isNightMode;
    });
    await _settingsService.setNightMode(_isNightMode);
    try {
      if (!mounted) return;
      final tp = Provider.of<ThemeProvider>(context, listen: false);
      await tp.setDarkMode(_isNightMode);
    } catch (_) {}
    if (mounted) {
      _showToast(_isNightMode ? '已切换至夜间模式' : '已切换至日间模式');
    }
  }

  // 切换应用锁
  void _toggleAppLock() async {
    if (!mounted) return;
    setState(() {
      _isAppLocked = !_isAppLocked;
    });
    await _settingsService.setAppLock(_isAppLocked);
    if (mounted) {
      _showToast(_isAppLocked ? '应用锁已开启' : '应用锁已关闭');
    }
  }

  // 复制设备ID
  void _copyDeviceId() async {
    if (_deviceId.isEmpty) {
      _showToast('设备ID未加载');
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: _deviceId));
      if (mounted) {
        _showToast('设备ID已复制到剪贴板');
      }
    } catch (e) {
      if (mounted) {
        _showToast('复制失败');
      }
    }
  }

  // 切换主题色
  void _changeTheme(String theme) async {
    if (!mounted) return;
    setState(() {
      _currentTheme = theme;
    });
    await _settingsService.setTheme(theme);
    try {
      if (!mounted) return;
      final tp = Provider.of<ThemeProvider>(context, listen: false);
      final map = {
        '默认': Colors.deepPurple,
        '靛蓝': Colors.indigo,
        '蓝色': Colors.blueAccent,
        '青色': Colors.cyan,
        '蓝绿': Colors.teal,
        '绿色': Colors.greenAccent,
        '琥珀': Colors.amber,
        '橙色': Colors.orange,
        '深橙': Colors.deepOrange,
        '红色': Colors.redAccent,
        '粉色': Colors.pinkAccent,
        '洋红': Colors.purpleAccent,
      };
      final color = map[theme] ?? Colors.deepPurple;
      await tp.setSeedColor(color);
    } catch (_) {}
    if (mounted) {
      _showToast('主题已切换为$theme');
    }
  }

  // 打开回收站
  void _openRecycleBin() {
    // 导航到回收站页面
    _showToast('打开回收站');
  }

  // 查看加密记录
  void _viewEncryptionHistory() {
    // 导航到加密记录页面
    _showToast('查看加密记录');
  }

  // 查看解密记录
  void _viewDecryptionHistory() {
    // 导航到解密记录页面
    _showToast('查看解密记录');
  }

  // 显示QQ群信息
  void _showQQGroupInfo() {
    // 显示QQ群信息弹窗
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('用户群信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('官方QQ群：868140659'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: '868140659'));
                _showToast('群号已复制到剪贴板');
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('复制群号'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // 显示提示信息
  void _showToast(String message) {
    if (!mounted) return;
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的'), elevation: 0, actions: const []),
      body: ListView(
        children: [
          // 用户信息卡片
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EditProfileScreen()),
            ),
            child: _buildUserInfoCard(),
          ),
          const SizedBox(height: 16),
          // 功能列表
          _buildFeatureSection(),
          const SizedBox(height: 16),
          // 设置列表
          _buildSettingsSection(),
          const SizedBox(height: 16),
          // 用户群信息
          _buildQQGroupSection(),
          const SizedBox(height: 32),
          // 版本信息
          _buildVersionInfo(),
        ],
      ),
    );
  }

  // 构建用户信息卡片
  Widget _buildUserInfoCard() {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户头像和状态
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: (() {
                      final p = (_avatarPath ?? '').toString();
                      if (p.isNotEmpty) {
                        if (p.startsWith('assets/')) {
                          return Image.asset(p, fit: BoxFit.cover);
                        }
                        try {
                          final f = File(p);
                          if (f.existsSync()) {
                            return Image.file(f, fit: BoxFit.cover);
                          }
                        } catch (_) {}
                      }
                      return Image.asset(
                        'assets/default_avatar.jpg',
                        fit: BoxFit.cover,
                      );
                    })(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (_nickname == null || _nickname!.isEmpty)
                            ? '未设置用户名'
                            : _nickname!,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isPremiumUser ? '已授权用户' : '未授权用户',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isPremiumUser)
                  FilledButton(
                    onPressed: () async {
                      final r = await Navigator.pushNamed(
                        context,
                        '/permission',
                      );
                      if (!context.mounted) return;
                      if (r == true) {
                        _loadUserInfo();
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('申请授权'),
                  ),
                if (_isPremiumUser)
                  FilledButton(
                    onPressed: () async {
                      final r = await Navigator.pushNamed(
                        context,
                        '/permission',
                      );
                      if (!context.mounted) return;
                      if (r == true) {
                        _loadUserInfo();
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('增加时长'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            // 设备信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '设备ID',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _deviceId.isNotEmpty && _deviceId.length >= 8
                              ? '${_deviceId.substring(0, 8)}...'
                              : _deviceId.isNotEmpty
                              ? _deviceId
                              : '加载中...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: _copyDeviceId,
                    icon: const Icon(Icons.copy),
                    tooltip: '复制ID',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建功能区域
  Widget _buildFeatureSection() {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          _buildFeatureItem(
            icon: Icons.delete_outline,
            title: '回收站',
            subtitle: '已删除的文件',
            onTap: _openRecycleBin,
          ),
          const Divider(height: 1, indent: 72),
          _buildFeatureItem(
            icon: Icons.lock_outline,
            title: '加密记录',
            subtitle: '历史加密文件',
            onTap: _viewEncryptionHistory,
          ),
          const Divider(height: 1, indent: 72),
          _buildFeatureItem(
            icon: Icons.lock_open,
            title: '解密记录',
            subtitle: '历史解密文件',
            onTap: _viewDecryptionHistory,
          ),
          const Divider(height: 1, indent: 72),
          _buildFeatureItem(
            icon: Icons.verified,
            title: '卡密激活',
            subtitle: '输入卡密以激活高级功能',
            onTap: () async {
              final r = await Navigator.pushNamed(context, '/permission');
              if (!context.mounted) return;
              if (r == true) {
                _loadUserInfo();
              }
            },
          ),
        ],
      ),
    );
  }

  // 构建功能项
  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.primaryContainer,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // 构建设置区域
  Widget _buildSettingsSection() {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        children: [
          _buildSettingItem(
            icon: Icons.color_lens_outlined,
            title: '主题色',
            value: _currentTheme,
            onTap: _showThemeSelectionDialog,
          ),
          const Divider(height: 1, indent: 72),
          _buildToggleSettingItem(
            icon: Icons.nightlight_round,
            title: '夜间模式',
            value: _isNightMode,
            onToggle: _toggleNightMode,
          ),
          const Divider(height: 1, indent: 72),
          _buildToggleSettingItem(
            icon: Icons.lock_outline,
            title: '应用锁',
            value: _isAppLocked,
            onToggle: _toggleAppLock,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.secondaryContainer,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
      title: Text(title),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ],
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildToggleSettingItem({
    required IconData icon,
    required String title,
    required bool value,
    required VoidCallback onToggle,
  }) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: theme.colorScheme.tertiaryContainer,
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 20,
          color: theme.colorScheme.onTertiaryContainer,
        ),
      ),
      title: Text(title),
      trailing: Switch(value: value, onChanged: (_) => onToggle()),
      onTap: onToggle,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _showThemeSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择主题色'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildThemeOption('默认', Colors.deepPurple),
            _buildThemeOption('红色', Colors.redAccent),
            _buildThemeOption('绿色', Colors.greenAccent),
            _buildThemeOption('橙色', Colors.orange),
            _buildThemeOption('靛蓝', Colors.indigo),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption(String name, Color color) {
    return ListTile(
      leading: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: color,
          border: _currentTheme == name
              ? Border.all(color: Colors.blue, width: 2)
              : Border.all(color: Colors.transparent),
        ),
      ),
      title: Text(name),
      onTap: () {
        _changeTheme(name);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildQQGroupSection() {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: theme.colorScheme.primaryContainer,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.group_outlined,
            size: 20,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        title: const Text('用户群'),
        subtitle: Text(
          '868140659',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        onTap: _showQQGroupInfo,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildVersionInfo() {
    return Align(
      alignment: Alignment.center,
      child: Text(
        'MxEnc $_version',
        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
      ),
    );
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nicknameController = TextEditingController();
  final _signatureController = TextEditingController();
  String? _avatarPath;
  final _userService = UserService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final nick = await _userService.getNickname() ?? '';
    final sig = await _userService.getSignature() ?? '';
    final ava = await _userService.getAvatarPath();
    if (mounted) {
      setState(() {
        _nicknameController.text = nick;
        _signatureController.text = sig;
        _avatarPath = ava ?? 'assets/default_avatar.jpg';
      });
    }
  }

  Future<void> _pickAvatar() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null) {
      setState(() {
        _avatarPath = result.files.single.path;
      });
    }
  }

  Future<void> _save() async {
    await _userService.setNickname(_nicknameController.text.trim());
    await _userService.setSignature(_signatureController.text.trim());
    if (_avatarPath != null && _avatarPath!.isNotEmpty) {
      await _userService.setAvatarPath(_avatarPath!);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('编辑个人信息')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: SizedBox(
                width: 100,
                height: 100,
                child: _avatarPath != null && _avatarPath!.startsWith('assets/')
                    ? Image.asset(_avatarPath!, fit: BoxFit.cover)
                    : (_avatarPath != null && File(_avatarPath!).existsSync()
                          ? Image.file(File(_avatarPath!), fit: BoxFit.cover)
                          : Image.asset(
                              'assets/default_avatar.jpg',
                              fit: BoxFit.cover,
                            )),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickAvatar,
              icon: const Icon(Icons.photo),
              label: const Text('更换头像'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _signatureController,
              decoration: const InputDecoration(labelText: '个签'),
            ),
            const Spacer(),
            FilledButton(onPressed: _save, child: const Text('保存')),
          ],
        ),
      ),
    );
  }
}
