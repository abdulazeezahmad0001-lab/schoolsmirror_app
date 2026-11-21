// flutter_result_upload_screen.dart
// Mirrors the web "Result Upload" flow 1:1:
//   resultUpload.php          -> FlutterResultUploadScreen   (students, class/department rail, search, pager, delete)
//   upload_results.php        -> _StudentPeriodScreen        (profile, history, class result, session/term picker)
//   fetch_result_upload.php   -> _ResultEntryScreen          (subject score entry, ABS, auto grade, comments)
//   traits_modal_content.php  -> _TraitsSheet                (5 psychomotor + 5 affective traits)
//   process_result_upload.php -> save_result in flutter_result_upload.php
//
// OFFLINE: scores, comments and traits can be saved with no network. They wait in a queue on the phone
// and are uploaded automatically (when the screen opens, when the app resumes, every 30s while online,
// or with the "Sync now" button). "Download for offline" stores a whole class for a session/term.
//
// pubspec.yaml needs (all already in your pubspec):  http, shared_preferences

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// Your host redirects "*.php" to the extensionless address, and a redirect turns POST into GET
// (the body is lost -> "Missing token"). The extensionless URL is tried first and the app falls
// back to the other form automatically.
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_result_upload',
  'https://schoolsmirror.com/flutter_result_upload.php',
];
int _apiIdx = 0;

/// Colour tokens: blue = resultUpload.php (:root), indigo = upload_results.php / fetch_result_upload.php (:root)
class _C {
  // resultUpload.php
  static const ink = Color(0xFF06283D);
  static const deep = Color(0xFF04415F);
  static const blue = Color(0xFF0083B0);
  static const sky = Color(0xFF00B4DB);
  static const mist = Color(0xFFE6F4FA);
  static const bg = Color(0xFFEAF3F8);
  static const text = Color(0xFF0F2A3A);
  static const muted = Color(0xFF5B7486);
  static const danger = Color(0xFFE5484D);
  // upload_results.php / fetch_result_upload.php
  static const pri = Color(0xFF4F46E5);
  static const priD = Color(0xFF3730A3);
  static const ok = Color(0xFF10B981);
  static const warn = Color(0xFFF59E0B);
  static const err = Color(0xFFEF4444);
  static const dark = Color(0xFF0F172A);
  static const muted2 = Color(0xFF64748B);
  static const bg2 = Color(0xFFF1F5F9);
  static const bdr = Color(0xFFE2E8F0);
  static const absBg = Color(0xFFFEF3C7);
  static const absColor = Color(0xFF92400E);

  static const heroGradient = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [ink, deep, blue]);
  static const headerGradient = LinearGradient(colors: [blue, sky]);
  static const indigoGradient = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [pri, priD]);
}

// ───────────────────────────── tiny helpers ─────────────────────────────
int? _toInt(dynamic v) => v == null ? null : int.tryParse('$v');
String _str(dynamic v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
Map<String, dynamic> _map(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

String _initial(String name) => name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();

void _toast(BuildContext context, String msg, {bool error = false, bool warn = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? _C.err : (warn ? _C.warn : _C.ok),
        behavior: SnackBarBehavior.floating));
}

Future<bool?> _confirm(BuildContext context, String title, String text,
    {String yes = 'Yes', String no = 'Cancel', bool destructive = false, IconData icon = Icons.warning_amber_rounded}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(children: [
        Icon(icon, size: 54, color: destructive ? _C.danger : _C.warn),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
      content: Text(text, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _C.muted2, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(no)),
        ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: destructive ? _C.danger : _C.pri, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes)),
      ],
    ),
  );
}

Future<void> _alert(BuildContext context, String title, String html,
    {IconData icon = Icons.info, Color color = _C.pri}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Column(children: [
        Icon(icon, size: 54, color: color),
        const SizedBox(height: 8),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
      ]),
      content: Text(html, textAlign: TextAlign.center),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _C.pri, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK')),
      ],
    ),
  );
}

Widget _avatar(String? url, String name, {double size = 46, Color ring = _C.sky}) {
  final ph = Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: _C.mist, shape: BoxShape.circle),
    child: Text(_initial(name),
        style: TextStyle(color: _C.blue, fontWeight: FontWeight.w800, fontSize: size * .4)),
  );
  return Container(
    width: size + 6,
    height: size + 6,
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ring, width: 2)),
    child: ClipOval(
      child: (url == null || url.isEmpty)
          ? ph
          : Image.network(url, width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ph),
    ),
  );
}

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
      [Map<String, String> fields = const {}, int timeoutSec = 30]) {
    return _send(token, action, form: fields, timeoutSec: timeoutSec);
  }

  /// JSON request (scores, traits). Used for saving and for offline sync.
  static Future<Map<String, dynamic>> postJson(String token, String action, Map<String, dynamic> body,
      {int timeoutSec = 60}) {
    return _send(token, action, json: body, timeoutSec: timeoutSec);
  }

  static Future<Map<String, dynamic>> _send(String token, String action,
      {Map<String, String> form = const {}, Map<String, dynamic>? json, int timeoutSec = 30}) async {
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

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN 1 — Manage Students  (resultUpload.php)
// ═════════════════════════════════════════════════════════════════════════════
class FlutterResultUploadScreen extends StatefulWidget {
  final String? token;
  const FlutterResultUploadScreen({super.key, this.token});

  @override
  State<FlutterResultUploadScreen> createState() => _FlutterResultUploadScreenState();
}

class _FlutterResultUploadScreenState extends State<FlutterResultUploadScreen> with WidgetsBindingObserver {
  String? _token;
  bool _loading = true;
  bool _loadingList = false;
  bool _offline = false;
  bool _syncing = false;
  int _pending = 0;
  Timer? _timer;

  String _role = '';
  bool _canDelete = true;
  List<Map<String, dynamic>> _sessions = [], _terms = [], _classes = [];

  // filters (same names as resultUpload.php)
  String _fClass = '', _fDept = '', _sClass = '', _sId = '';
  final _idCtrl = TextEditingController();
  final _clsCtrl = TextEditingController();

  List<Map<String, dynamic>> _students = [], _tree = [];
  int _total = 0, _page = 1, _totalPages = 1, _totalAll = 0, _classCount = 0;
  String? _banner;
  bool _bannerError = false;

  final _scroll = ScrollController();

  String get _activeClass => _fClass.isNotEmpty ? _fClass : _sClass;
  bool get _anyFilter => _activeClass.isNotEmpty || _fDept.isNotEmpty || _sId.isNotEmpty;

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
    _clsCtrl.dispose();
    _scroll.dispose();
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
      _toast(context, 'Session expired. Please log in again.', error: true);
      return;
    }
    await _loadBootstrap();
    await _loadStudents(page: 1);
    await _refreshPending();
    if (mounted) setState(() => _loading = false);
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _autoSync();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showInfoPopup());
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
      if (mounted) {
        setState(() {
          _applyBoot(d);
          _offline = false;
        });
      }
    } else if (_isNet(r)) {
      final c = await _Store.get('boot');
      if (c is Map && mounted) {
        setState(() {
          _applyBoot(Map<String, dynamic>.from(c));
          _offline = true;
        });
      } else if (mounted) {
        setState(() => _offline = true);
      }
    } else {
      _setBanner('${r['message'] ?? 'Failed to load'}', error: true);
    }
  }

  Map<String, String> _query(int page) => {
        'page': '$page',
        if (_sId.isNotEmpty) 'search_idnumber': _sId,
        if (_fClass.isNotEmpty) 'filter_class': _fClass,
        if (_fDept.isNotEmpty) 'filter_dept': _fDept,
        if (_sClass.isNotEmpty) 'search_class': _sClass,
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

  /// No connection and nothing cached for this search: build the list from the classes downloaded for offline use.
  Future<void> _applyLocal(int p) async {
    final bundles = await _Store.allBundles();
    final seen = <int>{};
    final all = <Map<String, dynamic>>[];
    for (final b in bundles) {
      for (final s in _maps(b['students'])) {
        if (seen.add(_toInt(s['user_id']) ?? 0)) all.add(s);
      }
    }
    // class tree
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
      return {
        'class_name': c,
        'total': dm.values.fold<int>(0, (a, b) => a + b),
        'depts': dn.map((x) => {'name': x, 'count': dm[x]}).toList(),
      };
    }).toList();
    // filters
    final ac = _activeClass.toLowerCase();
    var list = all.where((s) {
      if (_sId.isNotEmpty && !_str(s['idnumber']).toLowerCase().contains(_sId.toLowerCase())) return false;
      if (ac.isNotEmpty && !_str(s['class_name']).toLowerCase().contains(ac)) return false;
      if (_fDept.isNotEmpty && _str(s['department_name']) != _fDept) return false;
      return true;
    }).toList();
    list.sort((a, b) {
      final c = _str(a['class_name']).compareTo(_str(b['class_name']));
      if (c != 0) return c;
      final d = _str(a['department_name']).compareTo(_str(b['department_name']));
      if (d != 0) return d;
      return _str(a['fullname']).compareTo(_str(b['fullname']));
    });
    const per = 15;
    final pages = list.isEmpty ? 1 : ((list.length + per - 1) ~/ per);
    final page = p.clamp(1, pages);
    if (!mounted) return;
    setState(() {
      _students = list.skip((page - 1) * per).take(per).toList();
      _tree = treeList.map((e) => Map<String, dynamic>.from(e)).toList();
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
  }

  // ───────────────────────────── offline sync ─────────────────────────────
  Future<void> _refreshPending() async {
    final n = await _Store.pendingCount();
    if (mounted) setState(() => _pending = n);
  }

  /// every 30s and when the app comes back: re-check the connection and upload waiting results
  Future<void> _tick() async {
    if (_token == null || !mounted) return;
    if (_offline) {
      final r = await _Api.post(_token!, 'ping', const {}, 8);
      if (r['success'] == true && mounted) {
        setState(() => _offline = false);
        _loadStudents();
      }
    }
    await _autoSync();
  }

  Future<void> _autoSync({bool manual = false}) async {
    if (_token == null || _syncing) return;
    final n = await _Store.pendingCount();
    if (n == 0) {
      if (mounted) setState(() => _pending = 0);
      if (manual && mounted) _toast(context, 'Nothing waiting to upload.');
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
    if (r.synced > 0) _toast(context, '${r.synced} saved result${r.synced == 1 ? '' : 's'} uploaded successfully ✔');
    if (r.failed > 0) _toast(context, '${r.failed} item${r.failed == 1 ? '' : 's'} could not be uploaded. Tap the sync icon to review.', error: true);
    if (manual && r.offline) _toast(context, 'Still offline. Your results are safe on this phone.', warn: true);
    if (manual && r.authFailed) _toast(context, 'Session expired. Please log out and log in again.', error: true);
  }

  // ───────────────────────────── filters ─────────────────────────────
  void _setFilters({String? cls, String? dept, String? sId, String? sClass}) {
    setState(() {
      if (cls != null) _fClass = cls;
      if (dept != null) _fDept = dept;
      if (sId != null) _sId = sId;
      if (sClass != null) _sClass = sClass;
      _page = 1;
      _banner = null;
    });
    _loadStudents(page: 1);
  }

  void _doSearch() {
    FocusScope.of(context).unfocus();
    _setFilters(sId: _idCtrl.text.trim(), sClass: _fClass.isNotEmpty ? '' : _clsCtrl.text.trim());
  }

  void _clearAll() {
    _idCtrl.clear();
    _clsCtrl.clear();
    _setFilters(cls: '', dept: '', sId: '', sClass: '');
  }

  // ───────────────────────────── actions ─────────────────────────────
  void _showInfoPopup() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('📋', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          const Text.rich(
            TextSpan(children: [
              TextSpan(text: 'Visit '),
              TextSpan(text: 'Publish Result', style: TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: " to see which students you haven't uploaded results for."),
            ]),
            textAlign: TextAlign.center,
            style: TextStyle(color: _C.muted),
          ),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: _C.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Future<void> _openStudent(Map<String, dynamic> s) async {
    final id = _toInt(s['user_id']);
    if (id == null || _token == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _StudentPeriodScreen(token: _token!, studentId: id, role: _role),
    ));
    if (!mounted) return;
    _refreshPending();
    _autoSync();
  }

  Future<void> _deleteStudent(Map<String, dynamic> s) async {
    if (!_canDelete) {
      _toast(context, 'Only administrators can delete students.', error: true);
      return;
    }
    if (_offline) {
      _toast(context, 'Connect to the internet to delete a student.', error: true);
      return;
    }
    final ok = await _confirm(context, 'Delete student?', 'This permanently removes the student and their photo.',
        yes: 'Delete', destructive: true);
    if (ok != true) return;
    final r = await _Api.post(_token!, 'delete_student', {'id': '${s['user_id']}'});
    if (!mounted) return;
    if (r['success'] == true) {
      _toast(context, '${r['message']}');
      await _loadStudents();
    } else if (_isNet(r)) {
      _toast(context, 'No internet connection. Try again when you are online.', error: true);
    } else {
      _toast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _openOfflineSheet() async {
    if (_token == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _OfflineSheet(token: _token!, sessions: _sessions, terms: _terms, classes: _classes),
    );
    if (mounted && _offline) _loadStudents();
  }

  Future<void> _openQueueSheet() async {
    if (_token == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _QueueSheet(token: _token!),
    );
    _refreshPending();
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.headerGradient)),
        title: const Text('Result Upload', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
              tooltip: 'Download a class for offline use',
              icon: const Icon(Icons.cloud_download_outlined),
              onPressed: _loading ? null : _openOfflineSheet),
          IconButton(
              tooltip: 'Waiting to upload',
              icon: Badge(
                  label: Text('$_pending'),
                  isLabelVisible: _pending > 0,
                  child: _syncing
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync)),
              onPressed: _loading ? null : _openQueueSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.blue))
          : RefreshIndicator(
              color: _C.blue,
              onRefresh: _refresh,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 60),
                children: [
                  if (_offline) _offlineBanner(),
                  if (_pending > 0) _pendingBanner(),
                  if (_banner != null) _alertBox(),
                  _hero(),
                  if (_tree.isNotEmpty) ...[
                    _sectionTitle('Classes and departments', 'Select a class or department to filter'),
                    ..._tree.map(_classCard),
                  ],
                  const SizedBox(height: 18),
                  _searchBar(),
                  if (_anyFilter) _chips(),
                  _meta(),
                  _list(),
                  if (_totalPages > 1) _pager(),
                ],
              ),
            ),
    );
  }

  // ───────────────────────────── widgets ─────────────────────────────
  Widget _offlineBanner() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFEAA7))),
        child: const Row(children: [
          Icon(Icons.wifi_off, color: Color(0xFF856404)),
          SizedBox(width: 10),
          Expanded(
              child: Text(
                  "You're offline — showing saved data. Anything you save is kept on this phone and uploaded automatically when you are back online.",
                  style: TextStyle(color: Color(0xFF856404), fontSize: 13))),
        ]),
      );

  Widget _pendingBanner() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _C.mist, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.sky.withAlpha(120))),
        child: Row(children: [
          const Icon(Icons.cloud_upload_outlined, color: _C.blue),
          const SizedBox(width: 10),
          Expanded(
              child: Text('$_pending item${_pending == 1 ? '' : 's'} waiting to upload',
                  style: const TextStyle(color: _C.deep, fontWeight: FontWeight.w700))),
          TextButton.icon(
              onPressed: _syncing ? null : () => _autoSync(manual: true),
              icon: const Icon(Icons.sync, size: 18),
              label: Text(_syncing ? 'Syncing…' : 'Sync now')),
        ]),
      );

  Widget _alertBox() {
    final err = _bannerError;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: err ? const Color(0xFFF8D7DA) : const Color(0xFFE7F8EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: err ? const Color(0xFFF5C6CB) : const Color(0xFFA8E6C3)),
      ),
      child: Row(children: [
        Icon(err ? Icons.error : Icons.check_circle, color: err ? const Color(0xFF721C24) : const Color(0xFF0B5B36)),
        const SizedBox(width: 10),
        Expanded(child: Text(_banner!, style: TextStyle(color: err ? const Color(0xFF721C24) : const Color(0xFF0B5B36), fontWeight: FontWeight.w600))),
        InkWell(onTap: () => setState(() => _banner = null), child: const Icon(Icons.close, size: 18)),
      ]),
    );
  }

  Widget _stat(int n, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
            color: Colors.white.withAlpha(31), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withAlpha(56))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TweenAnimationBuilder<double>(
            key: ValueKey('$label$n'),
            tween: Tween(begin: 0, end: n.toDouble()),
            duration: const Duration(milliseconds: 1100),
            curve: Curves.easeOutQuart,
            builder: (_, v, __) => Text('${v.round()}',
                style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800, height: 1)),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );

  Widget _hero() => Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        decoration: BoxDecoration(
          gradient: _C.heroGradient,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: _C.deep.withAlpha(110), blurRadius: 28, offset: const Offset(0, 14))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
                color: Colors.white.withAlpha(36), borderRadius: BorderRadius.circular(99), border: Border.all(color: Colors.white.withAlpha(64))),
            child: Text(_role.isEmpty ? 'Admin' : '${_role[0].toUpperCase()}${_role.substring(1)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          const Text('Manage Students',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          const SizedBox(height: 6),
          const Text('Browse by class and department, search by ID, and upload results in one place.',
              style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _stat(_totalAll, 'Students')),
            const SizedBox(width: 12),
            Expanded(child: _stat(_classCount, 'Classes')),
          ]),
        ]),
      );

  Widget _sectionTitle(String t, String sub) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 26, 4, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(t, style: const TextStyle(color: _C.deep, fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(width: 10),
          Expanded(child: Text(sub, style: const TextStyle(color: _C.muted, fontSize: 12), overflow: TextOverflow.ellipsis)),
        ]),
      );

  Widget _classCard(Map<String, dynamic> c) {
    final cname = _str(c['class_name']);
    final active = _activeClass.isNotEmpty && _activeClass.toLowerCase() == cname.toLowerCase();
    final depts = _maps(c['depts']);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(200),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: active ? _C.blue : _C.blue.withAlpha(36), width: active ? 1.6 : 1),
        boxShadow: active ? [BoxShadow(color: _C.blue.withAlpha(60), blurRadius: 18, offset: const Offset(0, 8))] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => _setFilters(cls: (active && _fDept.isEmpty) ? '' : cname, dept: '', sClass: ''),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: active ? const LinearGradient(colors: [_C.blue, _C.sky]) : null,
              color: active ? null : _C.mist,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(children: [
              Expanded(child: Text(cname, style: TextStyle(fontWeight: FontWeight.w800, color: active ? Colors.white : _C.deep))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withAlpha(166), borderRadius: BorderRadius.circular(99)),
                child: Text('${c['total']}', style: const TextStyle(color: _C.deep, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: depts.map((d) {
            final dn = _str(d['name']);
            final none = dn == 'No Department';
            final on = active && _fDept == dn;
            return InkWell(
              borderRadius: BorderRadius.circular(99),
              onTap: () {
                if (none) {
                  _setFilters(cls: cname, dept: '', sClass: '');
                } else if (on) {
                  _setFilters(cls: cname, dept: '', sClass: '');
                } else {
                  _setFilters(cls: cname, dept: dn, sClass: '');
                }
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 5, 6, 5),
                decoration: BoxDecoration(
                  color: on ? _C.blue : Colors.white,
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: on ? _C.blue : _C.blue.withAlpha(36)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(dn,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontStyle: none ? FontStyle.italic : FontStyle.normal,
                          color: on ? Colors.white : (none ? _C.muted : _C.text))),
                  const SizedBox(width: 7),
                  Container(
                    constraints: const BoxConstraints(minWidth: 24),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: on ? Colors.white.withAlpha(64) : _C.mist, borderRadius: BorderRadius.circular(99)),
                    child: Text('${d['count']}',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 11.5, color: on ? Colors.white : _C.blue)),
                  ),
                ]),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }

  InputDecoration _searchDec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: _C.muted),
        filled: true,
        fillColor: _C.mist,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: _C.sky, width: 1.6)),
      );

  Widget _searchBar() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(210),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _C.blue.withAlpha(36)),
          boxShadow: [BoxShadow(color: _C.deep.withAlpha(36), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Column(children: [
          TextField(
              controller: _idCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
              decoration: _searchDec('Search by ID number', Icons.search)),
          const SizedBox(height: 8),
          TextField(
              controller: _clsCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _doSearch(),
              decoration: _searchDec('Search by class name', Icons.school_outlined)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _doSearch,
                style: ElevatedButton.styleFrom(
                    backgroundColor: _C.blue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Search', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            if (_anyFilter) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _clearAll,
                style: OutlinedButton.styleFrom(
                    foregroundColor: _C.muted,
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    side: BorderSide(color: _C.blue.withAlpha(50), width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
        ]),
      );

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: _C.mist, borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: const TextStyle(color: _C.deep, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );

  Widget _chips() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Showing:', style: TextStyle(color: _C.muted, fontSize: 13)),
          if (_activeClass.isNotEmpty) _chip('Class: $_activeClass'),
          if (_fDept.isNotEmpty) _chip('Dept: $_fDept'),
          if (_sId.isNotEmpty) _chip('ID: $_sId'),
        ]),
      );

  Widget _meta() => Padding(
        padding: const EdgeInsets.fromLTRB(6, 18, 6, 10),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text.rich(TextSpan(style: const TextStyle(color: _C.muted, fontSize: 13), children: [
            const TextSpan(text: 'Showing '),
            TextSpan(text: '${_students.length}', style: const TextStyle(color: _C.text, fontWeight: FontWeight.w800)),
            const TextSpan(text: ' of '),
            TextSpan(text: '$_total', style: const TextStyle(color: _C.text, fontWeight: FontWeight.w800)),
            TextSpan(text: ' student${_total != 1 ? 's' : ''}'),
          ])),
          if (_totalPages > 1)
            Text.rich(TextSpan(style: const TextStyle(color: _C.muted, fontSize: 13), children: [
              const TextSpan(text: 'Page '),
              TextSpan(text: '$_page', style: const TextStyle(color: _C.text, fontWeight: FontWeight.w800)),
              const TextSpan(text: ' of '),
              TextSpan(text: '$_totalPages', style: const TextStyle(color: _C.text, fontWeight: FontWeight.w800)),
            ])),
        ]),
      );

  Widget _tag(String t, Color bg, Color fg, {VoidCallback? onTap, bool italic = false}) {
    final w = Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(t, style: TextStyle(color: fg, fontWeight: italic ? FontWeight.w500 : FontWeight.w700, fontSize: 12.5, fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
    );
    return onTap == null ? w : InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: w);
  }

  Widget _studentCard(Map<String, dynamic> s) {
    final g = _str(s['gender']).toLowerCase();
    final cn = _str(s['class_name']);
    final dn = _str(s['department_name']);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.blue.withAlpha(36)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _avatar(_str(s['image_url']), _str(s['fullname'])),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_str(s['fullname']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, height: 1.3)),
            const SizedBox(height: 2),
            Row(children: [
              Flexible(
                  child: Text(_str(s['idnumber']),
                      style: const TextStyle(color: _C.muted, fontWeight: FontWeight.w600, fontSize: 13),
                      overflow: TextOverflow.ellipsis)),
              if (_sId.isNotEmpty && _str(s['idnumber']).toLowerCase().contains(_sId.toLowerCase()))
                const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Text('✓', style: TextStyle(color: Color(0xFF0B8A4F), fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _tag(_str(s['gender']).isEmpty ? '—' : _str(s['gender']),
                  g == 'female' ? const Color(0xFFFCE7F3) : (g == 'male' ? const Color(0xFFDBEAFE) : const Color(0xFFF1F5F9)),
                  g == 'female' ? const Color(0xFF9D174D) : (g == 'male' ? const Color(0xFF1D4ED8) : const Color(0xFF94A3B8)),
                  italic: g != 'female' && g != 'male'),
              cn.isNotEmpty
                  ? _tag(cn, _C.mist, _C.deep, onTap: () => _setFilters(cls: cn, dept: '', sClass: ''))
                  : _tag('N/A', const Color(0xFFF1F5F9), const Color(0xFF94A3B8), italic: true),
              dn.isNotEmpty
                  ? _tag(dn, const Color(0xFFE0F7FB), const Color(0xFF0A6178), onTap: () => _setFilters(cls: cn, dept: dn, sClass: ''))
                  : _tag('Not available', const Color(0xFFF1F5F9), const Color(0xFF94A3B8), italic: true),
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onSelected: (v) {
            if (v == 'upload') _openStudent(s);
            if (v == 'delete') _deleteStudent(s);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'upload', child: Row(children: [Icon(Icons.upload_file, size: 20, color: _C.blue), SizedBox(width: 10), Text('Upload result', style: TextStyle(fontWeight: FontWeight.w600))])),
            if (_canDelete)
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 20, color: _C.danger), SizedBox(width: 10), Text('Delete student', style: TextStyle(fontWeight: FontWeight.w600, color: _C.danger))])),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.blue.withAlpha(40), width: 1.5)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Actions', style: TextStyle(color: _C.deep, fontWeight: FontWeight.w700, fontSize: 13)),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 18, color: _C.deep),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _list() {
    if (_loadingList && _students.isEmpty) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: _C.blue)));
    }
    if (_students.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
        child: Column(children: [
          const Text('📭', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          const Text('No students found', style: TextStyle(color: _C.deep, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(_anyFilter ? 'No students match this filter or search.' : (_offline ? 'Download a class for offline use to see students here.' : 'No students have been added yet.'),
              textAlign: TextAlign.center, style: const TextStyle(color: _C.muted)),
          if (_anyFilter) ...[
            const SizedBox(height: 14),
            ElevatedButton(
                onPressed: _clearAll,
                style: ElevatedButton.styleFrom(backgroundColor: _C.blue, foregroundColor: Colors.white),
                child: const Text('View all students')),
          ],
        ]),
      );
    }
    return Opacity(opacity: _loadingList ? .5 : 1, child: Column(children: _students.map(_studentCard).toList()));
  }

  Widget _pageBtn(String label, int? page, {bool on = false}) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: page == null ? null : () => _loadStudents(page: page),
        child: Container(
          constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [_C.blue, _C.sky]) : null,
            color: on ? null : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: on ? Colors.transparent : _C.blue.withAlpha(36), width: 1.5),
          ),
          child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: on ? Colors.white : _C.text)),
        ),
      );

  Widget _pager() {
    final sp = (_page - 2).clamp(1, _totalPages);
    final ep = (_page + 2).clamp(1, _totalPages);
    final items = <Widget>[];
    if (_page > 1) items.add(_pageBtn('← Prev', _page - 1));
    if (sp > 1) {
      items.add(_pageBtn('1', 1));
      if (sp > 2) items.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('…', style: TextStyle(color: _C.muted))));
    }
    for (var i = sp; i <= ep; i++) {
      items.add(_pageBtn('$i', i, on: i == _page));
    }
    if (ep < _totalPages) {
      if (ep < _totalPages - 1) items.add(const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: Text('…', style: TextStyle(color: _C.muted))));
      items.add(_pageBtn('$_totalPages', _totalPages));
    }
    if (_page < _totalPages) items.add(_pageBtn('Next →', _page + 1));
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: items),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN 2 — Academic Result Upload: student + session/term  (upload_results.php)
// ═════════════════════════════════════════════════════════════════════════════
const String _blockMsg = 'These results were finalized more than 30 days ago. Contact the portal administrator to edit.';

class _StudentPeriodScreen extends StatefulWidget {
  final String token;
  final int studentId;
  final String role;
  const _StudentPeriodScreen({required this.token, required this.studentId, required this.role});

  @override
  State<_StudentPeriodScreen> createState() => _StudentPeriodScreenState();
}

class _StudentPeriodScreenState extends State<_StudentPeriodScreen> {
  static bool _summaryClosed = false; // web: sessionStorage 'resultsSummaryClosed'

  bool _loading = true;
  bool _offline = false;
  bool _busy = false;
  bool _pickError = false;
  String? _error;
  String? _flash;
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
    _flashTimer = Timer(const Duration(seconds: 6), () {
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
      _apply(d, offline: false);
    } else if (_isNet(r)) {
      final c = await _Store.get('periods_${widget.studentId}');
      if (c is Map) {
        _apply(Map<String, dynamic>.from(c), offline: true);
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
      final n = (_map(q['payload'])['subject'] is List) ? (_map(q['payload'])['subject'] as List).where((x) => '$x'.trim().isNotEmpty).length : 0;
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
    });
  }

  /// Offline and this student was never opened before: use the downloaded classes.
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
            .map((s) => {
                  'user_id': s['user_id'],
                  'fullname': s['fullname'],
                  'admission_number': s['admission_number'],
                  'image_url': s['image_url'],
                  'class_name': s['class_name'],
                })
            .toList();
      }
      final st = _map(_map(b['statuses'])['${widget.studentId}']);
      if (st.isNotEmpty) {
        summary.add({
          'session_id': b['session_id'],
          'term_id': b['term_id'],
          'status': st['status'],
          'last_updated': st['created_at'],
          'subject_count': st['subject_count'],
          'session_name': b['session_name'],
          'term_name': b['term_name'],
        });
      }
    }
    if (!mounted) return;
    if (stu == null) {
      setState(() {
        _error = "You're offline and this student's class has not been downloaded. Connect to the internet, or use “Download for offline” on the students page first.";
        _loading = false;
      });
      return;
    }
    await _apply({
      'student': stu,
      'sessions': bootM['sessions'] ?? [],
      'terms': bootM['terms'] ?? [],
      'summary': summary,
      'class_students': classStudents,
    }, offline: true);
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
    final r = await _Api.post(widget.token, 'open_period', {
      'student_id': '${widget.studentId}',
      'session_id': '$_selSession',
      'term_id': '$_selTerm',
    });
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
    final msg = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => _ResultEntryScreen(
          token: widget.token, studentId: widget.studentId, sessionId: _selSession!, termId: _selTerm!, role: widget.role),
    ));
    if (!mounted) return;
    if (msg != null && msg.isNotEmpty) _setFlash(msg);
    _load(silent: true);
  }

  void _openClassResult() {
    final cn = _str(_student['class_name']);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        minChildSize: .4,
        maxChildSize: .95,
        builder: (_, sc) => Column(children: [
          const SizedBox(height: 10),
          Container(width: 44, height: 4, decoration: BoxDecoration(color: _C.bdr, borderRadius: BorderRadius.circular(4))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 4),
            child: Row(children: [
              const Icon(Icons.groups, color: _C.pri),
              const SizedBox(width: 8),
              Expanded(child: Text('Students in ${cn.isEmpty ? 'Same Class' : cn}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: _C.muted2),
              SizedBox(width: 6),
              Expanded(child: Text('Tap any student below to upload their results', style: TextStyle(color: _C.muted2, fontSize: 13))),
            ]),
          ),
          Expanded(
            child: _classStudents.isEmpty
                ? const Center(child: Text('No other students found in this class', style: TextStyle(color: _C.muted2)))
                : ListView.builder(
                    controller: sc,
                    padding: const EdgeInsets.all(14),
                    itemCount: _classStudents.length,
                    itemBuilder: (_, i) {
                      final s = _classStudents[i];
                      final cur = _toInt(s['user_id']) == widget.studentId;
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () {
                          Navigator.pop(ctx);
                          if (cur) return;
                          Navigator.of(context).pushReplacement(MaterialPageRoute(
                            builder: (_) => _StudentPeriodScreen(token: widget.token, studentId: _toInt(s['user_id'])!, role: widget.role),
                          ));
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: cur ? _C.pri.withAlpha(20) : _C.bg2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: cur ? _C.pri : _C.bdr),
                          ),
                          child: Row(children: [
                            _avatar(_str(s['image_url']), _str(s['fullname']), size: 40, ring: _C.pri),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Flexible(child: Text(_str(s['fullname']), style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                                  if (cur)
                                    Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(color: _C.pri, borderRadius: BorderRadius.circular(99)),
                                      child: const Text('Current', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                                    ),
                                ]),
                                Text(_str(s['admission_number']).isEmpty ? 'No admission number' : _str(s['admission_number']),
                                    style: const TextStyle(color: _C.muted2, fontSize: 12.5)),
                              ]),
                            ),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg2,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.indigoGradient)),
        title: const Text('Academic Result Upload', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.pri))
          : _error != null
              ? _errorView()
              : RefreshIndicator(
                  color: _C.pri,
                  onRefresh: () => _load(silent: true),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                    children: [
                      const _TipsBanner(),
                      if (_offline) _offlineNote(),
                      if (_flash != null) _flashBox(),
                      _profileCard(),
                      const SizedBox(height: 12),
                      _reminders(),
                      const SizedBox(height: 14),
                      _steps(),
                      if (_summary.any((e) => e['status'] == 'finalized')) _finalizedWarning(),
                      _periodCard(),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.person_off, size: 56, color: _C.muted2),
            const SizedBox(height: 10),
            const Text('No Student Selected', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _C.muted2)),
            const SizedBox(height: 18),
            ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(backgroundColor: _C.pri, foregroundColor: Colors.white),
                icon: const Icon(Icons.people),
                label: const Text('Go to Students')),
          ]),
        ),
      );

  Widget _offlineNote() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFEAA7))),
        child: const Row(children: [
          Icon(Icons.wifi_off, size: 18, color: Color(0xFF856404)),
          SizedBox(width: 8),
          Expanded(child: Text('Offline — showing saved information.', style: TextStyle(color: Color(0xFF856404), fontSize: 13))),
        ]),
      );

  Widget _flashBox() {
    final e = _flashError;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: e ? _C.err : _C.ok, width: 5)),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(e ? Icons.error : Icons.check_circle, color: e ? _C.err : _C.ok),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e ? 'Error' : 'Success', style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(_flash!, style: const TextStyle(fontSize: 13.5)),
          ]),
        ),
        InkWell(onTap: () => setState(() => _flash = null), child: const Icon(Icons.close, size: 18, color: _C.muted2)),
      ]),
    );
  }

  Widget _meta(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: _C.bg2, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: _C.pri),
          const SizedBox(width: 5),
          Flexible(child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _C.dark))),
        ]),
      );

  Widget _badge(IconData i, String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
        ]),
      );

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(18)}) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: child,
      );

  Widget _profileCard() {
    final adm = _str(_student['admission_number']);
    final dept = _str(_student['department_name']);
    final transferred = _student['transferred'] == true;
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Stack(children: [
            _avatar(_str(_student['image_url']), _str(_student['fullname']), size: 70, ring: _C.pri),
            Positioned(
                right: 2,
                bottom: 2,
                child: Container(
                    width: 14, height: 14, decoration: BoxDecoration(color: _C.ok, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)))),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_str(_student['fullname']), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _C.dark)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (adm.isNotEmpty) _meta(Icons.tag, adm),
                _meta(Icons.badge, 'ID: ${_student['user_id']}'),
                if (dept.isNotEmpty) _meta(Icons.apartment, dept),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _badge(Icons.class_, _str(_student['class_name']).isEmpty ? 'N/A' : _str(_student['class_name']), _C.pri.withAlpha(24), _C.pri),
          transferred
              ? _badge(Icons.swap_horiz, 'Promoted from ${_str(_student['original_class_name'])}', _C.warn.withAlpha(30), const Color(0xFF92400E))
              : _badge(Icons.home, 'Original Class', _C.ok.withAlpha(30), const Color(0xFF047857)),
          _badge(Icons.circle, 'Active Enrollment', _C.ok.withAlpha(30), const Color(0xFF047857)),
        ]),
        if (_summary.isNotEmpty && !_summaryClosed) ...[const SizedBox(height: 14), _history()],
      ]),
    );
  }

  Widget _history() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: _C.pri.withAlpha(14), borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.pri.withAlpha(50))),
        child: Column(children: [
          Row(children: [
            const Icon(Icons.history, size: 18, color: _C.pri),
            const SizedBox(width: 6),
            const Expanded(child: Text('Existing Results History', style: TextStyle(fontWeight: FontWeight.w800, color: _C.priD))),
            InkWell(onTap: () => setState(() => _summaryClosed = true), child: const Icon(Icons.close, size: 18, color: _C.muted2)),
          ]),
          const SizedBox(height: 8),
          ..._summary.map((e) {
            final fin = e['status'] == 'finalized';
            final sn = _str(e['session_name']).isEmpty ? 'Session ${e['session_id']}' : _str(e['session_name']);
            final tn = _str(e['term_name']).isEmpty ? 'Term ${e['term_id']}' : _str(e['term_name']);
            final n = _toInt(e['subject_count']) ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const Icon(Icons.calendar_month, size: 15, color: _C.muted2),
                const SizedBox(width: 6),
                Expanded(child: Text('$sn — $tn  ($n subject${n == 1 ? '' : 's'})', style: const TextStyle(fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(color: fin ? _C.ok.withAlpha(40) : _C.warn.withAlpha(40), borderRadius: BorderRadius.circular(99)),
                  child: Text(fin ? 'Finalized' : 'Draft',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: fin ? const Color(0xFF047857) : const Color(0xFF92400E))),
                ),
              ]),
            );
          }),
        ]),
      );

  Widget _reminders() => Row(children: [
        Expanded(
          child: _reminder(Icons.people, 'Switch Student', _C.pri, () => Navigator.of(context).pop()),
        ),
        const SizedBox(width: 10),
        Expanded(child: _reminder(Icons.groups, 'Class Result', _C.ok, _openClassResult)),
      ]);

  Widget _reminder(IconData i, String t, Color c, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: c, width: 4)),
            boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(children: [
            Icon(i, size: 18, color: c),
            const SizedBox(width: 8),
            Flexible(child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
          ]),
        ),
      );

  Widget _steps() {
    Widget step(int n, String a, String b) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 6)]),
            child: Column(children: [
              Container(
                  width: 28, height: 28, alignment: Alignment.center,
                  decoration: const BoxDecoration(gradient: _C.indigoGradient, shape: BoxShape.circle),
                  child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
              const SizedBox(height: 6),
              Text(a, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              Text(b, textAlign: TextAlign.center, style: const TextStyle(color: _C.muted2, fontSize: 11)),
            ]),
          ),
        );
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      step(1, 'Select Period', 'Choose session & term below'),
      const SizedBox(width: 8),
      step(2, 'Enter Scores', 'Fill subject scores per class'),
      const SizedBox(width: 8),
      step(3, 'Save or Publish', 'Draft or finalize results'),
    ]);
  }

  Widget _finalizedWarning() => Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _C.warn.withAlpha(150)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.lock, size: 18, color: Color(0xFF92400E)),
            SizedBox(width: 8),
            Expanded(child: Text('Some Results Already Finalized', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF78350F)))),
          ]),
          const SizedBox(height: 6),
          const Text.rich(TextSpan(style: TextStyle(color: Color(0xFF78350F), fontSize: 13), children: [
            TextSpan(text: 'This student has '),
            TextSpan(text: 'finalized results', style: TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: '. You can still edit them by selecting the period below — they will open in edit mode.'),
          ])),
          const SizedBox(height: 6),
          ...[
            'Double-check all scores before re-publishing to avoid confusion.',
            'Edits within 30 days of finalization are available to all staff.',
            'After 30 days, only Portal Admins can make changes.',
            'Any changes should be re-finalized from the Result Overview page.',
          ].map((t) => Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('•  ', style: TextStyle(color: Color(0xFF78350F))),
                  Expanded(child: Text(t, style: const TextStyle(color: Color(0xFF78350F), fontSize: 12.5))),
                ]),
              )),
        ]),
      );

  Widget _statusBox() {
    if (_pickError) {
      return _box(Icons.warning_amber, const Color(0xFFEF4444), const Color(0xFF991B1B), const Color(0x14EF4444),
          'Please select both an Academic Session and a Term to continue.', boldPart: 'Please select both');
    }
    if (_selSession == null || _selTerm == null) return const SizedBox.shrink();
    final m = _match;
    if (m == null) {
      return _box(Icons.add_circle, _C.ok, const Color(0xFF065F46), const Color(0x1A10B981),
          'No results yet for this period. A fresh entry form will open.', boldPart: 'No results yet');
    }
    final fin = m['status'] == 'finalized';
    final n = _toInt(m['subject_count']) ?? 0;
    final txt = '${fin ? 'Finalized results found' : 'Draft results found'} — $n subject${n != 1 ? 's' : ''}. '
        '${fin ? 'You can edit these results. Please double-check before re-publishing.' : 'You can continue editing this draft.'}';
    return _box(fin ? Icons.lock_open : Icons.edit_note, fin ? _C.warn : const Color(0xFF818CF8),
        fin ? const Color(0xFF78350F) : _C.priD, fin ? const Color(0x1AF59E0B) : const Color(0x144F46E5), txt,
        boldPart: fin ? 'Finalized results found' : 'Draft results found');
  }

  Widget _box(IconData i, Color border, Color fg, Color bg, String text, {required String boldPart}) {
    final rest = text.startsWith(boldPart) ? text.substring(boldPart.length) : text;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: border, width: 1.5)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(i, color: border, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(TextSpan(style: TextStyle(color: fg, fontSize: 13), children: [
            TextSpan(text: boldPart, style: const TextStyle(fontWeight: FontWeight.w800)),
            TextSpan(text: rest),
          ])),
        ),
      ]),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.bdr, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.bdr, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.pri, width: 1.6)),
      );

  Widget _label(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Icon(i, size: 15, color: _C.pri),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ]),
      );

  Widget _periodCard() => Container(
        margin: const EdgeInsets.only(top: 14),
        child: _card(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _C.bdr))),
              child: Row(children: [
                Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: _C.pri.withAlpha(25), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.calendar_month, color: _C.pri, size: 20)),
                const SizedBox(width: 10),
                const Text('Select Academic Period', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _label(Icons.event_available, 'Academic Session'),
                DropdownButtonFormField<int>(
                  value: _selSession,
                  isExpanded: true,
                  decoration: _dec('— Choose Session —'),
                  items: _sessions.map((s) => DropdownMenuItem<int>(value: _toInt(s['id']), child: Text(_str(s['session_name']), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() {
                    _selSession = v;
                    _pickError = false;
                  }),
                ),
                _label(Icons.schedule, 'Academic Term'),
                DropdownButtonFormField<int>(
                  value: _selTerm,
                  isExpanded: true,
                  decoration: _dec('— Choose Term —'),
                  items: _terms.map((t) => DropdownMenuItem<int>(value: _toInt(t['id']), child: Text(_str(t['term_name']), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() {
                    _selTerm = v;
                    _pickError = false;
                  }),
                ),
                const SizedBox(height: 14),
                _statusBox(),
                const Divider(color: _C.bdr),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Students'),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: _C.pri,
                          side: const BorderSide(color: _C.pri, width: 1.5),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : _continue,
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.arrow_forward, size: 18),
                      label: const Text('Continue to Results', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: _C.pri,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: _C.pri,
                          disabledForegroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    ),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      );
}

/// The scrolling tips strip of upload_results.php ("notification-banner")
class _TipsBanner extends StatefulWidget {
  const _TipsBanner();

  @override
  State<_TipsBanner> createState() => _TipsBannerState();
}

class _TipsBannerState extends State<_TipsBanner> {
  static const _tips = <List<dynamic>>[
    ['⚠️ Fill all subject scores before publishing!', Color(0xFFFFF7E6), Color(0xFF92400E)],
    ["⭐ Don't forget to add Student Traits", Color(0xFFEEF2FF), Color(0xFF3730A3)],
    ["💬 Add Teacher's Comment for complete feedback", Color(0xFFECFDF5), Color(0xFF047857)],
    ['✅ Double-check all scores before FINALIZING!', Color(0xFFFEF2F2), Color(0xFF991B1B)],
    ['📊 Grade & Meaning auto-calculate from total scores', Color(0xFFFFF7E6), Color(0xFF92400E)],
    ['📴 No network? Save anyway — it uploads automatically later', Color(0xFFEEF2FF), Color(0xFF3730A3)],
  ];
  int _i = 0;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _i = (_i + 1) % _tips.length);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _tips[_i];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 400),
        child: Container(
          key: ValueKey(_i),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: t[1] as Color, borderRadius: BorderRadius.circular(12)),
          child: Text(t[0] as String, style: TextStyle(color: t[2] as Color, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN 3 — Subject score entry  (fetch_result_upload.php + process_result_upload.php)
// ═════════════════════════════════════════════════════════════════════════════
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

class _ResultEntryScreen extends StatefulWidget {
  final String token;
  final int studentId, sessionId, termId;
  final String role;
  const _ResultEntryScreen(
      {required this.token, required this.studentId, required this.sessionId, required this.termId, required this.role});

  @override
  State<_ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<_ResultEntryScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _fromCache = false;
  bool _queued = false;
  String? _error;

  Map<String, dynamic> _form = {};
  final List<_Row> _rows = [];
  List<Map<String, dynamic>> _grades = [];
  List<Map<String, dynamic>> _gradeMap = [];
  List<Map<String, dynamic>> _teacherList = [], _propList = [];
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

    // changes made offline are not on the server yet: keep showing what the user saved on the phone
    if (queued) {
      final c = await _Store.get(key);
      if (c is Map) {
        form = Map<String, dynamic>.from(c);
        fromCache = true;
      }
    }
    if (form == null) {
      final r = await _Api.post(widget.token, 'result_form', {
        'student_id': '${widget.studentId}',
        'session_id': '${widget.sessionId}',
        'term_id': '${widget.termId}',
      });
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
        fromCache = true;
        if (form == null) {
          if (!mounted) return;
          setState(() {
            _error = "You're offline and this class has not been downloaded for this session and term. "
                'Connect to the internet, or use “Download for offline” on the students page first.';
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
    _apply(form!, fromCache: fromCache, queued: queued);
  }

  void _apply(Map<String, dynamic> f, {required bool fromCache, required bool queued}) {
    for (final r in _rows) {
      r.dispose();
    }
    _rows
      ..clear()
      ..addAll(_maps(f['rows']).map(_Row.from));
    final gm = _maps(f['grade_map'])
        .map((g) => {
              'min': double.tryParse('${g['min']}') ?? 0.0,
              'max': double.tryParse('${g['max']}') ?? 100.0,
              'grade': _str(g['grade']),
              'meaning': _str(g['meaning']),
            })
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
      _dirty = false;
      _loading = false;
    });
  }

  // ───────────────────────────── calculation (calculateRow) ─────────────────────────────
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
    final c1 = _parseCa(r.ca1.text);
    final c2 = _parseCa(r.ca2.text);
    final ex = double.tryParse(r.exam.text) ?? 0;
    if (!c1.isAbs && c1.num > 20) {
      _toast(context, 'C.A 1 cannot exceed 20', error: true);
      r.ca1.clear();
      setState(() {});
      return;
    }
    if (!c2.isAbs && c2.num > 20) {
      _toast(context, 'C.A 2 cannot exceed 20', error: true);
      r.ca2.clear();
      setState(() {});
      return;
    }
    if (ex > 60) {
      _toast(context, 'Exam score cannot exceed 60', error: true);
      r.exam.clear();
      setState(() {});
      return;
    }
    final total = c1.num + c2.num + ex;
    if (total > 100) {
      _toast(context, 'Total score exceeds 100', error: true);
      return;
    }
    r.total.text = total.toStringAsFixed(2);
    final g = _gradeFor(total);
    final m = _remarkFor(total);
    if (g.isNotEmpty && _grades.any((x) => _str(x['grade']) == g)) r.grade = g;
    if (m.isNotEmpty && _grades.any((x) => _str(x['meaning']) == m)) r.remark = m;
    setState(() {});
  }

  void _addRow() {
    setState(() {
      _rows.add(_Row(fromClass: false));
      _dirty = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
      }
    });
    _toast(context, 'New subject row added');
  }

  Future<void> _removeRow(int i) async {
    final name = _rows[i].subject.text.trim();
    final ok = await _confirm(context, 'Remove subject?', name.isEmpty ? 'Remove this row?' : 'Remove “$name” from this result?',
        yes: 'Remove', destructive: true);
    if (ok != true || !mounted) return;
    setState(() {
      _rows[i].dispose();
      _rows.removeAt(i);
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
        _toast(context, 'Subject “$name” appears twice. Remove one of them.', error: true);
        return null;
      }
      final c1 = _parseCa(r.ca1.text), c2 = _parseCa(r.ca2.text);
      final ex = double.tryParse(r.exam.text) ?? 0;
      if (!c1.isAbs && (c1.num < 0 || c1.num > 20)) {
        _toast(context, "Invalid C.A 1 for '$name' — must be 0–20 or ABS", error: true);
        return null;
      }
      if (!c2.isAbs && (c2.num < 0 || c2.num > 20)) {
        _toast(context, "Invalid C.A 2 for '$name' — must be 0–20 or ABS", error: true);
        return null;
      }
      if (ex < 0 || ex > 60) {
        _toast(context, "Invalid exam score for '$name' — must be 0–60", error: true);
        return null;
      }
      if (c1.num + c2.num + ex > 100) {
        _toast(context, "Total score for '$name' exceeds 100", error: true);
        return null;
      }
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
      _toast(context, 'Please add at least one subject with data', error: true);
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

  /// the screen's current state in the same shape the server returns, so it can be reopened offline
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

  Future<void> _save() async {
    if (_saving) {
      _toast(context, 'Please wait, your results are already being saved...', warn: true);
      return;
    }
    FocusScope.of(context).unfocus();
    final payload = _buildPayload();
    if (payload == null) return;
    final ok = await _confirm(context, 'Save as Draft?',
        'Your progress will be saved and you can continue editing later.\n\nAre you sure?',
        yes: 'Yes, save draft', icon: Icons.help_outline);
    if (ok != true || !mounted) return;

    setState(() => _saving = true);
    final key = _Store.formKey(widget.studentId, widget.sessionId, widget.termId);
    final r = await _Api.postJson(widget.token, 'save_result', payload);
    if (!mounted) return;
    if (r['success'] == true) {
      await _Store.put(key, _snapshot());
      await _Store.removeQueued(await _queuedId() ?? '');
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
      Navigator.of(context).pop('📴 No internet — saved on this phone. It will upload automatically when you are back online.');
    } else {
      setState(() => _saving = false);
      _toast(context, '${r['message']}', error: true);
    }
  }

  Future<String?> _queuedId() async {
    for (final q in await _Store.queue()) {
      if (q['type'] == 'result' && q['student_id'] == widget.studentId && q['session_id'] == widget.sessionId && q['term_id'] == widget.termId) {
        return '${q['id']}';
      }
    }
    return null;
  }

  // ───────────────────────────── sheets ─────────────────────────────
  Future<void> _openTraits() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _TraitsSheet(
          token: widget.token, studentId: widget.studentId, sessionId: widget.sessionId, termId: widget.termId, role: widget.role),
    );
    if (saved == true && mounted) setState(() => _hasTraits = true);
  }

  Future<void> _openComments() async {
    final res = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _CommentsSheet(
          teacher: _teacherComment, proprietor: _proprietorComment, teacherList: _teacherList, propList: _propList, isAdmin: _isAdmin),
    );
    if (res != null && mounted) {
      setState(() {
        _teacherComment = res['teacher'] ?? '';
        if (_isAdmin) _proprietorComment = res['proprietor'] ?? '';
        _dirty = true;
      });
      _toast(context, 'Comments added — they are saved together with the result.');
    }
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirm(context, 'Discard changes?', 'You have unsaved changes on this page.', yes: 'Discard');
        if (ok == true && mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: _C.bg2,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.indigoGradient)),
          title: const Text('Enter Results', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        ),
        floatingActionButton: (_loading || _error != null)
            ? null
            : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                FloatingActionButton.extended(
                  heroTag: 'ru_comments',
                  backgroundColor: _C.pri,
                  foregroundColor: Colors.white,
                  onPressed: _openComments,
                  icon: const Icon(Icons.comment),
                  label: const Text('Comments'),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'ru_traits',
                  backgroundColor: _C.warn,
                  foregroundColor: Colors.white,
                  onPressed: _openTraits,
                  icon: Icon(_hasTraits ? Icons.star : Icons.star_border),
                  label: const Text('Traits'),
                ),
              ]),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _C.pri))
            : _error != null
                ? _errorView()
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 170),
                    children: [
                      _header(),
                      const SizedBox(height: 12),
                      ..._banners(),
                      _gradeStrip(),
                      const SizedBox(height: 12),
                      _subjectsTitle(),
                      if (_rows.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                          child: const Column(children: [
                            Icon(Icons.menu_book, size: 40, color: _C.muted2),
                            SizedBox(height: 8),
                            Text('No subjects are assigned to this class yet. Tap “Add Extra Subject” to add one.',
                                textAlign: TextAlign.center, style: TextStyle(color: _C.muted2)),
                          ]),
                        ),
                      for (var i = 0; i < _rows.length; i++) _rowCard(i, _rows[i]),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: _addRow,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Extra Subject', style: TextStyle(fontWeight: FontWeight.w700)),
                        style: OutlinedButton.styleFrom(
                            foregroundColor: _C.pri,
                            side: const BorderSide(color: _C.pri, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Saving...' : 'Save Draft', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _C.ok,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _C.ok.withAlpha(180),
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outline, size: 54, color: _C.muted2),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _C.dark, fontSize: 15)),
            const SizedBox(height: 18),
            Row(mainAxisSize: MainAxisSize.min, children: [
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Back')),
              const SizedBox(width: 10),
              ElevatedButton(
                  onPressed: _load,
                  style: ElevatedButton.styleFrom(backgroundColor: _C.pri, foregroundColor: Colors.white),
                  child: const Text('Try again')),
            ]),
          ]),
        ),
      );

  Widget _pill(String t, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(t, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _header() {
    final stu = _map(_form['student']);
    final fin = _resultStatus == 'finalized';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: _C.indigoGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: _C.pri.withAlpha(80), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(children: [
        Stack(children: [
          _avatar(_str(stu['image_url']), _str(stu['fullname']), size: 64, ring: Colors.white54),
          Positioned(
              right: 2,
              bottom: 2,
              child: Container(width: 14, height: 14, decoration: BoxDecoration(color: _C.ok, shape: BoxShape.circle, border: Border.all(color: _C.priD, width: 2)))),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_str(stu['fullname']), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _pill(_str(_form['class_name']).isEmpty ? 'N/A' : _str(_form['class_name']), Colors.white24, Colors.white),
              _pill(_str(_form['session_name']), Colors.white24, Colors.white),
              _pill(_str(_form['term_name']), Colors.white24, Colors.white),
              if (_str(stu['department_name']).isNotEmpty) _pill(_str(stu['department_name']), Colors.white24, Colors.white),
              _pill(fin ? 'Finalized — editing' : (_editMode ? 'Draft' : 'New entry'), fin ? _C.warn : Colors.white, fin ? Colors.white : _C.priD),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _banner(IconData i, String t, Color bg, Color fg, {String? bold}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: fg.withAlpha(90))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 19, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(style: TextStyle(color: fg, fontSize: 13), children: [
              if (bold != null) TextSpan(text: '$bold ', style: const TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: t),
            ])),
          ),
        ]),
      );

  List<Widget> _banners() {
    final w = <Widget>[];
    if (_queued) {
      w.add(_banner(Icons.cloud_upload_outlined, 'These changes are saved on this phone and will upload automatically when you are online.',
          _C.pri.withAlpha(20), _C.priD,
          bold: 'Waiting to upload.'));
    } else if (_fromCache) {
      w.add(_banner(Icons.wifi_off, 'Showing information saved on this phone. You can still enter scores and save — they will upload later.',
          const Color(0xFFFFF3CD), const Color(0xFF856404),
          bold: 'Offline.'));
    }
    if (_form['expired_warning'] == true) {
      w.add(_banner(Icons.lock_clock, 'These results were finalized more than 30 days ago. You can edit them because you are the Portal Admin.',
          const Color(0xFFFEF2F2), const Color(0xFF991B1B),
          bold: 'Edit window passed.'));
    }
    if (_resultStatus == 'finalized') {
      w.add(_banner(Icons.info, 'Saving moves these results back to Draft. Re-finalize them from the Result Overview page.',
          const Color(0xFFFFFBEB), const Color(0xFF92400E),
          bold: 'Editing finalized results.'));
    }
    w.add(_banner(Icons.info_outline, 'Type ABS (or ABSENT) in a C.A box for an absent student. It counts as 0 in the total. A blank C.A box also counts as 0.',
        _C.absBg, _C.absColor,
        bold: 'Absent?'));
    return w;
  }

  Widget _gradeStrip() {
    if (_grades.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Grading scale', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: _grades.map((g) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _C.pri.withAlpha(18), borderRadius: BorderRadius.circular(99)),
            child: Text('${_str(g['grade'])}  ${_str(g['score_range'])}  ${_str(g['meaning'])}',
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _C.priD)),
          );
        }).toList()),
      ]),
    );
  }

  Widget _subjectsTitle() {
    final n = _rows.where((r) => r.subject.text.trim().isNotEmpty).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(children: [
        const Icon(Icons.menu_book, size: 18, color: _C.pri),
        const SizedBox(width: 8),
        const Expanded(child: Text('Subject Scores', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
        _pill('$n subject${n == 1 ? '' : 's'}', _C.pri.withAlpha(25), _C.pri),
      ]),
    );
  }

  InputDecoration _fieldDec({String? hint, bool abs = false, bool ro = false}) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: abs ? _C.absBg : (ro ? _C.bg2 : Colors.white),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: abs ? _C.warn : _C.bdr, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: abs ? _C.warn : _C.bdr, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: abs ? _C.warn : _C.pri, width: 1.8)),
      );

  Widget _labelled(String label, Widget child) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _C.muted2))),
        child,
      ]);

  Widget _caField(String label, TextEditingController c, _Row r) {
    final abs = _parseCa(c.text).isAbs;
    return _labelled(
      label,
      TextField(
        controller: c,
        inputFormatters: _caFormatters,
        textCapitalization: TextCapitalization.characters,
        style: TextStyle(fontWeight: abs ? FontWeight.w800 : FontWeight.w500, color: abs ? _C.absColor : _C.dark),
        decoration: _fieldDec(hint: '0–20 / ABS', abs: abs),
        onChanged: (_) => _recalc(r),
      ),
    );
  }

  Widget _numField(String label, TextEditingController c, {void Function(String)? onChanged, String? hint, bool ro = false, bool decimal = true}) {
    return _labelled(
      label,
      TextField(
        controller: c,
        readOnly: ro,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: ro ? null : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: TextStyle(fontWeight: ro ? FontWeight.w800 : FontWeight.w500, color: ro ? _C.priD : _C.dark),
        decoration: _fieldDec(hint: hint, ro: ro),
        onChanged: onChanged ?? (_) => _markDirty(),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> values, List<String> labels, void Function(String?) onChanged) {
    final v = values.contains(value) ? value : null;
    return _labelled(
      label,
      DropdownButtonFormField<String>(
        value: v,
        isExpanded: true,
        decoration: _fieldDec(hint: '— Select —'),
        items: [
          for (var i = 0; i < values.length; i++) DropdownMenuItem<String>(value: values[i], child: Text(labels[i], overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _two(Widget a, Widget b) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 10), Expanded(child: b)]),
      );

  Widget _rowCard(int i, _Row r) {
    // unique options, same as the web <select>s
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
    return Container(
      key: ObjectKey(r),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _C.bdr),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(children: [
        Row(children: [
          Container(
              width: 28, height: 28, alignment: Alignment.center,
              decoration: BoxDecoration(color: _C.pri.withAlpha(25), shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(color: _C.pri, fontWeight: FontWeight.w800, fontSize: 12.5))),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: r.subject,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: _fieldDec(hint: 'Subject name'),
              onChanged: (_) => setState(() => _dirty = true),
            ),
          ),
        ]),
        if (r.type.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6, left: 36),
              child: Text(r.type, style: const TextStyle(color: _C.muted2, fontSize: 11.5)),
            ),
          ),
        _two(_caField('C.A 1 /20 or ABS', r.ca1, r), _caField('C.A 2 /20 or ABS', r.ca2, r)),
        _two(
          _numField('Exam /60', r.exam, hint: '0-60', onChanged: (_) => _recalc(r)),
          _numField('Total /100', r.total, ro: true, hint: 'Auto'),
        ),
        _two(
          _numField('Class Avg', r.avg, hint: 'Class Avg'),
          _dropdown('Grade', r.grade, gradeVals, gradeLabels, (v) => setState(() {
                r.grade = v ?? '';
                _dirty = true;
              })),
        ),
        _two(
          _labelled(
            'Position',
            TextField(
              controller: r.pos,
              decoration: _fieldDec(hint: 'e.g. 1st'),
              onChanged: (_) => _markDirty(),
            ),
          ),
          _numField('Highest', r.hi, hint: 'Highest'),
        ),
        _two(
          _numField('Lowest', r.lo, hint: 'Lowest'),
          _dropdown('Remark', r.remark, remarkVals, remarkVals, (v) => setState(() {
                r.remark = v ?? '';
                _dirty = true;
              })),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => _removeRow(i),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Remove Subject'),
            style: TextButton.styleFrom(foregroundColor: _C.err),
          ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Student Traits  (traits_modal_content.php)
// ═════════════════════════════════════════════════════════════════════════════
class _TraitsSheet extends StatefulWidget {
  final String token, role;
  final int studentId, sessionId, termId;
  const _TraitsSheet(
      {required this.token, required this.studentId, required this.sessionId, required this.termId, required this.role});

  @override
  State<_TraitsSheet> createState() => _TraitsSheetState();
}

class _TraitsSheetState extends State<_TraitsSheet> {
  bool _loading = true;
  bool _saving = false;
  bool _canEdit = true;
  bool _fromCache = false;
  String? _error;
  String _studentName = '';
  List<Map<String, dynamic>> _psyDefs = [], _affDefs = [];
  final Map<int, int> _psy = {}, _aff = {};

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
      final r = await _Api.post(widget.token, 'traits_get', {
        'student_id': '${widget.studentId}',
        'session_id': '${widget.sessionId}',
        'term_id': '${widget.termId}',
      });
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
            _error = "You're offline and the traits for this class were not downloaded.";
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
    final data = d!;
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
      setState(() => m.remove(id)); // tapping the same star again removes the selection
      return;
    }
    if (cur == 0 && m.length >= 5) {
      _alert(context, 'Selection Limit Reached!',
          'You can only select 5 $kind Traits.\nPlease unselect one before selecting another.',
          icon: Icons.warning_amber_rounded, color: _C.warn);
      return;
    }
    setState(() => m[id] = val);
  }

  Future<void> _save() async {
    if (_psy.length != _needP) {
      _alert(context, 'Incomplete Selection!', 'Please select exactly $_needP Psychomotor Traits.\nCurrently selected: ${_psy.length}',
          icon: Icons.error_outline, color: _C.err);
      return;
    }
    if (_aff.length != _needA) {
      _alert(context, 'Incomplete Selection!', 'Please select exactly $_needA Affective Traits.\nCurrently selected: ${_aff.length}',
          icon: Icons.error_outline, color: _C.err);
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
      _toast(context, '${r['message']}');
      Navigator.of(context).pop(true);
    } else if (_isNet(r)) {
      await _Store.put(key, snap());
      await _Store.enqueue({
        'type': 'traits',
        'student_id': widget.studentId,
        'student_name': _studentName,
        'session_id': widget.sessionId,
        'term_id': widget.termId,
        'label': 'Student traits',
        'payload': payload,
      });
      _toast(context, '📴 Traits saved on this phone. They will upload when you are back online.', warn: true);
      Navigator.of(context).pop(true);
    } else {
      setState(() => _saving = false);
      _toast(context, '${r['message']}', error: true);
    }
  }

  Widget _counter(int n, int need) {
    final ok = n == need;
    final over = n > need;
    final c = over ? _C.err : (ok ? _C.ok : _C.warn);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: c.withAlpha(30), borderRadius: BorderRadius.circular(99)),
      child: Text('Selected: $n/$need', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Widget _section(String title, IconData icon, List<Map<String, dynamic>> defs, Map<int, int> sel, int need, String kind) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: _C.pri),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
          _counter(sel.length, need),
        ]),
      ),
      if (defs.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _C.bg2, borderRadius: BorderRadius.circular(10)),
          child: Text('No ${kind.toLowerCase()} traits defined yet.', style: const TextStyle(color: _C.muted2)),
        ),
      ...defs.map((t) {
        final id = _toInt(t['id'])!;
        final cur = sel[id] ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(
            color: cur > 0 ? _C.pri.withAlpha(12) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cur > 0 ? _C.pri.withAlpha(90) : _C.bdr),
          ),
          child: Row(children: [
            Expanded(child: Text(_str(t['name']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
            for (var s = 1; s <= 5; s++)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _canEdit ? () => _rate(sel, id, s, kind) : null,
                child: Padding(
                  padding: const EdgeInsets.all(2.5),
                  child: Icon(s <= cur ? Icons.star : Icons.star_border,
                      size: 25, color: s <= cur ? const Color(0xFFFF5722) : (_canEdit ? const Color(0xFFBDBDBD) : const Color(0xFFE0E0E0))),
                ),
              ),
          ]),
        );
      }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .5,
      maxChildSize: .97,
      builder: (_, sc) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 44, height: 4, decoration: BoxDecoration(color: _C.bdr, borderRadius: BorderRadius.circular(4))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 0),
          child: Row(children: [
            const Icon(Icons.star, color: _C.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Student Traits Assessment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                if (_studentName.isNotEmpty) Text(_studentName, style: const TextStyle(color: _C.muted2, fontSize: 12.5)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _C.pri))
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _C.muted2))))
                  : ListView(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        if (_fromCache)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(10)),
                            child: const Text('Showing information saved on this phone.', style: TextStyle(color: Color(0xFF856404), fontSize: 12.5)),
                          ),
                        if (!_canEdit)
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: _C.bg2, borderRadius: BorderRadius.circular(10)),
                            child: const Row(children: [
                              Icon(Icons.lock, size: 16, color: _C.muted2),
                              SizedBox(width: 8),
                              Expanded(child: Text('Traits are already saved. Only the portal admin can change them.', style: TextStyle(color: _C.muted2, fontSize: 12.5))),
                            ]),
                          ),
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: _C.pri.withAlpha(16), borderRadius: BorderRadius.circular(10)),
                          child: const Text('Pick 5 traits in each group and rate each from 1 to 5 stars. Tap the same star again to remove it.',
                              style: TextStyle(color: _C.priD, fontSize: 12.5)),
                        ),
                        _section('Psychomotor Traits', Icons.directions_run, _psyDefs, _psy, _needP, 'Psychomotor'),
                        _section('Affective Traits', Icons.favorite, _affDefs, _aff, _needA, 'Affective'),
                        const SizedBox(height: 14),
                        if (_canEdit)
                          ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save),
                            label: Text(_saving ? 'Saving...' : 'Save Traits', style: const TextStyle(fontWeight: FontWeight.w800)),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _C.pri,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _C.pri.withAlpha(180),
                                disabledForegroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          ),
                      ],
                    ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  Comments (teacher + proprietor, with predefined comments)
// ═════════════════════════════════════════════════════════════════════════════
class _CommentsSheet extends StatefulWidget {
  final String teacher, proprietor;
  final List<Map<String, dynamic>> teacherList, propList;
  final bool isAdmin;
  const _CommentsSheet(
      {required this.teacher, required this.proprietor, required this.teacherList, required this.propList, required this.isAdmin});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  late final TextEditingController _t = TextEditingController(text: widget.teacher);
  late final TextEditingController _p = TextEditingController(text: widget.proprietor);

  @override
  void dispose() {
    _t.dispose();
    _p.dispose();
    super.dispose();
  }

  Future<void> _pick(List<Map<String, dynamic>> list, TextEditingController target, String title) async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _PredefinedSheet(title: title, items: list),
    );
    if (chosen != null) setState(() => target.text = chosen);
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.bdr, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.bdr, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.pri, width: 1.8)),
      );

  Widget _block(String title, IconData icon, TextEditingController c, List<Map<String, dynamic>> list, String pickTitle) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Icon(icon, size: 17, color: _C.pri),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
          TextButton.icon(
            onPressed: () => _pick(list, c, pickTitle),
            icon: const Icon(Icons.list_alt, size: 16),
            label: const Text('Predefined'),
          ),
        ]),
      ),
      TextField(controller: c, minLines: 3, maxLines: 6, textCapitalization: TextCapitalization.sentences, decoration: _dec('Write a comment...')),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: _C.bdr, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.comment, color: _C.pri),
            const SizedBox(width: 8),
            const Expanded(child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          _block("Teacher's Comment", Icons.person, _t, widget.teacherList, "Teacher's predefined comments"),
          if (widget.isAdmin) _block("Proprietor's Comment", Icons.school, _p, widget.propList, "Proprietor's predefined comments"),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, {'teacher': _t.text.trim(), 'proprietor': _p.text.trim()}),
            icon: const Icon(Icons.check),
            label: const Text('Save Comments', style: TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
                backgroundColor: _C.pri,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
        ]),
      ),
    );
  }
}

class _PredefinedSheet extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  const _PredefinedSheet({required this.title, required this.items});

  @override
  State<_PredefinedSheet> createState() => _PredefinedSheetState();
}

class _PredefinedSheetState extends State<_PredefinedSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.items.where((e) => _str(e['comment_text']).toLowerCase().contains(_q.toLowerCase())).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (_, sc) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 44, height: 4, decoration: BoxDecoration(color: _C.bdr, borderRadius: BorderRadius.circular(4))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 6),
          child: Row(children: [
            Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: InputDecoration(
              hintText: 'Search comments...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor: _C.bg2,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? const Center(child: Text('No comments found', style: TextStyle(color: _C.muted2)))
              : ListView.builder(
                  controller: sc,
                  padding: const EdgeInsets.all(14),
                  itemCount: list.length,
                  itemBuilder: (_, i) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(context, _str(list[i]['comment_text'])),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: _C.bg2, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.bdr)),
                      child: Text(_str(list[i]['comment_text']), style: const TextStyle(fontSize: 13.5)),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  OFFLINE: download a class for a session + term
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

  Future<void> _download() async {
    if (_sess == null || _term == null || _cls == null) {
      _toast(context, 'Choose a session, a term and a class first.', error: true);
      return;
    }
    setState(() => _busy = true);
    final r = await _Api.post(widget.token, 'offline_bundle', {'session_id': '$_sess', 'term_id': '$_term', 'class_id': '$_cls'}, 90);
    if (!mounted) return;
    if (r['success'] == true) {
      final d = _map(r['data']);
      await _Store.saveBundle(d);
      await _reload();
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(context, 'Downloaded ${(d['students'] as List).length} students. You can now work offline.');
    } else {
      setState(() => _busy = false);
      _toast(context, _isNet(r) ? 'No internet connection. Connect and try again.' : '${r['message']}', error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> e) async {
    final ok = await _confirm(context, 'Remove download?', 'Remove “${_str(e['label'])}” from this phone?', yes: 'Remove', destructive: true);
    if (ok != true) return;
    await _Store.deleteBundle('${e['key']}');
    await _reload();
  }

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: _C.mist,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    final noData = widget.sessions.isEmpty || widget.terms.isEmpty || widget.classes.isEmpty;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      minChildSize: .5,
      maxChildSize: .95,
      builder: (_, sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        children: [
          Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: _C.bdr, borderRadius: BorderRadius.circular(4)))),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.cloud_download, color: _C.blue),
            const SizedBox(width: 8),
            const Expanded(child: Text('Download for offline use', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const Text(
              'Save one class for a session and term on this phone: students, subjects, existing scores, comments and traits. '
              'Then you can enter results with no network and they upload automatically later.',
              style: TextStyle(color: _C.muted, fontSize: 13)),
          const SizedBox(height: 14),
          if (noData)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(10)),
              child: const Text('Sessions, terms and classes are not loaded yet. Connect to the internet and reopen this page.',
                  style: TextStyle(color: Color(0xFF856404), fontSize: 13)),
            )
          else ...[
            DropdownButtonFormField<int>(
              value: _sess,
              isExpanded: true,
              decoration: _dec('— Session —'),
              items: widget.sessions.map((s) => DropdownMenuItem<int>(value: _toInt(s['id']), child: Text(_str(s['session_name'])))).toList(),
              onChanged: (v) => setState(() => _sess = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _term,
              isExpanded: true,
              decoration: _dec('— Term —'),
              items: widget.terms.map((t) => DropdownMenuItem<int>(value: _toInt(t['id']), child: Text(_str(t['term_name'])))).toList(),
              onChanged: (v) => setState(() => _term = v),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              value: _cls,
              isExpanded: true,
              decoration: _dec('— Class —'),
              items: widget.classes.map((c) => DropdownMenuItem<int>(value: _toInt(c['class_id']), child: Text(_str(c['class_name'])))).toList(),
              onChanged: (v) => setState(() => _cls = v),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _busy ? null : _download,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download),
              label: Text(_busy ? 'Downloading…' : 'Download class', style: const TextStyle(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _C.blue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _C.blue.withAlpha(170),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ],
          const SizedBox(height: 22),
          const Text('On this phone', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          if (_bundles.isEmpty) const Text('Nothing downloaded yet.', style: TextStyle(color: _C.muted)),
          ..._bundles.map((e) {
            final dt = DateTime.tryParse(_str(e['saved_at']));
            final when = dt == null ? '' : '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              decoration: BoxDecoration(color: _C.mist, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_str(e['label']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text('${e['count']} students · saved $when', style: const TextStyle(color: _C.muted, fontSize: 12)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Refresh this download',
                  icon: const Icon(Icons.refresh, color: _C.blue),
                  onPressed: _busy
                      ? null
                      : () {
                          setState(() {
                            _sess = _toInt(e['session_id']);
                            _term = _toInt(e['term_id']);
                            _cls = _toInt(e['class_id']);
                          });
                          _download();
                        },
                ),
                IconButton(tooltip: 'Remove', icon: const Icon(Icons.delete_outline, color: _C.danger), onPressed: () => _delete(e)),
              ]),
            );
          }),
          const SizedBox(height: 6),
          const Text('Tip: download again before going offline to get the latest scores. Downloading replaces the older copy.',
              style: TextStyle(color: _C.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  OFFLINE: results waiting to upload
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
    if (r.synced > 0) _toast(context, '${r.synced} uploaded successfully ✔');
    if (r.offline) _toast(context, 'Still offline. Your work is safe on this phone.', warn: true);
    if (r.authFailed) _toast(context, 'Session expired. Please log out and log in again.', error: true);
    if (r.failed > 0) _toast(context, '${r.failed} could not be uploaded. See the red messages below.', error: true);
  }

  Future<void> _discard(Map<String, dynamic> e) async {
    final ok = await _confirm(context, 'Discard this item?', 'It has not been uploaded and will be lost.', yes: 'Discard', destructive: true);
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
      builder: (_, sc) => Column(children: [
        const SizedBox(height: 10),
        Container(width: 44, height: 4, decoration: BoxDecoration(color: _C.bdr, borderRadius: BorderRadius.circular(4))),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 8, 6),
          child: Row(children: [
            const Icon(Icons.cloud_upload, color: _C.blue),
            const SizedBox(width: 8),
            const Expanded(child: Text('Waiting to upload', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
        ),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Everything is uploaded. ✔\nResults you save without internet will appear here.',
                          textAlign: TextAlign.center, style: TextStyle(color: _C.muted))))
              : ListView.builder(
                  controller: sc,
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final e = _items[i];
                    final err = e['error'] != null;
                    final isTraits = e['type'] == 'traits';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      decoration: BoxDecoration(
                        color: err ? const Color(0xFFFEF2F2) : _C.mist,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: err ? _C.err.withAlpha(120) : _C.sky.withAlpha(90)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(isTraits ? Icons.star : Icons.assignment, color: err ? _C.err : _C.blue),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_str(e['student_name']).isEmpty ? 'Student ${e['student_id']}' : _str(e['student_name']),
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text(_str(e['label']), style: const TextStyle(color: _C.muted, fontSize: 12.5)),
                            if (err)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Not uploaded: ${e['error']}', style: const TextStyle(color: _C.err, fontSize: 12.5, fontWeight: FontWeight.w600)),
                              ),
                          ]),
                        ),
                        IconButton(tooltip: 'Discard', icon: const Icon(Icons.delete_outline, color: _C.danger), onPressed: () => _discard(e)),
                      ]),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_busy || _items.isEmpty) ? null : _sync,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync),
              label: Text(_busy ? 'Uploading…' : 'Sync now', style: const TextStyle(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _C.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
          ),
        ),
      ]),
    );
  }
}
