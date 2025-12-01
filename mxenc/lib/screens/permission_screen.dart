import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/auth_service.dart';
import '../utils/license_service.dart';
import 'dart:async';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> {
  String deviceId = '获取中...';
  final AuthService _authService = AuthService();
  final LicenseService _licenseService = LicenseService();
  final TextEditingController _licenseController = TextEditingController();
  bool _activating = false;
  int? _remainingSec;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
    _startTimer();
  }

  Future<void> _loadDeviceId() async {
    try {
      final id = await _authService.getDeviceId();
      if (mounted) {
        setState(() {
          deviceId = id;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          deviceId = '获取失败';
        });
      }
    }
  }

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: deviceId));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('序列号已复制到剪贴板')),
    );
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  Future<void> _updateRemaining() async {
    try {
      final obj = await _licenseService.decodeLicense();
      if (obj == null) {
        if (mounted) setState(() { _remainingSec = null; });
        return;
      }
      final exp = int.tryParse((obj['exp'] ?? '').toString()) ?? 0;
      if (exp <= 0) {
        if (mounted) setState(() { _remainingSec = null; });
        return;
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remain = exp - now;
      if (mounted) setState(() { _remainingSec = remain > 0 ? remain : 0; });
    } catch (_) {}
  }

  Future<void> _activate() async {
    if (_activating) return;
    setState(() { _activating = true; });
    try {
      await _licenseService.setLicense(_licenseController.text.trim());
      final ok = await _licenseService.isLicenseValid(deviceId: deviceId);
      if (ok) {
        await _authService.setPremiumUser(true);
        await _updateRemaining();
        if (mounted) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('激活成功')));
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('激活失败，请检查卡密')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('激活异常')));
      }
    } finally {
      if (mounted) setState(() { _activating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('权限提示'),
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
              // 哭脸表情包
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.red.withValues(alpha: 0.2)
                      : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Center(
                  child: Text(
                    '😢',
                    style: TextStyle(fontSize: 64),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              
              // 提示信息
              const Text(
                '唔……您还没有权限，请联系蛋饼获得支持！',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // QQ联系方式
              const Text(
                'QQ：1211239054',
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 24),
              
              
              // 设备序列号
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey.shade800
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '设备序列号：',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      deviceId,
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'Monospace',
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_remainingSec != null)
                      Text(
                        _remainingSec! > 0
                            ? _fmtRemain(_remainingSec!)
                            : '已过期',
                        style: TextStyle(
                          fontSize: 14,
                          color: _remainingSec! > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // 复制按钮
              ElevatedButton(
                onPressed: _copyToClipboard,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  '复制序列号',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
              const Text('输入卡密激活'),
              const SizedBox(height: 8),
              TextField(
                controller: _licenseController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '卡密',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _activating ? null : _activate,
                icon: const Icon(Icons.verified),
                label: Text(_activating ? '激活中...' : '激活'),
              ),
            ],
          ),
        ),
      );
    }

  String _fmtRemain(int sec) {
    final d = sec ~/ 86400;
    final h = (sec % 86400) ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    return '剩余时间 $d天 $h小时 $m分 $s秒';
  }
}
