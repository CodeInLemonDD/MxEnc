import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/auth_service.dart';
import '../utils/license_service.dart';
import 'dart:async';
import 'dart:convert';

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
  bool _isPremium = false;
  String _activationCode = '';

  @override
  void initState() {
    super.initState();
    _loadDeviceId();
    _loadPremium();
    _initCode();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('序列号已复制到剪贴板')));
  }

  Future<void> _loadPremium() async {
    try {
      final ok = await _authService.isPremiumUser();
      if (mounted) {
        setState(() {
          _isPremium = ok;
        });
      }
    } catch (_) {}
  }

  Future<void> _initCode() async {
    try {
      final code = await _licenseService.ensureActivationCode();
      if (mounted) {
        setState(() {
          _activationCode = code;
        });
      }
    } catch (_) {}
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateRemaining(),
    );
  }

  Future<void> _updateRemaining() async {
    try {
      final remain = await _licenseService.getRemainingWithBonus(
        deviceId: deviceId,
      );
      if (mounted) {
        setState(() {
          _remainingSec = remain > 0 ? remain : 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _activate() async {
    if (_activating) return;
    setState(() {
      _activating = true;
    });
    try {
      final newLic = _licenseController.text.trim();
      if (newLic.isEmpty) throw Exception('无效卡密');
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // 解析现有与新卡密
      final currentObj = await _licenseService.decodeLicense();
      final currentExp =
          int.tryParse((currentObj?['exp'] ?? '').toString()) ?? 0;
      final newObj = (() {
        try {
          final decoded = utf8.decode(base64Url.decode(newLic));
          return jsonDecode(decoded) as Map<String, dynamic>;
        } catch (_) {
          return null;
        }
      })();
      if (newObj == null) throw Exception('卡密格式错误');
      final newExp = int.tryParse((newObj['exp'] ?? '').toString()) ?? 0;
      final newCode = (newObj['code'] ?? '').toString();
      if (newExp <= 0) throw Exception('卡密过期或无效');
      if (newCode.isEmpty || newCode != _activationCode) throw Exception('验证码不匹配');
      // 先验证新卡密有效
      await _licenseService.setLicense(newLic);
      final ok = await _licenseService.isLicenseValid(deviceId: deviceId);
      if (ok) {
         // 累计时长：如果当前仍有效，则将新卡密时长加入 bonusSeconds，并保留较长的卡密
        final currentRemain = currentExp > now ? (currentExp - now) : 0;
        final newRemain = newExp > now ? (newExp - now) : 0;
        if (currentRemain > 0) {
          await _licenseService.addBonusSeconds(newRemain);
          if (newExp <= currentExp) {
            // 保留更长的现有卡密
            // 需要恢复为旧卡密字符串；由于我们已 set 为新卡密，尝试从 currentObj 重新编码恢复
            try {
              final restored = base64Url.encode(utf8.encode(jsonEncode(currentObj)));
              await _licenseService.setLicense(restored);
            } catch (_) {}
          }
        } else {
          // 当前无有效时长，直接使用新卡密，不追加 bonus
        }
        await _authService.setPremiumUser(true);
        await _updateRemaining();
        await _loadPremium();
        await _licenseService.refreshActivationCode();
        await _initCode();
        if (mounted) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('激活成功')));
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('激活失败，请检查卡密')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('激活异常')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _activating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('权限提示')),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!_isPremium) ...[
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
                  child: Text('😢', style: TextStyle(fontSize: 64)),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '唔……您还没有权限，请联系蛋饼获得支持！',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green.withValues(alpha: 0.2)
                      : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(50),
                ),
                child: const Center(
                  child: Icon(Icons.verified, color: Colors.green, size: 64),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                '已授权，可增加时长',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),

            // QQ联系方式
            const Text('QQ：868140659', style: TextStyle(fontSize: 16)),
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
                    style: TextStyle(fontSize: 14, color: Colors.grey),
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
                  const Text(
                    '当前验证码：',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    _activationCode,
                    style: const TextStyle(
                      fontSize: 16,
                      fontFamily: 'Monospace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_remainingSec != null)
                    Text(
                      _remainingSec! > 0 ? _fmtRemain(_remainingSec!) : '已过期',
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
              child: const Text('复制序列号', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 24),
            const Text('输入卡密激活'),
            const SizedBox(height: 8),
            TextField(
              controller: _licenseController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: '卡密',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    final text = data?.text ?? '';
                    if (text.isNotEmpty) {
                      _licenseController.text = text;
                    }
                  },
                  tooltip: '粘贴',
                ),
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
