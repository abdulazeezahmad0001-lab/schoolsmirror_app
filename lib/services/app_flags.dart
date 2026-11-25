// services/app_flags.dart
// Remembers things that must SURVIVE logout:
//   * has the onboarding already been shown on this phone?
//   * who logged in last (so the login screen can say "welcome back, just enter your password")
// Everything is written to BOTH SharedPreferences and secure storage, so clearing one of them
// (for example a logout that wipes preferences) cannot bring the onboarding back.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

class LastLogin {
  final String id, name, role;
  const LastLogin(this.id, this.name, this.role);
  bool get exists => id.isNotEmpty;
}

class AppFlags {
  static const _sec = FlutterSecureStorage();
  static const _kOnboard = 'has_seen_onboarding';
  static const _kId = 'last_login_id';
  static const _kName = 'last_login_name';
  static const _kRole = 'last_login_role';
  static const _kBioNo = 'bio_prompt_declined';

  static Future<String?> _secRead(String k) async {
    try {
      return await _sec.read(key: k);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _secWrite(String k, String v) async {
    try {
      await _sec.write(key: k, value: v);
    } catch (_) {}
  }

  /// Onboarding is for a brand-new install only. Anyone who has logged in before, or has a saved
  /// session, is never sent through it again.
  static Future<bool> hasSeenOnboarding() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (p.getBool(_kOnboard) == true) return true;
      if ((p.getString(_kId) ?? '').isNotEmpty) return true;
    } catch (_) {}
    if (await _secRead(_kOnboard) == '1') return true;
    if ((await _secRead(_kId) ?? '').isNotEmpty) return true;
    try {
      if ((ApiClient.token ?? '').isNotEmpty) return true;
    } catch (_) {}
    return false;
  }

  static Future<void> markOnboardingSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kOnboard, true);
    } catch (_) {}
    await _secWrite(_kOnboard, '1');
  }

  static Future<void> saveLastLogin({required String id, String name = '', String role = ''}) async {
    if (id.trim().isEmpty) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kId, id);
      await p.setString(_kName, name);
      await p.setString(_kRole, role);
    } catch (_) {}
    await _secWrite(_kId, id);
    await _secWrite(_kName, name);
    await _secWrite(_kRole, role);
    await markOnboardingSeen(); // someone who has logged in has obviously been through it
  }

  static Future<LastLogin> lastLogin() async {
    String id = '', name = '', role = '';
    try {
      final p = await SharedPreferences.getInstance();
      id = p.getString(_kId) ?? '';
      name = p.getString(_kName) ?? '';
      role = p.getString(_kRole) ?? '';
    } catch (_) {}
    if (id.isEmpty) {
      id = await _secRead(_kId) ?? '';
      name = await _secRead(_kName) ?? '';
      role = await _secRead(_kRole) ?? '';
    }
    return LastLogin(id, name, role);
  }

  /// "Not you?" on the login screen
  static Future<void> forgetLastLogin() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kId);
      await p.remove(_kName);
      await p.remove(_kRole);
    } catch (_) {}
    try {
      await _sec.delete(key: _kId);
      await _sec.delete(key: _kName);
      await _sec.delete(key: _kRole);
    } catch (_) {}
  }

  static Future<bool> bioPromptDeclined() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getBool(_kBioNo) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBioPromptDeclined(bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kBioNo, v);
    } catch (_) {}
  }
}
