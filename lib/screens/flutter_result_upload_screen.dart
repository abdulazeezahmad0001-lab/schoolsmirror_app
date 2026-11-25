// flutter_result_upload_screen.dart  —  "Aurora Glass" redesign
//   students list ........ FlutterResultUploadScreen   (resultUpload.php)
//   session + term ........ _StudentPeriodScreen        (upload_results.php)
//   score entry ........... _ResultEntryScreen          (fetch_result_upload.php)
//   traits / comments ..... bottom sheets
// OFFLINE: the app prepares an "offline pack" (all classes, latest session + term) in the background every
// time you open this page while online. With no network you can still open students, enter scores, comments
// and traits; they wait in a queue and upload automatically (screen open, app resume, every 30s, Sync now).
//
// pubspec.yaml: http, shared_preferences (already there). Files needed next to this one: sm_ui.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import 'sm_ui.dart';

// Your host redirects "*.php" to the extensionless address, and a redirect turns POST into GET
// (the body is lost -> "Missing token"). The extensionless URL is tried first, then the other form.
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_result_upload',
  'https://schoolsmirror.com/flutter_result_upload.php',
];
int _apiIdx = 0;

int? _toInt(dynamic v) => v == null ? null : int.tryParse('$v');
String _str(dynamic v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _maps(dynamic v) => (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

const String _blockMsg = 'These results were finalized more than 30 days ago. Contact the portal administrator to edit.';

/// ABS handling — same as parseCaInput() in fetch_result_upload.php
class _Ca {
  final bool isAbs;
  final double num;
  const _Ca(this.isAbs, this.num);
}

_Ca _parseCa(String raw) {
  final t = raw.trim().toUpperCase();
  if (t == 'ABS' || t == 'ABSENT') return const _Ca(true, 0);
  return _Ca(false, double.tryParse(t) ?? 0);
}

// ───────────────────────────── API helper ─────────────────────────────
class _Api {
  static const Map<String, dynamic> _netErr = {
    'success': false,
    'network': true,
    'message': 'No internet connection.',
  };

  /// true when the answer means "wrong address / body lost" -> try the other URL form
  static bool shouldRetry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' ||
            m.startsWith('The server received this request as') ||
            m.startsWith('Missing token'));
  }

  static Map<String, dynamic> decode(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected server response'};
  }

  /// Form request (small data). token + action are ALSO sent in the URL so they survive a redirect.
  static Future<Map<String, dynamic>> post(String token, String action,
      [Map<String, String> fields = const {}, int timeoutSec = 15]) {
    return _send(token, action, form: fields, timeoutSec: timeoutSec);
  }

  /// JSON request (scores, traits). Used for saving and for offline sync.
  static Future<Map<String, dynamic>> postJson(String token, String action, Map<String, dynamic> body,
      {int timeoutSec = 25}) {
    return _send(token, action, json: body, timeoutSec: timeoutSec);
  }

  static Future<Map<String, dynamic>> _send(String token, String action,
      {Map<String, String> form = const {}, Map<String, dynamic>? json, int timeoutSec = 15}) async {
    var idx = _apiIdx;
    var netFailed = false;
    Map<String, dynamic> last = {'success': false, 'message': 'Unexpected server response'};
    for (var tries = 0; tries < _apiUrls.length; tries++) {
      try {
        final q = json != null ? {'token': token, 'action': action} : {'token': token, 'action': action, ...form};
        final uri = Uri.parse(_apiUrls[idx]).replace(queryParameters: q);
        final http.Response res;
        if (json != null) {
          res = await http
              .post(uri,
                  headers: {'Content-Type': 'application/json; charset=utf-8'},
                  body: jsonEncode({...json, 'token': token, 'action': action}))
              .timeout(Duration(seconds: timeoutSec));
        } else {
          res = await http
              .post(uri,
                  headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
                  body: {'token': token, 'action': action, ...form})
              .timeout(Duration(seconds: timeoutSec));
        }
        last = decode(res.body);
        if (shouldRetry(last) && tries < _apiUrls.length - 1) {
          idx = (idx + 1) % _apiUrls.length;
          continue;
        }
        _apiIdx = idx; // remember the address that works
        return last;
      } catch (_) {
        // no connection / timeout: do NOT remember the other address, just try it once now
        netFailed = true;
        idx = (idx + 1) % _apiUrls.length;
      }
    }
    return netFailed ? Map<String, dynamic>.from(_netErr) : last;
  }
}

bool _isNet(Map<String, dynamic> r) => r['network'] == true;
bool _isAuthFail(Map<String, dynamic> r) {
  final m = '${r['message'] ?? ''}';
  return m.startsWith('Invalid token') || m.startsWith('Missing token');
}

// ───────────────────────────── OFFLINE STORE ─────────────────────────────
// Everything is kept in shared_preferences, prefixed by the school id so two schools on one phone never mix.
class _SyncResult {
  final int synced, failed;
  final bool offline, authFailed;
  const _SyncResult(this.synced, this.failed, this.offline, this.authFailed);
}

class _Store {
  static String _ns = 'x';
  static bool syncing = false;

  static Future<SharedPreferences> get _p => SharedPreferences.getInstance();
  static String _k(String k) => 'ru_${_ns}_$k';

  static Future<void> init() async {
    final p = await _p;
    _ns = p.getString('ru_last_ns') ?? 'x';
  }

  static Future<void> setNs(dynamic pid) async {
    _ns = '$pid';
    final p = await _p;
    await p.setString('ru_last_ns', _ns);
  }

  static Future<void> put(String key, Object? v) async {
    try {
      final p = await _p;
      await p.setString(_k(key), jsonEncode(v));
    } catch (_) {}
  }

  static Future<dynamic> get(String key) async {
    try {
      final p = await _p;
      final s = p.getString(_k(key));
      if (s == null) return null;
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  static Future<void> del(String key) async {
    try {
      final p = await _p;
      await p.remove(_k(key));
    } catch (_) {}
  }

  static String formKey(int sid, int sess, int term) => 'form_${sid}_${sess}_$term';
  static String traitsKey(int sid, int sess, int term) => 'traits_${sid}_${sess}_$term';

  // ───── queue
  static Future<List<Map<String, dynamic>>> queue() async => _maps(await get('queue'));

  static Future<void> _saveQueue(List<Map<String, dynamic>> q) => put('queue', q);

  static Future<int> pendingCount() async => (await queue()).length;

  /// One waiting item per type/student/session/term — a newer save replaces the older one.
  static Future<void> enqueue(Map<String, dynamic> item) async {
    final q = await queue();
    q.removeWhere((e) =>
        e['type'] == item['type'] &&
        e['student_id'] == item['student_id'] &&
        e['session_id'] == item['session_id'] &&
        e['term_id'] == item['term_id']);
    item['id'] = '${DateTime.now().microsecondsSinceEpoch}';
    item['created_at'] = DateTime.now().toIso8601String();
    item.remove('error');
    q.add(item);
    await _saveQueue(q);
  }

  static Future<bool> hasQueued(String type, int sid, int sess, int term) async {
    final q = await queue();
    return q.any((e) =>
        e['type'] == type && e['student_id'] == sid && e['session_id'] == sess && e['term_id'] == term);
  }

  static Future<void> removeQueued(String id) async {
    final q = await queue();
    q.removeWhere((e) => e['id'] == id);
    await _saveQueue(q);
  }

  static Future<void> _markError(String id, String msg) async {
    final q = await queue();
    for (final e in q) {
      if (e['id'] == id) e['error'] = msg;
    }
    await _saveQueue(q);
  }

  static Future<void> clearErrors() async {
    final q = await queue();
    for (final e in q) {
      e.remove('error');
    }
    await _saveQueue(q);
  }

  /// Upload everything that is waiting. Stops quietly when there is no connection.
  static Future<_SyncResult> sync(String token, {bool retryErrors = false}) async {
    if (syncing) return const _SyncResult(0, 0, false, false);
    syncing = true;
    var ok = 0, failed = 0;
    var offline = false, authFailed = false;
    try {
      if (retryErrors) await clearErrors();
      final q = await queue();
      for (final item in q) {
        if (item['error'] != null) continue; // needs the user to look at it
        final action = item['type'] == 'traits' ? 'traits_save' : 'save_result';
        final r = await _Api.postJson(token, action, _map(item['payload']));
        if (r['success'] == true) {
          ok++;
          await removeQueued('${item['id']}');
        } else if (_isNet(r)) {
          offline = true;
          break;
        } else if (_isAuthFail(r)) {
          authFailed = true;
          break;
        } else {
          failed++;
          await _markError('${item['id']}', '${r['message']}');
        }
      }
    } finally {
      syncing = false;
    }
    return _SyncResult(ok, failed, offline, authFailed);
  }

  // ───── downloaded classes ("bundles")
  static String bundleKey(int sess, int term, int cls) => 'bundle_${sess}_${term}_$cls';

  static Future<List<Map<String, dynamic>>> bundleIndex() async => _maps(await get('bundles'));

  static Future<void> saveBundle(Map<String, dynamic> b) async {
    final sess = _toInt(b['session_id']) ?? 0, term = _toInt(b['term_id']) ?? 0, cls = _toInt(b['class_id']) ?? 0;
    final key = bundleKey(sess, term, cls);
    await put(key, b);
    final idx = await bundleIndex();
    idx.removeWhere((e) => e['key'] == key);
    idx.add({
      'key': key,
      'session_id': sess,
      'term_id': term,
      'class_id': cls,
      'label': '${b['class_name']} — ${b['session_name']} / ${b['term_name']}',
      'count': (b['students'] as List).length,
      'saved_at': DateTime.now().toIso8601String(),
    });
    await put('bundles', idx);
  }

  static Future<void> deleteBundle(String key) async {
    await del(key);
    final idx = await bundleIndex();
    idx.removeWhere((e) => e['key'] == key);
    await put('bundles', idx);
  }

  static Future<Map<String, dynamic>?> loadBundle(String key) async {
    final v = await get(key);
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  /// first downloaded class that contains this student for this session/term
  static Future<Map<String, dynamic>?> findBundle(int sess, int term, int studentId) async {
    for (final e in await bundleIndex()) {
      if (_toInt(e['session_id']) != sess || _toInt(e['term_id']) != term) continue;
      final b = await loadBundle('${e['key']}');
      if (b == null) continue;
      if (_maps(b['students']).any((s) => _toInt(s['user_id']) == studentId)) return b;
    }
    return null;
  }

  /// any downloaded bundle that contains this student (used for the student list / profile offline)
  static Future<List<Map<String, dynamic>>> allBundles() async {
    final out = <Map<String, dynamic>>[];
    for (final e in await bundleIndex()) {
      final b = await loadBundle('${e['key']}');
      if (b != null) out.add(b);
    }
    return out;
  }
}

/// Builds the same JSON the server's result_form returns, from a downloaded class.
class _Offline {
  static Map<String, dynamic>? formFromBundle(Map<String, dynamic> b, int studentId, String role) {
    final stu = _maps(b['students']).where((s) => _toInt(s['user_id']) == studentId).toList();
    if (stu.isEmpty) return null;
    final s = stu.first;
    final classId = _toInt(s['class_id']);
    final deptId = _toInt(s['department_id']);
    final subjects = _maps(b['subjects']).where((x) {
      if (_toInt(x['class_id']) != classId) return false;
      final d = _toInt(x['department_id']);
      return d == null || (deptId != null && d == deptId);
    }).toList();
    final existing = _maps(_map(b['results'])['$studentId']);
    final byKey = <String, Map<String, dynamic>>{};
    for (final e in existing) {
      byKey[_str(e['subject']).trim().toLowerCase()] = e;
    }
    final rows = <Map<String, dynamic>>[];
    if (existing.isNotEmpty) {
      final handled = <String>{};
      for (final cs in subjects) {
        final k = _str(cs['subject_name']).trim().toLowerCase();
        rows.add({'subject': cs['subject_name'], 'type': _str(cs['subject_type']), 'from_class': true, 'ex': byKey[k]});
        handled.add(k);
      }
      for (final e in existing) {
        final k = _str(e['subject']).trim().toLowerCase();
        if (!handled.contains(k)) rows.add({'subject': e['subject'], 'type': '', 'from_class': false, 'ex': e});
      }
    } else {
      for (final cs in subjects) {
        rows.add({'subject': cs['subject_name'], 'type': _str(cs['subject_type']), 'from_class': true, 'ex': null});
      }
    }
    final st = _map(_map(b['statuses'])['$studentId']);
    final cm = _map(_map(b['comments'])['$studentId']);
    final tr = _map(_map(b['traits'])['$studentId']);
    final expired = _isExpired(_str(st['status']), _str(st['created_at']));
    return {
      'student': s,
      'session_id': b['session_id'],
      'term_id': b['term_id'],
      'session_name': b['session_name'],
      'term_name': b['term_name'],
      'class_id': classId,
      'class_name': _str(s['class_name']),
      'result_status': _str(st['status']),
      'edit_mode': existing.isNotEmpty,
      'edit_expired': expired,
      'expired_warning': expired && role == 'portaladmin',
      'rows': rows,
      'grades': b['grades'],
      'grade_map': b['grade_map'],
      'teacher_comments': b['teacher_comments'],
      'proprietor_comments': b['proprietor_comments'],
      'comments': {
        'teacher_comment': _str(cm['teacher_comment']),
        'proprietor_comment': _str(cm['proprietor_comment']),
      },
      'has_traits': tr.isNotEmpty,
      'role': role,
    };
  }

  static bool _isExpired(String status, String createdAt) {
    if (status != 'finalized') return false;
    final d = DateTime.tryParse(createdAt.replaceFirst(' ', 'T'));
    if (d == null) return false;
    return DateTime.now().difference(d).inDays > 30;
  }

  static bool isExpired(String status, String createdAt) => _isExpired(status, createdAt);

  static Map<String, dynamic>? traitsFromBundle(Map<String, dynamic> b, int studentId, String role) {
    final tr = _map(_map(b['traits'])['$studentId']);
    final p = _map(tr['psychomotor']);
    final a = _map(tr['affective']);
    List<Map<String, dynamic>> mk(dynamic defs, Map<String, dynamic> saved) => _maps(defs)
        .map((t) => {'id': t['id'], 'name': t['name'], 'rating': _toInt(saved['${t['id']}']) ?? 0})
        .toList();
    final exist = p.isNotEmpty || a.isNotEmpty;
    final name = _maps(b['students']).where((s) => _toInt(s['user_id']) == studentId).map((s) => _str(s['fullname'])).join();
    return {
      'student_name': name,
      'traits_exist': exist,
      'can_edit': role == 'portaladmin' || !exist,
      'psychomotor': mk(b['psychomotor'], p),
      'affective': mk(b['affective'], a),
    };
  }
}


// ───────────────────────────── offline additions ─────────────────────────────

class _Prep {
  static bool running = false;

  static Future<void> setLastPeriod(int s, int t) => _Store.put('last_period', {'s': s, 't': t});

  /// Silently downloads every class for the latest session/term (and the last period you used).
  /// Returns how many classes were (re)downloaded.
  static Future<int> prefetch(String token,
      {required List<Map<String, dynamic>> sessions,
      required List<Map<String, dynamic>> terms,
      required List<Map<String, dynamic>> classes,
      void Function(int done, int total)? onProgress}) async {
    if (running || sessions.isEmpty || terms.isEmpty || classes.isEmpty) return 0;
    running = true;
    var ok = 0;
    try {
      final s0 = _toInt(sessions.first['id']);
      final t0 = _toInt(terms.first['id']);
      final targets = <List<int>>[];
      if (s0 != null && t0 != null) targets.add([s0, t0]);
      final lp = _map(await _Store.get('last_period'));
      final ls = _toInt(lp['s']), lt = _toInt(lp['t']);
      if (ls != null && lt != null && !(ls == s0 && lt == t0)) targets.add([ls, lt]);

      final idx = await _Store.bundleIndex();
      final jobs = <List<int>>[];
      for (final t in targets) {
        for (final c in classes) {
          final cid = _toInt(c['class_id']);
          if (cid == null) continue;
          final key = _Store.bundleKey(t[0], t[1], cid);
          final hit = idx.where((e) => e['key'] == key).toList();
          final saved = hit.isEmpty ? null : DateTime.tryParse(_str(hit.first['saved_at']));
          final fresh = saved != null && DateTime.now().difference(saved).inHours < 3;
          if (!fresh) jobs.add([t[0], t[1], cid]);
        }
      }
      onProgress?.call(0, jobs.length);
      var done = 0;
      for (final j in jobs) {
        final r = await _Api.post(token, 'offline_bundle', {'session_id': '${j[0]}', 'term_id': '${j[1]}', 'class_id': '${j[2]}'}, 60);
        if (r['success'] == true) {
          await _Store.saveBundle(_map(r['data']));
          ok++;
        } else if (_isNet(r) || _isAuthFail(r)) {
          break;
        }
        done++;
        onProgress?.call(done, jobs.length);
      }
    } finally {
      running = false;
    }
    return ok;
  }
}

/// A form that works with NO downloaded class: the teacher adds the subjects by hand.
Map<String, dynamic> _minimalForm(Map<String, dynamic> student, int sess, int term, String role, Map<String, dynamic> boot) {
  final sessions = _maps(boot['sessions']), terms = _maps(boot['terms']);
  String nameOf(List<Map<String, dynamic>> l, int id, String k) => l.where((x) => _toInt(x['id']) == id).map((x) => _str(x[k])).join();
  const scale = [
    ['A', '70-100', 70.0, 100.0, 'EXCELLENT'],
    ['B', '60-69', 60.0, 69.99, 'VERY GOOD'],
    ['C', '50-59', 50.0, 59.99, 'CREDIT'],
    ['D', '40-49', 40.0, 49.99, 'PASS'],
    ['E', '30-39', 30.0, 39.99, 'FAIR'],
    ['F', '0-29', 0.0, 29.99, 'FAIL'],
  ];
  return {
    'student': student,
    'session_id': sess,
    'term_id': term,
    'session_name': nameOf(sessions, sess, 'session_name'),
    'term_name': nameOf(terms, term, 'term_name'),
    'class_id': _toInt(student['class_id']),
    'class_name': _str(student['class_name']),
    'result_status': '',
    'edit_mode': false,
    'edit_expired': false,
    'expired_warning': false,
    'rows': <Map<String, dynamic>>[],
    'grades': scale.map((g) => {'grade': g[0], 'score_range': g[1], 'meaning': g[4]}).toList(),
    'grade_map': scale.map((g) => {'min': g[2], 'max': g[3], 'grade': g[0], 'meaning': g[4]}).toList(),
    'teacher_comments': <Map<String, dynamic>>[],
    'proprietor_comments': <Map<String, dynamic>>[],
    'comments': {'teacher_comment': '', 'proprietor_comment': ''},
    'has_traits': false,
    'role': role,
    'minimal': true,
  };
}

// ───────────────────────────── ready-made comments ─────────────────────────────
class _CommentCat {
  final String id, label;
  final IconData icon;
  final Color color;
  const _CommentCat(this.id, this.label, this.icon, this.color);
}

const List<_CommentCat> _commentCats = [
  _CommentCat('excellent', 'Excellent', Icons.emoji_events_rounded, SM.amber),
  _CommentCat('good', 'Good performance', Icons.thumb_up_alt_rounded, SM.green),
  _CommentCat('average', 'Average', Icons.show_chart_rounded, SM.cyan),
  _CommentCat('fair', 'Fair', Icons.warning_amber_rounded, SM.orange),
  _CommentCat('poor', 'Poor', Icons.trending_down_rounded, SM.rose),
];

String _catForAverage(double avg) => avg >= 70 ? 'excellent' : (avg >= 60 ? 'good' : (avg >= 50 ? 'average' : (avg >= 40 ? 'fair' : 'poor')));

const Map<String, List<String>> _teacherLib = {
  'excellent': [
    'An outstanding student with excellent results. Keep up the brilliant work!',
    'Exceptional performance this term. A true role model to classmates.',
    'Brilliant and hardworking. Maintain this great standard.',
    'Excellent academic result. Your dedication is clearly paying off.',
    'A very bright and focused student. Keep aiming higher.',
    'Outstanding in all subjects. Well done and keep it up!',
    'Remarkable improvement and top-class performance. Congratulations.',
    'Excellent attitude to learning and superb scores. Continue to shine.',
  ],
  'good': [
    'Good performance this term. With more effort you can reach the top.',
    'A good result. Keep working hard to maintain and improve it.',
    'Well done. You have shown steady progress in your studies.',
    'Good performance. More effort in examinations will bring even better results.',
    'A hardworking student with a very good result. Keep it up.',
    'Commendable effort this term. Aim higher next term.',
    'Good understanding of most subjects. Keep practising regularly.',
    'Pleasing result and good conduct. Continue in the same spirit.',
  ],
  'average': [
    'An average performance. You can do better with more focus and practice.',
    'Satisfactory result. Aim higher next term with more reading time.',
    'Fair effort shown. Consistent revision will improve your scores.',
    'Average result. Pay more attention in class and complete all assignments.',
    'You have potential. More dedication is needed to move above average.',
    'A steady but average performance. Participate more in class activities.',
    'Needs to work harder in weak subjects to improve the overall result.',
    'Average performance. Seek help early in difficult topics.',
  ],
  'fair': [
    'A fair performance. Greater effort and regular study are required.',
    'The result is fair but below expectation. Please put in more work next term.',
    'You can achieve more. Concentrate and revise your lessons daily.',
    'Fair attempt. Improve on punctuality, class attention and homework.',
    'Needs serious improvement in several subjects. Extra lessons are advised.',
    'Below average result. More commitment is needed to improve.',
    'Fair result. With discipline and consistent study, you will do better.',
    'Put in more effort and ask your teachers for help where you struggle.',
  ],
  'poor': [
    'A poor result this term. Immediate and serious improvement is needed.',
    'Performance is weak. Parents are advised to supervise studies at home.',
    'Very low scores. The student must work much harder and attend regularly.',
    'Unsatisfactory result. Extra coaching and close monitoring are strongly recommended.',
    'Poor performance. Must improve attitude to studies and homework.',
    'Weak in most subjects. Please see the class teacher to discuss a plan.',
    'Does not meet the expected standard. A big change in effort is required.',
    'The result is below the pass mark. Hard work and discipline are needed urgently.',
  ],
};

const Map<String, List<String>> _proprietorLib = {
  'excellent': [
    'A promising student with a great future ahead. Well done!',
    'Outstanding performance. We are proud of you.',
    'Excellent result! Continue to make us proud.',
    'A shining star of the school. Keep soaring higher.',
    'Brilliant achievement. The school celebrates you.',
    'Superb result. Stay humble and keep working hard.',
  ],
  'good': [
    'A good result. Keep working hard and aim for the top.',
    'Well done. You are on the right path to excellence.',
    'Good performance. We expect even better next term.',
    'Commendable effort. Keep it up.',
    'Very good progress. Stay focused and disciplined.',
    'A pleasing result. Continue to work hard.',
  ],
  'average': [
    'An average result. You have the potential to do much better.',
    'Keep working hard. The sky is your starting point.',
    'You can be at the top. Work harder next term.',
    'A fair result. Be more serious with your studies.',
    'Your potential is higher than this result. Put in more effort.',
    'Average performance. We believe you can rise above it.',
  ],
  'fair': [
    'A fair result. You must put in more effort next term.',
    'Please sit up. Greater seriousness is expected of you.',
    'Below expectation. Work harder and listen to your teachers.',
    'Improve your study habits and attendance for a better result.',
    'We expect better. Parents and teachers will support you to improve.',
    'A fair result. Discipline and hard work will change this.',
  ],
  'poor': [
    'A poor result. Serious improvement is expected next term.',
    'This result is not acceptable. Please work much harder.',
    'Parents are advised to meet the school to discuss progress.',
    'The school expects a big improvement. Do not give up.',
    'A very weak result. Extra effort and close supervision are needed.',
    'Work hard and stay disciplined; you can still turn this around.',
  ],
};

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN 1 — Students  (resultUpload.php)
// ═════════════════════════════════════════════════════════════════════════════
class FlutterResultUploadScreen extends StatefulWidget {
  final String? token;
  const FlutterResultUploadScreen({super.key, this.token});

  @override
  State<FlutterResultUploadScreen> createState() => _FlutterResultUploadScreenState();
}

class _FlutterResultUploadScreenState extends State<FlutterResultUploadScreen> with WidgetsBindingObserver {
  static bool _tipClosed = false;

  String? _token;
  bool _loading = true, _loadingList = false, _offline = false, _syncing = false;
  int _pending = 0;
  Timer? _timer;

  String _role = '';
  bool _canDelete = true;
  List<Map<String, dynamic>> _sessions = [], _terms = [], _classes = [];

  // offline pack
  bool _prepping = false;
  int _prepDone = 0, _prepTotal = 0, _bundleCount = 0;

  String _fClass = '', _fDept = '', _sId = '';
  final _idCtrl = TextEditingController();

  List<Map<String, dynamic>> _students = [], _tree = [];
  int _total = 0, _page = 1, _totalPages = 1, _totalAll = 0, _classCount = 0;
  String? _banner;
  bool _bannerError = false;

  bool get _anyFilter => _fClass.isNotEmpty || _fDept.isNotEmpty || _sId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _idCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _tick();
  }

  Future<String?> _getToken() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) return widget.token!.trim();
    try {
      await ApiClient.loadToken();
      if (ApiClient.token != null) return ApiClient.token!.trim();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  void _setBanner(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _banner = msg;
      _bannerError = error;
    });
  }

  // ───────────────────────────── loading ─────────────────────────────
  Future<void> _init() async {
    await _Store.init();
    _token = await _getToken();
    if (_token == null) {
      setState(() => _loading = false);
      smToast(context, 'Session expired. Please log in again.', kind: SmKind.error);
      return;
    }
    await _loadBootstrap();
    await _loadStudents(page: 1);
    await _refreshPending();
    final n = (await _Store.bundleIndex()).length;
    if (mounted) setState(() {
          _bundleCount = n;
          _loading = false;
        });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _autoSync();
    _startPrep();
  }

  void _applyBoot(Map<String, dynamic> d) {
    _role = _str(d['role']);
    _sessions = _maps(d['sessions']);
    _terms = _maps(d['terms']);
    _classes = _maps(d['classes']);
    _canDelete = d['can_delete_students'] != false;
  }

  Future<void> _loadBootstrap() async {
    final r = await _Api.post(_token!, 'bootstrap');
    if (r['success'] == true) {
      final d = _map(r['data']);
      await _Store.setNs(d['portaladmin_id']);
      await _Store.put('boot', d);
      if (mounted) setState(() {
            _applyBoot(d);
            _offline = false;
          });
    } else if (_isNet(r)) {
      final c = await _Store.get('boot');
      if (mounted) setState(() {
            if (c is Map) _applyBoot(Map<String, dynamic>.from(c));
            _offline = true;
          });
    } else {
      _setBanner('${r['message'] ?? 'Failed to load'}', error: true);
    }
  }

  /// background: keep an offline copy of every class so the app works with no signal
  Future<void> _startPrep() async {
    if (_token == null || _offline || _prepping || !mounted) return;
    setState(() {
      _prepping = true;
      _prepDone = 0;
      _prepTotal = 0;
    });
    await _Prep.prefetch(_token!, sessions: _sessions, terms: _terms, classes: _classes, onProgress: (d, t) {
      if (mounted) setState(() {
            _prepDone = d;
            _prepTotal = t;
          });
    });
    final n = (await _Store.bundleIndex()).length;
    if (mounted) setState(() {
          _prepping = false;
          _bundleCount = n;
        });
  }

  Map<String, String> _query(int page) => {
        'page': '$page',
        if (_sId.isNotEmpty) 'search_idnumber': _sId,
        if (_fClass.isNotEmpty) 'filter_class': _fClass,
        if (_fDept.isNotEmpty) 'filter_dept': _fDept,
      };

  Future<void> _loadStudents({int? page}) async {
    if (_token == null) return;
    final p = page ?? _page;
    setState(() => _loadingList = true);
    final fields = _query(p);
    final cacheKey = 'students|${(fields.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) => '${e.key}=${e.value}').join('&')}';
    final r = await _Api.post(_token!, 'students', fields);
    if (!mounted) return;
    if (r['success'] == true) {
      final d = _map(r['data']);
      await _Store.put(cacheKey, d);
      setState(() {
        _applyList(d);
        _offline = false;
        _loadingList = false;
      });
    } else if (_isNet(r)) {
      final c = await _Store.get(cacheKey);
      if (!mounted) return;
      if (c is Map) {
        setState(() {
          _applyList(Map<String, dynamic>.from(c));
          _offline = true;
          _loadingList = false;
        });
      } else {
        await _applyLocal(p);
      }
    } else {
      setState(() => _loadingList = false);
      _setBanner('${r['message']}', error: true);
    }
  }

  void _applyList(Map<String, dynamic> d) {
    _students = _maps(d['students']);
    _tree = _maps(d['class_tree']);
    _total = _toInt(d['total']) ?? 0;
    _page = _toInt(d['page']) ?? 1;
    _totalPages = _toInt(d['total_pages']) ?? 1;
    _totalAll = _toInt(d['total_students']) ?? 0;
    _classCount = _toInt(d['class_count']) ?? 0;
  }

  /// No connection and nothing cached for this search: build the list from the downloaded classes.
  Future<void> _applyLocal(int p) async {
    final bundles = await _Store.allBundles();
    final seen = <int>{};
    final all = <Map<String, dynamic>>[];
    for (final b in bundles) {
      for (final s in _maps(b['students'])) {
        if (seen.add(_toInt(s['user_id']) ?? 0)) all.add(s);
      }
    }
    final tree = <String, Map<String, int>>{};
    for (final s in all) {
      final c = _str(s['class_name']);
      if (c.isEmpty) continue;
      final dn = _str(s['department_name']).isEmpty ? 'No Department' : _str(s['department_name']);
      tree.putIfAbsent(c, () => {});
      tree[c]![dn] = (tree[c]![dn] ?? 0) + 1;
    }
    final names = tree.keys.toList()..sort();
    final treeList = names.map((c) {
      final dm = tree[c]!;
      final dn = dm.keys.toList()..sort();
      return <String, dynamic>{'class_name': c, 'total': dm.values.fold<int>(0, (a, b) => a + b), 'depts': dn.map((x) => {'name': x, 'count': dm[x]}).toList()};
    }).toList();
    final ac = _fClass.toLowerCase();
    final list = all.where((s) {
      if (_sId.isNotEmpty && !_str(s['idnumber']).toLowerCase().contains(_sId.toLowerCase())) return false;
      if (ac.isNotEmpty && _str(s['class_name']).toLowerCase() != ac) return false;
      if (_fDept.isNotEmpty && _str(s['department_name']) != _fDept) return false;
      return true;
    }).toList()
      ..sort((a, b) => _str(a['fullname']).compareTo(_str(b['fullname'])));
    const per = 15;
    final pages = list.isEmpty ? 1 : ((list.length + per - 1) ~/ per);
    final page = p.clamp(1, pages);
    if (!mounted) return;
    setState(() {
      _students = list.skip((page - 1) * per).take(per).toList();
      _tree = treeList;
      _total = list.length;
      _page = page;
      _totalPages = pages;
      _totalAll = all.length;
      _classCount = treeList.length;
      _offline = true;
      _loadingList = false;
    });
  }

  Future<void> _refresh() async {
    await _loadBootstrap();
    await _loadStudents();
    await _refreshPending();
    _startPrep();
  }

  // ───────────────────────────── offline sync ─────────────────────────────
  Future<void> _refreshPending() async {
    final n = await _Store.pendingCount();
    if (mounted) setState(() => _pending = n);
  }

  Future<void> _tick() async {
    if (_token == null || !mounted) return;
    if (_offline) {
      final r = await _Api.post(_token!, 'ping', const {}, 8);
      if (r['success'] == true && mounted) {
        setState(() => _offline = false);
        _loadStudents();
        _startPrep();
      }
    }
    await _autoSync();
  }

  Future<void> _autoSync({bool manual = false}) async {
    if (_token == null || _syncing) return;
    final n = await _Store.pendingCount();
    if (n == 0) {
      if (mounted) setState(() => _pending = 0);
      if (manual && mounted) smToast(context, 'Nothing waiting to upload.', kind: SmKind.info);
      return;
    }
    if (mounted) setState(() => _syncing = true);
    final r = await _Store.sync(_token!, retryErrors: manual);
    final left = await _Store.pendingCount();
    if (!mounted) return;
    setState(() {
      _syncing = false;
      _pending = left;
      if (r.offline) _offline = true;
      if (r.synced > 0 || r.failed > 0) _offline = false;
    });
    if (r.synced > 0) smToast(context, '${r.synced} saved result${r.synced == 1 ? '' : 's'} uploaded ✔');
    if (r.failed > 0) smToast(context, '${r.failed} item${r.failed == 1 ? '' : 's'} could not be uploaded. Tap the sync icon to review.', kind: SmKind.error);
    if (manual && r.offline) smToast(context, 'Still offline. Your results are safe on this phone.', kind: SmKind.warn);
    if (manual && r.authFailed) smToast(context, 'Session expired. Please log out and log in again.', kind: SmKind.error);
  }

  // ───────────────────────────── filters ─────────────────────────────
  void _setFilters({String? cls, String? dept, String? sId}) {
    setState(() {
      if (cls != null) _fClass = cls;
      if (dept != null) _fDept = dept;
      if (sId != null) _sId = sId;
      _page = 1;
      _banner = null;
    });
    _loadStudents(page: 1);
  }

  void _doSearch() {
    FocusScope.of(context).unfocus();
    _setFilters(sId: _idCtrl.text.trim());
  }

  void _clearAll() {
    _idCtrl.clear();
    _setFilters(cls: '', dept: '', sId: '');
  }

  // ───────────────────────────── actions ─────────────────────────────
  Future<void> _openStudent(Map<String, dynamic> s) async {
    final id = _toInt(s['user_id']);
    if (id == null || _token == null) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _StudentPeriodScreen(token: _token!, studentId: id, role: _role, studentInfo: s)));
    if (!mounted) return;
    _refreshPending();
    _autoSync();
  }

  Future<void> _deleteStudent(Map<String, dynamic> s) async {
    if (!_canDelete) {
      smToast(context, 'Only administrators can delete students.', kind: SmKind.error);
      return;
    }
    if (_offline) {
      smToast(context, 'Connect to the internet to delete a student.', kind: SmKind.error);
      return;
    }
    final ok = await smConfirm(context, 'Delete student?', 'This permanently removes ${_str(s['fullname'])} and their photo.',
        yes: 'Delete', destructive: true, icon: Icons.delete_forever_rounded);
    if (ok != true) return;
    final r = await _Api.post(_token!, 'delete_student', {'id': '${s['user_id']}'});
    if (!mounted) return;
    if (r['success'] == true) {
      smToast(context, '${r['message']}');
      await _loadStudents();
    } else if (_isNet(r)) {
      smToast(context, 'No internet connection. Try again when you are online.', kind: SmKind.error);
    } else {
      smToast(context, '${r['message']}', kind: SmKind.error);
    }
  }

  Future<void> _openOfflineSheet() async {
    if (_token == null) return;
    await smSheet<void>(context, (_) => _OfflineSheet(token: _token!, sessions: _sessions, terms: _terms, classes: _classes));
    final n = (await _Store.bundleIndex()).length;
    if (mounted) {
      setState(() => _bundleCount = n);
      if (_offline) _loadStudents();
    }
  }

  Future<void> _openQueueSheet() async {
    if (_token == null) return;
    await smSheet<void>(context, (_) => _QueueSheet(token: _token!));
    _refreshPending();
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SM.bg1,
      body: SmBackground(
        child: SafeArea(
          child: Column(children: [
            SmTopBar(
              title: 'Result Upload',
              subtitle: _loading ? 'Loading…' : '$_totalAll students · $_classCount classes',
              onBack: () => Navigator.of(context).maybePop(),
              actions: [
                SmIconBtn(icon: Icons.cloud_download_rounded, onTap: _loading ? null : _openOfflineSheet),
                SmIconBtn(icon: _syncing ? Icons.sync_rounded : Icons.cloud_upload_rounded, badge: _pending, color: _pending > 0 ? SM.orange : null, onTap: _loading ? null : _openQueueSheet),
              ],
            ),
            Expanded(
              child: _loading
                  ? const Center(child: SmLogoLoader(size: 120, label: 'Loading students…'))
                  : RefreshIndicator(
                      color: SM.orange,
                      backgroundColor: SM.sheet,
                      onRefresh: _refresh,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 50),
                        children: [
                          if (_offline) _note(Icons.wifi_off_rounded, SM.amber, "You're offline", 'Showing saved data. Anything you save stays on this phone and uploads automatically.'),
                          if (_pending > 0) _pendingCard(),
                          if (_banner != null) _alertBox(),
                          if (!_tipClosed) _tip(),
                          _packCard(),
                          const SizedBox(height: 14),
                          _searchPill(),
                          const SizedBox(height: 14),
                          _classRail(),
                          _meta(),
                          _list(),
                          if (_totalPages > 1) _pager(),
                        ],
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  // ───────────────────────────── widgets ─────────────────────────────
  Widget _note(IconData i, Color c, String title, String text) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: SM.a(c, .13), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .45))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, color: c, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 14)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.35)),
            ]),
          ),
        ]),
      );

  Widget _pendingCard() => SmGlass(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        border: SM.a(SM.orange, .5),
        color: SM.a(SM.orange, .10),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 21)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_pending item${_pending == 1 ? '' : 's'} waiting to upload', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14)),
              const Text('Saved on this phone', style: TextStyle(color: SM.muted, fontSize: 12)),
            ]),
          ),
          TextButton(onPressed: _syncing ? null : () => _autoSync(manual: true), child: Text(_syncing ? 'Syncing…' : 'Sync now', style: const TextStyle(color: SM.orange, fontWeight: FontWeight.w800))),
        ]),
      );

  Widget _alertBox() {
    final c = _bannerError ? SM.rose : SM.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SM.a(c, .13), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .5))),
      child: Row(children: [
        Icon(_bannerError ? Icons.error_rounded : Icons.check_circle_rounded, color: c),
        const SizedBox(width: 10),
        Expanded(child: Text(_banner!, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w600, fontSize: 13.5))),
        InkWell(onTap: () => setState(() => _banner = null), child: const Icon(Icons.close_rounded, size: 19, color: SM.muted)),
      ]),
    );
  }

  Widget _tip() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(gradient: LinearGradient(colors: [SM.a(SM.blueLight, .22), SM.a(SM.violet, .12)]), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(SM.blueLight, .4))),
        child: Row(children: [
          const Text('📋', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          const Expanded(child: Text("Open Result Overview to see which students you haven't uploaded results for.", style: TextStyle(color: SM.text, fontSize: 13, height: 1.35))),
          IconButton(onPressed: () => setState(() => _tipClosed = true), icon: const Icon(Icons.close_rounded, size: 19, color: SM.muted)),
        ]),
      );

  /// offline pack status
  Widget _packCard() {
    final ready = _bundleCount > 0;
    final c = _prepping ? SM.cyan : (ready ? SM.green : SM.amber);
    final title = _prepping ? 'Preparing offline data…' : (ready ? 'Offline ready' : 'Offline data not ready');
    final sub = _prepping
        ? (_prepTotal == 0 ? 'Checking classes…' : 'Downloading classes $_prepDone / $_prepTotal')
        : (ready ? '$_bundleCount class${_bundleCount == 1 ? '' : 'es'} saved on this phone' : (_offline ? 'Connect once to download your classes' : 'Will download automatically'));
    return SmGlass(
      radius: 22,
      padding: const EdgeInsets.all(14),
      onTap: _openOfflineSheet,
      child: Column(children: [
        Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: SM.a(c, .18), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(c, .5))),
              child: Icon(_prepping ? Icons.downloading_rounded : (ready ? Icons.cloud_done_rounded : Icons.cloud_off_rounded), color: c, size: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(sub, style: const TextStyle(color: SM.muted, fontSize: 12.5)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: SM.faint),
        ]),
        if (_prepping && _prepTotal > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: _prepDone / _prepTotal, minHeight: 6, backgroundColor: SM.a(Colors.white, .1), color: SM.cyan)),
        ],
      ]),
    );
  }

  Widget _searchPill() => TextField(
        controller: _idCtrl,
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _doSearch(),
        style: const TextStyle(color: SM.text, fontWeight: FontWeight.w600),
        cursorColor: SM.orange,
        decoration: smInput('Search by ID number', icon: Icons.search_rounded, dense: true, accent: SM.orange,
            suffix: _anyFilter
                ? IconButton(icon: const Icon(Icons.close_rounded, color: SM.muted, size: 20), onPressed: _clearAll)
                : IconButton(icon: const Icon(Icons.arrow_forward_rounded, color: SM.orange, size: 20), onPressed: _doSearch)),
      );

  Widget _classRail() {
    final cls = _tree.firstWhere((c) => _str(c['class_name']).toLowerCase() == _fClass.toLowerCase(), orElse: () => <String, dynamic>{});
    final depts = _maps(cls['depts']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 46,
        child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
          SmChoice(label: 'All · $_totalAll', selected: _fClass.isEmpty, icon: Icons.apps_rounded, onTap: () => _setFilters(cls: '', dept: '')),
          for (final c in _tree) ...[
            const SizedBox(width: 8),
            SmChoice(label: '${_str(c['class_name'])} · ${c['total']}', selected: _fClass.toLowerCase() == _str(c['class_name']).toLowerCase(), onTap: () => _setFilters(cls: _str(c['class_name']), dept: '')),
          ],
        ]),
      ),
      if (_fClass.isNotEmpty && depts.length > 1) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final d in depts)
            SmChoice(
              label: '${_str(d['name'])} · ${d['count']}',
              selected: _fDept == _str(d['name']),
              color: SM.cyan,
              onTap: () => _setFilters(dept: (_str(d['name']) == 'No Department' || _fDept == _str(d['name'])) ? '' : _str(d['name'])),
            ),
        ]),
      ],
    ]);
  }

  Widget _meta() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${_students.length} of $_total student${_total == 1 ? '' : 's'}', style: const TextStyle(color: SM.muted, fontSize: 13, fontWeight: FontWeight.w600)),
          if (_totalPages > 1) Text('Page $_page / $_totalPages', style: const TextStyle(color: SM.muted, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _studentTile(Map<String, dynamic> s) {
    final g = _str(s['gender']).toLowerCase();
    final cn = _str(s['class_name']);
    final dn = _str(s['department_name']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SmGlass(
        radius: 24,
        padding: const EdgeInsets.all(12),
        onTap: () => _openStudent(s),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SmAvatar(url: _str(s['image_url']).isNotEmpty ? _str(s['image_url']) : _str(s['image']), name: _str(s['fullname']), size: 54),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_str(s['fullname']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.25)),
              const SizedBox(height: 3),
              Text('ID  ${_str(s['idnumber']).isEmpty ? '—' : _str(s['idnumber'])}', style: const TextStyle(color: SM.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (g == 'male' || g == 'female') SmPill(g == 'male' ? 'Male' : 'Female', color: g == 'male' ? SM.blueLight : const Color(0xFFF472B6)),
                if (cn.isNotEmpty) SmPill(cn, color: SM.violet),
                if (dn.isNotEmpty) SmPill(dn, color: SM.cyan),
              ]),
            ]),
          ),
          const SizedBox(width: 8),
          Column(children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: SM.a(SM.orange, .4), blurRadius: 14, offset: const Offset(0, 6))]),
              child: const Icon(Icons.upload_rounded, color: Colors.white, size: 24),
            ),
            if (_canDelete) ...[
              const SizedBox(height: 6),
              SmPress(onTap: () => _deleteStudent(s), child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.delete_outline_rounded, size: 20, color: SM.a(SM.rose, .8)))),
            ],
          ]),
        ]),
      ),
    );
  }

  Widget _list() {
    if (_loadingList && _students.isEmpty) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: SM.orange)));
    if (_students.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          const Text('📭', style: TextStyle(fontSize: 50)),
          const SizedBox(height: 10),
          const Text('No students found', style: TextStyle(color: SM.text, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_anyFilter ? 'Nothing matches this filter.' : (_offline ? 'Connect once so the app can download your classes.' : 'No students have been added yet.'), textAlign: TextAlign.center, style: const TextStyle(color: SM.muted)),
          if (_anyFilter) ...[const SizedBox(height: 16), SmButton(label: 'View all students', height: 46, onTap: _clearAll)],
        ]),
      );
    }
    return AnimatedOpacity(opacity: _loadingList ? .5 : 1, duration: const Duration(milliseconds: 200), child: Column(children: _students.map(_studentTile).toList()));
  }

  Widget _pageBtn(String label, int? page, {bool on = false}) => SmPress(
        onTap: page == null ? null : () => _loadStudents(page: page),
        child: Container(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: on ? SM.brand : null, color: on ? null : SM.glass, borderRadius: BorderRadius.circular(15), border: Border.all(color: on ? Colors.transparent : SM.glassLine)),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: on ? Colors.white : SM.text)),
        ),
      );

  Widget _pager() {
    final sp = (_page - 2).clamp(1, _totalPages);
    final ep = (_page + 2).clamp(1, _totalPages);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        if (_page > 1) _pageBtn('‹ Prev', _page - 1),
        if (sp > 1) _pageBtn('1', 1),
        for (var i = sp; i <= ep; i++) _pageBtn('$i', i, on: i == _page),
        if (ep < _totalPages) _pageBtn('$_totalPages', _totalPages),
        if (_page < _totalPages) _pageBtn('Next ›', _page + 1),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN 2 — Student + session/term  (upload_results.php)
// ═════════════════════════════════════════════════════════════════════════════
class _StudentPeriodScreen extends StatefulWidget {
  final String token, role;
  final int studentId;
  final Map<String, dynamic>? studentInfo;
  const _StudentPeriodScreen({required this.token, required this.studentId, required this.role, this.studentInfo});

  @override
  State<_StudentPeriodScreen> createState() => _StudentPeriodScreenState();
}

class _StudentPeriodScreenState extends State<_StudentPeriodScreen> {
  bool _loading = true, _offline = false, _busy = false, _pickError = false;
  String? _error, _flash;
  bool _flashError = false;
  Timer? _flashTimer;

  Map<String, dynamic> _student = {};
  List<Map<String, dynamic>> _sessions = [], _terms = [], _summary = [], _classStudents = [];
  int? _selSession, _selTerm;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _setFlash(String msg, {bool error = false}) {
    if (!mounted) return;
    _flashTimer?.cancel();
    setState(() {
      _flash = msg;
      _flashError = error;
    });
    _flashTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final r = await _Api.post(widget.token, 'student_periods', {'student_id': '${widget.studentId}'});
    if (!mounted) return;
    if (r['success'] == true) {
      final d = _map(r['data']);
      await _Store.put('periods_${widget.studentId}', d);
      await _apply(d, offline: false);
    } else if (_isNet(r)) {
      final c = await _Store.get('periods_${widget.studentId}');
      if (c is Map) {
        await _apply(Map<String, dynamic>.from(c), offline: true);
      } else {
        await _fromBundles();
      }
    } else {
      setState(() {
        _error = '${r['message']}';
        _loading = false;
      });
    }
  }

  Future<void> _apply(Map<String, dynamic> d, {required bool offline}) async {
    final summary = _maps(d['summary']);
    final sessions = _maps(d['sessions']);
    final terms = _maps(d['terms']);
    // results saved on this phone but not uploaded yet count as drafts
    for (final q in await _Store.queue()) {
      if (q['type'] != 'result' || q['student_id'] != widget.studentId) continue;
      final sid = _toInt(q['session_id']), tid = _toInt(q['term_id']);
      final subs = _map(q['payload'])['subject'];
      final n = subs is List ? subs.where((x) => '$x'.trim().isNotEmpty).length : 0;
      summary.removeWhere((e) => _toInt(e['session_id']) == sid && _toInt(e['term_id']) == tid);
      summary.insert(0, {
        'session_id': sid,
        'term_id': tid,
        'status': 'draft',
        'last_updated': DateTime.now().toIso8601String(),
        'subject_count': n,
        'session_name': sessions.where((s) => _toInt(s['id']) == sid).map((s) => _str(s['session_name'])).join(),
        'term_name': terms.where((t) => _toInt(t['id']) == tid).map((t) => _str(t['term_name'])).join(),
      });
    }
    // start on the period used last time
    final lp = _map(await _Store.get('last_period'));
    if (!mounted) return;
    setState(() {
      _student = _map(d['student']);
      _sessions = sessions;
      _terms = terms;
      _summary = summary;
      _classStudents = _maps(d['class_students']);
      _offline = offline;
      _error = null;
      _loading = false;
      _selSession ??= sessions.any((s) => _toInt(s['id']) == _toInt(lp['s'])) ? _toInt(lp['s']) : null;
      _selTerm ??= terms.any((t) => _toInt(t['id']) == _toInt(lp['t'])) ? _toInt(lp['t']) : null;
    });
  }

  /// Offline and this student was never opened before: use the downloaded classes, or the list row itself.
  Future<void> _fromBundles() async {
    final boot = await _Store.get('boot');
    final bootM = boot is Map ? Map<String, dynamic>.from(boot) : <String, dynamic>{};
    Map<String, dynamic>? stu;
    final summary = <Map<String, dynamic>>[];
    List<Map<String, dynamic>> classStudents = [];
    for (final b in await _Store.allBundles()) {
      final m = _maps(b['students']).where((s) => _toInt(s['user_id']) == widget.studentId).toList();
      if (m.isEmpty) continue;
      stu ??= m.first;
      if (classStudents.isEmpty) {
        classStudents = _maps(b['students'])
            .map((s) => {'user_id': s['user_id'], 'fullname': s['fullname'], 'admission_number': s['admission_number'], 'image_url': s['image_url'], 'class_name': s['class_name']})
            .toList();
      }
      final st = _map(_map(b['statuses'])['${widget.studentId}']);
      if (st.isNotEmpty) {
        summary.add({'session_id': b['session_id'], 'term_id': b['term_id'], 'status': st['status'], 'last_updated': st['created_at'], 'subject_count': st['subject_count'], 'session_name': b['session_name'], 'term_name': b['term_name']});
      }
    }
    // not downloaded? the row you tapped in the student list is enough to start
    stu ??= widget.studentInfo == null ? null : Map<String, dynamic>.from(widget.studentInfo!);
    if (!mounted) return;
    if (stu == null || bootM.isEmpty) {
      setState(() {
        _error = "You're offline and this student hasn't been saved on this phone yet. Open the app once with internet so it can prepare your classes.";
        _loading = false;
      });
      return;
    }
    await _apply({'student': stu, 'sessions': bootM['sessions'] ?? [], 'terms': bootM['terms'] ?? [], 'summary': summary, 'class_students': classStudents}, offline: true);
  }

  Map<String, dynamic>? get _match {
    if (_selSession == null || _selTerm == null) return null;
    for (final r in _summary) {
      if (_toInt(r['session_id']) == _selSession && _toInt(r['term_id']) == _selTerm) return r;
    }
    return null;
  }

  Future<void> _continue() async {
    if (_selSession == null || _selTerm == null) {
      setState(() => _pickError = true);
      return;
    }
    setState(() {
      _pickError = false;
      _busy = true;
    });
    final r = await _Api.post(widget.token, 'open_period', {'student_id': '${widget.studentId}', 'session_id': '$_selSession', 'term_id': '$_selTerm'});
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['success'] == true) {
      _openEntry();
    } else if (_isNet(r)) {
      final m = _match;
      final blocked = m != null && widget.role != 'portaladmin' && _Offline.isExpired(_str(m['status']), _str(m['last_updated']));
      if (blocked) {
        _setFlash(_blockMsg, error: true);
      } else {
        _openEntry();
      }
    } else {
      _setFlash('${r['message']}', error: true);
    }
  }

  Future<void> _openEntry() async {
    await _Prep.setLastPeriod(_selSession!, _selTerm!);
    if (!mounted) return;
    final msg = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => _ResultEntryScreen(token: widget.token, studentId: widget.studentId, sessionId: _selSession!, termId: _selTerm!, role: widget.role, studentInfo: _student),
    ));
    if (!mounted) return;
    if (msg != null && msg.isNotEmpty) _setFlash(msg);
    _load(silent: true);
  }

  void _openClassList() {
    final cn = _str(_student['class_name']);
    smSheet<void>(context, (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: .8,
          maxChildSize: .95,
          minChildSize: .45,
          builder: (_, sc) => SmSheetFrame(
            title: 'Students in ${cn.isEmpty ? 'this class' : cn}',
            subtitle: 'Tap a student to upload their results',
            icon: Icons.groups_rounded,
            child: _classStudents.isEmpty
                ? const Center(child: Text('No other students found in this class', style: TextStyle(color: SM.muted)))
                : ListView.builder(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _classStudents.length,
                    itemBuilder: (_, i) {
                      final s = _classStudents[i];
                      final cur = _toInt(s['user_id']) == widget.studentId;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SmGlass(
                          radius: 20,
                          padding: const EdgeInsets.all(10),
                          border: cur ? SM.a(SM.orange, .7) : null,
                          color: cur ? SM.a(SM.orange, .10) : null,
                          onTap: () {
                            Navigator.pop(ctx);
                            if (cur) return;
                            Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => _StudentPeriodScreen(token: widget.token, studentId: _toInt(s['user_id'])!, role: widget.role, studentInfo: s)));
                          },
                          child: Row(children: [
                            SmAvatar(url: _str(s['image_url']), name: _str(s['fullname']), size: 44),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_str(s['fullname']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
                                Text(_str(s['admission_number']).isEmpty ? 'No admission number' : _str(s['admission_number']), style: const TextStyle(color: SM.muted, fontSize: 12.5)),
                              ]),
                            ),
                            if (cur) const SmPill('Current', color: SM.orange, filled: true),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ));
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SM.bg1,
      body: SmBackground(
        child: SafeArea(
          child: Column(children: [
            SmTopBar(title: 'Upload result', subtitle: _loading ? 'Loading…' : _str(_student['fullname']), onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: _loading
                  ? const Center(child: SmLogoLoader(size: 110))
                  : _error != null
                      ? _errorView()
                      : RefreshIndicator(
                          color: SM.orange,
                          backgroundColor: SM.sheet,
                          onRefresh: () => _load(silent: true),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 40),
                            children: [
                              if (_offline) _banner(Icons.wifi_off_rounded, SM.amber, 'Offline — showing saved information.'),
                              if (_flash != null) _flashBox(),
                              _profile(),
                              const SizedBox(height: 14),
                              _periodCard(),
                              if (_summary.isNotEmpty) _history(),
                              if (_summary.any((e) => e['status'] == 'finalized')) _finalizedWarning(),
                              _steps(),
                            ],
                          ),
                        ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SmGlass(
            radius: 28,
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 52, color: SM.amber),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: SM.text, fontSize: 14.5, height: 1.4)),
              const SizedBox(height: 18),
              SmButton(label: 'Back to students', icon: Icons.arrow_back_rounded, onTap: () => Navigator.of(context).pop()),
            ]),
          ),
        ),
      );

  Widget _banner(IconData i, Color c, String t) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SM.a(c, .13), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(c, .45))),
        child: Row(children: [Icon(i, color: c, size: 20), const SizedBox(width: 10), Expanded(child: Text(t, style: const TextStyle(color: SM.text, fontSize: 13)))]),
      );

  Widget _flashBox() {
    final c = _flashError ? SM.rose : SM.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SM.a(c, .14), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .55))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_flashError ? Icons.error_rounded : Icons.check_circle_rounded, color: c),
        const SizedBox(width: 12),
        Expanded(child: Text(_flash!, style: const TextStyle(color: SM.text, fontSize: 13.5, fontWeight: FontWeight.w600, height: 1.35))),
        InkWell(onTap: () => setState(() => _flash = null), child: const Icon(Icons.close_rounded, size: 19, color: SM.muted)),
      ]),
    );
  }

  Widget _profile() {
    final adm = _str(_student['admission_number']);
    final dept = _str(_student['department_name']);
    final transferred = _student['transferred'] == true;
    return SmGlass(
      radius: 30,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [SM.a(SM.blueLight, .28), SM.a(SM.blue, .12)]),
      border: SM.a(SM.blueLight, .4),
      child: Column(children: [
        Row(children: [
          SmAvatar(url: _str(_student['image_url']).isNotEmpty ? _str(_student['image_url']) : _str(_student['image']), name: _str(_student['fullname']), size: 76),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_str(_student['fullname']), style: const TextStyle(color: SM.text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4, height: 1.2)),
              const SizedBox(height: 4),
              Text('ID ${_student['user_id'] ?? widget.studentId}${adm.isEmpty ? '' : '  ·  $adm'}', style: const TextStyle(color: SM.muted, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            SmPill(_str(_student['class_name']).isEmpty ? 'No class' : _str(_student['class_name']), color: SM.violet, icon: Icons.class_rounded),
            if (dept.isNotEmpty) SmPill(dept, color: SM.cyan, icon: Icons.apartment_rounded),
            transferred ? SmPill('Promoted from ${_str(_student['original_class_name'])}', color: SM.amber, icon: Icons.swap_horiz_rounded) : const SmPill('Original class', color: SM.green, icon: Icons.home_rounded),
          ]),
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: SmButton(label: 'Class list', icon: Icons.groups_rounded, outline: true, height: 44, onTap: _openClassList)),
          const SizedBox(width: 10),
          Expanded(child: SmButton(label: 'Switch student', icon: Icons.swap_horiz_rounded, outline: true, height: 44, onTap: () => Navigator.of(context).pop())),
        ]),
      ]),
    );
  }

  Widget _lbl(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 10),
        child: Row(children: [Icon(i, size: 16, color: SM.orange), const SizedBox(width: 7), Text(t, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14))]),
      );

  Widget _periodCard() => SmGlass(
        radius: 28,
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 21)),
            const SizedBox(width: 12),
            const Expanded(child: Text('Choose the period', style: TextStyle(color: SM.text, fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
          _lbl(Icons.event_available_rounded, 'Academic session'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in _sessions)
              SmChoice(label: _str(s['session_name']), selected: _toInt(s['id']) == _selSession, onTap: () => setState(() {
                    _selSession = _toInt(s['id']);
                    _pickError = false;
                  })),
          ]),
          _lbl(Icons.schedule_rounded, 'Academic term'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in _terms)
              SmChoice(label: _str(t['term_name']), selected: _toInt(t['id']) == _selTerm, color: SM.orange, onTap: () => setState(() {
                    _selTerm = _toInt(t['id']);
                    _pickError = false;
                  })),
          ]),
          const SizedBox(height: 16),
          AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: KeyedSubtree(key: ValueKey('$_selSession-$_selTerm-$_pickError-${_summary.length}'), child: _status())),
          const SizedBox(height: 4),
          SmButton(label: 'Continue to scores', icon: Icons.arrow_forward_rounded, gradient: SM.hot, glow: SM.orange, height: 56, loading: _busy, onTap: _continue),
        ]),
      );

  Widget _statusBox(IconData i, Color c, String bold, String rest) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: SM.a(c, .13), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .5))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, color: c, size: 23),
          const SizedBox(width: 12),
          Expanded(child: Text.rich(TextSpan(style: const TextStyle(color: SM.text, fontSize: 13.5, height: 1.4), children: [TextSpan(text: '$bold ', style: const TextStyle(fontWeight: FontWeight.w800)), TextSpan(text: rest, style: const TextStyle(color: SM.muted))]))),
        ]),
      );

  Widget _status() {
    if (_pickError) return _statusBox(Icons.warning_amber_rounded, SM.rose, 'Pick both.', 'Please choose an academic session and a term to continue.');
    if (_selSession == null || _selTerm == null) return _statusBox(Icons.touch_app_rounded, SM.blueLight, 'Select a period.', 'Tap a session and a term above.');
    final m = _match;
    if (m == null) return _statusBox(Icons.add_circle_rounded, SM.green, 'New entry.', 'No results yet for this period. A fresh form will open.');
    final fin = m['status'] == 'finalized';
    final n = _toInt(m['subject_count']) ?? 0;
    return fin
        ? _statusBox(Icons.lock_open_rounded, SM.amber, 'Finalized results found.', '$n subject${n == 1 ? '' : 's'}. You can edit them — please double-check before re-publishing.')
        : _statusBox(Icons.edit_note_rounded, SM.violet, 'Draft found.', '$n subject${n == 1 ? '' : 's'}. You can continue editing this draft.');
  }

  Widget _history() => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: SmGlass(
          radius: 26,
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.history_rounded, size: 19, color: SM.cyan), SizedBox(width: 8), Text('Existing results', style: TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 15))]),
            const SizedBox(height: 10),
            for (final e in _summary)
              Builder(builder: (_) {
                final fin = e['status'] == 'finalized';
                final sn = _str(e['session_name']).isEmpty ? 'Session ${e['session_id']}' : _str(e['session_name']);
                final tn = _str(e['term_name']).isEmpty ? 'Term ${e['term_id']}' : _str(e['term_name']);
                final n = _toInt(e['subject_count']) ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: fin ? SM.green : SM.amber)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('$sn — $tn  ($n subject${n == 1 ? '' : 's'})', style: const TextStyle(color: SM.text, fontSize: 13.5, height: 1.3))),
                    SmPill(fin ? 'Finalized' : 'Draft', color: fin ? SM.green : SM.amber),
                  ]),
                );
              }),
          ]),
        ),
      );

  Widget _finalizedWarning() => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: SM.a(SM.amber, .10), borderRadius: BorderRadius.circular(22), border: Border.all(color: SM.a(SM.amber, .45))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.lock_clock_rounded, size: 20, color: SM.amber), SizedBox(width: 8), Expanded(child: Text('Some results are already finalized', style: TextStyle(color: SM.amber, fontWeight: FontWeight.w800, fontSize: 14.5)))]),
          const SizedBox(height: 8),
          for (final t in const [
            'Editing within 30 days of finalizing is open to all staff.',
            'After 30 days only the Portal Admin can make changes.',
            'Saving moves the result back to Draft — re-finalize it from Result Overview.',
          ])
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('•  ', style: TextStyle(color: SM.amber)), Expanded(child: Text(t, style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.35)))]),
            ),
        ]),
      );

  Widget _steps() {
    Widget step(int n, String a, String b) => Expanded(
          child: SmGlass(
            radius: 20,
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Container(width: 30, height: 30, alignment: Alignment.center, decoration: const BoxDecoration(gradient: SM.brand, shape: BoxShape.circle), child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
              const SizedBox(height: 8),
              Text(a, textAlign: TextAlign.center, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text(b, textAlign: TextAlign.center, style: const TextStyle(color: SM.muted, fontSize: 11.5, height: 1.3)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        step(1, 'Pick period', 'Session and term'),
        const SizedBox(width: 8),
        step(2, 'Enter scores', 'Per subject'),
        const SizedBox(width: 8),
        step(3, 'Save draft', 'Publish in Overview'),
      ]),
    );
  }
}

class _Row {
  final TextEditingController subject = TextEditingController();
  final TextEditingController ca1 = TextEditingController();
  final TextEditingController ca2 = TextEditingController();
  final TextEditingController exam = TextEditingController();
  final TextEditingController total = TextEditingController();
  final TextEditingController avg = TextEditingController();
  final TextEditingController pos = TextEditingController();
  final TextEditingController hi = TextEditingController();
  final TextEditingController lo = TextEditingController();
  String grade = '';
  String remark = '';
  final bool fromClass;
  final String type;
  final GlobalKey key = GlobalKey();

  _Row({required this.fromClass, this.type = ''});

  factory _Row.from(Map<String, dynamic> row) {
    final r = _Row(fromClass: row['from_class'] == true, type: _str(row['type']));
    r.subject.text = _str(row['subject']);
    final ex = row['ex'];
    if (ex is Map) {
      r.ca1.text = _str(ex['first_cbt']);
      r.ca2.text = _str(ex['second_cbt']);
      r.exam.text = _str(ex['term_exam']);
      r.total.text = _str(ex['total_scores']);
      r.avg.text = _str(ex['class_average']);
      r.pos.text = _str(ex['subject_position']);
      r.hi.text = _str(ex['highest_in_subject']);
      r.lo.text = _str(ex['lowest_in_subject']);
      r.grade = _str(ex['grade']);
      r.remark = _str(ex['remark']);
    }
    return r;
  }

  void dispose() {
    for (final c in [subject, ca1, ca2, exam, total, avg, pos, hi, lo]) {
      c.dispose();
    }
  }
}

/// ABS / ABSENT are typed as letters: force capitals, only letters of ABSENT, digits and a dot
final List<TextInputFormatter> _caFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.ABSENTabsent]')),
  LengthLimitingTextInputFormatter(6),
  TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
];


// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN 3 — Score entry  (fetch_result_upload.php + process_result_upload.php)
// ═════════════════════════════════════════════════════════════════════════════
Color _gradeColor(double t) => t >= 70 ? SM.green : (t >= 60 ? SM.cyan : (t >= 50 ? SM.blueLight : (t >= 40 ? SM.amber : (t >= 30 ? SM.orange : SM.rose))));

class _ResultEntryScreen extends StatefulWidget {
  final String token, role;
  final int studentId, sessionId, termId;
  final Map<String, dynamic>? studentInfo;
  const _ResultEntryScreen({required this.token, required this.studentId, required this.sessionId, required this.termId, required this.role, this.studentInfo});

  @override
  State<_ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<_ResultEntryScreen> {
  bool _loading = true, _saving = false, _dirty = false, _fromCache = false, _queued = false, _minimal = false;
  String? _error;
  int? _openIdx;

  Map<String, dynamic> _form = {};
  final List<_Row> _rows = [];
  List<Map<String, dynamic>> _grades = [], _gradeMap = [], _teacherList = [], _propList = [];
  String _teacherComment = '', _proprietorComment = '';
  bool _hasTraits = false;
  final _scroll = ScrollController();

  bool get _isAdmin => widget.role == 'portaladmin';
  bool get _editMode => _form['edit_mode'] == true;
  String get _resultStatus => _str(_form['result_status']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  // ───────────────────────────── load ─────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final key = _Store.formKey(widget.studentId, widget.sessionId, widget.termId);
    final queued = await _Store.hasQueued('result', widget.studentId, widget.sessionId, widget.termId);
    Map<String, dynamic>? form;
    var fromCache = false;
    if (queued) {
      // changes made offline are not on the server yet: keep showing what was saved on the phone
      final c = await _Store.get(key);
      if (c is Map) {
        form = Map<String, dynamic>.from(c);
        fromCache = true;
      }
    }
    if (form == null) {
      final r = await _Api.post(widget.token, 'result_form', {'student_id': '${widget.studentId}', 'session_id': '${widget.sessionId}', 'term_id': '${widget.termId}'});
      if (r['success'] == true) {
        form = _map(r['data']);
        await _Store.put(key, form);
      } else if (_isNet(r)) {
        final c = await _Store.get(key);
        if (c is Map) {
          form = Map<String, dynamic>.from(c);
        } else {
          final b = await _Store.findBundle(widget.sessionId, widget.termId, widget.studentId);
          if (b != null) form = _Offline.formFromBundle(b, widget.studentId, widget.role);
        }
        // nothing downloaded for this class: still let the teacher work, adding subjects by hand
        if (form == null && widget.studentInfo != null) {
          final boot = await _Store.get('boot');
          form = _minimalForm(Map<String, dynamic>.from(widget.studentInfo!), widget.sessionId, widget.termId, widget.role, boot is Map ? Map<String, dynamic>.from(boot) : {});
        }
        fromCache = true;
        if (form == null) {
          if (!mounted) return;
          setState(() {
            _error = "You're offline and this class isn't saved on this phone yet. Open Result Upload once with internet — it prepares your classes automatically.";
            _loading = false;
          });
          return;
        }
      } else {
        if (!mounted) return;
        setState(() {
          _error = '${r['message']}';
          _loading = false;
        });
        return;
      }
    }
    if (!mounted) return;
    _apply(form, fromCache: fromCache, queued: queued);
  }

  void _apply(Map<String, dynamic> f, {required bool fromCache, required bool queued}) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..addAll(_maps(f['rows']).map(_Row.from));
    final gm = _maps(f['grade_map'])
        .map((g) => {'min': double.tryParse('${g['min']}') ?? 0.0, 'max': double.tryParse('${g['max']}') ?? 100.0, 'grade': _str(g['grade']), 'meaning': _str(g['meaning'])})
        .toList();
    gm.sort((a, b) => (b['min'] as double).compareTo(a['min'] as double));
    final cm = _map(f['comments']);
    setState(() {
      _form = f;
      _grades = _maps(f['grades']);
      _gradeMap = gm;
      _teacherList = _maps(f['teacher_comments']);
      _propList = _maps(f['proprietor_comments']);
      _teacherComment = _str(cm['teacher_comment']);
      _proprietorComment = _str(cm['proprietor_comment']);
      _hasTraits = f['has_traits'] == true;
      _fromCache = fromCache;
      _queued = queued;
      _minimal = f['minimal'] == true;
      _dirty = false;
      _loading = false;
      _openIdx = _rows.isEmpty ? null : 0;
    });
  }

  // ───────────────────────────── calculation ─────────────────────────────
  String _gradeFor(double s) {
    for (final g in _gradeMap) {
      if (s >= (g['min'] as double) && s <= (g['max'] as double)) return g['grade'] as String;
    }
    return _gradeMap.isEmpty ? '' : _gradeMap.last['grade'] as String;
  }

  String _remarkFor(double s) {
    for (final g in _gradeMap) {
      if (s >= (g['min'] as double) && s <= (g['max'] as double)) return g['meaning'] as String;
    }
    return _gradeMap.isEmpty ? '' : _gradeMap.last['meaning'] as String;
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _recalc(_Row r) {
    _markDirty();
    final c1 = _parseCa(r.ca1.text), c2 = _parseCa(r.ca2.text);
    final ex = double.tryParse(r.exam.text) ?? 0;
    if (!c1.isAbs && c1.num > 20) {
      smToast(context, 'C.A 1 cannot exceed 20', kind: SmKind.error);
      r.ca1.clear();
      setState(() {});
      return;
    }
    if (!c2.isAbs && c2.num > 20) {
      smToast(context, 'C.A 2 cannot exceed 20', kind: SmKind.error);
      r.ca2.clear();
      setState(() {});
      return;
    }
    if (ex > 60) {
      smToast(context, 'Exam score cannot exceed 60', kind: SmKind.error);
      r.exam.clear();
      setState(() {});
      return;
    }
    final total = c1.num + c2.num + ex;
    if (total > 100) {
      smToast(context, 'Total score exceeds 100', kind: SmKind.error);
      return;
    }
    r.total.text = total.toStringAsFixed(2);
    final g = _gradeFor(total), m = _remarkFor(total);
    if (g.isNotEmpty && _grades.any((x) => _str(x['grade']) == g)) r.grade = g;
    if (m.isNotEmpty && _grades.any((x) => _str(x['meaning']) == m)) r.remark = m;
    setState(() {});
  }

  /// average of the subjects that have a total
  double? get _avg {
    final t = _rows.where((r) => r.total.text.trim().isNotEmpty && r.subject.text.trim().isNotEmpty).map((r) => double.tryParse(r.total.text) ?? 0).toList();
    if (t.isEmpty) return null;
    return t.reduce((a, b) => a + b) / t.length;
  }

  int get _subjectCount => _rows.where((r) => r.subject.text.trim().isNotEmpty).length;

  void _addRow() {
    final r = _Row(fromClass: false);
    setState(() {
      _rows.add(r);
      _openIdx = _rows.length - 1;
      _dirty = true;
    });
    _reveal(r);
  }

  void _reveal(_Row r) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = r.key.currentContext;
      if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic, alignment: .04);
    });
  }

  Future<void> _removeRow(int i) async {
    final name = _rows[i].subject.text.trim();
    final ok = await smConfirm(context, 'Remove subject?', name.isEmpty ? 'Remove this row?' : 'Remove “$name” from this result?', yes: 'Remove', destructive: true, icon: Icons.delete_outline_rounded);
    if (ok != true || !mounted) return;
    setState(() {
      _rows[i].dispose();
      _rows.removeAt(i);
      _openIdx = null;
      _dirty = true;
    });
  }

  // ───────────────────────────── save ─────────────────────────────
  Map<String, dynamic>? _buildPayload() {
    final subjects = <String>[], f = <String>[], s = <String>[], e = <String>[], avg = <String>[];
    final grade = <String>[], remark = <String>[], pos = <String>[], hi = <String>[], lo = <String>[];
    final seen = <String>{};
    for (final r in _rows) {
      final name = r.subject.text.trim();
      if (name.isEmpty) continue;
      if (!seen.add(name.toLowerCase())) {
        smToast(context, 'Subject “$name” appears twice. Remove one of them.', kind: SmKind.error);
        return null;
      }
      final c1 = _parseCa(r.ca1.text), c2 = _parseCa(r.ca2.text);
      final ex = double.tryParse(r.exam.text) ?? 0;
      if (!c1.isAbs && (c1.num < 0 || c1.num > 20)) { smToast(context, "Invalid C.A 1 for '$name' — must be 0–20 or ABS", kind: SmKind.error); return null; }
      if (!c2.isAbs && (c2.num < 0 || c2.num > 20)) { smToast(context, "Invalid C.A 2 for '$name' — must be 0–20 or ABS", kind: SmKind.error); return null; }
      if (ex < 0 || ex > 60) { smToast(context, "Invalid exam score for '$name' — must be 0–60", kind: SmKind.error); return null; }
      if (c1.num + c2.num + ex > 100) { smToast(context, "Total score for '$name' exceeds 100", kind: SmKind.error); return null; }
      subjects.add(name);
      f.add(r.ca1.text.trim());
      s.add(r.ca2.text.trim());
      e.add(r.exam.text.trim());
      avg.add(r.avg.text.trim());
      grade.add(r.grade);
      remark.add(r.remark);
      pos.add(r.pos.text.trim());
      hi.add(r.hi.text.trim());
      lo.add(r.lo.text.trim());
    }
    if (subjects.isEmpty) {
      smToast(context, 'Please add at least one subject with data', kind: SmKind.error);
      return null;
    }
    return {
      'user_id': widget.studentId,
      'session_id': widget.sessionId,
      'term_id': widget.termId,
      'class_id': _form['class_id'],
      'status': 'draft',
      'edit_mode': _editMode ? '1' : '0',
      'teacher_comment': _teacherComment,
      'proprietor_comment': _proprietorComment,
      'subject': subjects,
      'first_cbt': f,
      'second_cbt': s,
      'term_exam': e,
      'class_average': avg,
      'grade': grade,
      'remark': remark,
      'subject_position': pos,
      'highest_in_subject': hi,
      'lowest_in_subject': lo,
    };
  }

  Map<String, dynamic> _snapshot() {
    final f = Map<String, dynamic>.from(_form);
    f['rows'] = _rows
        .where((r) => r.subject.text.trim().isNotEmpty)
        .map((r) => {
              'subject': r.subject.text.trim(),
              'type': r.type,
              'from_class': r.fromClass,
              'ex': {
                'first_cbt': r.ca1.text.trim(),
                'second_cbt': r.ca2.text.trim(),
                'term_exam': r.exam.text.trim(),
                'total_scores': r.total.text.trim(),
                'class_average': r.avg.text.trim(),
                'grade': r.grade,
                'subject_position': r.pos.text.trim(),
                'highest_in_subject': r.hi.text.trim(),
                'lowest_in_subject': r.lo.text.trim(),
                'remark': r.remark,
              },
            })
        .toList();
    f['comments'] = {'teacher_comment': _teacherComment, 'proprietor_comment': _proprietorComment};
    f['result_status'] = 'draft';
    f['edit_mode'] = true;
    f['has_traits'] = _hasTraits;
    return f;
  }

  Future<String?> _queuedId() async {
    for (final q in await _Store.queue()) {
      if (q['type'] == 'result' && q['student_id'] == widget.studentId && q['session_id'] == widget.sessionId && q['term_id'] == widget.termId) return '${q['id']}';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) {
      smToast(context, 'Please wait, your results are already being saved…', kind: SmKind.warn);
      return;
    }
    FocusScope.of(context).unfocus();
    final payload = _buildPayload();
    if (payload == null) return;
    final ok = await smConfirm(context, 'Save as draft?', 'Your progress is saved and you can keep editing later. Publish it from Result Overview.', yes: 'Save draft', icon: Icons.save_rounded, gradient: SM.mint);
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final key = _Store.formKey(widget.studentId, widget.sessionId, widget.termId);
    final r = await _Api.postJson(widget.token, 'save_result', payload);
    if (!mounted) return;
    if (r['success'] == true) {
      await _Store.put(key, _snapshot());
      final qid = await _queuedId();
      if (qid != null) await _Store.removeQueued(qid);
      _dirty = false;
      Navigator.of(context).pop('${r['message']}');
    } else if (_isNet(r)) {
      await _Store.put(key, _snapshot());
      await _Store.enqueue({
        'type': 'result',
        'student_id': widget.studentId,
        'student_name': _str(_map(_form['student'])['fullname']),
        'session_id': widget.sessionId,
        'term_id': widget.termId,
        'label': '${_str(_form['session_name'])} / ${_str(_form['term_name'])} — ${(payload['subject'] as List).length} subjects',
        'payload': payload,
      });
      _dirty = false;
      Navigator.of(context).pop('📴 Saved on this phone. It uploads automatically when you are back online.');
    } else {
      setState(() => _saving = false);
      smToast(context, '${r['message']}', kind: SmKind.error);
    }
  }

  // ───────────────────────────── sheets ─────────────────────────────
  Future<void> _openTraits() async {
    final saved = await smSheet<bool>(context, (_) => _TraitsSheet(token: widget.token, studentId: widget.studentId, sessionId: widget.sessionId, termId: widget.termId, role: widget.role));
    if (saved == true && mounted) setState(() => _hasTraits = true);
  }

  Future<void> _openComments() async {
    final res = await smSheet<Map<String, String>>(context, (_) => _CommentsSheet(
          teacher: _teacherComment,
          proprietor: _proprietorComment,
          teacherList: _teacherList,
          propList: _propList,
          isAdmin: _isAdmin,
          average: _avg ?? 0,
          studentName: _str(_map(_form['student'])['fullname']),
        ));
    if (res != null && mounted) {
      setState(() {
        _teacherComment = res['teacher'] ?? '';
        if (_isAdmin) _proprietorComment = res['proprietor'] ?? '';
        _dirty = true;
      });
      smToast(context, 'Comments added — they are saved together with the result.');
    }
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final stu = _map(_form['student']);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await smConfirm(context, 'Discard changes?', 'You have scores that are not saved yet.', yes: 'Discard', destructive: true, icon: Icons.warning_amber_rounded);
        if (ok == true && mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: SM.bg1,
        body: SmBackground(
          child: SafeArea(
            child: Column(children: [
              SmTopBar(title: 'Enter scores', subtitle: _loading ? 'Loading…' : '${_str(stu['fullname'])}', onBack: () => Navigator.of(context).maybePop()),
              Expanded(
                child: _loading
                    ? const Center(child: SmLogoLoader(size: 110, label: 'Opening form…'))
                    : _error != null
                        ? _errorView()
                        : ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                            children: [
                              _header(),
                              const SizedBox(height: 12),
                              ..._banners(),
                              _gradeStrip(),
                              _subjectsTitle(),
                              if (_rows.isEmpty) _emptyRows(),
                              for (var i = 0; i < _rows.length; i++) _rowCard(i, _rows[i]),
                              const SizedBox(height: 4),
                              SmButton(label: 'Add subject', icon: Icons.add_rounded, outline: true, height: 50, onTap: _addRow),
                            ],
                          ),
              ),
              if (!_loading && _error == null) _bottomBar(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SmGlass(
            radius: 28,
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline_rounded, size: 50, color: SM.amber),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: SM.text, fontSize: 14.5, height: 1.4)),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(child: SmButton(label: 'Back', outline: true, height: 46, onTap: () => Navigator.of(context).pop())),
                const SizedBox(width: 10),
                Expanded(child: SmButton(label: 'Try again', height: 46, onTap: _load)),
              ]),
            ]),
          ),
        ),
      );

  Widget _header() {
    final stu = _map(_form['student']);
    final fin = _resultStatus == 'finalized';
    final avg = _avg;
    return SmGlass(
      radius: 30,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [SM.a(SM.blueLight, .30), SM.a(SM.violet, .14)]),
      border: SM.a(SM.blueLight, .4),
      child: Column(children: [
        Row(children: [
          SmAvatar(url: _str(stu['image_url']).isNotEmpty ? _str(stu['image_url']) : _str(stu['image']), name: _str(stu['fullname']), size: 62),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_str(stu['fullname']), style: const TextStyle(color: SM.text, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.3, height: 1.2)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                SmPill(_str(_form['class_name']).isEmpty ? 'No class' : _str(_form['class_name']), color: SM.violet),
                SmPill(_str(_form['session_name']), color: SM.cyan),
                SmPill(_str(_form['term_name']), color: SM.orange),
                if (_str(stu['department_name']).isNotEmpty) SmPill(_str(stu['department_name']), color: SM.blueLight),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _miniStat('Subjects', '$_subjectCount', SM.blueLight),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(color: SM.a(Colors.white, .06), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.glassLine)),
              child: Row(children: [
                SmRing(value: (avg ?? 0) / 100, size: 40, stroke: 4.5, color: avg == null ? SM.faint : _gradeColor(avg)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(avg == null ? '—' : '${avg.toStringAsFixed(1)}%', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 16)),
                  const Text('Average', style: TextStyle(color: SM.muted, fontSize: 11.5)),
                ])),
              ]),
            ),
          ),
          const SizedBox(width: 10),
          _miniStat('Status', fin ? 'Final' : (_editMode ? 'Draft' : 'New'), fin ? SM.amber : (_editMode ? SM.violet : SM.green)),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value, Color c) => Container(
        width: 86,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(color: SM.a(c, .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .4))),
        child: Column(children: [
          Text(value, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 18)),
          Text(label, style: const TextStyle(color: SM.muted, fontSize: 11.5)),
        ]),
      );

  Widget _banner(IconData i, Color c, String bold, String text) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: SM.a(c, .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .45))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 20, color: c),
          const SizedBox(width: 10),
          Expanded(child: Text.rich(TextSpan(style: const TextStyle(color: SM.text, fontSize: 13, height: 1.4), children: [TextSpan(text: '$bold ', style: TextStyle(fontWeight: FontWeight.w800, color: c)), TextSpan(text: text, style: const TextStyle(color: SM.muted))]))),
        ]),
      );

  List<Widget> _banners() {
    final w = <Widget>[];
    if (_queued) {
      w.add(_banner(Icons.cloud_upload_rounded, SM.orange, 'Waiting to upload.', 'These changes are saved on this phone and upload automatically when you are online.'));
    } else if (_minimal) {
      w.add(_banner(Icons.cloud_off_rounded, SM.amber, 'Offline, class not saved.', 'Add the subjects below by hand and save. It uploads when you are back online.'));
    } else if (_fromCache) {
      w.add(_banner(Icons.wifi_off_rounded, SM.amber, 'Offline.', 'Showing information saved on this phone. You can still enter scores and save.'));
    }
    if (_form['expired_warning'] == true) w.add(_banner(Icons.lock_clock_rounded, SM.rose, 'Edit window passed.', 'Finalized more than 30 days ago. You can edit because you are the Portal Admin.'));
    if (_resultStatus == 'finalized') w.add(_banner(Icons.info_rounded, SM.amber, 'Editing finalized results.', 'Saving moves them back to Draft. Re-finalize from Result Overview.'));
    return w;
  }

  Widget _gradeStrip() {
    if (_grades.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _grades.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final g = _grades[i];
            final lo = double.tryParse(_str(g['score_range']).split('-').first.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
            final c = _gradeColor(lo);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: SM.a(c, .14), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(c, .45))),
              child: Text('${_str(g['grade'])}  ${_str(g['score_range'])}  ${_str(g['meaning'])}', style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w800)),
            );
          },
        ),
      ),
    );
  }

  Widget _subjectsTitle() => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 12),
        child: Row(children: [
          Container(width: 4, height: 18, decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          const Expanded(child: Text('Subject scores', style: TextStyle(color: SM.text, fontSize: 17, fontWeight: FontWeight.w800))),
          const SmPill('ABS = absent', color: SM.amber),
        ]),
      );

  Widget _emptyRows() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SmGlass(
          radius: 24,
          padding: const EdgeInsets.all(22),
          child: const Column(children: [
            Icon(Icons.menu_book_rounded, size: 42, color: SM.faint),
            SizedBox(height: 10),
            Text('No subjects yet. Tap “Add subject” to start.', textAlign: TextAlign.center, style: TextStyle(color: SM.muted, height: 1.4)),
          ]),
        ),
      );

  // ───────────────────────────── subject card ─────────────────────────────
  Widget _lab(String t) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(t, style: const TextStyle(color: SM.muted, fontSize: 12, fontWeight: FontWeight.w700)));

  TextStyle get _inStyle => const TextStyle(color: SM.text, fontWeight: FontWeight.w700, fontSize: 15);

  Widget _caField(String label, TextEditingController c, _Row r) {
    final abs = _parseCa(c.text).isAbs;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lab(label),
      TextField(
        controller: c,
        inputFormatters: _caFormatters,
        textCapitalization: TextCapitalization.characters,
        style: _inStyle.copyWith(color: abs ? SM.amber : SM.text),
        cursorColor: SM.orange,
        decoration: smInput('0–20 or ABS', dense: true, accent: abs ? SM.amber : SM.orange).copyWith(fillColor: abs ? SM.a(SM.amber, .12) : null),
        onChanged: (_) => _recalc(r),
      ),
    ]);
  }

  Widget _numField(String label, TextEditingController c, {void Function(String)? onChanged, String? hint, bool ro = false}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lab(label),
        TextField(
          controller: c,
          readOnly: ro,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: ro ? null : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          style: _inStyle.copyWith(color: ro ? SM.orange : SM.text),
          cursorColor: SM.orange,
          decoration: smInput(hint ?? '', dense: true, accent: SM.orange).copyWith(fillColor: ro ? SM.a(SM.orange, .10) : null),
          onChanged: onChanged ?? (_) => _markDirty(),
        ),
      ]);

  Widget _textField(String label, TextEditingController c, String hint) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lab(label),
        TextField(controller: c, style: _inStyle, cursorColor: SM.orange, decoration: smInput(hint, dense: true, accent: SM.orange), onChanged: (_) => _markDirty()),
      ]);

  Widget _dropdown(String label, String value, List<String> values, List<String> labels, void Function(String?) onChanged) {
    final v = values.contains(value) ? value : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lab(label),
      DropdownButtonFormField<String>(
        value: v,
        isExpanded: true,
        dropdownColor: SM.sheet,
        iconEnabledColor: SM.muted,
        borderRadius: BorderRadius.circular(16),
        style: _inStyle.copyWith(fontSize: 14),
        decoration: smInput('Select', dense: true, accent: SM.orange),
        items: [for (var i = 0; i < values.length; i++) DropdownMenuItem<String>(value: values[i], child: Text(labels[i], softWrap: true, style: _inStyle.copyWith(fontSize: 14)))],
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _two(Widget a, Widget b) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]),
      );

  String _caShow(String s) {
    final t = s.trim();
    return t.isEmpty ? '0' : t.toUpperCase();
  }

  Widget _rowCard(int i, _Row r) {
    final open = _openIdx == i;
    final filled = r.total.text.trim().isNotEmpty;
    final total = double.tryParse(r.total.text) ?? 0;
    final gc = filled ? _gradeColor(total) : SM.faint;
    final gradeVals = <String>[], gradeLabels = <String>[], remarkVals = <String>[];
    for (final g in _grades) {
      final gv = _str(g['grade']);
      if (gv.isNotEmpty && !gradeVals.contains(gv)) {
        gradeVals.add(gv);
        gradeLabels.add('$gv (${_str(g['score_range'])})');
      }
      final mv = _str(g['meaning']);
      if (mv.isNotEmpty && !remarkVals.contains(mv)) remarkVals.add(mv);
    }
    final name = r.subject.text.trim();
    return Padding(
      key: r.key,
      padding: const EdgeInsets.only(bottom: 12),
      child: SmGlass(
        radius: 26,
        padding: EdgeInsets.zero,
        border: open ? SM.a(SM.orange, .6) : null,
        glow: open ? SM.orange : null,
        child: Column(children: [
          SmPress(
            scale: .99,
            onTap: () => setState(() => _openIdx = open ? null : i),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Container(width: 36, height: 36, alignment: Alignment.center, decoration: BoxDecoration(gradient: open ? SM.hot : SM.brand, borderRadius: BorderRadius.circular(13)), child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14))),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name.isEmpty ? 'New subject' : name, style: TextStyle(color: name.isEmpty ? SM.muted : SM.text, fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.25)),
                    const SizedBox(height: 3),
                    Text(filled || r.ca1.text.isNotEmpty || r.exam.text.isNotEmpty ? 'C.A1 ${_caShow(r.ca1.text)}  ·  C.A2 ${_caShow(r.ca2.text)}  ·  Exam ${r.exam.text.trim().isEmpty ? '0' : r.exam.text.trim()}' : 'Tap to enter scores', style: const TextStyle(color: SM.muted, fontSize: 12.5)),
                    if (filled && r.remark.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: SmPill(r.remark, color: gc)),
                  ]),
                ),
                const SizedBox(width: 8),
                SmRing(
                  value: total / 100,
                  size: 58,
                  color: gc,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(filled ? total.toStringAsFixed(total % 1 == 0 ? 0 : 1) : '–', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 15, height: 1)),
                    if (filled && r.grade.isNotEmpty) Text(r.grade, style: TextStyle(color: gc, fontWeight: FontWeight.w800, fontSize: 11, height: 1.2)),
                  ]),
                ),
                Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: SM.muted),
              ]),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(children: [
                      Container(height: 1, color: SM.glassLine),
                      const SizedBox(height: 14),
                      _textField('Subject name', r.subject, 'e.g. Mathematics'),
                      _two(_caField('C.A 1 (20)', r.ca1, r), _caField('C.A 2 (20)', r.ca2, r)),
                      _two(_numField('Exam (60)', r.exam, hint: '0–60', onChanged: (_) => _recalc(r)), _numField('Total (100)', r.total, ro: true, hint: 'Auto')),
                      _two(_dropdown('Grade', r.grade, gradeVals, gradeLabels, (v) => setState(() { r.grade = v ?? ''; _dirty = true; })),
                          _dropdown('Remark', r.remark, remarkVals, remarkVals, (v) => setState(() { r.remark = v ?? ''; _dirty = true; }))),
                      _two(_numField('Class average', r.avg, hint: 'Optional'), _textField('Position', r.pos, 'e.g. 1st')),
                      _two(_numField('Highest', r.hi, hint: 'Optional'), _numField('Lowest', r.lo, hint: 'Optional')),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(child: SmButton(label: 'Remove', icon: Icons.delete_outline_rounded, outline: true, height: 46, onTap: () => _removeRow(i))),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SmButton(
                            label: i + 1 < _rows.length ? 'Next subject' : 'Done',
                            icon: i + 1 < _rows.length ? Icons.arrow_downward_rounded : Icons.check_rounded,
                            height: 46,
                            onTap: () {
                              FocusScope.of(context).unfocus();
                              if (i + 1 < _rows.length) {
                                setState(() => _openIdx = i + 1);
                                _reveal(_rows[i + 1]);
                              } else {
                                setState(() => _openIdx = null);
                              }
                            },
                          ),
                        ),
                      ]),
                    ]),
                  ),
          ),
        ]),
      ),
    );
  }

  // ───────────────────────────── bottom bar ─────────────────────────────
  Widget _barBtn(IconData icon, String label, VoidCallback onTap, {bool dot = false, Color color = SM.blueLight}) => SmPress(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Container(width: 52, height: 52, decoration: BoxDecoration(color: SM.a(color, .16), borderRadius: BorderRadius.circular(17), border: Border.all(color: SM.a(color, .5))), child: Icon(icon, color: color, size: 24)),
            if (dot) Positioned(right: -2, top: -2, child: Container(width: 14, height: 14, decoration: BoxDecoration(color: SM.green, shape: BoxShape.circle, border: Border.all(color: SM.bg1, width: 2)), child: const Icon(Icons.check, size: 8, color: Colors.white))),
          ]),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: SM.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _bottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SM.a(SM.bg1, 0), SM.a(SM.bg0, .96)]),
          border: Border(top: BorderSide(color: SM.glassLine)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _barBtn(Icons.star_rounded, 'Traits', _openTraits, dot: _hasTraits, color: SM.amber),
          const SizedBox(width: 10),
          _barBtn(Icons.chat_bubble_rounded, 'Comments', _openComments, dot: _teacherComment.trim().isNotEmpty, color: SM.cyan),
          const SizedBox(width: 14),
          Expanded(child: Padding(padding: const EdgeInsets.only(top: 0), child: SmButton(label: _saving ? 'Saving…' : 'Save draft', icon: Icons.save_rounded, gradient: SM.mint, glow: SM.green, height: 52, loading: _saving, onTap: _save))),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Student traits  (traits_modal_content.php)
// ═════════════════════════════════════════════════════════════════════════════
class _TraitsSheet extends StatefulWidget {
  final String token, role;
  final int studentId, sessionId, termId;
  const _TraitsSheet({required this.token, required this.studentId, required this.sessionId, required this.termId, required this.role});

  @override
  State<_TraitsSheet> createState() => _TraitsSheetState();
}

class _TraitsSheetState extends State<_TraitsSheet> {
  bool _loading = true, _saving = false, _canEdit = true, _fromCache = false;
  String? _error;
  String _studentName = '';
  List<Map<String, dynamic>> _psyDefs = [], _affDefs = [];
  final Map<int, int> _psy = {}, _aff = {};

  static const _words = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

  int get _needP => _psyDefs.length < 5 ? _psyDefs.length : 5;
  int get _needA => _affDefs.length < 5 ? _affDefs.length : 5;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = _Store.traitsKey(widget.studentId, widget.sessionId, widget.termId);
    Map<String, dynamic>? d;
    var cache = false;
    if (await _Store.hasQueued('traits', widget.studentId, widget.sessionId, widget.termId)) {
      final c = await _Store.get(key);
      if (c is Map) {
        d = Map<String, dynamic>.from(c);
        cache = true;
      }
    }
    if (d == null) {
      final r = await _Api.post(widget.token, 'traits_get', {'student_id': '${widget.studentId}', 'session_id': '${widget.sessionId}', 'term_id': '${widget.termId}'});
      if (r['success'] == true) {
        d = _map(r['data']);
        await _Store.put(key, d);
      } else if (_isNet(r)) {
        final c = await _Store.get(key);
        if (c is Map) {
          d = Map<String, dynamic>.from(c);
        } else {
          final b = await _Store.findBundle(widget.sessionId, widget.termId, widget.studentId);
          if (b != null) d = _Offline.traitsFromBundle(b, widget.studentId, widget.role);
        }
        cache = true;
        if (d == null) {
          if (!mounted) return;
          setState(() {
            _error = "You're offline and the traits list isn't saved on this phone yet. Open Result Upload once with internet.";
            _loading = false;
          });
          return;
        }
      } else {
        if (!mounted) return;
        setState(() {
          _error = '${r['message']}';
          _loading = false;
        });
        return;
      }
    }
    if (!mounted) return;
    final data = d;
    setState(() {
      _studentName = _str(data['student_name']);
      _canEdit = data['can_edit'] != false;
      _psyDefs = _maps(data['psychomotor']);
      _affDefs = _maps(data['affective']);
      _psy.clear();
      _aff.clear();
      for (final t in _psyDefs) {
        final rt = _toInt(t['rating']) ?? 0;
        if (rt > 0) _psy[_toInt(t['id'])!] = rt;
      }
      for (final t in _affDefs) {
        final rt = _toInt(t['rating']) ?? 0;
        if (rt > 0) _aff[_toInt(t['id'])!] = rt;
      }
      _fromCache = cache;
      _loading = false;
    });
  }

  void _rate(Map<int, int> m, int id, int val, String kind) {
    if (!_canEdit) return;
    final cur = m[id] ?? 0;
    if (cur == val) {
      setState(() => m.remove(id)); // tap the same star again to clear it
      return;
    }
    if (cur == 0 && m.length >= 5) {
      smAlert(context, 'Limit reached', 'You can only pick 5 $kind traits.\nClear one before choosing another.', icon: Icons.warning_amber_rounded, color: SM.amber);
      return;
    }
    setState(() => m[id] = val);
  }

  Future<void> _save() async {
    if (_psy.length != _needP) {
      smAlert(context, 'Incomplete selection', 'Please pick exactly $_needP psychomotor traits.\nSelected so far: ${_psy.length}', icon: Icons.error_outline_rounded, color: SM.rose);
      return;
    }
    if (_aff.length != _needA) {
      smAlert(context, 'Incomplete selection', 'Please pick exactly $_needA affective traits.\nSelected so far: ${_aff.length}', icon: Icons.error_outline_rounded, color: SM.rose);
      return;
    }
    final payload = {
      'user_id': widget.studentId,
      'session_id': widget.sessionId,
      'term_id': widget.termId,
      'psychomotor': _psy.map((k, v) => MapEntry('$k', v)),
      'affective': _aff.map((k, v) => MapEntry('$k', v)),
    };
    setState(() => _saving = true);
    final key = _Store.traitsKey(widget.studentId, widget.sessionId, widget.termId);
    Map<String, dynamic> snap() => {
          'student_name': _studentName,
          'traits_exist': true,
          'can_edit': _canEdit,
          'psychomotor': _psyDefs.map((t) => {'id': t['id'], 'name': t['name'], 'rating': _psy[_toInt(t['id'])] ?? 0}).toList(),
          'affective': _affDefs.map((t) => {'id': t['id'], 'name': t['name'], 'rating': _aff[_toInt(t['id'])] ?? 0}).toList(),
        };
    final r = await _Api.postJson(widget.token, 'traits_save', payload);
    if (!mounted) return;
    if (r['success'] == true) {
      await _Store.put(key, snap());
      smToast(context, '${r['message']}');
      Navigator.of(context).pop(true);
    } else if (_isNet(r)) {
      await _Store.put(key, snap());
      await _Store.enqueue({'type': 'traits', 'student_id': widget.studentId, 'student_name': _studentName, 'session_id': widget.sessionId, 'term_id': widget.termId, 'label': 'Student traits', 'payload': payload});
      smToast(context, '📴 Traits saved on this phone. They upload when you are back online.', kind: SmKind.warn);
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      smToast(context, '${r['message']}', kind: SmKind.error);
    }
  }

  Widget _counter(int n, int need) {
    final c = n > need ? SM.rose : (n == need ? SM.green : SM.amber);
    return SmPill('$n / $need selected', color: c);
  }

  Widget _section(String title, IconData icon, List<Map<String, dynamic>> defs, Map<int, int> sel, int need, String kind, Color accent) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 10),
        child: Row(children: [
          Container(width: 34, height: 34, decoration: BoxDecoration(color: SM.a(accent, .18), borderRadius: BorderRadius.circular(12), border: Border.all(color: SM.a(accent, .5))), child: Icon(icon, size: 18, color: accent)),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 16))),
          _counter(sel.length, need),
        ]),
      ),
      if (defs.isEmpty) SmGlass(radius: 18, child: Text('No ${kind.toLowerCase()} traits defined yet.', style: const TextStyle(color: SM.muted))),
      ...defs.map((t) {
        final id = _toInt(t['id'])!;
        final cur = sel[id] ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SmGlass(
            radius: 20,
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
            color: cur > 0 ? SM.a(SM.amber, .10) : null,
            border: cur > 0 ? SM.a(SM.amber, .5) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_str(t['name']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.3))),
                if (cur > 0) SmPill(_words[cur], color: SM.amber),
              ]),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                for (var s = 1; s <= 5; s++)
                  SmPress(
                    onTap: _canEdit ? () => _rate(sel, id, s, kind) : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Icon(s <= cur ? Icons.star_rounded : Icons.star_outline_rounded, size: 34, color: s <= cur ? SM.amber : (_canEdit ? SM.faint : SM.a(SM.faint, .5))),
                    ),
                  ),
              ]),
            ]),
          ),
        );
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .94,
      minChildSize: .5,
      maxChildSize: .97,
      builder: (_, sc) => SmSheetFrame(
        title: 'Student traits',
        subtitle: _studentName.isEmpty ? 'Rate 5 psychomotor and 5 affective traits' : _studentName,
        icon: Icons.star_rounded,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: SM.orange))
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: SM.muted, height: 1.4))))
                : Column(children: [
                    Expanded(
                      child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                        if (_fromCache) _note(Icons.wifi_off_rounded, SM.amber, 'Showing information saved on this phone.'),
                        if (!_canEdit) _note(Icons.lock_rounded, SM.muted, 'Traits are already saved. Only the portal admin can change them.'),
                        _note(Icons.info_outline_rounded, SM.blueLight, 'Pick 5 traits in each group and rate them from 1 to 5 stars. Tap the same star again to clear it.'),
                        _section('Psychomotor traits', Icons.directions_run_rounded, _psyDefs, _psy, _needP, 'Psychomotor', SM.cyan),
                        _section('Affective traits', Icons.favorite_rounded, _affDefs, _aff, _needA, 'Affective', const Color(0xFFF472B6)),
                      ]),
                    ),
                    if (_canEdit)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: SmButton(label: _saving ? 'Saving…' : 'Save traits', icon: Icons.check_rounded, gradient: SM.hot, glow: SM.orange, loading: _saving, onTap: _save),
                      ),
                  ]),
      ),
    );
  }

  Widget _note(IconData i, Color c, String t) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SM.a(c, .12), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(c, .4))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, size: 18, color: c), const SizedBox(width: 10), Expanded(child: Text(t, style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.4)))]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Comments — many ready-made options by performance level + your school's own
// ═════════════════════════════════════════════════════════════════════════════
class _CommentsSheet extends StatefulWidget {
  final String teacher, proprietor, studentName;
  final List<Map<String, dynamic>> teacherList, propList;
  final bool isAdmin;
  final double average;
  const _CommentsSheet({required this.teacher, required this.proprietor, required this.teacherList, required this.propList, required this.isAdmin, required this.average, required this.studentName});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late final TextEditingController _t = TextEditingController(text: widget.teacher);
  late final TextEditingController _p = TextEditingController(text: widget.proprietor);
  int _tab = 0;
  late String _cat = widget.average > 0 ? _catForAverage(widget.average) : 'good';
  bool _append = false;

  @override
  void dispose() {
    _t.dispose();
    _p.dispose();
    super.dispose();
  }

  TextEditingController get _ctrl => _tab == 0 ? _t : _p;

  List<String> _items() {
    if (_cat == 'school') {
      final src = _tab == 0 ? widget.teacherList : widget.propList;
      final seen = <String>{};
      return src.map((e) => _str(e['comment_text']).trim()).where((s) => s.isNotEmpty && seen.add(s)).toList();
    }
    return (_tab == 0 ? _teacherLib : _proprietorLib)[_cat] ?? const [];
  }

  int get _schoolCount => (_tab == 0 ? widget.teacherList : widget.propList).map((e) => _str(e['comment_text']).trim()).where((s) => s.isNotEmpty).toSet().length;

  void _apply(String text) {
    HapticFeedback.selectionClick();
    final c = _ctrl;
    setState(() {
      if (_append && c.text.trim().isNotEmpty) {
        c.text = '${c.text.trim()} $text';
      } else {
        c.text = text;
      }
      c.selection = TextSelection.collapsed(offset: c.text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final suggested = widget.average > 0 ? _catForAverage(widget.average) : null;
    final items = _items();
    final cur = _ctrl.text.trim();
    return AnimatedPadding(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .95,
        minChildSize: .6,
        maxChildSize: .97,
        builder: (_, sc) => SmSheetFrame(
          title: 'Comments',
          subtitle: widget.studentName.isEmpty ? 'Tap a ready-made comment or write your own' : widget.studentName,
          icon: Icons.chat_bubble_rounded,
          child: Column(children: [
            Expanded(
              child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 0, 16, 12), children: [
                if (widget.isAdmin)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Expanded(child: SmChoice(label: "Teacher's", icon: Icons.person_rounded, selected: _tab == 0, onTap: () => setState(() { _tab = 0; if (_cat == 'school') _cat = suggested ?? 'good'; }))),
                      const SizedBox(width: 10),
                      Expanded(child: SmChoice(label: "Proprietor's", icon: Icons.school_rounded, color: SM.orange, selected: _tab == 1, onTap: () => setState(() { _tab = 1; if (_cat == 'school') _cat = suggested ?? 'good'; }))),
                    ]),
                  ),
                // writing area
                SmGlass(
                  radius: 24,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(_tab == 0 ? Icons.person_rounded : Icons.school_rounded, size: 17, color: SM.orange),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_tab == 0 ? "Teacher's comment" : "Proprietor's comment", style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5))),
                      if (_ctrl.text.isNotEmpty) InkWell(onTap: () => setState(() => _ctrl.clear()), child: const Padding(padding: EdgeInsets.all(4), child: Text('Clear', style: TextStyle(color: SM.rose, fontWeight: FontWeight.w700, fontSize: 12.5)))),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ctrl,
                      minLines: 4,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: SM.text, fontSize: 15, height: 1.45),
                      cursorColor: SM.orange,
                      decoration: smInput('Write a comment or pick one below…', accent: SM.orange),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 6),
                    Text('${_ctrl.text.length} characters', style: const TextStyle(color: SM.faint, fontSize: 11.5)),
                  ]),
                ),
                const SizedBox(height: 14),
                // replace / add
                Row(children: [
                  const Text('When I tap one:', style: TextStyle(color: SM.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  SmChoice(label: 'Replace', selected: !_append, onTap: () => setState(() => _append = false)),
                  const SizedBox(width: 8),
                  SmChoice(label: 'Add to end', selected: _append, color: SM.cyan, onTap: () => setState(() => _append = true)),
                ]),
                const SizedBox(height: 14),
                // categories
                SizedBox(
                  height: 46,
                  child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
                    for (final c in _commentCats) ...[
                      SmChoice(label: c.id == suggested ? '${c.label}  ★' : c.label, icon: c.icon, color: c.color, selected: _cat == c.id, onTap: () => setState(() => _cat = c.id)),
                      const SizedBox(width: 8),
                    ],
                    SmChoice(label: "School's own${_schoolCount > 0 ? ' · $_schoolCount' : ''}", icon: Icons.bookmark_rounded, color: SM.violet, selected: _cat == 'school', onTap: () => setState(() => _cat = 'school')),
                  ]),
                ),
                if (suggested != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('★ Suggested for an average of ${widget.average.toStringAsFixed(1)}%', style: const TextStyle(color: SM.muted, fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  SmGlass(radius: 20, child: Text(_cat == 'school' ? 'No comments saved by your school yet. Use the ready-made ones above.' : 'No options here.', style: const TextStyle(color: SM.muted)))
                else
                  ...items.map((t) {
                    final used = cur.contains(t);
                    final cat = _commentCats.firstWhere((c) => c.id == _cat, orElse: () => const _CommentCat('school', '', Icons.bookmark_rounded, SM.violet));
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SmGlass(
                        radius: 20,
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        color: used ? SM.a(cat.color, .14) : null,
                        border: used ? SM.a(cat.color, .6) : null,
                        onTap: () => _apply(t),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: Text(t, style: const TextStyle(color: SM.text, fontSize: 14, height: 1.45))),
                          const SizedBox(width: 10),
                          Icon(used ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded, color: used ? cat.color : SM.faint, size: 22),
                        ]),
                      ),
                    );
                  }),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SmButton(label: 'Save comments', icon: Icons.check_rounded, gradient: SM.hot, glow: SM.orange, onTap: () => Navigator.pop(context, {'teacher': _t.text.trim(), 'proprietor': _p.text.trim()})),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  OFFLINE data sheet
// ═════════════════════════════════════════════════════════════════════════════
class _OfflineSheet extends StatefulWidget {
  final String token;
  final List<Map<String, dynamic>> sessions, terms, classes;
  const _OfflineSheet({required this.token, required this.sessions, required this.terms, required this.classes});

  @override
  State<_OfflineSheet> createState() => _OfflineSheetState();
}

class _OfflineSheetState extends State<_OfflineSheet> {
  int? _sess, _term, _cls;
  bool _busy = false;
  List<Map<String, dynamic>> _bundles = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final b = await _Store.bundleIndex();
    if (mounted) setState(() => _bundles = b);
  }

  Future<void> _download({int? s, int? t, int? c}) async {
    final sess = s ?? _sess, term = t ?? _term, cls = c ?? _cls;
    if (sess == null || term == null || cls == null) {
      smToast(context, 'Choose a session, a term and a class first.', kind: SmKind.error);
      return;
    }
    setState(() => _busy = true);
    final r = await _Api.post(widget.token, 'offline_bundle', {'session_id': '$sess', 'term_id': '$term', 'class_id': '$cls'}, 90);
    if (!mounted) return;
    if (r['success'] == true) {
      final d = _map(r['data']);
      await _Store.saveBundle(d);
      await _reload();
      if (!mounted) return;
      setState(() => _busy = false);
      smToast(context, 'Downloaded ${(d['students'] as List).length} students. You can now work offline.');
    } else {
      setState(() => _busy = false);
      smToast(context, _isNet(r) ? 'No internet connection. Connect and try again.' : '${r['message']}', kind: SmKind.error);
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await smConfirm(context, 'Remove download?', 'Remove “${_str(e['label'])}” from this phone?', yes: 'Remove', destructive: true, icon: Icons.delete_outline_rounded);
    if (ok != true) return;
    await _Store.deleteBundle('${e['key']}');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final noData = widget.sessions.isEmpty || widget.terms.isEmpty || widget.classes.isEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .88,
      minChildSize: .5,
      maxChildSize: .96,
      builder: (_, sc) => SmSheetFrame(
        title: 'Offline data',
        subtitle: 'Work without internet',
        icon: Icons.cloud_download_rounded,
        child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
          SmGlass(
            radius: 22,
            color: SM.a(SM.green, .10),
            border: SM.a(SM.green, .4),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome_rounded, color: SM.green, size: 22),
              SizedBox(width: 12),
              Expanded(child: Text('Your classes download automatically whenever you open Result Upload with internet. Use this page only to download another session or term.', style: TextStyle(color: SM.muted, fontSize: 13, height: 1.45))),
            ]),
          ),
          const SizedBox(height: 18),
          const Text('Download another period', style: TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 12),
          if (noData)
            SmGlass(radius: 18, color: SM.a(SM.amber, .10), border: SM.a(SM.amber, .4), child: const Text('Sessions, terms and classes are not loaded yet. Connect to the internet and reopen this page.', style: TextStyle(color: SM.amber, fontSize: 13)))
          else ...[
            _lbl('Session'),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final s in widget.sessions) SmChoice(label: _str(s['session_name']), selected: _toInt(s['id']) == _sess, onTap: () => setState(() => _sess = _toInt(s['id'])))]),
            _lbl('Term'),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final t in widget.terms) SmChoice(label: _str(t['term_name']), color: SM.orange, selected: _toInt(t['id']) == _term, onTap: () => setState(() => _term = _toInt(t['id'])))]),
            _lbl('Class'),
            Wrap(spacing: 8, runSpacing: 8, children: [for (final c in widget.classes) SmChoice(label: _str(c['class_name']), color: SM.violet, selected: _toInt(c['class_id']) == _cls, onTap: () => setState(() => _cls = _toInt(c['class_id'])))]),
            const SizedBox(height: 16),
            SmButton(label: _busy ? 'Downloading…' : 'Download class', icon: Icons.download_rounded, loading: _busy, onTap: _download),
          ],
          const SizedBox(height: 24),
          const Text('Saved on this phone', style: TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 10),
          if (_bundles.isEmpty) const Text('Nothing downloaded yet.', style: TextStyle(color: SM.muted)),
          ..._bundles.map((e) {
            final dt = DateTime.tryParse(_str(e['saved_at']));
            final when = dt == null ? '' : '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SmGlass(
                radius: 20,
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_str(e['label']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w700, fontSize: 13.5, height: 1.3)),
                      const SizedBox(height: 2),
                      Text('${e['count']} students · saved $when', style: const TextStyle(color: SM.muted, fontSize: 12)),
                    ]),
                  ),
                  IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh_rounded, color: SM.cyan), onPressed: _busy ? null : () => _download(s: _toInt(e['session_id']), t: _toInt(e['term_id']), c: _toInt(e['class_id']))),
                  IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline_rounded, color: SM.rose), onPressed: () => _delete(e)),
                ]),
              ),
            );
          }),
        ]),
      ),
    );
  }

  Widget _lbl(String t) => Padding(padding: const EdgeInsets.only(top: 14, bottom: 8), child: Text(t, style: const TextStyle(color: SM.muted, fontSize: 12.5, fontWeight: FontWeight.w700)));
}

// ═════════════════════════════════════════════════════════════════════════════
//  OFFLINE queue — results waiting to upload
// ═════════════════════════════════════════════════════════════════════════════
class _QueueSheet extends StatefulWidget {
  final String token;
  const _QueueSheet({required this.token});

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final q = await _Store.queue();
    if (mounted) setState(() => _items = q);
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final r = await _Store.sync(widget.token, retryErrors: true);
    await _reload();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r.synced > 0) smToast(context, '${r.synced} uploaded successfully ✔');
    if (r.offline) smToast(context, 'Still offline. Your work is safe on this phone.', kind: SmKind.warn);
    if (r.authFailed) smToast(context, 'Session expired. Please log out and log in again.', kind: SmKind.error);
    if (r.failed > 0) smToast(context, '${r.failed} could not be uploaded. See the red messages.', kind: SmKind.error);
  }

  Future<void> _discard(Map<String, dynamic> e) async {
    final ok = await smConfirm(context, 'Discard this item?', 'It has not been uploaded and will be lost.', yes: 'Discard', destructive: true, icon: Icons.delete_outline_rounded);
    if (ok != true) return;
    await _Store.removeQueued('${e['id']}');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (_, sc) => SmSheetFrame(
        title: 'Waiting to upload',
        subtitle: _items.isEmpty ? 'All caught up' : '${_items.length} item${_items.length == 1 ? '' : 's'}',
        icon: Icons.cloud_upload_rounded,
        child: Column(children: [
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(28), child: Text('Everything is uploaded ✔\nResults you save without internet will appear here.', textAlign: TextAlign.center, style: TextStyle(color: SM.muted, height: 1.5))))
                : ListView.builder(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final e = _items[i];
                      final err = e['error'] != null;
                      final c = err ? SM.rose : SM.cyan;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SmGlass(
                          radius: 20,
                          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                          color: SM.a(c, .10),
                          border: SM.a(c, .5),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Icon(e['type'] == 'traits' ? Icons.star_rounded : Icons.assignment_rounded, color: c),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_str(e['student_name']).isEmpty ? 'Student ${e['student_id']}' : _str(e['student_name']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5)),
                                Text(_str(e['label']), style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.3)),
                                if (err) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Not uploaded: ${e['error']}', style: const TextStyle(color: SM.rose, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.3))),
                              ]),
                            ),
                            IconButton(tooltip: 'Discard', icon: const Icon(Icons.delete_outline_rounded, color: SM.rose), onPressed: () => _discard(e)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), child: SmButton(label: _busy ? 'Uploading…' : 'Sync now', icon: Icons.sync_rounded, loading: _busy, onTap: _items.isEmpty ? null : _sync)),
        ]),
      ),
    );
  }
}
