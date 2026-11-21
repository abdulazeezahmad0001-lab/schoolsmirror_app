// flutter_results_overview_screen.dart
// Mirrors results_overview.php ("Result Finalization"):
//   class / session / term / department filters -> student list with Draft / Finalized / No Result,
//   30-day edit window, Select All Drafts, Select Edited, Finalize Selected, Re-Finalize Edited.
// NEW: after finalizing, the app can push a notification to each student (and parent) and to the other admins.
//      (server side: flutter_results_overview.php + flutter_lib.php + flutter_push.php)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'push_notification_service.dart';

// Same trick as your other screens: the extensionless address first (a redirect from "*.php" would drop the POST body).
const List<String> _roUrls = [
  'https://schoolsmirror.com/flutter_results_overview',
  'https://schoolsmirror.com/flutter_results_overview.php',
];
int _roIdx = 0;

/// Bootstrap colours used by results_overview.php
class _B {
  static const primary = Color(0xFF0D6EFD);
  static const success = Color(0xFF28A745);
  static const warning = Color(0xFFFFC107);
  static const secondary = Color(0xFF6C757D);
  static const info = Color(0xFF17A2B8);
  static const danger = Color(0xFFDC3545);
  static const reFinal = Color(0xFFFD7E14);
  static const light = Color(0xFFF8F9FA);
  static const dark = Color(0xFF212529);
  static const bg = Color(0xFFF1F4F8);
  static const rowSelected = Color(0xFFCFE2FF);
  static const rowEdited = Color(0xFFFFF3CD);
  static const header = LinearGradient(colors: [Color(0xFF0083B0), Color(0xFF00B4DB)]);
}

int? _i(dynamic v) => v == null ? null : int.tryParse('$v');
String _s(dynamic v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _ml(dynamic v) =>
    (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
Map<String, dynamic> _mm(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

class _RoApi {
  static Map<String, dynamic> _decode(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected server response'};
  }

  static bool _retry(Map<String, dynamic> d) {
    final m = _s(d['message']);
    return d['success'] != true &&
        (m == 'Unexpected server response' || m.startsWith('Missing token') || m.startsWith('The server received this request as'));
  }

  /// [json] = body is JSON (used for finalizing: lists + booleans). Otherwise a small form.
  static Future<Map<String, dynamic>> call(String token, String action,
      {Map<String, String> form = const {}, Map<String, dynamic>? json, int timeout = 40}) async {
    var idx = _roIdx;
    var net = false;
    Map<String, dynamic> last = {'success': false, 'message': 'Unexpected server response'};
    for (var t = 0; t < _roUrls.length; t++) {
      try {
        final q = json != null ? {'token': token, 'action': action} : {'token': token, 'action': action, ...form};
        final uri = Uri.parse(_roUrls[idx]).replace(queryParameters: q);
        final http.Response res = json != null
            ? await http
                .post(uri,
                    headers: {'Content-Type': 'application/json; charset=utf-8'},
                    body: jsonEncode({...json, 'token': token, 'action': action}))
                .timeout(Duration(seconds: timeout))
            : await http
                .post(uri,
                    headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
                    body: {'token': token, 'action': action, ...form})
                .timeout(Duration(seconds: timeout));
        last = _decode(res.body);
        if (_retry(last) && t < _roUrls.length - 1) {
          idx = (idx + 1) % _roUrls.length;
          continue;
        }
        _roIdx = idx;
        return last;
      } catch (_) {
        net = true;
        idx = (idx + 1) % _roUrls.length;
      }
    }
    return net ? {'success': false, 'network': true, 'message': 'No internet connection. Please try again.'} : last;
  }
}

class FlutterResultsOverviewScreen extends StatefulWidget {
  final String token;
  const FlutterResultsOverviewScreen({super.key, required this.token});

  @override
  State<FlutterResultsOverviewScreen> createState() => _FlutterResultsOverviewScreenState();
}

class _FlutterResultsOverviewScreenState extends State<FlutterResultsOverviewScreen> {
  bool _booting = true;
  String? _bootError;
  bool _fetching = false;
  bool _busy = false; // finalizing

  String _role = '';
  bool _canFinalize = false;
  bool _pushReady = false;
  bool _guardians = false;
  List<Map<String, dynamic>> _classes = [], _sessions = [], _terms = [], _depts = [];

  int? _cls, _sess, _term, _dept;
  // the filters that were actually used for the list on screen
  int? _curCls, _curSess, _curTerm;
  String _sessionLabel = '', _termLabel = '';

  List<Map<String, dynamic>> _students = [];
  int _page = 1, _totalPages = 0, _total = 0, _perPage = 20;
  bool _hasList = false;
  final Set<int> _sel = {};

  bool _guideOpen = true;
  bool _notify = true;
  String? _alertMsg;
  String? _alertNote;
  bool _alertError = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  // ───────────────────────────── loading ─────────────────────────────
  Future<void> _boot() async {
    setState(() {
      _booting = true;
      _bootError = null;
    });
    final r = await _RoApi.call(widget.token, 'bootstrap');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = _mm(r['data']);
      setState(() {
        _role = _s(d['role']);
        _canFinalize = d['can_finalize'] == true;
        _pushReady = d['push_ready'] == true;
        _guardians = d['guardians_configured'] == true;
        _classes = _ml(d['classes']);
        _sessions = _ml(d['sessions']);
        _terms = _ml(d['terms']);
        _depts = _ml(d['departments']);
        _booting = false;
      });
    } else {
      setState(() {
        _bootError = _s(r['message']);
        _booting = false;
      });
    }
  }

  bool get _canFetch => _cls != null && _sess != null && _term != null;

  Future<void> _load({int page = 1}) async {
    if (!_canFetch) return;
    setState(() => _fetching = true);
    final r = await _RoApi.call(widget.token, 'students', form: {
      'class_id': '$_cls',
      'session_id': '$_sess',
      'term_id': '$_term',
      'page': '$page',
      if (_dept != null) 'department_id': '$_dept',
    });
    if (!mounted) return;
    if (r['success'] == true) {
      final d = _mm(r['data']);
      final p = _mm(d['pagination']);
      setState(() {
        _students = _ml(d['students']);
        _page = _i(p['current_page']) ?? 1;
        _totalPages = _i(p['total_pages']) ?? 0;
        _total = _i(p['total']) ?? 0;
        _perPage = _i(p['per_page']) ?? 20;
        _curCls = _cls;
        _curSess = _sess;
        _curTerm = _term;
        _sessionLabel = _sessions.where((x) => _i(x['id']) == _sess).map((x) => _s(x['session_name'])).join();
        _termLabel = _terms.where((x) => _i(x['id']) == _term).map((x) => _s(x['term_name'])).join();
        _hasList = true;
        _sel.clear();
        _fetching = false;
      });
    } else {
      setState(() => _fetching = false);
      _showAlert(_s(r['message']), error: true);
    }
  }

  void _showAlert(String msg, {bool error = false, String? note}) {
    if (!mounted) return;
    setState(() {
      _alertMsg = msg;
      _alertNote = note;
      _alertError = error;
    });
  }

  // ───────────────────────────── selection rules (same as the web) ─────────────────────────────
  bool _isDraft(Map<String, dynamic> s) => s['result_status'] == 'draft';
  bool _isFinal(Map<String, dynamic> s) => s['result_status'] == 'finalized';
  int? _days(Map<String, dynamic> s) => _i(s['days_since_publish']);
  bool _withinWindow(Map<String, dynamic> s) => _isFinal(s) && _days(s) != null && _days(s)! <= 30;
  bool _selectable(Map<String, dynamic> s) => _isDraft(s) || _withinWindow(s);

  List<Map<String, dynamic>> get _selectedRows => _students.where((s) => _sel.contains(_i(s['user_id']))).toList();
  bool get _hasDraftSelected => _selectedRows.any(_isDraft);
  bool get _hasFinalSelected => _selectedRows.any(_withinWindow);

  void _toggle(Map<String, dynamic> s) {
    if (!_canFinalize || !_selectable(s)) return;
    final id = _i(s['user_id'])!;
    setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));
  }

  void _selectAllDrafts() {
    final ids = _students.where(_selectable).map((s) => _i(s['user_id'])!).toList();
    final allOn = ids.isNotEmpty && ids.every(_sel.contains);
    setState(() {
      if (allOn) {
        _sel.removeAll(ids);
      } else {
        _sel.addAll(ids);
      }
    });
  }

  void _selectEdited() {
    final ids = _students.where(_withinWindow).map((s) => _i(s['user_id'])!).toList();
    if (ids.isEmpty) {
      _showAlert('No finalized results inside the 30-day edit window on this page.', error: true);
      return;
    }
    setState(() {
      _sel
        ..clear()
        ..addAll(ids);
    });
  }

  // ───────────────────────────── finalize ─────────────────────────────
  String _pushNote(Map<String, dynamic> push) {
    if (push['requested'] != true) return '';
    final devices = _i(push['devices']) ?? 0;
    final rec = _i(push['recipients']) ?? 0;
    if (push['configured'] != true) {
      return 'Push is not set up on the server yet, so the notification was saved in the in-app inbox only.';
    }
    if (devices == 0) {
      return 'No registered phones were found for these students or parents yet. The notification was saved in their in-app inbox.';
    }
    return '🔔 Sending notifications to $rec ${rec == 1 ? 'person' : 'people'} on $devices device${devices == 1 ? '' : 's'}.';
  }

  Future<void> _finalize({required bool re}) async {
    final rows = _selectedRows;
    if (rows.isEmpty || _busy) return;
    final n = rows.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(re ? 'Re-finalize results?' : 'Finalize results?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(re
              ? 'Are you sure you want to re-finalize results for $n selected student(s)? This will update the published results with the latest edits.'
              : 'Are you sure you want to finalize results for $n selected student(s)? This action cannot be undone.'),
          const SizedBox(height: 12),
          Row(children: [
            Icon(_notify ? Icons.notifications_active : Icons.notifications_off, size: 18, color: _notify ? _B.success : _B.secondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_notify ? 'Students and parents will get a push notification.' : 'No push notification will be sent.',
                  style: const TextStyle(fontSize: 13, color: _B.secondary)),
            ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: re ? _B.reFinal : _B.success, foregroundColor: Colors.white),
              child: Text(re ? 'Re-Finalize' : 'Finalize')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final r = await _RoApi.call(widget.token, re ? 're_finalize_results' : 'finalize_results', json: {
      'student_ids': _sel.toList(),
      'session_id': _curSess,
      'term_id': _curTerm,
      'class_id': _curCls,
      'notify': _notify,
    }, timeout: 90);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['success'] == true) {
      final d = _mm(r['data']);
      _showAlert(_s(r['message']), note: _pushNote(_mm(d['push'])));
      await _load(page: _page);
    } else {
      _showAlert(_s(r['message']), error: true);
    }
  }

  Future<void> _sendTest() async {
    final msg = await PushNotificationService.instance.sendTest(widget.token);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _B.bg,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _B.header)),
        title: const Text('Result Finalization', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'test') _sendTest();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'test', child: Row(children: [Icon(Icons.notifications_active, size: 20), SizedBox(width: 10), Text('Send test notification')])),
            ],
          ),
        ],
      ),
      body: _booting
          ? const Center(child: CircularProgressIndicator())
          : _bootError != null
              ? _bootErrorView()
              : RefreshIndicator(
                  onRefresh: () async => _hasList ? _load(page: _page) : _boot(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                    children: [
                      if (_alertMsg != null) _alertBox(),
                      if (_guideOpen) _guide(),
                      _filters(),
                      if (_hasList) ..._results(),
                    ],
                  ),
                ),
    );
  }

  Widget _bootErrorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, size: 54, color: _B.danger),
            const SizedBox(height: 10),
            Text(_bootError!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _boot, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _alertBox() {
    final e = _alertError;
    final fg = e ? const Color(0xFF842029) : const Color(0xFF0F5132);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: e ? const Color(0xFFF8D7DA) : const Color(0xFFD1E7DD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: e ? const Color(0xFFF5C2C7) : const Color(0xFFBADBCC)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(e ? Icons.error : Icons.check_circle, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_alertMsg!, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
            if (_alertNote != null && _alertNote!.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(_alertNote!, style: TextStyle(color: fg, fontSize: 13))),
          ]),
        ),
        InkWell(onTap: () => setState(() => _alertMsg = null), child: Icon(Icons.close, size: 18, color: fg)),
      ]),
    );
  }

  Widget _guide() {
    Widget li(String bold, String rest) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('•  ', style: TextStyle(color: Color(0xFF055160))),
            Expanded(
              child: Text.rich(TextSpan(style: const TextStyle(color: Color(0xFF055160), fontSize: 12.5), children: [
                TextSpan(text: bold, style: const TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: rest),
              ])),
            ),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFCFF4FC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFB6EFFB))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.info, size: 18, color: Color(0xFF055160)),
          const SizedBox(width: 8),
          const Expanded(child: Text('Result Publishing Guide:', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF055160)))),
          InkWell(onTap: () => setState(() => _guideOpen = false), child: const Icon(Icons.close, size: 18, color: Color(0xFF055160))),
        ]),
        li('Draft Results: ', 'Can be edited at any time. Tap "Finalize" to publish.'),
        li('Finalized Results: ', 'Published results with a 30-day edit window. After editing, tap "Re-Finalize" to publish the updated version.'),
        li('Edit Window: ', 'Results can be edited within 30 days of publication. After 30 days, only admins can edit.'),
        li('Notifications: ', 'Finalizing can send a push notification to students and parents.'),
      ]),
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  Widget _filters() {
    final classOn = _cls != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _B.light, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFDEE2E6))),
      child: Column(children: [
        DropdownButtonFormField<int>(
          value: _cls,
          isExpanded: true,
          decoration: _dec('Class'),
          hint: const Text('Select Class'),
          items: _classes
              .map((c) => DropdownMenuItem<int>(
                  value: _i(c['class_id']), child: Text('${_s(c['class_name'])} (${_s(c['student_count'])} students)', overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() {
            _cls = v;
            _hasList = false;
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _sess,
          isExpanded: true,
          decoration: _dec('Session'),
          hint: const Text('Select Session'),
          items: _sessions.map((x) => DropdownMenuItem<int>(value: _i(x['id']), child: Text(_s(x['session_name'])))).toList(),
          onChanged: classOn ? (v) => setState(() => _sess = v) : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          value: _term,
          isExpanded: true,
          decoration: _dec('Term'),
          hint: const Text('Select Term'),
          items: _terms.map((x) => DropdownMenuItem<int>(value: _i(x['id']), child: Text(_s(x['term_name'])))).toList(),
          onChanged: classOn ? (v) => setState(() => _term = v) : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          value: _dept,
          isExpanded: true,
          decoration: _dec('Department'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('All Departments')),
            ..._depts.map((x) => DropdownMenuItem<int?>(value: _i(x['id']), child: Text(_s(x['department_name'])))),
          ],
          onChanged: classOn ? (v) => setState(() => _dept = v) : null,
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: (_canFetch && !_fetching) ? () => _load() : null,
              icon: _fetching
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 18),
              label: const Text('Fetch Students'),
              style: ElevatedButton.styleFrom(backgroundColor: _B.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: (_canFetch && _hasList && !_fetching) ? () => _load(page: _page) : null,
            icon: const Icon(Icons.sync, size: 18),
            label: const Text('Refresh'),
            style: OutlinedButton.styleFrom(foregroundColor: _B.secondary, padding: const EdgeInsets.symmetric(vertical: 13)),
          ),
        ]),
      ]),
    );
  }

  List<Widget> _results() {
    return [
      Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFE9ECEF), borderRadius: BorderRadius.circular(5)),
        child: Row(children: [
          const Icon(Icons.calendar_month, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text('$_sessionLabel  |  $_termLabel', style: const TextStyle(fontWeight: FontWeight.bold))),
        ]),
      ),
      Row(children: [
        const Icon(Icons.groups, size: 20),
        const SizedBox(width: 8),
        const Text('Students', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _B.primary, borderRadius: BorderRadius.circular(6)),
          child: Text('Total: $_total students', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 10),
      if (_canFinalize) _actionBar() else _viewOnlyNote(),
      ..._students.isEmpty
          ? [
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFCFF4FC), borderRadius: BorderRadius.circular(8)),
                child: const Text('No students found with results for this selection.', style: TextStyle(color: Color(0xFF055160))),
              )
            ]
          : [for (var k = 0; k < _students.length; k++) _studentCard(_students[k], (_page - 1) * _perPage + k + 1)],
      if (_totalPages > 1) _pager(),
    ];
  }

  Widget _viewOnlyNote() => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _B.light, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDEE2E6))),
        child: const Row(children: [
          Icon(Icons.lock, size: 16, color: _B.secondary),
          SizedBox(width: 8),
          Expanded(child: Text('Only administrators can finalize results. You can view the status here.', style: TextStyle(color: _B.secondary, fontSize: 13))),
        ]),
      );

  Widget _actionBar() {
    final canFin = _sel.isNotEmpty && _hasDraftSelected && !_busy;
    final canRe = _sel.isNotEmpty && _hasFinalSelected && !_busy;
    return Column(children: [
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDEE2E6))),
        child: SwitchListTile(
          value: _notify,
          onChanged: (v) => setState(() => _notify = v),
          dense: true,
          activeColor: _B.success,
          title: const Text('Send push notification', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
              !_pushReady
                  ? 'Push is not set up on the server yet. Notifications will only appear in the in-app inbox.'
                  : (_guardians ? 'Students, parents and the other admins are notified.' : 'Students and the other admins are notified.'),
              style: TextStyle(fontSize: 12, color: _pushReady ? _B.secondary : _B.reFinal)),
          secondary: Icon(_notify ? Icons.notifications_active : Icons.notifications_off, color: _notify ? _B.success : _B.secondary),
        ),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          onPressed: _students.any(_selectable) ? _selectAllDrafts : null,
          icon: const Icon(Icons.check_circle_outline, size: 17),
          label: const Text('Select All Drafts'),
          style: OutlinedButton.styleFrom(foregroundColor: _B.primary, side: const BorderSide(color: _B.primary)),
        ),
        OutlinedButton.icon(
          onPressed: _selectEdited,
          icon: const Icon(Icons.edit, size: 17),
          label: const Text('Select Edited'),
          style: OutlinedButton.styleFrom(foregroundColor: _B.info, side: const BorderSide(color: _B.info)),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canFin ? () => _finalize(re: false) : null,
            icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send, size: 17),
            label: const Text('Finalize Selected'),
            style: ElevatedButton.styleFrom(backgroundColor: _B.success, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canRe ? () => _finalize(re: true) : null,
            icon: const Icon(Icons.sync, size: 17),
            label: const Text('Re-Finalize'),
            style: ElevatedButton.styleFrom(backgroundColor: _B.reFinal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 13)),
          ),
        ),
      ]),
      if (_sel.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(alignment: Alignment.centerLeft, child: Text('${_sel.length} selected', style: const TextStyle(color: _B.secondary, fontSize: 12.5))),
        ),
      const SizedBox(height: 10),
    ]);
  }

  Widget _badge(String t, Color bg, Color fg, {bool bold = true}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: TextStyle(color: fg, fontSize: 11.5, fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
      );

  String _fmtDate(String s) {
    final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (d == null) return s;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Widget _studentCard(Map<String, dynamic> st, int sn) {
    final id = _i(st['user_id'])!;
    final selected = _sel.contains(id);
    final transferred = st['student_status'] == 'Transferred';
    final hasResult = st['result_status'] != null;
    final fin = _isFinal(st);
    final days = _days(st);
    final selectable = _canFinalize && _selectable(st);
    final displayClass = transferred
        ? '${_s(st['effective_class_name']).isEmpty ? _s(st['class_name']) : _s(st['effective_class_name'])} (Current)'
        : (_s(st['original_class_name']).isEmpty ? _s(st['class_name']) : _s(st['original_class_name']));

    Widget status;
    if (!hasResult) {
      status = _badge('No Result', _B.secondary, Colors.white);
    } else if (fin) {
      status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _badge('● Finalized', _B.success, Colors.white),
        if (days != null)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: days <= 30
                ? Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.schedule, size: 12, color: Color(0xFFB58100)),
                    const SizedBox(width: 3),
                    Text('${30 - days} days left to edit', style: const TextStyle(fontSize: 11, color: Color(0xFFB58100))),
                  ])
                : const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock, size: 12, color: _B.danger),
                    SizedBox(width: 3),
                    Text('Edit window expired', style: TextStyle(fontSize: 11, color: _B.danger)),
                  ]),
          ),
      ]);
    } else {
      status = _badge('● Draft', _B.warning, _B.dark);
    }

    return InkWell(
      onTap: selectable ? () => _toggle(st) : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(6, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? _B.rowSelected : (_withinWindow(st) ? _B.rowEdited : Colors.white),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFDEE2E6)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 40,
            child: _canFinalize
                ? (selectable
                    ? Checkbox(value: selected, onChanged: (_) => _toggle(st), activeColor: _B.primary)
                    : const Padding(padding: EdgeInsets.only(top: 12), child: Icon(Icons.block, size: 18, color: _B.secondary)))
                : Padding(padding: const EdgeInsets.only(top: 12, left: 8), child: Text('$sn', style: const TextStyle(fontWeight: FontWeight.bold))),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_canFinalize ? '$sn. ${_s(st['fullname'])}' : _s(st['fullname']), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              const SizedBox(height: 2),
              Text('ID: ${_s(st['idnumber']).isEmpty ? 'N/A' : _s(st['idnumber'])}   •   Adm: ${_s(st['admission_number']).isEmpty ? 'N/A' : _s(st['admission_number'])}',
                  style: const TextStyle(color: _B.secondary, fontSize: 12.5)),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _badge(displayClass, transferred ? const Color(0xFFF3E5F5) : const Color(0xFFE3F2FD), transferred ? const Color(0xFF7B1FA2) : const Color(0xFF1565C0), bold: false),
                if (_s(st['department_name']).isNotEmpty) _badge(_s(st['department_name']), _B.secondary, Colors.white, bold: false),
                _badge(transferred ? 'Transferred' : 'Original', transferred ? const Color(0xFFFFF3E0) : const Color(0xFFE8F5E9),
                    transferred ? const Color(0xFFEF6C00) : const Color(0xFF2E7D32), bold: false),
              ]),
              if (transferred && _s(st['original_class_name']).isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 3), child: Text('Original: ${_s(st['original_class_name'])}', style: const TextStyle(color: _B.secondary, fontSize: 11.5))),
              const SizedBox(height: 8),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                status,
                const Spacer(),
                Text(_s(st['publish_date']).isNotEmpty ? 'Published ${_fmtDate(_s(st['publish_date']))}' : 'Not published',
                    style: const TextStyle(fontSize: 11.5, color: _B.secondary)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _pager() {
    Widget btn(String label, int? page, {bool on = false}) => InkWell(
          onTap: page == null ? null : () => _load(page: page),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 38),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _B.primary : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: on ? _B.primary : const Color(0xFFDEE2E6)),
            ),
            child: Text(label, style: TextStyle(color: on ? Colors.white : _B.primary, fontWeight: FontWeight.w600)),
          ),
        );
    final start = (_page - 2).clamp(1, _totalPages);
    final end = (_page + 2).clamp(1, _totalPages);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        if (_page > 1) btn('‹ Prev', _page - 1),
        if (start > 1) btn('1', 1),
        for (var p = start; p <= end; p++) btn('$p', p, on: p == _page),
        if (end < _totalPages) btn('$_totalPages', _totalPages),
        if (_page < _totalPages) btn('Next ›', _page + 1),
      ]),
    );
  }
}
