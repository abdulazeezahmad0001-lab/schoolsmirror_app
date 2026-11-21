import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  static const String baseUrl = 'https://schoolsmirror.com';
  static String? _token;

  static Future<void> loadToken() async {
    // 1. Check memory first
    if (_token != null && _token!.isNotEmpty) return;

    // 2. If memory is empty, check SharedPreferences (LocalStorage in Web)
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // Force browser to check disk
    _token = prefs.getString('auth_token');
    
    // Print to console so you can see it in Chrome DevTools
    print("API CLIENT LOADED TOKEN: $_token");
  }

  static String? get token => _token;

  static Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    required String deviceId,
    bool isBiometric = false,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/flutter_login'), 
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: {
          'login': login,
          'password': password,
          'device_id': deviceId,
          'is_biometric': isBiometric ? '1' : '0',
        },
      ).timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = jsonDecode(res.body);

      if (data['success'] == true && data['data'] != null) {
        final token = data['data']['token'] as String;
        _token = token;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setInt('user_id', data['data']['user_id'] ?? 0);
        await prefs.setInt('portaladmin_id', data['data']['portaladmin_id'] ?? 0);
        await prefs.setString('role', data['data']['role'] ?? '');
        await prefs.setString('fullname', data['data']['fullname'] ?? '');
      }

      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: $e',
      };
    }
  }

  static Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.clear(); 
    print("API CLIENT LOGGED OUT - TOKEN CLEARED");
  }
}