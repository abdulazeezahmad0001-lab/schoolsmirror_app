// lib/screens/student_api.dart — talks to flutter_student.php (and keeps a per-student offline cache)

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../services/app_flags.dart';

// extensionless address first (a redirect from "*.php" would drop the POST body), then the other form
const List<String> _stuUrls = [
  'https://schoolsmirror.com/flutter_student',
  'https://schoolsmirror.com/flutter_student.php',
];
int _stuIdx = 0;

int? stInt(dynamic v) => v == null ? null : int.tryParse('$v');
double? stDouble(dynamic v) => v == null ? null : double.tryParse('$v');
String stStr(dynamic v) => v == null ? '' : '$v';
List<Map<String, dynamic>> stMaps(dynamic v) => (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
Map<String, dynamic> stMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// A file to upload (rebuilt for every attempt, because a stream can only be read once)
class StFile {
  final String field, path, name, mime;
  const StFile(this.field, this.path, this.name, this.mime);
}

class StudentApi {
  static Future<String?> token() async {
    try {
      await ApiClient.loadToken();
      final t = ApiClient.token;
      return (t == null || t.isEmpty) ? null : t;
    } catch (_) {
      return null;
    }
  }

  static bool isNet(Map<String, dynamic> r) => r['network'] == true;

  static Map<String, dynamic> _decode(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected server response'};
  }

  static bool _retry(Map<String, dynamic> d) {
    final m = stStr(d['message']);
    return d['success'] != true && (m == 'Unexpected server response' || m.startsWith('Missing token') || m.startsWith('The server received this request as') || m.startsWith('The data was lost'));
  }

  static Future<Map<String, dynamic>> call(String token, String action, {Map<String, String> form = const {}, int timeout = 20}) {
    return _send(token, action, form: form, timeout: timeout);
  }

  /// multipart upload: [fields] may contain keys like "answers[1]"
  static Future<Map<String, dynamic>> upload(String token, String action, {Map<String, String> fields = const {}, List<StFile> files = const [], int timeout = 120}) {
    return _send(token, action, form: fields, files: files, timeout: timeout);
  }

  static Future<Map<String, dynamic>> _send(String token, String action, {Map<String, String> form = const {}, List<StFile>? files, int timeout = 20}) async {
    var idx = _stuIdx;
    var net = false;
    Map<String, dynamic> last = {'success': false, 'message': 'Unexpected server response'};
    for (var t = 0; t < _stuUrls.length; t++) {
      try {
        // token + action travel in the URL so they survive a redirect
        final uri = Uri.parse(_stuUrls[idx]).replace(queryParameters: {'token': token, 'action': action, if (files == null) ...form});
        final http.Response res;
        if (files == null) {
          res = await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: {'token': token, 'action': action, ...form}).timeout(Duration(seconds: timeout));
        } else {
          final req = http.MultipartRequest('POST', uri)..fields.addAll({'token': token, 'action': action, ...form});
          for (final f in files) {
            final parts = f.mime.split('/');
            req.files.add(await http.MultipartFile.fromPath(f.field, f.path, filename: f.name, contentType: MediaType(parts.first, parts.length > 1 ? parts.last : 'octet-stream')));
          }
          res = await http.Response.fromStream(await req.send().timeout(Duration(seconds: timeout)));
        }
        last = _decode(res.body);
        if (_retry(last) && t < _stuUrls.length - 1) {
          idx = (idx + 1) % _stuUrls.length;
          continue;
        }
        _stuIdx = idx;
        return last;
      } catch (_) {
        net = true;
        idx = (idx + 1) % _stuUrls.length;
      }
    }
    return net ? {'success': false, 'network': true, 'message': 'No internet connection.'} : last;
  }
}

/// Saved copies of the last answers from the server, kept per student so a shared phone never mixes them up.
class StudentCache {
  static String _ns = 'x';

  static Future<void> init() async {
    try {
      final l = await AppFlags.lastLogin();
      _ns = l.id.isEmpty ? 'x' : l.id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
    } catch (_) {}
  }

  static String _k(String k) => 'stu_${_ns}_$k';

  static Future<void> put(String key, Object? value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k(key), jsonEncode(value));
    } catch (_) {}
  }

  static Future<dynamic> get(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_k(key));
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_k(key));
    } catch (_) {}
  }

  /// forget everything saved for this student (Settings → Clear saved data)
  static Future<int> clearAll() async {
    var n = 0;
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith('stu_${_ns}_')).toList()) {
        await p.remove(k);
        n++;
      }
    } catch (_) {}
    return n;
  }
}
