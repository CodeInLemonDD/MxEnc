import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static const _avatarKey = 'user_avatar_path';
  static const _nicknameKey = 'user_nickname';
  static const _signatureKey = 'user_signature';
  static const _oobeDoneKey = 'oobe_done';

  Future<SharedPreferences> _prefs() async => await SharedPreferences.getInstance();

  Future<void> setAvatarPath(String path) async {
    final p = await _prefs();
    await p.setString(_avatarKey, path);
  }

  Future<void> setNickname(String nickname) async {
    final p = await _prefs();
    await p.setString(_nicknameKey, nickname);
  }

  Future<void> setSignature(String signature) async {
    final p = await _prefs();
    await p.setString(_signatureKey, signature);
  }

  Future<void> setOobeDone(bool done) async {
    final p = await _prefs();
    await p.setBool(_oobeDoneKey, done);
  }

  Future<String?> getAvatarPath() async {
    final p = await _prefs();
    return p.getString(_avatarKey);
  }

  Future<String?> getNickname() async {
    final p = await _prefs();
    return p.getString(_nicknameKey);
  }

  Future<String?> getSignature() async {
    final p = await _prefs();
    return p.getString(_signatureKey);
  }

  Future<bool> isOobeDone() async {
    final p = await _prefs();
    return p.getBool(_oobeDoneKey) ?? false;
  }

  Future<bool> isProfileComplete() async {
    final p = await _prefs();
    final nick = p.getString(_nicknameKey);
    final sig = p.getString(_signatureKey);
    final ava = p.getString(_avatarKey);
    return (nick != null && nick.isNotEmpty) && (sig != null && sig.isNotEmpty) && (ava != null && ava.isNotEmpty);
  }
}

