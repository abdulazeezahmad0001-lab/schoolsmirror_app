// flutter_assign_subject_screen.dart
// Mirrors admin_assign_subject.php 1:1:
//  • Class / Session / Term filters (+ active-filter pills, Clear Filters)
//  • Assign / Reassign list: pre-checked already-assigned subjects, Minutes + Total Score inputs,
//    subject ON/OFF, "N taken" warning, reassign-mode banner, confirm dialog, 10 per page
//  • Assigned Subjects table: progress (students taken), status, ON/OFF, delete, 12 per page
//  • Delete All Assigned (scoped to the filters) and the Help sheet
// API: https://schoolsmirror.com/flutter_assign_subjects.php  (upload flutter_assign_subjects.php)

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// Your host redirects "*.php" to the extensionless address and a redirect turns POST into GET
// (form data lost -> "Missing token"). The extensionless URL is tried first; the app switches
// to the other form automatically if one of them fails.
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_assign_subjects',
  'https://schoolsmirror.com/flutter_assign_subjects.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

// ---- palette (same :root variables as the web page) ----
const Color _primary = Color(0xFF4361ee);
const Color _secondary = Color(0xFF3f37c9);
const Color _dark = Color(0xFF1a1a2e);
const Color _success = Color(0xFF4caf50);
const Color _warning = Color(0xFFff9800);
const Color _danger = Color(0xFFf44336);
const Color _muted = Color(0xFF8a8f9c);
const Color _line = Color(0xFFe2e6ee);
const LinearGradient _grad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_primary, _secondary],
);
const TextStyle _fieldStyle = TextStyle(fontSize: 14, color: _dark);

/// The app theme can be dark; this page always uses a light theme so text is readable.
ThemeData _lightTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFf5f7fa),
    canvasColor: Colors.white,
    cardColor: Colors.white,
    colorScheme: base.colorScheme.copyWith(primary: _primary, surface: Colors.white, onSurface: _dark),
    textTheme: base.textTheme.apply(bodyColor: _dark, displayColor: _dark),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: _primary),
  );
}

// ───────────────────────────── helpers ─────────────────────────────
int _int(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

String _friendly(Object e) {
  final s = e.toString();
  if (e is TimeoutException) return 'Request timed out. Please try again.';
  if (e is http.ClientException || s.contains('Failed to fetch') || s.contains('SocketException')) {
    return 'Cannot reach the server. Check your internet connection.';
  }
  return s.replaceFirst('Exception: ', '');
}

class _Api {
  static bool _retry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' ||
            m.startsWith('The server received this request as') ||
            m.startsWith('Missing token'));
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected server response'};
  }

  /// POST. token + action (and small fields) are ALSO put in the URL so they survive a redirect
  /// that drops the body. Pass queryToo:false for large bodies (assign_subjects).
  static Future<Map<String, dynamic>> call(
    String token,
    String action, [
    Map<String, String> fields = const {},
    bool queryToo = true,
  ]) async {
    Object? err;
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        final uri = Uri.parse(_apiUrl).replace(queryParameters: {
          'token': token,
          'action': action,
          if (queryToo) ...fields,
        });
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
              body: {'token': token, 'action': action, ...fields},
            )
            .timeout(const Duration(seconds: 40));
        final d = _decode(res.body);
        if (_retry(d) && _apiIdx < _apiUrls.length - 1) {
          _apiIdx++;
          continue;
        }
        return d;
      } catch (e) {
        err = e;
        if (_apiIdx < _apiUrls.length - 1) {
          _apiIdx++;
          continue;
        }
      }
    }
    throw Exception(_friendly(err ?? 'Request failed'));
  }
}

// ───────────────────────────── SCREEN ─────────────────────────────
class FlutterAssignSubjectScreen extends StatefulWidget {
  final String? token;
  const FlutterAssignSubjectScreen({super.key, this.token});

  @override
  State<FlutterAssignSubjectScreen> createState() => _FlutterAssignSubjectScreenState();
}

class _FlutterAssignSubjectScreenState extends State<FlutterAssignSubjectScreen> {
  String? _token;

  // filters
  List<Map<String, dynamic>> _classes = [], _sessions = [], _terms = [];
  int? _classId, _sessionId, _termId;
  bool _loadingData = true;
  String? _dataError;

  // assign list
  List<Map<String, dynamic>> _subjects = [];
  bool _loadingSubjects = false;
  String? _subjectsError;
  int _sPage = 1, _sTotalPages = 1, _sTotal = 0, _sFrom = 0, _sTo = 0;
  int _subjSeq = 0;
  final Map<int, bool> _sel = {}; // subject id -> checked (kept across pages)
  final Map<int, Map<String, dynamic>> _meta = {}; // subject id -> {name, assigned}
  final Map<int, TextEditingController> _durCtrl = {};
  final Map<int, TextEditingController> _scoreCtrl = {};

  // assigned table
  List<Map<String, dynamic>> _assigned = [];
  bool _loadingAssigned = false;
  String? _assignedError;
  int _aPage = 1, _aTotalPages = 1, _aTotal = 0, _aFrom = 0, _aTo = 0;
  int _assignedSeq = 0;

  bool _saving = false;
  bool _deletingAll = false;
  final _scroll = ScrollController();

  bool get _filtersComplete => _classId != null && _sessionId != null && _termId != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in _durCtrl.values) {
      c.dispose();
    }
    for (final c in _scoreCtrl.values) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) return widget.token!.trim();
    try {
      await ApiClient.loadToken();
      final t = ApiClient.token;
      if (t != null && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      final t = p.getString('auth_token') ?? p.getString('token');
      if (t != null && t.trim().isNotEmpty) return t.trim();
    } catch (_) {}
    return null;
  }

  void _toast(String msg, {Color color = _success}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ───────────────────────────── loading ─────────────────────────────
  Future<void> _init() async {
    setState(() {
      _loadingData = true;
      _dataError = null;
    });
    try {
      _token = await _getToken();
      if (_token == null) throw Exception('Session expired. Please log in again.');
      final r = await _Api.call(_token!, 'load_data');
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load');
      final d = (r['data'] as Map?) ?? {};
      if (!mounted) return;
      setState(() {
        _classes = _maps(d['classes']);
        _sessions = _maps(d['sessions']);
        _terms = _maps(d['terms']);
        _loadingData = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dataError = _friendly(e);
        _loadingData = false;
      });
    }
  }

  void _resetSelection() {
    final old = [..._durCtrl.values, ..._scoreCtrl.values];
    _durCtrl.clear();
    _scoreCtrl.clear();
    _sel.clear();
    _meta.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in old) {
        c.dispose();
      }
    });
  }

  void _onFilterChanged() {
    setState(() {
      _resetSelection();
      _subjects = [];
      _assigned = [];
      _subjectsError = null;
      _assignedError = null;
    });
    if (_filtersComplete) {
      _loadSubjects(page: 1);
      _loadAssigned(page: 1);
    }
  }

  void _clearFilters() {
    setState(() {
      _classId = _sessionId = _termId = null;
    });
    _onFilterChanged();
  }

  Future<void> _loadSubjects({int page = 1}) async {
    if (!_filtersComplete || _token == null) return;
    final seq = ++_subjSeq;
    setState(() {
      _loadingSubjects = true;
      _subjectsError = null;
    });
    try {
      final r = await _Api.call(_token!, 'load_subjects', {
        'class_id': '$_classId',
        'session_id': '$_sessionId',
        'term_id': '$_termId',
        'page': '$page',
      });
      if (seq != _subjSeq || !mounted) return;
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load subjects');
      final d = (r['data'] as Map?) ?? {};
      final list = _maps(d['subjects']);
      setState(() {
        _subjects = list;
        _sPage = _int(d['page']) == 0 ? 1 : _int(d['page']);
        _sTotalPages = math.max(1, _int(d['total_pages']));
        _sTotal = _int(d['total']);
        _sFrom = _int(d['from']);
        _sTo = _int(d['to']);
        for (final s in list) {
          final id = _int(s['id']);
          final assigned = s['is_assigned'] == true;
          _meta[id] = {'name': '${s['subject_name']}', 'assigned': assigned};
          // already-assigned subjects come pre-checked (unless the user unchecked them)
          _sel.putIfAbsent(id, () => assigned);
          _durCtrl.putIfAbsent(id, () => TextEditingController(text: '${_int(s['duration']) == 0 ? 60 : _int(s['duration'])}'));
          _scoreCtrl.putIfAbsent(id, () => TextEditingController(text: '${_int(s['total_score']) == 0 ? 100 : _int(s['total_score'])}'));
        }
        _loadingSubjects = false;
      });
    } catch (e) {
      if (seq != _subjSeq || !mounted) return;
      setState(() {
        _subjectsError = _friendly(e);
        _loadingSubjects = false;
      });
    }
  }

  Future<void> _loadAssigned({int page = 1}) async {
    if (!_filtersComplete || _token == null) return;
    final seq = ++_assignedSeq;
    setState(() {
      _loadingAssigned = true;
      _assignedError = null;
    });
    try {
      final r = await _Api.call(_token!, 'load_assigned', {
        'class_id': '$_classId',
        'session_id': '$_sessionId',
        'term_id': '$_termId',
        'page': '$page',
      });
      if (seq != _assignedSeq || !mounted) return;
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load assignments');
      final d = (r['data'] as Map?) ?? {};
      setState(() {
        _assigned = _maps(d['assigned']);
        _aPage = _int(d['page']) == 0 ? 1 : _int(d['page']);
        _aTotalPages = math.max(1, _int(d['total_pages']));
        _aTotal = _int(d['total']);
        _aFrom = _int(d['from']);
        _aTo = _int(d['to']);
        _loadingAssigned = false;
      });
    } catch (e) {
      if (seq != _assignedSeq || !mounted) return;
      setState(() {
        _assignedError = _friendly(e);
        _loadingAssigned = false;
      });
    }
  }

  // ───────────────────────────── actions ─────────────────────────────
  int get _selectedCount => _sel.values.where((v) => v).length;
  bool get _reassignMode => _sel.entries.any((e) => e.value && (_meta[e.key]?['assigned'] == true));

  Future<void> _notice(String title, String text, {IconData icon = Icons.info, Color color = _primary, bool autoClose = false}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        if (autoClose) {
          Timer(const Duration(seconds: 4), () {
            if (ctx.mounted && Navigator.of(ctx).canPop()) Navigator.of(ctx).pop();
          });
        }
        return Theme(
          data: _lightTheme(),
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Column(children: [
              Icon(icon, size: 52, color: color),
              const SizedBox(height: 10),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
            ]),
            content: Text(text, textAlign: TextAlign.center),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _confirm({
    required String title,
    required Widget body,
    required String yes,
    Color yesColor = _success,
    IconData icon = Icons.help_outline,
    Color iconColor = _primary,
  }) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: _lightTheme(),
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(children: [
            Icon(icon, size: 52, color: iconColor),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20)),
          ]),
          content: SingleChildScrollView(child: body),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: yesColor, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(yes),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFe74c3c), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
    return r == true;
  }

  String _nameOf(List<Map<String, dynamic>> list, String idKey, String nameKey, int? id) {
    for (final m in list) {
      if (_int(m[idKey]) == id) return '${m[nameKey]}';
    }
    return '';
  }

  Future<void> _submit() async {
    final ids = _sel.entries.where((e) => e.value).map((e) => e.key).toList()..sort();
    if (ids.isEmpty) {
      await _notice('No Subjects Selected', 'Please select at least one subject to assign or update.');
      return;
    }
    // same limits as the web form inputs
    for (final id in ids) {
      final d = int.tryParse(_durCtrl[id]?.text.trim() ?? '') ?? 0;
      final sc = int.tryParse(_scoreCtrl[id]?.text.trim() ?? '') ?? 0;
      final name = '${_meta[id]?['name'] ?? 'subject $id'}';
      if (d < 1 || d > 300) {
        _toast('$name: Minutes must be between 1 and 300.', color: _danger);
        return;
      }
      if (sc < 1 || sc > 100) {
        _toast('$name: Total Score must be between 1 and 100.', color: _danger);
        return;
      }
    }
    final existing = ids.where((id) => _meta[id]?['assigned'] == true).length;
    final hasExisting = existing > 0;
    final hasNew = existing < ids.length;

    final ok = await _confirm(
      title: hasExisting ? 'Assign / Reassign Subjects?' : 'Assign Subjects?',
      icon: hasExisting ? Icons.warning_amber_rounded : Icons.help_outline,
      iconColor: hasExisting ? _warning : _primary,
      yes: hasExisting ? 'Yes, Assign & Update!' : 'Yes, Assign!',
      body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'You are about to assign '),
          TextSpan(text: '${ids.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' subject(s) to:'),
        ])),
        const SizedBox(height: 8),
        _kv('Class:', _nameOf(_classes, 'class_id', 'class_name', _classId)),
        _kv('Session:', _nameOf(_sessions, 'id', 'session_name', _sessionId)),
        _kv('Term:', _nameOf(_terms, 'id', 'term_name', _termId)),
        if (hasExisting) ...[
          const SizedBox(height: 12),
          Text(
            hasNew
                ? '↻ $existing existing subject(s) will be UPDATED.'
                : '↻ All selected subjects are already assigned and will be UPDATED.',
            style: const TextStyle(color: Color(0xFFf39c12), fontWeight: FontWeight.w600),
          ),
        ],
      ]),
    );
    if (!ok) return;

    setState(() => _saving = true);
    try {
      final fields = <String, String>{
        'class_id': '$_classId',
        'session_id': '$_sessionId',
        'term_id': '$_termId',
      };
      for (var i = 0; i < ids.length; i++) {
        final id = ids[i];
        fields['subjects[$i]'] = '$id';
        fields['durations[$id]'] = _durCtrl[id]!.text.trim();
        fields['total_scores[$id]'] = _scoreCtrl[id]!.text.trim();
      }
      final r = await _Api.call(_token!, 'assign_subjects', fields, false);
      if (!mounted) return;
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to process request.');
      final d = (r['data'] as Map?) ?? {};
      final isSuccess = d['status'] == 'success';
      await _notice(isSuccess ? 'Success' : 'Info', '${r['message']}',
          icon: isSuccess ? Icons.check_circle : Icons.info, color: isSuccess ? _success : _primary, autoClose: isSuccess);
      if (isSuccess) {
        setState(_resetSelection);
        await Future.wait([_loadSubjects(page: 1), _loadAssigned(page: 1)]);
      }
    } catch (e) {
      if (mounted) await _notice('Error', _friendly(e), icon: Icons.error, color: _danger);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$k ', style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: v),
        ])),
      );

  Future<void> _toggleSubject(Map<String, dynamic> s) async {
    try {
      final r = await _Api.call(_token!, 'toggle_subject', {'subject_id': '${s['id']}', 'current_status': '${s['subject_status']}'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed');
      final st = '${(r['data'] as Map)['status']}';
      if (!mounted) return;
      setState(() => s['subject_status'] = st);
      _toast('Subject ${st == 'active' ? 'activated' : 'deactivated'}!', color: st == 'active' ? _success : _warning);
    } catch (e) {
      _toast(_friendly(e), color: _danger);
    }
  }

  Future<void> _toggleAssigned(Map<String, dynamic> a) async {
    try {
      final r = await _Api.call(_token!, 'toggle_assigned', {'assignment_id': '${a['assignment_id']}', 'current_status': '${a['status']}'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed');
      final st = '${(r['data'] as Map)['status']}';
      if (!mounted) return;
      setState(() => a['status'] = st);
      _toast('Assignment ${st == 'active' ? 'activated' : 'deactivated'}!', color: st == 'active' ? _success : _warning);
    } catch (e) {
      _toast(_friendly(e), color: _danger);
    }
  }

  Future<void> _deleteAssignment(Map<String, dynamic> a) async {
    final ok = await _confirm(
      title: 'Delete Assignment?',
      icon: Icons.warning_amber_rounded,
      iconColor: _warning,
      yes: 'Yes, Delete!',
      yesColor: const Color(0xFFd33333),
      body: const Text('This will remove this subject from the assigned list. This action cannot be undone!', textAlign: TextAlign.center),
    );
    if (!ok) return;
    try {
      final r = await _Api.call(_token!, 'delete_assignment', {'assignment_id': '${a['assignment_id']}'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to delete assignment');
      _toast('Assignment deleted successfully!');
      await Future.wait([_loadAssigned(page: 1), _loadSubjects(page: 1)]);
    } catch (e) {
      _toast(_friendly(e), color: _danger);
    }
  }

  Future<void> _deleteAll() async {
    if (!_filtersComplete) {
      await _notice('Select Filters First', 'Please select Class, Session and Term before deleting.');
      return;
    }
    if (_aTotal == 0) {
      await _notice('No Assignments', 'There are no assignments to delete for the selected filters.');
      return;
    }
    final ok = await _confirm(
      title: 'Delete All Assigned Subjects?',
      icon: Icons.cancel,
      iconColor: _danger,
      yes: 'Yes, Delete All',
      yesColor: const Color(0xFFd33333),
      body: Text(
        'You are about to delete $_aTotal assignment(s) for the selected Class/Session/Term. This cannot be undone!',
        textAlign: TextAlign.center,
      ),
    );
    if (!ok) return;
    setState(() => _deletingAll = true);
    try {
      final r = await _Api.call(_token!, 'delete_all', {
        'class_id': '$_classId',
        'session_id': '$_sessionId',
        'term_id': '$_termId',
      });
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to delete');
      if (!mounted) return;
      await _notice('Deleted!', 'All assigned subjects removed.', icon: Icons.check_circle, color: _success);
      await Future.wait([_loadAssigned(page: 1), _loadSubjects(page: 1)]);
    } catch (e) {
      _toast(_friendly(e), color: _danger);
    } finally {
      if (mounted) setState(() => _deletingAll = false);
    }
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _lightTheme(),
      child: Scaffold(
        backgroundColor: const Color(0xFFf5f7fa),
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: _grad)),
          title: const Text('Assign Subjects', style: TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _init();
                if (_filtersComplete) _onFilterChanged();
              },
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _showHelp,
          backgroundColor: _primary,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.help_outline),
          label: const Text('Help', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFf5f7fa), Color(0xFFe4e8f0)],
            ),
          ),
          child: _loadingData
              ? const Center(child: CircularProgressIndicator(color: _primary))
              : _dataError != null
                  ? _errorBox(_dataError!, _init)
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _pageHeader(),
                            _filterCard(),
                            if (_filtersComplete) ...[_assignCard(), _assignedCard()],
                          ]),
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  Widget _errorBox(String msg, VoidCallback retry) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: _danger, size: 44),
            const SizedBox(height: 10),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(color: _danger)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
              onPressed: retry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );

  Widget _pageHeader() => Container(
        margin: const EdgeInsets.only(bottom: 22),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
        decoration: BoxDecoration(
          gradient: _grad,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 5))],
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.menu_book, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text('Subject Assignment System',
                  style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w600)),
            ),
          ]),
          SizedBox(height: 6),
          Text(
            'Assign or Reassign subjects to a Class, Session & Term — existing assignments will be updated with new settings.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ]),
      );

  // ---------------------------- generic card ----------------------------
  Widget _card({required IconData icon, required String title, String? scope, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.04)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 5))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black.withOpacity(0.05)))),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
            Icon(icon, color: _primary, size: 20),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
            if (scope != null && scope.isNotEmpty) Text(scope, style: const TextStyle(fontSize: 12, color: _muted)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(20), child: child),
      ]),
    );
  }

  Widget _pill(String text, Color bg, Color fg, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 4)],
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ]),
      );

  Widget _emptyState(IconData icon, String title, [String? text, Color iconColor = const Color(0xFFdfe3ec)]) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
        child: Column(children: [
          Icon(icon, size: 48, color: iconColor),
          const SizedBox(height: 12),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, color: Color(0xFF495057), fontWeight: FontWeight.w600)),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 14)),
          ],
        ]),
      );

  // ---------------------------- filters ----------------------------
  InputDecoration _selectDec() => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _line, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _primary, width: 1.5)),
      );

  Widget _filterDropdown(String label, int? value, List<Map<String, dynamic>> items, String idKey, String nameKey, ValueChanged<int?> onChanged) {
    final has = items.any((m) => _int(m[idKey]) == value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF555555), fontSize: 13)),
      ),
      DropdownButtonFormField<int>(
        value: has ? value : null,
        isExpanded: true,
        decoration: _selectDec(),
        style: _fieldStyle,
        dropdownColor: Colors.white,
        menuMaxHeight: 320,
        hint: Text('-- Select $label --', style: const TextStyle(color: Color(0xFF9ca3af), fontSize: 14)),
        items: [for (final m in items) DropdownMenuItem(value: _int(m[idKey]), child: Text('${m[nameKey]}', overflow: TextOverflow.ellipsis))],
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _filterCard() {
    final cls = _nameOf(_classes, 'class_id', 'class_name', _classId);
    final ses = _nameOf(_sessions, 'id', 'session_name', _sessionId);
    final trm = _nameOf(_terms, 'id', 'term_name', _termId);
    return _card(
      icon: Icons.filter_alt,
      title: 'Select Class, Session & Term',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 640 ? 3 : 1;
          final w = (c.maxWidth - 16 * (cols - 1)) / cols;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            SizedBox(
              width: w,
              child: _filterDropdown('Class', _classId, _classes, 'class_id', 'class_name', (v) {
                _classId = v;
                _onFilterChanged();
              }),
            ),
            SizedBox(
              width: w,
              child: _filterDropdown('Session', _sessionId, _sessions, 'id', 'session_name', (v) {
                _sessionId = v;
                _onFilterChanged();
              }),
            ),
            SizedBox(
              width: w,
              child: _filterDropdown('Term', _termId, _terms, 'id', 'term_name', (v) {
                _termId = v;
                _onFilterChanged();
              }),
            ),
          ]);
        }),
        const SizedBox(height: 16),
        if (!_filtersComplete)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFe6f0ff), borderRadius: BorderRadius.circular(10)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info, size: 18, color: _primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Select a Class, Session and Term above to view and assign subjects for that combination.',
                  style: TextStyle(color: Color(0xFF334155), fontSize: 13),
                ),
              ),
            ]),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.check_circle, size: 18, color: _primary),
            const Text('Showing:', style: TextStyle(fontSize: 13)),
            _pill(cls, const Color(0xFFe6f0ff), _primary),
            _pill(ses, const Color(0xFFe6f0ff), _primary),
            _pill(trm, const Color(0xFFe6f0ff), _primary),
            InkWell(
              onTap: _clearFilters,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text('Clear Filters', style: TextStyle(color: _primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline, fontSize: 13)),
              ),
            ),
          ]),
      ]),
    );
  }

  // ---------------------------- assign / reassign ----------------------------
  Widget _assignCard() {
    final n = _selectedCount;
    return _card(
      icon: Icons.add_circle,
      title: 'Assign / Reassign Subjects',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_reassignMode)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFfff3cd),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFffeaa7)),
            ),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.sync, size: 18, color: Color(0xFF856404)),
              SizedBox(width: 8),
              Expanded(
                child: Text.rich(TextSpan(style: TextStyle(color: Color(0xFF856404), fontSize: 13), children: [
                  TextSpan(text: 'Reassign Mode: ', style: TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: 'You have selected subjects that are already assigned. Updating will modify their duration and score settings.'),
                ])),
              ),
            ]),
          ),
        _subjectsBody(),
        const SizedBox(height: 14),
        Opacity(
          opacity: (_saving || _subjects.isEmpty) ? 0.6 : 1,
          child: Container(
            decoration: BoxDecoration(gradient: _grad, borderRadius: BorderRadius.circular(12)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: (_saving || _subjects.isEmpty) ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_saving)
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    else
                      const Icon(Icons.check, color: Colors.white, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      _saving ? 'Processing...' : (n > 0 ? 'Assign $n Selected Subject${n > 1 ? 's' : ''}' : 'Assign Selected Subjects'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _subjectsBody() {
    if (_loadingSubjects) {
      return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _primary)));
    }
    if (_subjectsError != null) {
      return Column(children: [
        _emptyState(Icons.error_outline, 'Error Loading Subjects', _subjectsError, _danger),
        TextButton.icon(onPressed: () => _loadSubjects(page: _sPage), icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          _sTotal > 0 ? 'Showing $_sFrom - $_sTo of $_sTotal subjects for selected class' : 'No subjects found for this class, session, and term',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
      ),
      if (_subjects.isEmpty)
        _emptyState(Icons.menu_book, 'No Subjects Found', 'No subjects have been created for this class, session, and term combination yet.')
      else
        for (final s in _subjects) _subjectItem(s),
      _pager(_sPage, _sTotalPages, (p) => _loadSubjects(page: p)),
    ]);
  }

  Widget _subjectItem(Map<String, dynamic> s) {
    final id = _int(s['id']);
    final assigned = s['is_assigned'] == true;
    final taken = _int(s['taken_count']);
    final checked = _sel[id] ?? false;
    final subjActive = '${s['subject_status']}' == 'active';
    final assignedActive = '${s['assigned_status']}' == 'active';

    Color bg = Colors.white, border = const Color(0xFFedf0f7);
    if (taken > 0) {
      bg = const Color(0xFFfff8ee);
      border = const Color(0xFFffe1b3);
    } else if (assigned) {
      bg = const Color(0xFFf0fbff);
      border = const Color(0xFFbfe9fb);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(10, 12, 14, 14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 6, children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _sel[id] = !checked),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: checked,
                activeColor: _primary,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => _sel[id] = v ?? false),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text('${s['subject_name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ]),
          ),
          _pill(subjActive ? 'Active' : 'Inactive', subjActive ? _success.withOpacity(0.15) : _danger.withOpacity(0.12), subjActive ? _success : _danger),
          if (assigned) ...[
            _pill('Assigned', const Color(0xFF4cc9f0).withOpacity(0.18), const Color(0xFF0b7ba3), icon: Icons.check),
            _pill(assignedActive ? 'Active' : 'Inactive', assignedActive ? _success.withOpacity(0.15) : _danger.withOpacity(0.12), assignedActive ? _success : _danger),
            if (taken > 0) _pill('$taken taken', _success.withOpacity(0.15), _success, icon: Icons.groups),
          ],
        ]),
        if (assigned && taken > 0)
          Container(
            margin: const EdgeInsets.only(top: 8, left: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFfff3de), borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFe67e22)),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: Color(0xFFa15c00)), children: [
                  TextSpan(text: '$taken student${taken == 1 ? '' : 's'} already took this exam. '),
                  const TextSpan(text: 'Updating will affect future attempts.', style: TextStyle(fontWeight: FontWeight.bold)),
                ])),
              ),
            ]),
          ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.end, children: [
            _miniInput('Minutes', _durCtrl[id]),
            _miniInput('Total Score', _scoreCtrl[id]),
            SizedBox(
              height: 38,
              child: OutlinedButton(
                onPressed: () => _toggleSubject(s),
                style: OutlinedButton.styleFrom(
                  foregroundColor: subjActive ? _success : _danger,
                  side: BorderSide(color: subjActive ? _success : _danger),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(subjActive ? 'ON' : 'OFF', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _miniInput(String label, TextEditingController? c) => SizedBox(
        width: 110,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF555555), fontWeight: FontWeight.w600)),
          ),
          TextField(
            controller: c,
            style: _fieldStyle,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _selectDec().copyWith(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)),
          ),
        ]),
      );

  // ---------------------------- assigned subjects ----------------------------
  Widget _assignedCard() {
    final scope = '(${_nameOf(_classes, 'class_id', 'class_name', _classId)} • ${_nameOf(_sessions, 'id', 'session_name', _sessionId)} • ${_nameOf(_terms, 'id', 'term_name', _termId)})';
    return _card(
      icon: Icons.checklist,
      title: 'Assigned Subjects',
      scope: scope,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _assignedBody(),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _deletingAll ? null : _deleteAll,
          style: OutlinedButton.styleFrom(
            foregroundColor: _danger,
            side: const BorderSide(color: _danger, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: _deletingAll
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _danger))
              : const Icon(Icons.delete, size: 18),
          label: Text(_deletingAll ? 'Deleting...' : 'Delete All Assigned', style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _assignedBody() {
    if (_loadingAssigned) {
      return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _primary)));
    }
    if (_assignedError != null) {
      return Column(children: [
        _emptyState(Icons.error_outline, 'Error Loading Assignments', _assignedError, _danger),
        TextButton.icon(onPressed: () => _loadAssigned(page: _aPage), icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          _aTotal > 0 ? 'Showing $_aFrom - $_aTo of $_aTotal assignments' : 'No assignments found',
          style: const TextStyle(fontSize: 12, color: _muted),
        ),
      ),
      if (_assigned.isEmpty)
        _emptyState(Icons.menu_book, 'No Subjects Assigned Yet', 'Nothing has been assigned for this Class / Session / Term combination.')
      else
        _assignedTable(),
      _pager(_aPage, _aTotalPages, (p) => _loadAssigned(page: p)),
    ]);
  }

  Widget _cell(Widget child) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12), child: child);
  Widget _th(String t) => _cell(Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))));

  Widget _progress(Map<String, dynamic> a) {
    final total = _int(a['total_students']);
    final taken = _int(a['taken_count']);
    if (total == 0) return _pill('No students', const Color(0xFFeeeeee), const Color(0xFF888888), icon: Icons.person_off);
    if (taken == 0) return _pill('Not started', _warning.withOpacity(0.14), _warning, icon: Icons.hourglass_bottom);
    final pct = ((taken / total) * 100).round();
    return _pill('$taken/$total ($pct%)', _success.withOpacity(0.15), _success, icon: Icons.check_circle);
  }

  Widget _assignedTable() {
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFf1f5f9), border: Border(bottom: BorderSide(color: _line, width: 1.5))),
        children: [
          _th('#'), _th('Class'), _th('Subject'), _th('Session'), _th('Term'),
          _th('Duration'), _th('Score'), _th('Progress'), _th('Status'), _th('Actions'),
        ],
      ),
    ];
    for (final a in _assigned) {
      final active = '${a['status']}' == 'active';
      rows.add(TableRow(
        decoration: BoxDecoration(
          color: _int(a['taken_count']) > 0 ? const Color(0xFFfff8ee) : Colors.white,
          border: const Border(bottom: BorderSide(color: Color(0xFFf1f5f9))),
        ),
        children: [
          _cell(Text('${a['sn']}')),
          _cell(Text('${a['class_name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
          _cell(Text('${a['subject_name']}')),
          _cell(Text('${a['session_name']}')),
          _cell(Text('${a['term_name']}')),
          _cell(Text('${a['duration']} min')),
          _cell(Text('${a['total_score']}')),
          _cell(Align(alignment: Alignment.centerLeft, child: _progress(a))),
          _cell(Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: active ? _success : _danger, borderRadius: BorderRadius.circular(20)),
              child: Text(active ? 'Active' : 'Inactive', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ),
          )),
          _cell(Row(children: [
            SizedBox(
              height: 30,
              child: OutlinedButton(
                onPressed: () => _toggleAssigned(a),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  foregroundColor: const Color(0xFF6c757d),
                  side: const BorderSide(color: Color(0xFF6c757d)),
                ),
                child: Text(active ? 'ON' : 'OFF', style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              height: 30,
              width: 34,
              child: ElevatedButton(
                onPressed: () => _deleteAssignment(a),
                style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: _danger, foregroundColor: Colors.white),
                child: const Icon(Icons.delete, size: 16),
              ),
            ),
          ])),
        ],
      ));
    }

    return LayoutBuilder(builder: (context, c) {
      final width = math.max(c.maxWidth, 1080.0);
      return Container(
        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFedf0f7)), borderRadius: BorderRadius.circular(10)),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(48),
                1: FlexColumnWidth(1.2),
                2: FlexColumnWidth(1.6),
                3: FlexColumnWidth(1.1),
                4: FlexColumnWidth(1.0),
                5: FixedColumnWidth(88),
                6: FixedColumnWidth(66),
                7: FixedColumnWidth(150),
                8: FixedColumnWidth(92),
                9: FixedColumnWidth(110),
              },
              children: rows,
            ),
          ),
        ),
      );
    });
  }

  // ---------------------------- pagination (same windowing as the web page) ----------------------------
  Widget _pager(int page, int total, void Function(int) go) {
    if (total <= 1) return const SizedBox.shrink();
    final start = math.max(1, page - 2);
    final end = math.min(total, page + 2);

    Widget btn({String? label, IconData? icon, VoidCallback? onTap, bool active = false}) => InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _primary : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: active ? _primary : const Color(0xFFdee2e6)),
            ),
            child: label != null
                ? Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? Colors.white : (onTap == null ? _muted : _primary)))
                : Icon(icon, size: 18, color: _primary),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        if (page > 1) btn(icon: Icons.chevron_left, onTap: () => go(page - 1)),
        if (start > 1) ...[
          btn(label: '1', onTap: () => go(1)),
          if (start > 2) btn(label: '...'),
        ],
        for (var i = start; i <= end; i++) btn(label: '$i', active: i == page, onTap: i == page ? null : () => go(i)),
        if (end < total) ...[
          if (end < total - 1) btn(label: '...'),
          btn(label: '$total', onTap: () => go(total)),
        ],
        if (page < total) btn(icon: Icons.chevron_right, onTap: () => go(page + 1)),
      ]),
    );
  }

  // ---------------------------- help ----------------------------
  void _showHelp() {
    Widget panel(IconData icon, String title, Widget child) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFFdee2e6)), borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, size: 18, color: _primary),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: const TextStyle(color: _primary, fontWeight: FontWeight.w700, fontSize: 15))),
            ]),
            const SizedBox(height: 8),
            child,
          ]),
        );

    Widget li(String t, {bool bold = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  '),
            Expanded(child: Text(t, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: 13))),
          ]),
        );

    showDialog<void>(
      context: context,
      builder: (ctx) => Theme(
        data: _lightTheme(),
        child: Dialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 640),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
                decoration: const BoxDecoration(gradient: _grad),
                child: Row(children: [
                  const Icon(Icons.info, color: Colors.white),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('How to Use This Page', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    panel(Icons.add_circle, 'Assign / Reassign', Column(children: [
                      li('1. Select Class, Session, and Term from the dropdowns'),
                      li('2. All subjects for that combination appear automatically'),
                      li('3. Already assigned subjects are pre-checked', bold: true),
                      li('4. Modify Duration & Total Score as needed'),
                      li('5. Tap "Assign Selected Subjects" to save changes'),
                      li('6. Existing assignments will be updated with new settings'),
                    ])),
                    panel(Icons.sync, 'Reassign Mode', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("When you select a subject that's already assigned:", style: TextStyle(fontSize: 13)),
                      const SizedBox(height: 6),
                      li('The checkbox is pre-checked for you'),
                      li('Current duration and score are pre-filled'),
                      li('Tapping Assign will update the existing record'),
                      li("Students who already took the exam won't lose their results"),
                    ])),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFfff3cd),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFffeaa7)),
                      ),
                      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFF856404)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text.rich(TextSpan(style: TextStyle(color: Color(0xFF856404), fontSize: 13), children: [
                            TextSpan(text: 'Note: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            TextSpan(text: 'Updating duration or score for already assigned subjects will affect future exam attempts only.'),
                          ])),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6c757d), foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
