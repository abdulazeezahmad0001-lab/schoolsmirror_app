// flutter_position_of_student_screen.dart
// Mirrors position_of_student.php 1:1: gradient "Student Position Management" header, Session / Term /
// Class (with student counts) / Department filters, "Automatic Position Set for All Students", ranked student
// list (global rank, class + original class, Transferred / Original badge, department, total scores,
// coloured percentage), position input with Save, quick-action buttons (exact position + gold / silver /
// bronze for the top 3), 20-per-page pagination and the success / error alerts.
// The wide table becomes one card per student.
//
// pubspec.yaml needs:  http, shared_preferences

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// extensionless address first (a redirect from "*.php" turns POST into GET and loses the form data)
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_position_of_student',
  'https://schoolsmirror.com/flutter_position_of_student.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

/// Same colour tokens as the :root block of position_of_student.php
class _C {
  static const primary = Color(0xFF4F46E5);
  static const secondary = Color(0xFFF59E0B);
  static const success = Color(0xFF10B981);
  static const danger = Color(0xFFEF4444);
  static const bg = Color(0xFFF8FAFC);
  static const text = Color(0xFF1F2937);
  static const grey = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const headerGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)]);
}

class _Api {
  static bool shouldRetry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' || m.startsWith('The server received this request as') || m.startsWith('Missing token'));
  }

  static Future<Map<String, dynamic>> post(String token, String action, [Map<String, String> fields = const {}]) async {
    Map<String, dynamic> last = {'success': false, 'message': 'Network error. Check your connection.'};
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        final uri = Uri.parse(_apiUrl).replace(queryParameters: {'token': token, 'action': action, ...fields});
        final res = await http
            .post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: {'token': token, 'action': action, ...fields})
            .timeout(const Duration(seconds: 90));
        last = decode(res.body);
        if (shouldRetry(last) && _apiIdx < _apiUrls.length - 1) {
          _apiIdx++;
          continue;
        }
        return last;
      } catch (_) {
        if (_apiIdx < _apiUrls.length - 1) {
          _apiIdx++;
          continue;
        }
        return {'success': false, 'message': 'Network error. Check your connection.'};
      }
    }
    return last;
  }

  static Map<String, dynamic> decode(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected server response'};
  }
}

List<Map<String, dynamic>> _maps(dynamic v) => (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
int _toInt(dynamic v) => int.tryParse('$v') ?? 0;
double _toDouble(dynamic v) => double.tryParse('$v') ?? 0;

// ═════════════════════════════════════════════════════════════════════════════
class FlutterPositionOfStudentScreen extends StatefulWidget {
  final String? token;
  const FlutterPositionOfStudentScreen({super.key, this.token});

  @override
  State<FlutterPositionOfStudentScreen> createState() => _FlutterPositionOfStudentScreenState();
}

class _FlutterPositionOfStudentScreenState extends State<FlutterPositionOfStudentScreen> {
  String? _token;
  bool _loading = true;

  List<Map<String, dynamic>> _sessions = [], _terms = [], _classes = [], _departments = [];
  String? _session, _term, _class, _dept; // selected in the form

  // filters the list was fetched with (the web page's current_* values)
  String _curSession = '', _curTerm = '', _curClass = '', _curDept = '';
  bool _fetched = false;
  bool _listLoading = false;
  bool _calculating = false;
  List<Map<String, dynamic>> _students = [];
  int _total = 0, _page = 1, _totalPages = 0, _offset = 0;

  String? _alertText;
  bool _alertOk = true;

  final Map<int, TextEditingController> _inputs = {};
  final Set<int> _saving = {};
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    _scroll.dispose();
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

  void _alert(String msg, {bool ok = true}) {
    if (!mounted) return;
    setState(() {
      _alertText = msg;
      _alertOk = ok;
    });
  }

  Future<void> _init() async {
    _token = await _getToken();
    if (_token != null) {
      final r = await _Api.post(_token!, 'bootstrap');
      if (!mounted) return;
      if (r['success'] == true) {
        final d = r['data'] as Map;
        setState(() {
          _sessions = _maps(d['sessions']);
          _terms = _maps(d['terms']);
          _classes = _maps(d['classes']);
          _departments = _maps(d['departments']);
        });
      } else {
        _alert('${r['message']}', ok: false);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  // ───────────────────────────── actions ─────────────────────────────
  Future<void> _fetch({int page = 1, bool fromForm = true}) async {
    if (fromForm) {
      if (_session == null || _term == null || _class == null) {
        _alert('Please select session, term and class.', ok: false);
        return;
      }
      _curSession = _session!;
      _curTerm = _term!;
      _curClass = _class!;
      _curDept = _dept ?? '';
    }
    setState(() {
      _listLoading = true;
      _fetched = true;
    });
    final r = await _Api.post(_token!, 'students', {
      'session_id': _curSession,
      'term_id': _curTerm,
      'class_id': _curClass,
      if (_curDept.isNotEmpty) 'department_id': _curDept,
      'page': '$page',
    });
    if (!mounted) return;
    if (r['success'] == true) {
      final d = r['data'] as Map;
      for (final c in _inputs.values) {
        c.dispose();
      }
      _inputs.clear();
      final list = _maps(d['students']);
      for (final s in list) {
        _inputs[_toInt(s['user_id'])] = TextEditingController(text: '${s['position'] ?? ''}');
      }
      setState(() {
        _students = list;
        _total = _toInt(d['total']);
        _page = _toInt(d['page']);
        _totalPages = _toInt(d['total_pages']);
        _offset = _toInt(d['offset']);
        _listLoading = false;
      });
    } else {
      setState(() {
        _listLoading = false;
        _students = [];
        _total = 0;
        _totalPages = 0;
      });
      _alert('${r['message']}', ok: false);
    }
  }

  void _clear() {
    for (final c in _inputs.values) {
      c.dispose();
    }
    _inputs.clear();
    setState(() {
      _session = _term = _class = _dept = null;
      _fetched = false;
      _students = [];
      _total = 0;
      _totalPages = 0;
      _alertText = null;
    });
  }

  Future<void> _save(Map<String, dynamic> s, String position) async {
    final id = _toInt(s['user_id']);
    if (_saving.contains(id)) return;
    setState(() {
      _saving.add(id);
      _alertText = null;
    });
    final r = await _Api.post(_token!, 'save_position', {
      'student_id': '$id',
      'session_id': _curSession,
      'term_id': _curTerm,
      'class_id': _curClass,
      'position': position.trim(),
    });
    if (!mounted) return;
    setState(() => _saving.remove(id));
    _alert('${r['message']}', ok: r['success'] == true);
    if (r['success'] == true) _fetch(page: _page, fromForm: false); // reload the same page with the same filters
  }

  Future<void> _calculate() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Automatic Position Set'),
        content: const Text('This will calculate percentages for all students with finalized results. Positions will be set as 1st, 2nd, 3rd, etc. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: _C.success, foregroundColor: Colors.white), child: const Text('Continue')),
        ],
      ),
    );
    if (yes != true) return;
    setState(() {
      _calculating = true;
      _alertText = null;
    });
    final r = await _Api.post(_token!, 'calculate_percentages', {'session_id': _curSession, 'term_id': _curTerm, 'class_id': _curClass});
    if (!mounted) return;
    setState(() => _calculating = false);
    _alert('${r['message']}', ok: r['success'] == true);
    if (r['success'] == true) _fetch(page: 1, fromForm: false);
  }

  // ───────────────────────────── build ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.headerGradient)),
        title: const Text('Student Positions', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : _token == null
              ? const Center(child: Text('Session expired. Please log out and log back in.'))
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(15),
                  children: [
                    _header(),
                    if (_alertText != null) _alertBox(),
                    _filterCard(),
                    if (_fetched && _total > 0) _calculateCard(),
                    if (_fetched) _resultsCard(),
                  ],
                ),
    );
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, 2))]),
        child: child,
      );

  Widget _header() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: _C.headerGradient, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: _C.primary.withAlpha(77), blurRadius: 16, offset: const Offset(0, 6))]),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.emoji_events, color: Colors.white, size: 28),
            SizedBox(width: 10),
            Flexible(child: Text('Student Position Management', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
          ]),
          SizedBox(height: 6),
          Text('Calculate percentages and assign positions to students', style: TextStyle(color: Colors.white70, fontSize: 13)),
        ]),
      );

  Widget _alertBox() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _alertOk ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
          border: Border.all(color: _alertOk ? const Color(0xFFA7F3D0) : const Color(0xFFFECACA)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(_alertOk ? Icons.check_circle : Icons.error, size: 18, color: _alertOk ? const Color(0xFF065F46) : const Color(0xFF991B1B)),
          const SizedBox(width: 10),
          Expanded(child: Text(_alertText!, style: TextStyle(color: _alertOk ? const Color(0xFF065F46) : const Color(0xFF991B1B), fontSize: 14))),
          InkWell(onTap: () => setState(() => _alertText = null), child: Icon(Icons.close, size: 18, color: _alertOk ? const Color(0xFF065F46) : const Color(0xFF991B1B))),
        ]),
      );

  // ───────────────────────────── filters ─────────────────────────────
  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.border, width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: _C.primary, width: 2)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      );

  Widget _dropdown(String label, String hint, String? value, List<Map<String, dynamic>> items, String idKey, String Function(Map<String, dynamic>) nameOf, ValueChanged<String?> onChanged) {
    final ok = value != null && items.any((i) => '${i[idKey]}' == value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: ok ? value : null,
        isExpanded: true,
        decoration: _dec(label),
        items: [
          DropdownMenuItem<String>(value: null, child: Text(hint, style: const TextStyle(color: _C.grey))),
          for (final i in items) DropdownMenuItem(value: '${i[idKey]}', child: Text(nameOf(i), overflow: TextOverflow.ellipsis)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback? onTap, {bool busy = false}) => ElevatedButton.icon(
        onPressed: onTap,
        icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(icon, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      );

  Widget _filterCard() => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.filter_alt, color: _C.primary, size: 20),
            SizedBox(width: 8),
            Text('Filter Students', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          _dropdown('Session', 'Select Session', _session, _sessions, 'id', (i) => '${i['session_name']}', (v) => setState(() => _session = v)),
          _dropdown('Term', 'Select Term', _term, _terms, 'id', (i) => '${i['term_name']}', (v) => setState(() => _term = v)),
          _dropdown('Class', 'Select Class', _class, _classes, 'class_id', (i) => '${i['class_name']} (${i['student_count']} students)', (v) => setState(() => _class = v)),
          _dropdown('Department (Optional)', 'All Departments', _dept, _departments, 'id', (i) => '${i['department_name']}', (v) => setState(() => _dept = v)),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _btn('Fetch Students', Icons.search, _C.primary, _listLoading ? null : () => _fetch(), busy: _listLoading),
            if (_fetched) _btn('Clear Filters', Icons.close, _C.grey, _clear),
          ]),
        ]),
      );

  Widget _calculateCard() => _card(
        child: SizedBox(
          width: double.infinity,
          child: _btn('Automatic Position Set for All Students', Icons.calculate, _C.success, _calculating ? null : _calculate, busy: _calculating),
        ),
      );

  // ───────────────────────────── results ─────────────────────────────
  Widget _resultsCard() => _card(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Icon(Icons.list, color: _C.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Student Results', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (_total > 0) Padding(padding: const EdgeInsets.only(left: 8), child: Text('($_total students found)', style: const TextStyle(fontSize: 14, color: _C.grey))),
          ]),
          const SizedBox(height: 14),
          if (_listLoading)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _C.primary)))
          else if (_total == 0)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Column(children: [
                Icon(Icons.group_off, size: 52, color: Color(0xFFD1D5DB)),
                SizedBox(height: 10),
                Text('No Students Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
                SizedBox(height: 6),
                Text('No students match your filter criteria. Please try different filters.', textAlign: TextAlign.center, style: TextStyle(color: _C.grey)),
              ]),
            )
          else ...[
            _infoBox(),
            const SizedBox(height: 14),
            for (var i = 0; i < _students.length; i++) _studentCard(_students[i], _offset + i + 1),
            _pagination(),
          ],
        ]),
      );

  Widget _infoBox() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFF0F9FF), border: Border.all(color: const Color(0xFFBAE6FD)), borderRadius: BorderRadius.circular(8)),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info, size: 18, color: Color(0xFF0369A1)),
          SizedBox(width: 10),
          Expanded(
            child: Text.rich(TextSpan(style: TextStyle(color: Color(0xFF0C4A6E), fontSize: 13, height: 1.45), children: [
              TextSpan(text: 'Note: ', style: TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: 'Enter position for each student and click Save. The suggested position is based on global ranking by percentage.\n'),
              TextSpan(text: '• Transferred students show both original and current classes\n', style: TextStyle(fontSize: 12)),
              TextSpan(text: '• Clicking "Automatic Position Set for All Students" will automatically assign positions as 1st, 2nd, 3rd, etc.\n', style: TextStyle(fontSize: 12)),
              TextSpan(text: '• Global Rank: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              TextSpan(text: "Shows the student's actual rank among all students in this class", style: TextStyle(fontSize: 12)),
            ])),
          ),
        ]),
      );

  Widget _kv(String k, Widget v) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k.toUpperCase(), style: const TextStyle(fontSize: 10, color: _C.grey, fontWeight: FontWeight.w600, letterSpacing: .4)),
          const SizedBox(height: 2),
          v,
        ]),
      );

  Widget _avatar(Map<String, dynamic> s) {
    final url = s['image_url'];
    final placeholder = Container(width: 48, height: 48, decoration: const BoxDecoration(color: Color(0xFFE5E7EB), shape: BoxShape.circle), child: const Icon(Icons.person, color: Color(0xFF9CA3AF)));
    if (url == null) return placeholder;
    return ClipOval(child: Image.network('$url', width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (c, e, st) => placeholder));
  }

  Widget _studentCard(Map<String, dynamic> s, int serial) {
    final id = _toInt(s['user_id']);
    final pct = _toDouble(s['percentage']);
    final pctColor = pct <= 0 ? _C.text : (pct >= 70 ? _C.success : (pct >= 50 ? _C.secondary : _C.danger));
    final transferred = '${s['student_status']}' == 'Transferred';
    final rank = _toInt(s['actual_rank']);
    final suggested = '${s['suggested_position']}';
    final saved = '${s['position'] ?? ''}';
    final exact = saved.isNotEmpty ? saved : suggested;
    final ctrl = _inputs[id]!;
    final busy = _saving.contains(id);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.border), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('$serial', style: const TextStyle(color: _C.grey, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          _avatar(s),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['fullname']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('${s['admission_number'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: _C.grey)),
              Text('Global Rank: $rank', style: const TextStyle(fontSize: 10, color: _C.grey, fontStyle: FontStyle.italic)),
            ]),
          ),
        ]),
        const Divider(height: 22),
        Wrap(spacing: 8, runSpacing: 12, children: [
          _kv('ID Number', Text('${s['idnumber'] ?? ''}', style: const TextStyle(fontSize: 13))),
          _kv(
            'Class Details',
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['display_class_name'] ?? 'N/A'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              if (transferred && s['original_class_name'] != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.swap_horiz, size: 11, color: _C.grey),
                  const SizedBox(width: 3),
                  Flexible(child: Text('Original: ${s['original_class_name']}', style: const TextStyle(fontSize: 10, color: _C.grey))),
                ]),
            ]),
          ),
          _kv(
            'Status',
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: transferred ? const Color(0xFFFEF3C7) : const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(5)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(transferred ? Icons.swap_horiz : Icons.home, size: 12, color: transferred ? const Color(0xFF92400E) : const Color(0xFF1E40AF)),
                const SizedBox(width: 4),
                Text(transferred ? 'Transferred' : 'Original', style: TextStyle(fontSize: 11, color: transferred ? const Color(0xFF92400E) : const Color(0xFF1E40AF))),
              ]),
            ),
          ),
          _kv('Department', Text('${s['department_name'] ?? 'N/A'}', style: const TextStyle(fontSize: 13))),
          _kv('Total Scores', Text(_toDouble(s['total_scores']).toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          _kv('Percentage', Text(pct > 0 ? '${pct.toStringAsFixed(2)}%' : 'N/A', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: pctColor))),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (v) => _save(s, v),
              decoration: InputDecoration(
                hintText: suggested,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _C.border, width: 2)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _C.primary, width: 2)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: busy ? null : () => _save(s, ctrl.text),
            icon: busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
            label: const Text('Save'),
            style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _quick(exact, Icons.military_tech, _C.primary, busy ? null : () => _save(s, exact)),
          if (rank == 1) _quick('1st', Icons.workspace_premium, const Color(0xFFF59E0B), busy ? null : () => _save(s, '1st')),
          if (rank == 2) _quick('2nd', Icons.military_tech, const Color(0xFF6B7280), busy ? null : () => _save(s, '2nd')),
          if (rank == 3) _quick('3rd', Icons.emoji_events, const Color(0xFFA855F7), busy ? null : () => _save(s, '3rd')),
        ]),
      ]),
    );
  }

  Widget _quick(String label, IconData icon, Color c, VoidCallback? onTap) => ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
      );

  // ───────────────────────────── pagination (same windowing as the web page) ─────────────────────────────
  Widget _pagination() {
    if (_totalPages <= 1) return const SizedBox.shrink();
    Widget link(String text, int page, {bool active = false}) => InkWell(
          onTap: active ? null : () => _fetch(page: page, fromForm: false),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: active ? _C.primary : Colors.white, border: Border.all(color: active ? _C.primary : _C.border), borderRadius: BorderRadius.circular(6)),
            child: Text(text, style: TextStyle(fontSize: 13, color: active ? Colors.white : _C.text, fontWeight: FontWeight.w600)),
          ),
        );
    final start = (_page - 2).clamp(1, _totalPages).toInt();
    final end = (_page + 2).clamp(1, _totalPages).toInt();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 6, children: [
        if (_page > 1) link('← Previous', _page - 1),
        if (start > 1) link('1', 1),
        if (start > 2) const Text('...'),
        for (var i = start; i <= end; i++) link('$i', i, active: i == _page),
        if (end < _totalPages - 1) const Text('...'),
        if (end < _totalPages) link('$_totalPages', _totalPages),
        if (_page < _totalPages) link('Next →', _page + 1),
      ]),
    );
  }
}
