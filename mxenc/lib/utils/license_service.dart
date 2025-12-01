import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class LicenseService {
  static const _licenseKey = 'license_string';
  static const _secretOverrideKey = 'license_shared_secret_override';
  static const _defaultSecret = String.fromEnvironment('MX_SHARED_SECRET', defaultValue: 'maoxiaoencoder');

  Future<SharedPreferences> _prefs() async => await SharedPreferences.getInstance();

  Future<void> setLicense(String licenseString) async {
    final p = await _prefs();
    await p.setString(_licenseKey, licenseString);
  }

  Future<String?> getLicense() async {
    final p = await _prefs();
    return p.getString(_licenseKey);
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
      if (licDevice.isEmpty || sigB64.isEmpty || exp <= 0) return false;
      if (licDevice != deviceId) return false;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      if (now > exp) return false;
      final secretOverride = await getSecretOverride();
      final secret = (secretOverride != null && secretOverride.isNotEmpty) ? secretOverride : _defaultSecret;
      if (secret.isEmpty) return false;
      final message = utf8.encode('$licDevice|$exp');
      final hmacSha256 = Hmac(sha256, utf8.encode(secret));
      final digest = hmacSha256.convert(message);
      final expectedSig = base64Encode(digest.bytes);
      return expectedSig == sigB64;
    } catch (_) {
      return false;
    }
  }
}
