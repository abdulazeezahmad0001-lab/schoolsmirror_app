// flutter_results_overview_screen.dart  —  "Aurora Glass" redesign
// Mirrors results_overview.php ("Result Finalization"): class / session / term / department filters,
// student list with Draft / Finalized / No Result, the 30-day edit window, Select All Drafts, Select Edited,
// Finalize Selected and Re-Finalize — plus a PUSH notification to students, parents and admins.
// Needs: sm_ui.dart, push_notification_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'sm_ui.dart';
import 'push_notification_service.dart';

// extensionless address first (a redirect from "*.php" would drop the POST body), then the other form
const List<String> _roUrls = [
  'https://schoolsmirror.com/flutter_results_overview',
  'https://schoolsmirror.com/flutter_results_overview.php',
];
int _roIdx = 0;

int? _i(dynamic v) => v == null ? null : int.tryParse('$v');
String _s(dynamic v) => v == null ? '' : '$v';
List<Map<String, dynamic>> _ml(dynamic v) => (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
    return d['success'] != true && (m == 'Unexpected server response' || m.startsWith('Missing token') || m.startsWith('The server received this request as'));
  }

  static Future<Map<String, dynamic>> call(String token, String action, {Map<String, String> form = const {}, Map<String, dynamic>? json, int timeout = 25}) async {
    var idx = _roIdx;
    var net = false;
    Map<String, dynamic> last = {'success': false, 'message': 'Unexpected server response'};
    for (var t = 0; t < _roUrls.length; t++) {
      try {
        final q = json != null ? {'token': token, 'action': action} : {'token': token, 'action': action, ...form};
        final uri = Uri.parse(_roUrls[idx]).replace(queryParameters: q);
        final http.Response res = json != null
            ? await http.post(uri, headers: {'Content-Type': 'application/json; charset=utf-8'}, body: jsonEncode({...json, 'token': token, 'action': action})).timeout(Duration(seconds: timeout))
            : await http.post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: {'token': token, 'action': action, ...form}).timeout(Duration(seconds: timeout));
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
  bool _booting = true, _fetching = false, _busy = false;
  String? _bootError;

  bool _canFinalize = false, _pushReady = false, _guardians = false;
  List<Map<String, dynamic>> _classes = [], _sessions = [], _terms = [], _depts = [];

  int? _cls, _sess, _term, _dept;
  int? _curCls, _curSess, _curTerm; // the filters used for the list on screen
  String _sessionLabel = '', _termLabel = '';

  List<Map<String, dynamic>> _students = [];
  int _page = 1, _totalPages = 0, _total = 0, _perPage = 20;
  bool _hasList = false;
  final Set<int> _sel = {};

  bool _guideOpen = true, _notify = true;
  String? _alertMsg, _alertNote;
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
        _bootError = _network(r) ? 'No internet connection. Result Overview needs the internet to load and publish results.' : _s(r['message']);
        _booting = false;
      });
    }
  }

  bool _network(Map<String, dynamic> r) => r['network'] == true;

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
      _showAlert(_network(r) ? 'No internet connection.' : _s(r['message']), error: true);
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
    setState(() => allOn ? _sel.removeAll(ids) : _sel.addAll(ids));
  }

  void _selectEdited() {
    final ids = _students.where(_withinWindow).map((s) => _i(s['user_id'])!).toList();
    if (ids.isEmpty) {
      smToast(context, 'No finalized results inside the 30-day edit window on this page.', kind: SmKind.warn);
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
    if (push['configured'] != true) return 'Push is not set up on the server yet — the notification was saved in the in-app inbox only.';
    if (devices == 0) return 'No registered phones were found for these people yet. The notification was saved in their in-app inbox.';
    return '🔔 Sending notifications to $rec ${rec == 1 ? 'person' : 'people'} on $devices device${devices == 1 ? '' : 's'}.';
  }

  Future<void> _finalize({required bool re}) async {
    final rows = _selectedRows;
    if (rows.isEmpty || _busy) return;
    final n = rows.length;
    final ok = await smConfirm(
      context,
      re ? 'Re-finalize results?' : 'Finalize results?',
      '${re ? 'Update the published results of' : 'Publish the results of'} $n selected student${n == 1 ? '' : 's'}?\n\n'
      '${_notify ? '🔔 Students${_guardians ? ', parents' : ''} and admins will get a push notification.' : '🔕 No push notification will be sent.'}',
      yes: re ? 'Re-finalize' : 'Finalize',
      icon: re ? Icons.sync_rounded : Icons.send_rounded,
      gradient: re ? SM.hot : SM.mint,
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
      _showAlert(_network(r) ? 'No internet connection. Nothing was changed.' : _s(r['message']), error: true);
    }
  }

  Future<void> _sendTest() async {
    final msg = await PushNotificationService.instance.sendTest(widget.token);
    if (mounted) smToast(context, msg, kind: msg.toLowerCase().contains('sent') ? SmKind.success : SmKind.warn);
  }

  /// bell button: shows what is connected, with a "Send test notification" button
  Future<void> _pushStatus() async {
    smToast(context, 'Checking push setup…', kind: SmKind.info);
    final r = await PushNotificationService.instance.status(widget.token);
    if (!mounted) return;
    final checks = _ml(r['checks']);
    final ready = r['ready'] == true;
    await smSheet<void>(
      context,
      (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        minChildSize: .45,
        maxChildSize: .95,
        builder: (_, sc) => SmSheetFrame(
          title: 'Push notification status',
          subtitle: ready ? 'Everything is connected' : (_s(r['message']).isEmpty ? 'Something needs attention' : _s(r['message'])),
          icon: ready ? Icons.verified_rounded : Icons.notifications_active_rounded,
          child: Column(children: [
            Expanded(
              child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), children: [
                for (final c in checks)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SmGlass(
                      radius: 20,
                      padding: const EdgeInsets.all(14),
                      color: SM.a(c['ok'] == true ? SM.green : SM.rose, .08),
                      border: SM.a(c['ok'] == true ? SM.green : SM.rose, .45),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(c['ok'] == true ? Icons.check_circle_rounded : Icons.cancel_rounded, color: c['ok'] == true ? SM.green : SM.rose, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_s(c['title']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5)),
                            if (_s(c['hint']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(_s(c['hint']), style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.4))),
                          ]),
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SmButton(
                label: 'Send test notification',
                icon: Icons.send_rounded,
                gradient: SM.hot,
                glow: SM.orange,
                onTap: () {
                  Navigator.pop(ctx);
                  _sendTest();
                },
              ),
            ),
          ]),
        ),
      ),
    );
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
              title: 'Result Overview',
              subtitle: _hasList ? '$_sessionLabel · $_termLabel' : 'Finalize and publish results',
              onBack: () => Navigator.of(context).maybePop(),
              actions: [SmIconBtn(icon: Icons.notifications_active_rounded, onTap: _booting ? null : _pushStatus)],
            ),
            Expanded(
              child: _booting
                  ? const Center(child: SmLogoLoader(size: 110, label: 'Loading…'))
                  : _bootError != null
                      ? _bootErrorView()
                      : RefreshIndicator(
                          color: SM.orange,
                          backgroundColor: SM.sheet,
                          onRefresh: () async => _hasList ? _load(page: _page) : _boot(),
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                            children: [
                              if (_alertMsg != null) _alertBox(),
                              if (_guideOpen) _guide(),
                              _filters(),
                              if (_hasList) ..._results(),
                            ],
                          ),
                        ),
            ),
            if (_hasList && _canFinalize && _students.isNotEmpty) _actionBar(),
          ]),
        ),
      ),
    );
  }

  Widget _bootErrorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SmGlass(
            radius: 28,
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 52, color: SM.amber),
              const SizedBox(height: 12),
              Text(_bootError!, textAlign: TextAlign.center, style: const TextStyle(color: SM.text, fontSize: 14.5, height: 1.4)),
              const SizedBox(height: 18),
              SmButton(label: 'Try again', icon: Icons.refresh_rounded, onTap: _boot),
            ]),
          ),
        ),
      );

  Widget _alertBox() {
    final c = _alertError ? SM.rose : SM.green;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SM.a(c, .13), borderRadius: BorderRadius.circular(20), border: Border.all(color: SM.a(c, .55))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(_alertError ? Icons.error_rounded : Icons.check_circle_rounded, color: c, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_alertMsg!, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w700, fontSize: 14, height: 1.35)),
            if (_alertNote != null && _alertNote!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_alertNote!, style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.4))),
          ]),
        ),
        InkWell(onTap: () => setState(() => _alertMsg = null), child: const Icon(Icons.close_rounded, size: 19, color: SM.muted)),
      ]),
    );
  }

  Widget _guide() {
    Widget li(Color c, String bold, String rest) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(margin: const EdgeInsets.only(top: 5), width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(child: Text.rich(TextSpan(style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.4), children: [TextSpan(text: '$bold ', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800)), TextSpan(text: rest)]))),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 16),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [SM.a(SM.cyan, .16), SM.a(SM.blueLight, .10)]), borderRadius: BorderRadius.circular(22), border: Border.all(color: SM.a(SM.cyan, .4))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.lightbulb_rounded, size: 20, color: SM.cyan),
          const SizedBox(width: 8),
          const Expanded(child: Text('How publishing works', style: TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5))),
          IconButton(onPressed: () => setState(() => _guideOpen = false), icon: const Icon(Icons.close_rounded, size: 19, color: SM.muted)),
        ]),
        li(SM.amber, 'Draft:', 'can be edited any time. Select and tap Finalize to publish.'),
        li(SM.green, 'Finalized:', 'published, with a 30-day edit window. After editing, use Re-Finalize.'),
        li(SM.rose, 'After 30 days:', 'only admins can edit the results.'),
        li(SM.orange, 'Notifications:', 'publishing can send a push notification to students, parents and admins.'),
      ]),
    );
  }

  Widget _lbl(String t, {IconData? icon}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 10),
        child: Row(children: [if (icon != null) ...[Icon(icon, size: 16, color: SM.orange), const SizedBox(width: 7)], Text(t, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14))]),
      );

  Widget _filters() {
    final classOn = _cls != null;
    return SmGlass(
      radius: 28,
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl('1 · Class', icon: Icons.class_rounded),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in _classes)
            SmChoice(label: '${_s(c['class_name'])} · ${_s(c['student_count'])}', color: SM.violet, selected: _i(c['class_id']) == _cls, onTap: () => setState(() {
                  _cls = _i(c['class_id']);
                  _hasList = false;
                })),
        ]),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !classOn
              ? const SizedBox(width: double.infinity)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('2 · Session', icon: Icons.event_available_rounded),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final x in _sessions) SmChoice(label: _s(x['session_name']), selected: _i(x['id']) == _sess, onTap: () => setState(() => _sess = _i(x['id'])))]),
                  _lbl('3 · Term', icon: Icons.schedule_rounded),
                  Wrap(spacing: 8, runSpacing: 8, children: [for (final x in _terms) SmChoice(label: _s(x['term_name']), color: SM.orange, selected: _i(x['id']) == _term, onTap: () => setState(() => _term = _i(x['id'])))]),
                  if (_depts.isNotEmpty) ...[
                    _lbl('Department (optional)', icon: Icons.apartment_rounded),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      SmChoice(label: 'All', color: SM.cyan, selected: _dept == null, onTap: () => setState(() => _dept = null)),
                      for (final x in _depts) SmChoice(label: _s(x['department_name']), color: SM.cyan, selected: _i(x['id']) == _dept, onTap: () => setState(() => _dept = _i(x['id']))),
                    ]),
                  ],
                ]),
        ),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(child: SmButton(label: 'Fetch students', icon: Icons.search_rounded, loading: _fetching, onTap: _canFetch ? () => _load() : null)),
          if (_hasList) ...[const SizedBox(width: 10), SizedBox(width: 56, child: SmButton(label: '', icon: Icons.refresh_rounded, outline: true, onTap: _fetching ? null : () => _load(page: _page)))],
        ]),
      ]),
    );
  }

  List<Widget> _results() {
    final drafts = _students.where(_isDraft).length;
    final finals = _students.where(_isFinal).length;
    final none = _students.length - drafts - finals;
    return [
      const SizedBox(height: 16),
      Row(children: [
        _stat('Draft', drafts, SM.amber),
        const SizedBox(width: 10),
        _stat('Finalized', finals, SM.green),
        const SizedBox(width: 10),
        _stat('No result', none, SM.muted),
      ]),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [
          Expanded(child: Text('$_total student${_total == 1 ? '' : 's'}', style: const TextStyle(color: SM.text, fontSize: 17, fontWeight: FontWeight.w800))),
          if (_canFinalize) ...[
            _chipBtn('Select drafts', Icons.checklist_rounded, SM.blueLight, _students.any(_selectable) ? _selectAllDrafts : null),
            const SizedBox(width: 8),
            _chipBtn('Edited', Icons.edit_rounded, SM.cyan, _selectEdited),
          ],
        ]),
      ),
      if (!_canFinalize)
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: SM.glass, borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.glassLine)),
          child: const Row(children: [Icon(Icons.lock_rounded, size: 18, color: SM.muted), SizedBox(width: 10), Expanded(child: Text('Only administrators can finalize results. You can view the status here.', style: TextStyle(color: SM.muted, fontSize: 13)))]),
        ),
      if (_students.isEmpty)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No students found with results for this selection.', textAlign: TextAlign.center, style: TextStyle(color: SM.muted))))
      else
        for (var k = 0; k < _students.length; k++) _studentCard(_students[k], (_page - 1) * _perPage + k + 1),
      if (_totalPages > 1) _pager(),
      const SizedBox(height: 20),
    ];
  }

  Widget _stat(String label, int n, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: SM.a(c, .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .4))),
          child: Column(children: [
            SmCount(n, style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: SM.muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _chipBtn(String label, IconData i, Color c, VoidCallback? onTap) => SmPress(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? .4 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: SM.a(c, .14), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(c, .5))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 15, color: c), const SizedBox(width: 6), Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5))]),
          ),
        ),
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
    final cls = transferred ? (_s(st['effective_class_name']).isEmpty ? _s(st['class_name']) : _s(st['effective_class_name'])) : (_s(st['original_class_name']).isEmpty ? _s(st['class_name']) : _s(st['original_class_name']));

    Widget status;
    if (!hasResult) {
      status = const SmPill('No result', color: SM.muted, icon: Icons.remove_circle_outline_rounded);
    } else if (fin) {
      status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SmPill('Finalized', color: SM.green, icon: Icons.check_circle_rounded),
        if (days != null) Padding(padding: const EdgeInsets.only(top: 5), child: Text(days <= 30 ? '${30 - days} days left to edit' : 'Edit window expired', style: TextStyle(color: days <= 30 ? SM.amber : SM.rose, fontSize: 11.5, fontWeight: FontWeight.w700))),
      ]);
    } else {
      status = const SmPill('Draft', color: SM.amber, icon: Icons.edit_note_rounded);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SmGlass(
        radius: 24,
        padding: const EdgeInsets.all(12),
        color: selected ? SM.a(SM.blueLight, .20) : (_withinWindow(st) ? SM.a(SM.amber, .07) : null),
        border: selected ? SM.a(SM.blueLight, .8) : null,
        onTap: selectable ? () => _toggle(st) : null,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (_canFinalize)
            Padding(
              padding: const EdgeInsets.only(right: 10, top: 14),
              child: selectable
                  ? AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(shape: BoxShape.circle, gradient: selected ? SM.brand : null, border: Border.all(color: selected ? Colors.transparent : SM.faint, width: 2)),
                      child: selected ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
                    )
                  : const Icon(Icons.lock_outline_rounded, size: 24, color: SM.faint),
            ),
          SmAvatar(url: _s(st['image_url']).isNotEmpty ? _s(st['image_url']) : _s(st['image']), name: _s(st['fullname']), size: 50),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_s(st['fullname']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 15, height: 1.25)),
              const SizedBox(height: 2),
              Text('#$sn  ·  ID ${_s(st['idnumber']).isEmpty ? 'N/A' : _s(st['idnumber'])}${_s(st['admission_number']).isEmpty ? '' : '  ·  Adm ${_s(st['admission_number'])}'}', style: const TextStyle(color: SM.muted, fontSize: 12, height: 1.3)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                SmPill(transferred ? '$cls (current)' : cls, color: transferred ? SM.violet : SM.blueLight),
                if (_s(st['department_name']).isNotEmpty) SmPill(_s(st['department_name']), color: SM.cyan),
                if (transferred) const SmPill('Transferred', color: SM.orange),
              ]),
              const SizedBox(height: 10),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                status,
                const Spacer(),
                Text(_s(st['publish_date']).isNotEmpty ? _fmtDate(_s(st['publish_date'])) : 'Not published', style: const TextStyle(fontSize: 11.5, color: SM.faint)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _pager() {
    Widget btn(String label, int? page, {bool on = false}) => SmPress(
          onTap: page == null ? null : () => _load(page: page),
          child: Container(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: on ? SM.brand : null, color: on ? null : SM.glass, borderRadius: BorderRadius.circular(15), border: Border.all(color: on ? Colors.transparent : SM.glassLine)),
            child: Text(label, style: TextStyle(color: on ? Colors.white : SM.text, fontWeight: FontWeight.w800)),
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

  // ───────────────────────────── sticky action bar ─────────────────────────────
  Widget _actionBar() {
    final canFin = _sel.isNotEmpty && _hasDraftSelected && !_busy;
    final canRe = _sel.isNotEmpty && _hasFinalSelected && !_busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SM.a(SM.bg1, 0), SM.a(SM.bg0, .97)]),
        border: Border(top: BorderSide(color: SM.glassLine)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SmPress(
          onTap: () => setState(() => _notify = !_notify),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(color: SM.a(_notify ? SM.green : SM.muted, .10), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(_notify ? SM.green : SM.muted, .4))),
            child: Row(children: [
              Icon(_notify ? Icons.notifications_active_rounded : Icons.notifications_off_rounded, size: 20, color: _notify ? SM.green : SM.muted),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_notify ? 'Push notification ON' : 'Push notification OFF', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 13)),
                  Text(!_pushReady ? 'Server push not set up — inbox only' : (_guardians ? 'Students, parents & admins' : 'Students & admins'), style: TextStyle(color: _pushReady ? SM.muted : SM.orange, fontSize: 11.5)),
                ]),
              ),
              Switch(value: _notify, onChanged: (v) => setState(() => _notify = v), activeColor: SM.green),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: SmButton(label: _sel.isEmpty ? 'Finalize' : 'Finalize (${_selectedRows.where(_isDraft).length})', icon: Icons.send_rounded, gradient: SM.mint, glow: SM.green, height: 52, loading: _busy, onTap: canFin ? () => _finalize(re: false) : null)),
          const SizedBox(width: 10),
          Expanded(child: SmButton(label: 'Re-finalize', icon: Icons.sync_rounded, gradient: SM.hot, glow: SM.orange, height: 52, onTap: canRe ? () => _finalize(re: true) : null)),
        ]),
      ]),
    );
  }
}
