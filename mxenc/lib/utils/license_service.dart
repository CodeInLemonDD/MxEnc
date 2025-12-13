import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class LicenseService {
  static const _licenseKey = 'license_string';
  static const _secretOverrideKey = 'license_shared_secret_override';
  static const _defaultSecret = String.fromEnvironment(
    'MX_SHARED_SECRET',
    defaultValue: 'maoxiaoencoder',
  );
  static const _bonusSecondsKey = 'license_bonus_seconds';
  static const _activationCodeKey = 'activation_code';

  Future<SharedPreferences> _prefs() async =>
      await SharedPreferences.getInstance();

  Future<void> setLicense(String licenseString) async {
    final p = await _prefs();
    await p.setString(_licenseKey, licenseString);
  }

  Future<String?> getLicense() async {
    final p = await _prefs();
    return p.getString(_licenseKey);
  }

  Future<Map<String, dynamic>?> decodeLicense() async {
    try {
      final lic = await getLicense();
      if (lic == null || lic.isEmpty) return null;
      final decoded = utf8.decode(base64Url.decode(lic));
      final obj = jsonDecode(decoded) as Map<String, dynamic>;
      return obj;
    } catch (_) {
      return null;
    }
  }

  Future<void> setSecretOverride(String secret) async {
    final p = await _prefs();
    await p.setString(_secretOverrideKey, secret);
  }

  Future<String?> getSecretOverride() async {
    final p = await _prefs();
    return p.getString(_secretOverrideKey);
  }

  Future<bool> isLicenseValid({required String deviceId}) async {
    try {
      final lic = await getLicense();
      if (lic == null || lic.isEmpty) return false;
      final decoded = utf8.decode(base64Url.decode(lic));
      final obj = jsonDecode(decoded) as Map<String, dynamic>;
      final licDevice = (obj['deviceId'] ?? '').toString();
      final exp = int.tryParse((obj['exp'] ?? '').toString()) ?? 0;
      final sigB64 = (obj['sig'] ?? '').toString();
      final code = (obj['code'] ?? '').toString();
      if (licDevice.isEmpty || sigB64.isEmpty || exp <= 0) return false;
      if (licDevice != deviceId) return false;
      final localCode = await getActivationCode();
      if (localCode.isEmpty || localCode != code) return false;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now > exp) return false;
      final secretOverride = await getSecretOverride();
      final secret = (secretOverride != null && secretOverride.isNotEmpty) ? secretOverride : _defaultSecret;
      if (secret.isEmpty) return false;
      final message = utf8.encode('$licDevice|$exp|$code');
      final hmacSha256 = Hmac(sha256, utf8.encode(secret));
      final digest = hmacSha256.convert(message);
      final expectedSig = base64Encode(digest.bytes);
      return expectedSig == sigB64;
    } catch (_) {
      return false;
    }
  }

  Future<int> getBonusSeconds() async {
    final p = await _prefs();
    return p.getInt(_bonusSecondsKey) ?? 0;
  }

  Future<void> addBonusSeconds(int seconds) async {
    if (seconds <= 0) return;
    final p = await _prefs();
    final cur = p.getInt(_bonusSecondsKey) ?? 0;
    await p.setInt(_bonusSecondsKey, cur + seconds);
  }

  Future<void> clearBonusSeconds() async {
    final p = await _prefs();
    await p.remove(_bonusSecondsKey);
  }

  Future<int> getRemainingWithBonus({required String deviceId}) async {
    try {
      final obj = await decodeLicense();
      final bonus = await getBonusSeconds();
      if (obj == null) return bonus;
      final exp = int.tryParse((obj['exp'] ?? '').toString()) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final remain = exp - now;
      final base = remain > 0 ? remain : 0;
      return base + (bonus > 0 ? bonus : 0);
    } catch (_) {
      return 0;
    }
  }

  Future<String> ensureActivationCode() async {
    final p = await _prefs();
    final existing = p.getString(_activationCodeKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final code = _genCode(4);
    await p.setString(_activationCodeKey, code);
    return code;
  }

  Future<String> getActivationCode() async {
    final p = await _prefs();
    return p.getString(_activationCodeKey) ?? '';
  }

  Future<void> refreshActivationCode() async {
    final p = await _prefs();
    final code = _genCode(4);
    await p.setString(_activationCodeKey, code);
  }

  String _genCode(int len) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final now = DateTime.now().microsecondsSinceEpoch;
    int seed = now & 0xFFFFFFFF;
    String out = '';
    for (int i = 0; i < len; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final idx = seed % chars.length;
      out += chars[idx];
    }
    return out;
  }
}
