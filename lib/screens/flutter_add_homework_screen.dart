// flutter_add_homework_screen.dart
// Redesigned "Post Homework" screen.
//  • Fixes "FormatException: Unexpected character (at character 1)": every response is checked before it is
//    decoded, both URL forms (extensionless / .php) are tried, and the real cause is shown in plain words
//    (HTTP status + start of what the server sent) instead of a raw exception.
//  • Class / subject chips (subjects filtered by the chosen class), quick due-date chips, live "student view"
//    preview card, push-notification switch, progress ring and a success dialog.
//  • Offline: if there is no connection the homework is queued in SharedPreferences ('homework_offline_queue')
//    exactly as before.
//
// Needs the new flutter_homework.php (actions: bootstrap, add). If it is missing the screen falls back to
// flutter_manage_students (list) for the class / subject pickers, as the old screen did.
//
// pubspec.yaml needs:  http, shared_preferences

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// ───────────────────────────── palette ─────────────────────────────
class _P {
  static const ink = Color(0xFF1E1B4B);
  static const primary = Color(0xFF4F46E5);
  static const violet = Color(0xFF7C3AED);
  static const pink = Color(0xFFDB2777);
  static const mint = Color(0xFF059669);
  static const amber = Color(0xFFD97706);
  static const rose = Color(0xFFE11D48);
  static const sky = Color(0xFF0284C7);
  static const bg = Color(0xFFF5F3FF);
  static const line = Color(0xFFE4E0F5);
  static const muted = Color(0xFF6B7280);
  static const paper = Color(0xFFFFFCF0);
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _two(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _nice(DateTime d) => '${_wd[d.weekday - 1]}, ${d.day} ${_mo[d.month - 1]} ${d.year}';
DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

String _dueLabel(DateTime d) {
  final days = DateTime(d.year, d.month, d.day).difference(_today()).inDays;
  if (days <= 0) return 'Due today';
  if (days == 1) return 'Due tomorrow';
  return 'Due in $days days';
}

// ───────────────────────────── networking ─────────────────────────────
class _NetError implements Exception {
  const _NetError();
}

class _ApiError implements Exception {
  final String message;
  const _ApiError(this.message);
  @override
  String toString() => message;
}

/// One API with two possible addresses. Tries the one that worked last, then the other.
class _Endpoint {
  final List<String> urls;
  int _i = 0;
  _Endpoint(this.urls);

  Future<Map<String, dynamic>> call(Map<String, String> fields, {bool post = true}) async {
    String? lastProblem;
    var gotAnswer = false;
    for (var k = 0; k < urls.length; k++) {
      final idx = (_i + k) % urls.length;
      try {
        final base = Uri.parse(urls[idx]);
        final http.Response res;
        if (post) {
          // token + action also go in the URL so they survive a redirect that drops the body
          final uri = base.replace(queryParameters: {'token': fields['token'] ?? '', 'action': fields['action'] ?? ''});
          res = await http
              .post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: fields)
              .timeout(const Duration(seconds: 30));
        } else {
          res = await http.get(base.replace(queryParameters: fields)).timeout(const Duration(seconds: 30));
        }
        gotAnswer = true;
        final parsed = _parse(res.body);
        if (parsed != null) {
          _i = idx;
          return parsed;
        }
        lastProblem = _describe(res.body, res.statusCode);
      } on TimeoutException {
        // try the other address
      } catch (_) {
        // network problem on this address, try the other
      }
    }
    if (!gotAnswer) throw const _NetError();
    throw _ApiError(lastProblem ?? 'The server sent an unexpected response.');
  }

  static Map<String, dynamic>? _parse(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return null;
  }

  static String _describe(String body, int status) {
    var s = body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 120) s = '${s.substring(0, 120)}...';
    return 'The server sent an unexpected response (HTTP $status${s.isEmpty ? ', empty reply' : ': $s'}).';
  }
}

List<Map<String, dynamic>> _maps(dynamic v) => (v is List ? v : []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
int? _int(dynamic v) => int.tryParse('${v ?? ''}');

// ═════════════════════════════════════════════════════════════════════════════
class FlutterAddHomeworkScreen extends StatefulWidget {
  final String? token;
  const FlutterAddHomeworkScreen({super.key, this.token});

  @override
  State<FlutterAddHomeworkScreen> createState() => _FlutterAddHomeworkScreenState();
}

class _FlutterAddHomeworkScreenState extends State<FlutterAddHomeworkScreen> {
  final _hw = _Endpoint(['https://schoolsmirror.com/flutter_homework', 'https://schoolsmirror.com/flutter_homework.php']);
  final _students = _Endpoint(['https://schoolsmirror.com/flutter_manage_students', 'https://schoolsmirror.com/flutter_manage_students.php']);

  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _notify = TextEditingController(text: 'Please complete this homework.');

  List<Map<String, dynamic>> _classes = []; // {id, name}
  List<Map<String, dynamic>> _subjects = []; // {id, name, class_id?}
  int? _classId;
  int? _subjectId;
  DateTime? _due;
  bool _push = true;

  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  bool _submitted = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    for (final c in [_title, _desc, _notify]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _notify.dispose();
    super.dispose();
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

  // ───────────────────────────── data ─────────────────────────────
  void _apply(dynamic data) {
    final d = data is Map ? data : {};
    final cls = _maps(d['classes'])
        .map((c) => {'id': _int(c['class_id'] ?? c['id']), 'name': '${c['class_name'] ?? c['name'] ?? ''}'})
        .where((c) => c['id'] != null && '${c['name']}'.isNotEmpty)
        .toList();
    final subs = _maps(d['subjects'])
        .map((s) => {'id': _int(s['subject_id'] ?? s['id']), 'name': '${s['subject_name'] ?? s['name'] ?? ''}', 'class_id': _int(s['class_id'])})
        .where((s) => s['id'] != null && '${s['name']}'.isNotEmpty)
        .toList();
    _classes = cls;
    _subjects = subs;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final token = await _getToken();
    if (token == null) {
      setState(() {
        _loading = false;
        _loadError = 'Your session has expired. Please log out and log back in.';
      });
      return;
    }
    String? problem;
    // 1) the homework API
    try {
      final d = await _hw.call({'token': token, 'action': 'bootstrap'});
      if (d['success'] == true) {
        _apply(d['data']);
      } else {
        problem = '${d['message'] ?? 'Could not load classes.'}';
      }
    } on _NetError {
      problem = 'No internet connection.';
    } on _ApiError catch (e) {
      problem = e.message;
    }
    // 2) fall back to the manage-students list (what the old screen used)
    if (_classes.isEmpty) {
      try {
        final d = await _students.call({'token': token, 'action': 'list', 'limit': '1'}, post: false);
        if (d['success'] == true) _apply(d['data']);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadError = _classes.isEmpty ? (problem ?? 'No classes were found for your school.') : null;
    });
  }

  List<Map<String, dynamic>> get _visibleSubjects {
    if (_classId == null) return _subjects;
    return _subjects.where((s) => s['class_id'] == null || s['class_id'] == _classId).toList();
  }

  String get _className => _classes.firstWhere((c) => c['id'] == _classId, orElse: () => {'name': ''})['name'] as String;
  String get _subjectName => _subjects.firstWhere((s) => s['id'] == _subjectId, orElse: () => {'name': ''})['name'] as String;

  // ───────────────────────────── validation ─────────────────────────────
  Map<String, String> _errors() {
    final e = <String, String>{};
    if (_classId == null) e['class'] = 'Choose who this homework is for';
    if (_title.text.trim().isEmpty) e['title'] = 'Give the homework a title';
    if (_desc.text.trim().isEmpty) e['desc'] = 'Tell students what to do';
    if (_due == null) e['due'] = 'Pick a deadline';
    return e;
  }

  int get _stepsDone {
    var n = 0;
    if (_classId != null) n++;
    if (_title.text.trim().isNotEmpty && _desc.text.trim().isNotEmpty) n++;
    if (_due != null) n++;
    return n;
  }

  // ───────────────────────────── submit ─────────────────────────────
  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _formError = null;
    });
    if (_errors().isNotEmpty) {
      HapticFeedback.lightImpact();
      return;
    }
    final token = await _getToken();
    if (token == null) {
      setState(() => _formError = 'Your session has expired. Please log out and log back in.');
      return;
    }
    final body = {
      'token': token,
      'action': 'add',
      'class_id': '$_classId',
      'subject_id': _subjectId != null ? '$_subjectId' : '',
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'due_date': _ymd(_due!),
      'notify_message': _notify.text.trim(),
      'send_push': _push ? '1' : '0',
    };
    setState(() => _saving = true);
    try {
      final d = await _hw.call(body);
      if (d['success'] != true) {
        setState(() => _formError = '${d['message'] ?? 'Could not save the homework.'}');
        return;
      }
      final data = d['data'] is Map ? d['data'] as Map : {};
      if (!mounted) return;
      await _successDialog('${d['message'] ?? 'Homework posted.'}', pushSent: data['push_sent'] == true, pushAsked: _push);
      if (mounted) Navigator.pop(context, true);
    } on _NetError {
      // offline: queue it exactly like the old screen did
      final p = await SharedPreferences.getInstance();
      final list = jsonDecode(p.getString('homework_offline_queue') ?? '[]') as List;
      list.add(body);
      await p.setString('homework_offline_queue', jsonEncode(list));
      if (!mounted) return;
      await _successDialog('You are offline. The homework is saved on this phone and will sync later.', offline: true);
      if (mounted) Navigator.pop(context, true);
    } on _ApiError catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _successDialog(String message, {bool pushSent = false, bool pushAsked = false, bool offline = false}) {
    final color = offline ? _P.amber : _P.mint;
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 650),
              curve: Curves.elasticOut,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color.withAlpha(30)),
                child: Icon(offline ? Icons.cloud_off_rounded : Icons.check_circle_rounded, size: 52, color: color),
              ),
            ),
            const SizedBox(height: 18),
            Text(offline ? 'Saved offline' : 'Homework posted!', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _P.ink, letterSpacing: -.3)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.45, color: _P.muted)),
            if (!offline && pushAsked) ...[
              const SizedBox(height: 14),
              _pill(pushSent ? Icons.notifications_active_rounded : Icons.notifications_off_outlined, pushSent ? 'Students notified' : 'Saved. Push is not set up on the server yet', pushSent ? _P.mint : _P.amber),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(c),
                style: FilledButton.styleFrom(backgroundColor: _P.ink, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due ?? _today().add(const Duration(days: 1)),
      firstDate: _today(),
      lastDate: _today().add(const Duration(days: 365)),
      builder: (c, child) => Theme(data: Theme.of(c).copyWith(colorScheme: Theme.of(c).colorScheme.copyWith(primary: _P.primary)), child: child!),
    );
    if (d != null) setState(() => _due = d);
  }

  // ───────────────────────────── build ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: _P.bg,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: Colors.white,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      bottomNavigationBar: _loading || _loadError != null ? null : _bottomBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _P.primary))
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                _hero(top),
                if (_loadError != null) _loadErrorCard() else ..._form(),
              ],
            ),
    );
  }

  // ───────────────────────────── hero ─────────────────────────────
  Widget _hero(double top) {
    final done = _stepsDone;
    return Container(
      padding: EdgeInsets.fromLTRB(22, top + kToolbarHeight + 6, 22, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF312E81), _P.primary, _P.violet]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(34)),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        const Positioned.fill(child: CustomPaint(painter: _RuledPainter())),
        Positioned(
          right: -6,
          top: -4,
          child: Transform.rotate(angle: .45, child: Icon(Icons.edit_rounded, size: 104, color: Colors.white.withAlpha(30))),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _pill(Icons.auto_stories_rounded, 'HOMEWORK', Colors.white, onDark: true),
          const SizedBox(height: 14),
          const Text('Post a new\nassignment', style: TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w800, height: 1.08, letterSpacing: -.8)),
          const SizedBox(height: 10),
          Text('Choose a class, describe the task, set a deadline and let students know.', style: TextStyle(color: Colors.white.withAlpha(215), fontSize: 13.5, height: 1.4)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: done / 3),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 7, backgroundColor: Colors.white.withAlpha(46), color: const Color(0xFFFDE68A)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text('$done / 3 steps', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
          ]),
        ]),
      ]),
    );
  }

  Widget _pill(IconData icon, String text, Color c, {bool onDark = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(color: onDark ? Colors.white.withAlpha(36) : c.withAlpha(26), borderRadius: BorderRadius.circular(30)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: .6))),
        ]),
      );

  Widget _loadErrorCard() => Padding(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: _cardDeco(),
          child: Column(children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, color: _P.rose.withAlpha(24)), child: const Icon(Icons.cloud_off_rounded, color: _P.rose, size: 32)),
            const SizedBox(height: 14),
            const Text("Couldn't load your classes", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _P.ink)),
            const SizedBox(height: 8),
            Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: _P.muted, height: 1.4, fontSize: 13)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
              style: FilledButton.styleFrom(backgroundColor: _P.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            ),
          ]),
        ),
      );

  // ───────────────────────────── form sections ─────────────────────────────
  BoxDecoration _cardDeco() => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: _P.ink.withAlpha(14), blurRadius: 24, offset: const Offset(0, 10))]);

  Widget _section({required int n, required String title, required String hint, required Color color, required Widget child, String? error}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      padding: const EdgeInsets.all(18),
      decoration: _cardDeco().copyWith(border: Border.all(color: error != null && _submitted ? _P.rose.withAlpha(120) : Colors.transparent, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color.withAlpha(28), borderRadius: BorderRadius.circular(10)),
            child: Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _P.ink, letterSpacing: -.2)),
              Text(hint, style: const TextStyle(fontSize: 12, color: _P.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        child,
        if (error != null && _submitted)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, size: 15, color: _P.rose),
              const SizedBox(width: 6),
              Expanded(child: Text(error, style: const TextStyle(color: _P.rose, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          ),
      ]),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, Color color, {IconData? icon}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? color : _P.line, width: 1.4),
          boxShadow: selected ? [BoxShadow(color: color.withAlpha(70), blurRadius: 12, offset: const Offset(0, 5))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : color), const SizedBox(width: 6)],
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: selected ? Colors.white : _P.ink)),
        ]),
      ),
    );
  }

  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _P.muted.withAlpha(170), fontSize: 14),
        prefixIcon: icon == null ? null : Icon(icon, size: 20, color: _P.muted),
        filled: true,
        fillColor: const Color(0xFFF9F8FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _P.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _P.primary, width: 1.8)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  List<Widget> _form() {
    final err = _errors();
    final subs = _visibleSubjects;
    final today = _today();
    bool isDue(int days) => _due != null && _ymd(_due!) == _ymd(today.add(Duration(days: days)));
    final custom = _due != null && ![1, 3, 7].any(isDue);

    return [
      if (_formError != null)
        Container(
          margin: const EdgeInsets.fromLTRB(18, 16, 18, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFFECDD3))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.error_rounded, color: _P.rose, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(_formError!, style: const TextStyle(color: Color(0xFF9F1239), fontSize: 13, height: 1.4, fontWeight: FontWeight.w600))),
            GestureDetector(onTap: () => setState(() => _formError = null), child: const Icon(Icons.close_rounded, size: 18, color: _P.rose)),
          ]),
        ),

      // 1 ─ class + subject
      _section(
        n: 1,
        title: 'Who is it for?',
        hint: 'Pick the class, and a subject if you want',
        color: _P.primary,
        error: err['class'],
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in _classes)
              _chip('${c['name']}', _classId == c['id'], () {
                setState(() {
                  _classId = c['id'] as int?;
                  if (_subjectId != null && !_visibleSubjects.any((s) => s['id'] == _subjectId)) _subjectId = null;
                });
              }, _P.primary, icon: Icons.groups_rounded),
          ]),
          if (subs.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('SUBJECT (OPTIONAL)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .8, color: _P.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final s in subs) _chip('${s['name']}', _subjectId == s['id'], () => setState(() => _subjectId = _subjectId == s['id'] ? null : s['id'] as int?), _P.violet, icon: Icons.menu_book_rounded),
            ]),
          ],
        ]),
      ),

      // 2 ─ the task
      _section(
        n: 2,
        title: 'What should they do?',
        hint: 'A short title and clear instructions',
        color: _P.pink,
        error: err['title'] ?? err['desc'],
        child: Column(children: [
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: _P.ink),
            decoration: _dec('e.g. Algebra practice, set 4', icon: Icons.title_rounded),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 5,
            minLines: 4,
            maxLength: 800,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14.5, height: 1.45, color: _P.ink),
            decoration: _dec('Explain the task, page numbers, what to submit...').copyWith(counterStyle: const TextStyle(color: _P.muted, fontSize: 11)),
          ),
        ]),
      ),

      // 3 ─ deadline
      _section(
        n: 3,
        title: 'When is it due?',
        hint: 'Students see a countdown',
        color: _P.amber,
        error: err['due'],
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _chip('Tomorrow', isDue(1), () => setState(() => _due = today.add(const Duration(days: 1))), _P.amber),
            _chip('In 3 days', isDue(3), () => setState(() => _due = today.add(const Duration(days: 3))), _P.amber),
            _chip('Next week', isDue(7), () => setState(() => _due = today.add(const Duration(days: 7))), _P.amber),
            _chip(custom ? _nice(_due!) : 'Pick a date', custom, _pickDate, _P.amber, icon: Icons.calendar_month_rounded),
          ]),
          if (_due != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                const Icon(Icons.event_available_rounded, size: 17, color: _P.amber),
                const SizedBox(width: 8),
                Text('${_nice(_due!)}  ·  ${_dueLabel(_due!)}', style: const TextStyle(fontWeight: FontWeight.w700, color: _P.ink, fontSize: 13.5)),
              ]),
            ),
        ]),
      ),

      // 4 ─ notify
      _section(
        n: 4,
        title: 'Tell students',
        hint: 'Send a push notification when you post',
        color: _P.mint,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: _push ? _P.mint.withAlpha(20) : const Color(0xFFF9F8FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: _push ? _P.mint.withAlpha(90) : _P.line)),
            child: Row(children: [
              Icon(_push ? Icons.notifications_active_rounded : Icons.notifications_off_outlined, color: _push ? _P.mint : _P.muted),
              const SizedBox(width: 10),
              Expanded(child: Text(_push ? 'Notify students' : 'Do not notify', style: const TextStyle(fontWeight: FontWeight.w700, color: _P.ink))),
              Switch(value: _push, activeColor: _P.mint, onChanged: (v) => setState(() => _push = v)),
            ]),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            child: _push
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(controller: _notify, maxLength: 120, decoration: _dec('Notification message', icon: Icons.chat_bubble_outline_rounded)),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ]),
      ),

      // preview
      Padding(padding: const EdgeInsets.fromLTRB(18, 22, 18, 8), child: Row(children: [const Icon(Icons.visibility_rounded, size: 16, color: _P.muted), const SizedBox(width: 6), const Text('STUDENT VIEW PREVIEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .9, color: _P.muted))])),
      _preview(),
      const SizedBox(height: 28),
    ];
  }

  Widget _preview() {
    final title = _title.text.trim();
    final desc = _desc.text.trim();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(color: _P.paper, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFF1E7B8)), boxShadow: [BoxShadow(color: _P.amber.withAlpha(30), blurRadius: 20, offset: const Offset(0, 8))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(children: [
          const Positioned.fill(child: CustomPaint(painter: _PaperPainter())),
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 18, 18, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 6, children: [
                if (_className.isNotEmpty) _pill(Icons.groups_rounded, _className, _P.primary),
                if (_subjectName.isNotEmpty) _pill(Icons.menu_book_rounded, _subjectName, _P.violet),
                if (_className.isEmpty && _subjectName.isEmpty) _pill(Icons.groups_rounded, 'CLASS', _P.muted),
              ]),
              const SizedBox(height: 12),
              Text(title.isEmpty ? 'Your homework title' : title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -.3, color: title.isEmpty ? _P.muted.withAlpha(150) : _P.ink)),
              const SizedBox(height: 8),
              Text(desc.isEmpty ? 'The instructions you write will appear here.' : desc, maxLines: 4, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, height: 1.5, color: desc.isEmpty ? _P.muted.withAlpha(150) : const Color(0xFF374151))),
              const SizedBox(height: 14),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(color: _due == null ? _P.line : _P.rose.withAlpha(22), borderRadius: BorderRadius.circular(12)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.timer_outlined, size: 15, color: _due == null ? _P.muted : _P.rose),
                    const SizedBox(width: 6),
                    Text(_due == null ? 'No deadline yet' : '${_dueLabel(_due!)}  ·  ${_nice(_due!)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _due == null ? _P.muted : _P.rose)),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  // ───────────────────────────── bottom bar ─────────────────────────────
  Widget _bottomBar() {
    final ready = _errors().isEmpty;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 12, 18, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: _P.ink.withAlpha(20), blurRadius: 24, offset: const Offset(0, -6))], borderRadius: const BorderRadius.vertical(top: Radius.circular(26))),
      child: GestureDetector(
        onTap: _saving ? null : _submit,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 56,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: ready ? const [_P.primary, _P.violet] : [_P.primary.withAlpha(150), _P.violet.withAlpha(150)]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: ready ? [BoxShadow(color: _P.primary.withAlpha(90), blurRadius: 18, offset: const Offset(0, 8))] : null,
          ),
          alignment: Alignment.center,
          child: _saving
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_push ? Icons.send_rounded : Icons.check_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(_push ? 'Post & notify students' : 'Post homework', style: const TextStyle(color: Colors.white, fontSize: 16.5, fontWeight: FontWeight.w800, letterSpacing: .1)),
                ]),
        ),
      ),
    );
  }
}

// ───────────────────────────── painters ─────────────────────────────
/// faint notebook rules over the hero
class _RuledPainter extends CustomPainter {
  const _RuledPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = Colors.white.withAlpha(22)
      ..strokeWidth = 1;
    for (double y = 28; y < s.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
    canvas.drawLine(
      const Offset(34, 0),
      Offset(34, s.height),
      Paint()
        ..color = const Color(0xFFFB7185).withAlpha(70)
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// ruled paper with a margin line for the preview card
class _PaperPainter extends CustomPainter {
  const _PaperPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..color = const Color(0xFFBFD3F2).withAlpha(120)
      ..strokeWidth = 1;
    for (double y = 30; y < s.height; y += 26) {
      canvas.drawLine(Offset(0, y), Offset(s.width, y), p);
    }
    canvas.drawLine(
      const Offset(34, 0),
      Offset(34, s.height),
      Paint()
        ..color = const Color(0xFFFCA5A5).withAlpha(160)
        ..strokeWidth = 1.4,
    );
    // binder holes
    final hole = Paint()..color = const Color(0xFFE5E7EB);
    for (double y = 40; y < s.height - 10; y += 70) {
      canvas.drawCircle(Offset(15, y), 5, hole);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
