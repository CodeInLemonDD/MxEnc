import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../rust_bridge.dart';
import '../utils/lan_transfer_service.dart';
import '../utils/migrate_service.dart';
import '../utils/user_service.dart';

/// 换手机传输：旧机发送 / 新机接收。
///
/// 同一 Wi-Fi 下自动发现并直接传输；网络不通时可导出 .mxbak 离线包手动搬运。
class DeviceTransferScreen extends StatefulWidget {
  const DeviceTransferScreen({super.key, required this.rustBridge});

  final RustBridge rustBridge;

  @override
  State<DeviceTransferScreen> createState() => _DeviceTransferScreenState();
}

enum _Stage { choose, send, receive }

class _DeviceTransferScreenState extends State<DeviceTransferScreen> {
  _Stage _stage = _Stage.choose;

  // 发送端
  bool _preparing = false;
  double _sendProgress = 0;
  String _sendMessage = '';
  String? _sendError;
  String _code = '';
  String _deviceName = '';
  MigratePackage? _package;
  TransferSender? _sender;
  bool _served = false;

  // 接收端
  TransferReceiver? _receiver;
  List<DiscoveredPeer> _peers = const [];
  String? _receiveError;
  bool _busy = false;
  double _busyProgress = 0;
  String _busyMessage = '';

  @override
  void dispose() {
    _sender?.dispose();
    _receiver?.dispose();
    unawaited(MigrateService.discardPackage(_package));
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 发送
  // ---------------------------------------------------------------------------

  Future<void> _startSend() async {
    setState(() {
      _stage = _Stage.send;
      _preparing = true;
      _sendProgress = 0;
      _sendMessage = '正在整理数据…';
      _sendError = null;
      _served = false;
    });
    try {
      final pkg = await MigrateService.buildPackage(
        bridge: widget.rustBridge,
        onProgress: (message, progress) {
          if (!mounted) return;
          setState(() {
            _sendMessage = message;
            _sendProgress = progress;
          });
        },
      );
      _package = pkg;
      _deviceName = await _resolveDeviceName();
      _code = _randomCode();
      final sender = await TransferSender.start(
        packagePath: pkg.path,
        deviceName: _deviceName,
        code: _code,
        itemCount: pkg.itemCount,
        onServed: () {
          if (!mounted) return;
          setState(() => _served = true);
        },
      );
      if (!mounted) {
        await sender.dispose();
        return;
      }
      _sender = sender;
      setState(() => _preparing = false);
    } on MigrateException catch (e) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _sendError = _friendlyError(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _preparing = false;
        _sendError = '无法开启局域网传输，请改用「导出离线包」。';
      });
    }
  }

  Future<void> _exportOffline() async {
    var pkg = _package;
    setState(() {
      _busy = true;
      _busyProgress = 0;
      _busyMessage = '正在生成离线包…';
    });
    try {
      pkg ??= await MigrateService.buildPackage(
        bridge: widget.rustBridge,
        onProgress: (message, progress) {
          if (!mounted) return;
          setState(() {
            _busyMessage = message;
            _busyProgress = progress;
          });
        },
      );
      final result = await MigrateService.savePackage(pkg);
      if (!mounted) return;
      setState(() => _busy = false);
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.path)],
          text: '猫鸮加密 · 换机迁移包',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_friendlyError(e));
    }
  }

  // ---------------------------------------------------------------------------
  // 接收
  // ---------------------------------------------------------------------------

  Future<void> _startReceive() async {
    setState(() {
      _stage = _Stage.receive;
      _receiveError = null;
      _peers = const [];
    });
    try {
      final receiver = TransferReceiver(
        onUpdate: (peers) {
          if (!mounted) return;
          setState(() => _peers = peers);
        },
      );
      await receiver.start();
      if (!mounted) {
        await receiver.dispose();
        return;
      }
      _receiver = receiver;
    } on TransferException {
      if (!mounted) return;
      setState(() {
        _receiveError = '无法监听局域网，请改用「从文件导入」。';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _receiveError = '无法监听局域网，请改用「从文件导入」。';
      });
    }
  }

  Future<void> _connectPeer(DiscoveredPeer peer) async {
    final code = await _askCode(peer);
    if (code == null || code.length != 6) return;
    setState(() {
      _busy = true;
      _busyProgress = 0;
      _busyMessage = '正在连接 ${peer.name}…';
    });
    try {
      final receivedPath = await _receiver!.download(
        peer,
        code,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _busyProgress = progress * 0.5;
            _busyMessage = '正在接收…${(progress * 100).toStringAsFixed(0)}%';
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _busyProgress = 0.55;
        _busyMessage = '正在导入…';
      });
      try {
        final result = await MigrateService.importPackageFile(
          receivedPath,
          bridge: widget.rustBridge,
          onProgress: (message, progress) {
            if (!mounted) return;
            setState(() {
              _busyProgress = 0.5 + progress * 0.5;
              _busyMessage = message;
            });
          },
        );
        if (!mounted) return;
        setState(() => _busy = false);
        await _showResult(result);
      } finally {
        await _deleteQuietly(receivedPath);
      }
    } on TransferException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(
        e.code == 'wrong_code'
            ? '配对码不正确，请核对旧手机上的 6 位数字。'
            : '传输失败，请重试或改用离线包。',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_friendlyError(e));
    }
  }

  Future<void> _pickAndImport() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: false,
      );
      if (picked == null || picked.files.isEmpty) return;
      final file = picked.files.single;
      final path = file.path;
      if (path == null) {
        _toast('无法读取所选文件，请换一个途径再试。');
        return;
      }
      if (!mounted) return;
      setState(() {
        _busy = true;
        _busyProgress = 0;
        _busyMessage = '正在导入…';
      });
      final result = await MigrateService.importPackageFile(
        path,
        bridge: widget.rustBridge,
        onProgress: (message, progress) {
          if (!mounted) return;
          setState(() {
            _busyProgress = progress;
            _busyMessage = message;
          });
        },
      );
      if (!mounted) return;
      setState(() => _busy = false);
      await _showResult(result);
    } on MigrateException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(_friendlyError(e.code));
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('导入失败，请确认选择的是猫鸮加密的迁移包。');
    }
  }

  Future<String?> _askCode(DiscoveredPeer peer) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('输入配对码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('在「${peer.name}」上查看 6 位配对码'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, letterSpacing: 8),
              decoration: const InputDecoration(
                hintText: '000000',
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showResult(MigrateImportResult result) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('迁移完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已导入 ${result.importedItems} 项书架内容'),
            if (result.skippedItems > 0)
              Text('跳过 ${result.skippedItems} 项（已存在）'),
            if (result.nickname != null) Text('昵称：${result.nickname}'),
            if (result.appVersion.isNotEmpty)
              Text('来自版本：${result.appVersion}'),
            const SizedBox(height: 12),
            const Text(
              '加密文件与卡密不随迁移。新手机如需高级功能，请重新输入卡密激活。',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('好'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('换手机传输'),
        actions: [
          if (_stage != _Stage.choose)
            TextButton(
              onPressed: _reset,
              child: const Text('退出'),
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.choose => _buildChoose(),
          _Stage.send => _buildSend(),
          _Stage.receive => _buildReceive(),
        },
      ),
    );
  }

  Future<void> _reset() async {
    await _sender?.dispose();
    _sender = null;
    await _receiver?.dispose();
    _receiver = null;
    await MigrateService.discardPackage(_package);
    if (!mounted) return;
    setState(() {
      _stage = _Stage.choose;
      _package = null;
      _peers = const [];
      _busy = false;
      _sendError = null;
      _receiveError = null;
      _served = false;
      _preparing = false;
    });
  }

  Widget _buildChoose() {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              Icon(
                Icons.swap_horiz,
                size: 44,
                color: theme.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(height: 8),
              Text(
                '把书架、密码表和个人资料搬到新手机',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '两台设备连同一个 Wi-Fi 即可自动发现，直接传输；网络不通时可导出离线包手动搬运。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildRoleCard(
          icon: Icons.phone_android,
          title: '这台是旧手机',
          subtitle: '发送书架和个人资料',
          color: theme.colorScheme.primary,
          onTap: _startSend,
        ),
        const SizedBox(height: 12),
        _buildRoleCard(
          icon: Icons.phone_iphone,
          title: '这台是新手机',
          subtitle: '自动发现旧手机并接收',
          color: theme.colorScheme.tertiary,
          onTap: _startReceive,
        ),
        const SizedBox(height: 24),
        Text(
          '说明',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        const _Hint(
          icon: Icons.lock_outline,
          text: '加密过的文件和卡密不会迁移；新手机需要重新激活卡密。',
        ),
        const _Hint(
          icon: Icons.wifi,
          text: '传输过程只在局域网内进行，不上传云端。',
        ),
        const _Hint(
          icon: Icons.inventory_2_outlined,
          text: '离线包为 .mxbak 文件，可通过微信、数据线等任意方式搬运。',
        ),
      ],
    );
  }

  Widget _buildRoleCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _buildSend() {
    final theme = Theme.of(context);
    if (_preparing) {
      return _buildBusy(_sendMessage, _sendProgress);
    }
    if (_sendError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_sendError!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _exportOffline,
                child: const Text('导出离线包'),
              ),
              TextButton(onPressed: _reset, child: const Text('返回')),
            ],
          ),
        ),
      );
    }
    final sizeMb = ((_package?.size ?? 0) / 1024 / 1024).toStringAsFixed(1);
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text('配对码', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Text(
                      _code,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '在新手机上打开「换手机传输」→「这台是新手机」，\n发现「$_deviceName」后输入上面的数字。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.wifi_tethering,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _served ? '已发送完成' : '正在等待新手机连接…',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: _served
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '本次可迁移：${_package?.itemCount ?? 0} 项书架内容 · 约 $sizeMb MB',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _exportOffline,
              icon: const Icon(Icons.ios_share),
              label: const Text('导出离线包（.mxbak）'),
            ),
            const SizedBox(height: 8),
            Text(
              '如果新手机找不到这台设备，可导出离线包后通过微信或数据线发过去，在新手机上选择「从文件导入」。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              child: _buildBusy(_busyMessage, _busyProgress),
            ),
          ),
      ],
    );
  }

  Widget _buildReceive() {
    final theme = Theme.of(context);
    if (_receiveError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_receiveError!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _pickAndImport,
                icon: const Icon(Icons.folder_open),
                label: const Text('从文件导入'),
              ),
              TextButton(onPressed: _reset, child: const Text('返回')),
            ],
          ),
        ),
      );
    }
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text('正在搜索附近的旧手机…', style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 16),
            if (_peers.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(
                      Icons.devices_other,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '还没有发现设备',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '请在旧手机上选择「这台是旧手机」，并保持同一 Wi-Fi。',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              ..._peers.map(
                (peer) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.15),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      peer.platform == 'ios'
                          ? Icons.phone_iphone
                          : Icons.phone_android,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(
                      peer.name.isEmpty ? '附近设备' : peer.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${peer.itemCount} 项 · ${_formatSize(peer.size)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : () => _connectPeer(peer),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickAndImport,
              icon: const Icon(Icons.folder_open),
              label: const Text('没找到？从文件导入'),
            ),
            const SizedBox(height: 8),
            Text(
              '已在旧手机导出 .mxbak 文件时，可通过微信或文件管理传到本机后在这里选择。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (_busy)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surface.withValues(alpha: 0.9),
              child: _buildBusy(_busyMessage, _busyProgress),
            ),
          ),
      ],
    );
  }

  Widget _buildBusy(String message, double progress) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: progress > 0 && progress < 1 ? progress : null,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 工具
  // ---------------------------------------------------------------------------

  String _friendlyError(Object error) {
    final code = error is MigrateException ? error.code : error.toString();
    switch (code) {
      case 'not_package':
        return '这个文件不是换机迁移包。';
      case 'invalid_package':
        return '迁移包已损坏或不完整。';
      case 'newer_version':
        return '迁移包来自更新版本的 App，请先升级本机。';
      case 'package_missing':
        return '找不到迁移包文件。';
      case 'empty':
        return '本机没有可迁移的内容。';
      case 'export_failed':
        return '导出失败，请检查存储空间后重试。';
      default:
        return '迁移失败，请重试。';
    }
  }

  static Future<void> _deleteQuietly(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<String> _resolveDeviceName() async {
    final nickname = await UserService().getNickname();
    if (nickname != null && nickname.trim().isNotEmpty) {
      return nickname.trim();
    }
    if (Platform.isIOS) return 'iPhone';
    if (Platform.isAndroid) return '安卓手机';
    return '这台设备';
  }

  String _randomCode() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '未知大小';
    final mb = bytes / 1024 / 1024;
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
