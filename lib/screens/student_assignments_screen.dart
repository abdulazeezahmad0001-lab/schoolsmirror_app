// lib/screens/student_assignments_screen.dart — mirrors assignment.php
//   list of the class assignments (Pending / Submitted / Overdue), open one to answer each question with
//   text and a photo/file, save a draft, submit, see score + feedback, export a PDF.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'sm_ui.dart';
import 'student_api.dart';

// ───────────────────────────── shared helpers (also used by student_home.dart) ─────────────────────────────
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

DateTime? _parseDate(dynamic v) => DateTime.tryParse(stStr(v).replaceFirst(' ', 'T'));

String fmtDue(dynamic v) {
  final d = _parseDate(v);
  return d == null ? '—' : '${_months[d.month - 1]} ${d.day}, ${d.year}';
}

Color statusColor(String s) => s == 'submitted' ? SM.green : (s == 'overdue' ? SM.rose : (s == 'draft' ? SM.violet : SM.amber));

Widget statusPill(String s) {
  final label = s == 'submitted' ? 'Submitted' : (s == 'overdue' ? 'Overdue' : (s == 'draft' ? 'Draft' : 'Pending'));
  final icon = s == 'submitted' ? Icons.check_circle_rounded : (s == 'overdue' ? Icons.error_rounded : (s == 'draft' ? Icons.edit_note_rounded : Icons.schedule_rounded));
  return SmPill(label, color: statusColor(s), icon: icon);
}

String _timeLeft(dynamic deadline, bool done) {
  final d = _parseDate(deadline);
  if (d == null) return '';
  final diff = d.difference(DateTime.now());
  if (done) return '';
  if (diff.isNegative) return 'Deadline passed';
  if (diff.inDays >= 1) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} left';
  if (diff.inHours >= 1) return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} left';
  return '${diff.inMinutes} min left';
}

// ═════════════════════════════════════════════════════════════════════════════
//  LIST
// ═════════════════════════════════════════════════════════════════════════════
class StudentAssignmentsTab extends StatefulWidget {
  final String token;
  final ValueNotifier<int?> openId; // set by a notification tap / dashboard tap
  const StudentAssignmentsTab({super.key, required this.token, required this.openId});

  @override
  State<StudentAssignmentsTab> createState() => _StudentAssignmentsTabState();
}

class _StudentAssignmentsTabState extends State<StudentAssignmentsTab> {
  bool _loading = true, _offline = false;
  String? _error;
  List<Map<String, dynamic>> _list = [];
  String _className = '';
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    widget.openId.addListener(_maybeOpen);
    _load();
  }

  @override
  void dispose() {
    widget.openId.removeListener(_maybeOpen);
    super.dispose();
  }

  Future<void> _load() async {
    final r = await StudentApi.call(widget.token, 'assignments');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = stMap(r['data']);
      await StudentCache.put('assignments', d);
      _apply(d, offline: false);
    } else if (StudentApi.isNet(r)) {
      final c = await StudentCache.get('assignments');
      if (c is Map) {
        _apply(Map<String, dynamic>.from(c), offline: true);
      } else {
        setState(() {
          _error = 'No internet connection and nothing saved yet.';
          _loading = false;
        });
      }
    } else {
      setState(() {
        _error = stStr(r['message']);
        _loading = false;
      });
    }
  }

  void _apply(Map<String, dynamic> d, {required bool offline}) {
    setState(() {
      _list = stMaps(d['assignments']);
      _className = stStr(d['class_name']);
      _offline = offline;
      _error = null;
      _loading = false;
    });
    _maybeOpen();
  }

  void _maybeOpen() {
    final id = widget.openId.value;
    if (id == null || _loading || !mounted) return;
    widget.openId.value = null;
    final a = _list.where((x) => stInt(x['id']) == id).toList();
    if (a.isNotEmpty) _open(a.first);
  }

  Future<void> _open(Map<String, dynamic> a) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _AssignmentDetailScreen(token: widget.token, assignment: a)));
    if (changed == true) _load();
  }

  int _count(String s) => _list.where((a) => s == 'pending' ? (a['status'] == 'pending' || a['status'] == 'draft') : a['status'] == s).length;

  @override
  Widget build(BuildContext context) {
    final shown = _filter == 'all' ? _list : _list.where((a) => _filter == 'pending' ? (a['status'] == 'pending' || a['status'] == 'draft') : a['status'] == _filter).toList();
    return Column(children: [
      SmTopBar(title: 'My assignments', subtitle: _className.isEmpty ? null : _className),
      Expanded(
        child: _loading
            ? const Center(child: SmLogoLoader(size: 100))
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: SmGlass(radius: 26, padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_off_rounded, size: 46, color: SM.amber),
                    const SizedBox(height: 10),
                    Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: SM.text)),
                    const SizedBox(height: 16),
                    SmButton(label: 'Try again', onTap: () { setState(() => _loading = true); _load(); }),
                  ]))))
                : RefreshIndicator(
                    color: SM.orange,
                    backgroundColor: SM.sheet,
                    onRefresh: _load,
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 130), children: [
                      if (_offline)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: SM.a(SM.amber, .13), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(SM.amber, .45))),
                          child: const Row(children: [Icon(Icons.wifi_off_rounded, color: SM.amber, size: 20), SizedBox(width: 10), Expanded(child: Text("Offline — showing what was saved last time. Connect to submit.", style: TextStyle(color: SM.text, fontSize: 13)))]),
                        ),
                      Row(children: [
                        _stat('Total', _list.length, SM.blueLight),
                        const SizedBox(width: 10),
                        _stat('Pending', _count('pending'), SM.amber),
                        const SizedBox(width: 10),
                        _stat('Done', _count('submitted'), SM.green),
                      ]),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 46,
                        child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
                          for (final f in const [['all', 'All'], ['pending', 'Pending'], ['submitted', 'Submitted'], ['overdue', 'Overdue']]) ...[
                            SmChoice(label: f[1], selected: _filter == f[0], color: f[0] == 'overdue' ? SM.rose : (f[0] == 'submitted' ? SM.green : (f[0] == 'pending' ? SM.amber : SM.blueLight)), onTap: () => setState(() => _filter = f[0])),
                            const SizedBox(width: 8),
                          ],
                        ]),
                      ),
                      const SizedBox(height: 14),
                      if (shown.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 50), child: Column(children: [Icon(Icons.assignment_turned_in_outlined, size: 56, color: SM.faint), SizedBox(height: 12), Text('Nothing here', style: TextStyle(color: SM.text, fontSize: 17, fontWeight: FontWeight.w800)), SizedBox(height: 4), Text('No assignments in this list.', style: TextStyle(color: SM.muted))]))
                      else
                        for (final a in shown) _card(a),
                    ]),
                  ),
      ),
    ]);
  }

  Widget _stat(String label, int n, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(color: SM.a(c, .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .4))),
          child: Column(children: [SmCount(n, style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.w800)), Text(label, style: const TextStyle(color: SM.muted, fontSize: 11.5, fontWeight: FontWeight.w600))]),
        ),
      );

  Widget _card(Map<String, dynamic> a) {
    final st = stStr(a['status']);
    final c = statusColor(st);
    final left = _timeLeft(a['deadline'], st == 'submitted');
    final graded = a['graded'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SmGlass(
        radius: 26,
        padding: EdgeInsets.zero,
        onTap: () => _open(a),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [SM.a(c, .22), SM.a(c, .04)]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
              border: Border(bottom: BorderSide(color: SM.glassLine)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(stStr(a['title']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 16, height: 1.25))),
              const SizedBox(width: 8),
              statusPill(st),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                SmPill(stStr(a['subject']).isEmpty ? 'General' : stStr(a['subject']), color: SM.violet, icon: Icons.menu_book_rounded),
                SmPill('Due ${fmtDue(a['deadline'])}', color: SM.cyan, icon: Icons.event_rounded),
                if (left.isNotEmpty) SmPill(left, color: st == 'overdue' ? SM.rose : SM.amber, icon: Icons.timer_rounded),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.person_rounded, size: 16, color: SM.muted),
                const SizedBox(width: 6),
                Expanded(child: Text(stStr(a['teacher_name']).isEmpty ? 'Teacher' : stStr(a['teacher_name']), style: const TextStyle(color: SM.muted, fontSize: 13))),
                Text('${a['question_count']} question${a['question_count'] == 1 ? '' : 's'} · ${_fmtMarks(a['total_marks'])} marks', style: const TextStyle(color: SM.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
              if (graded) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: SM.a(SM.green, .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(SM.green, .4))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.grade_rounded, size: 16, color: SM.green), const SizedBox(width: 6), Text('Score: ${_fmtMarks(a['total_score'])} / ${_fmtMarks(a['total_marks'])}', style: const TextStyle(color: SM.green, fontWeight: FontWeight.w800, fontSize: 13))]),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

String _fmtMarks(dynamic v) {
  final d = stDouble(v) ?? 0;
  return d % 1 == 0 ? d.toStringAsFixed(0) : d.toStringAsFixed(1);
}

// ═════════════════════════════════════════════════════════════════════════════
//  DETAIL — answer, attach, draft, submit
// ═════════════════════════════════════════════════════════════════════════════
class _AssignmentDetailScreen extends StatefulWidget {
  final String token;
  final Map<String, dynamic> assignment;
  const _AssignmentDetailScreen({required this.token, required this.assignment});

  @override
  State<_AssignmentDetailScreen> createState() => _AssignmentDetailScreenState();
}

class _AssignmentDetailScreenState extends State<_AssignmentDetailScreen> {
  late Map<String, dynamic> _a = Map<String, dynamic>.from(widget.assignment);
  final Map<int, TextEditingController> _ctrl = {};
  final Map<int, XFile> _picked = {};
  final _picker = ImagePicker();
  bool _saving = false, _changed = false;
  Timer? _debounce;

  int get _id => stInt(_a['id']) ?? 0;
  String get _status => stStr(_a['status']);
  bool get _locked => _status == 'submitted' || _a['is_overdue'] == true;
  List<Map<String, dynamic>> get _questions => stMaps(_a['questions']);
  Map<String, dynamic> get _answers => stMap(_a['answers']);

  @override
  void initState() {
    super.initState();
    _setupControllers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _setupControllers() async {
    final local = stMap(await StudentCache.get('draft_$_id')); // text typed earlier but not saved to the server
    for (final q in _questions) {
      final n = stInt(q['number']) ?? 0;
      final server = stStr(stMap(_answers['$n'])['text']);
      final c = TextEditingController(text: (!_locked && local['$n'] != null) ? stStr(local['$n']) : server);
      c.addListener(_keepLocal);
      _ctrl[n] = c;
    }
    if (mounted) setState(() {});
  }

  /// keep what the student typed on the phone, so leaving the screen or losing signal never loses it
  void _keepLocal() {
    if (_locked) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      StudentCache.put('draft_$_id', {for (final e in _ctrl.entries) '${e.key}': e.value.text});
    });
  }

  Future<void> _pick(int n, ImageSource src) async {
    try {
      final x = await _picker.pickImage(source: src, imageQuality: 80, maxWidth: 1800);
      if (x != null && mounted) setState(() => _picked[n] = x);
    } catch (_) {
      if (mounted) smToast(context, 'Could not open the ${src == ImageSource.camera ? 'camera' : 'gallery'}.', kind: SmKind.error);
    }
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) smToast(context, 'Could not open the file.', kind: SmKind.error);
    }
  }

  Future<void> _save(String mode) async {
    if (_saving || _locked) return;
    FocusScope.of(context).unfocus();
    if (mode == 'submit') {
      final empty = _questions.where((q) {
        final n = stInt(q['number']) ?? 0;
        final hasText = (_ctrl[n]?.text.trim().isNotEmpty ?? false);
        final hasFile = _picked.containsKey(n) || stStr(stMap(_answers['$n'])['file_url']).isNotEmpty;
        return !hasText && !hasFile;
      }).length;
      final ok = await smConfirm(
        context,
        'Submit assignment?',
        empty > 0 ? '$empty question${empty == 1 ? ' is' : 's are'} still unanswered.\nOnce submitted you cannot change your answers.' : 'Once submitted you cannot change your answers.',
        yes: 'Submit',
        icon: Icons.send_rounded,
        gradient: SM.mint,
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    final fields = <String, String>{'assignment_id': '$_id', 'mode': mode == 'draft' ? 'draft' : 'submit'};
    for (final e in _ctrl.entries) {
      fields['answers[${e.key}]'] = e.value.text;
    }
    final files = [
      for (final e in _picked.entries)
        StFile('answer_files[${e.key}]', e.value.path, e.value.name.isEmpty ? 'photo_${e.key}.jpg' : e.value.name, _mime(e.value.name)),
    ];
    final r = await StudentApi.upload(widget.token, 'save_submission', fields: fields, files: files);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['success'] == true) {
      final fresh = stMap(stMap(r['data'])['assignment']);
      await StudentCache.remove('draft_$_id');
      await StudentCache.remove('assignments');
      _changed = true;
      if (fresh.isNotEmpty) {
        setState(() {
          _a = fresh;
          _picked.clear();
          for (final q in _questions) {
            final n = stInt(q['number']) ?? 0;
            _ctrl[n]?.removeListener(_keepLocal);
            _ctrl[n]?.text = stStr(stMap(_answers['$n'])['text']);
            _ctrl[n]?.addListener(_keepLocal);
          }
        });
      }
      smToast(context, stStr(r['message']));
      if (mode == 'submit') Navigator.of(context).pop(true);
    } else if (StudentApi.isNet(r)) {
      smToast(context, 'No internet. Your answers are kept on this phone — connect and tap again.', kind: SmKind.warn);
    } else {
      smToast(context, stStr(r['message']), kind: SmKind.error);
    }
  }

  String _mime(String name) {
    final e = name.toLowerCase().split('.').last;
    return e == 'png' ? 'image/png' : (e == 'webp' ? 'image/webp' : (e == 'gif' ? 'image/gif' : (e == 'pdf' ? 'application/pdf' : 'image/jpeg')));
  }

  // ───────────────────────────── PDF (same content as the web page's PDF button) ─────────────────────────────
  String _safe(String s) => s.replaceAll(RegExp(r'[^\x00-\xFF]'), '?');

  Future<void> _exportPdf() async {
    try {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (c) => [
          pw.Text(_safe(stStr(_a['title'])), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text('Subject: ${_safe(stStr(_a['subject']).isEmpty ? 'General' : stStr(_a['subject']))}'),
          pw.Text('Teacher: ${_safe(stStr(_a['teacher_name']))}'),
          pw.Text('Class: ${_safe(stStr(_a['class_name']))}'),
          pw.Text('Due date: ${fmtDue(_a['deadline'])}'),
          pw.Text('Total marks: ${_fmtMarks(_a['total_marks'])}'),
          if (stStr(_a['description']).isNotEmpty) ...[pw.SizedBox(height: 10), pw.Text('Instructions', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.Text(_safe(stStr(_a['description'])))],
          pw.SizedBox(height: 16),
          pw.Divider(),
          for (final q in _questions) ...[
            pw.SizedBox(height: 8),
            pw.Text('Question ${q['number']}  (${_fmtMarks(q['marks'])} marks)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 3),
            pw.Text(_safe(stStr(q['text']))),
            pw.SizedBox(height: 6),
          ],
        ],
      ));
      await Printing.sharePdf(bytes: await doc.save(), filename: 'assignment_$_id.pdf');
    } catch (e) {
      if (mounted) smToast(context, 'Could not create the PDF.', kind: SmKind.error);
    }
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) Navigator.of(context).pop(_changed); // tells the list to refresh if something changed
      },
      child: Scaffold(
        backgroundColor: SM.bg1,
        body: SmBackground(
          child: SafeArea(
            child: Column(children: [
              SmTopBar(
                title: stStr(_a['title']),
                subtitle: stStr(_a['subject']).isEmpty ? 'Assignment' : stStr(_a['subject']),
                onBack: () => Navigator.of(context).pop(_changed),
                actions: [SmIconBtn(icon: Icons.picture_as_pdf_rounded, onTap: _exportPdf)],
              ),
              Expanded(
                child: ListView(padding: const EdgeInsets.fromLTRB(16, 6, 16, 24), children: [
                  _info(),
                  if (_a['is_overdue'] == true) _note(Icons.error_rounded, SM.rose, 'This assignment is overdue and can no longer be submitted.'),
                  if (_status == 'submitted') _note(Icons.check_circle_rounded, SM.green, 'Submitted on ${stStr(stMap(_a['submission'])['submitted_at'])}. Your answers are locked.'),
                  const SmSectionTitle('Questions'),
                  if (_questions.isEmpty) const SmGlass(radius: 22, child: Text('This assignment has no questions.', style: TextStyle(color: SM.muted))),
                  for (final q in _questions) _question(q),
                ]),
              ),
              if (!_locked) _bar(),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _note(IconData i, Color c, String t) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: SM.a(c, .12), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(c, .45))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, color: c, size: 22), const SizedBox(width: 10), Expanded(child: Text(t, style: const TextStyle(color: SM.text, fontSize: 13.5, height: 1.4)))]),
      );

  Widget _info() {
    final left = _timeLeft(_a['deadline'], _status == 'submitted');
    return SmGlass(
      radius: 28,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [SM.a(statusColor(_status), .20), SM.a(SM.blue, .10)]),
      border: SM.a(statusColor(_status), .4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [statusPill(_status), const Spacer(), if (left.isNotEmpty) SmPill(left, color: _status == 'overdue' ? SM.rose : SM.amber, icon: Icons.timer_rounded)]),
        const SizedBox(height: 14),
        Text(stStr(_a['title']), style: const TextStyle(color: SM.text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.3, height: 1.25)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          SmPill(stStr(_a['subject']).isEmpty ? 'General' : stStr(_a['subject']), color: SM.violet, icon: Icons.menu_book_rounded),
          SmPill('Due ${fmtDue(_a['deadline'])}', color: SM.cyan, icon: Icons.event_rounded),
          SmPill('${_fmtMarks(_a['total_marks'])} marks', color: SM.orange, icon: Icons.grade_rounded),
        ]),
        const SizedBox(height: 10),
        Row(children: [const Icon(Icons.person_rounded, size: 16, color: SM.muted), const SizedBox(width: 6), Expanded(child: Text(stStr(_a['teacher_name']), style: const TextStyle(color: SM.muted, fontSize: 13)))]),
        if (stStr(_a['description']).isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(height: 1, color: SM.glassLine),
          const SizedBox(height: 12),
          Text(stStr(_a['description']), style: const TextStyle(color: SM.text, fontSize: 14, height: 1.5)),
        ],
        if (_a['graded'] == true) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: SM.a(SM.green, .12), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(SM.green, .45))),
            child: Row(children: [const Icon(Icons.grade_rounded, color: SM.green), const SizedBox(width: 10), Text('Your score: ${_fmtMarks(_a['total_score'])} / ${_fmtMarks(_a['total_marks'])}', style: const TextStyle(color: SM.green, fontWeight: FontWeight.w800, fontSize: 15))]),
          ),
        ],
      ]),
    );
  }

  Widget _question(Map<String, dynamic> q) {
    final n = stInt(q['number']) ?? 0;
    final ans = stMap(_answers['$n']);
    final ctrl = _ctrl[n];
    final picked = _picked[n];
    final fileUrl = stStr(ans['file_url']);
    final score = stDouble(ans['score']);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SmGlass(
        radius: 26,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 34, height: 34, alignment: Alignment.center, decoration: BoxDecoration(gradient: SM.brand, borderRadius: BorderRadius.circular(12)), child: Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Text('Question $n', style: const TextStyle(color: SM.muted, fontWeight: FontWeight.w700, fontSize: 13)),
            const Spacer(),
            SmPill('${_fmtMarks(q['marks'])} mark${stDouble(q['marks']) == 1 ? '' : 's'}', color: SM.orange),
          ]),
          const SizedBox(height: 12),
          Text(stStr(q['text']), style: const TextStyle(color: SM.text, fontSize: 15, height: 1.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          if (_locked)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: SM.a(Colors.white, .05), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.glassLine)),
              child: Text(stStr(ans['text']).isEmpty ? 'No written answer' : stStr(ans['text']), style: TextStyle(color: stStr(ans['text']).isEmpty ? SM.faint : SM.text, fontSize: 14, height: 1.5)),
            )
          else
            TextField(
              controller: ctrl,
              minLines: 4,
              maxLines: 10,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(color: SM.text, fontSize: 15, height: 1.45),
              cursorColor: SM.orange,
              decoration: smInput('Type your answer here…', accent: SM.orange),
            ),
          const SizedBox(height: 12),
          if (fileUrl.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SmPress(
                onTap: () => _openUrl(fileUrl),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: SM.a(SM.cyan, .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(SM.cyan, .4))),
                  child: Row(children: [const Icon(Icons.attach_file_rounded, size: 18, color: SM.cyan), const SizedBox(width: 8), Expanded(child: Text(stStr(ans['file_name']).isEmpty ? 'View attached file' : stStr(ans['file_name']), style: const TextStyle(color: SM.cyan, fontWeight: FontWeight.w700, fontSize: 13))), const Icon(Icons.open_in_new_rounded, size: 16, color: SM.cyan)]),
                ),
              ),
            ),
          if (picked != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
              decoration: BoxDecoration(color: SM.a(SM.green, .12), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(SM.green, .4))),
              child: Row(children: [
                const Icon(Icons.image_rounded, size: 18, color: SM.green),
                const SizedBox(width: 8),
                Expanded(child: Text('${picked.name.isEmpty ? 'Photo' : picked.name} — will upload', maxLines: 2, style: const TextStyle(color: SM.green, fontWeight: FontWeight.w700, fontSize: 12.5))),
                IconButton(onPressed: () => setState(() => _picked.remove(n)), icon: const Icon(Icons.close_rounded, size: 18, color: SM.muted)),
              ]),
            ),
          if (!_locked)
            Row(children: [
              Expanded(child: SmButton(label: 'Camera', icon: Icons.photo_camera_rounded, outline: true, height: 44, onTap: () => _pick(n, ImageSource.camera))),
              const SizedBox(width: 10),
              Expanded(child: SmButton(label: 'Gallery', icon: Icons.photo_library_rounded, outline: true, height: 44, onTap: () => _pick(n, ImageSource.gallery))),
            ]),
          if (_locked && (score != null || stStr(ans['feedback']).isNotEmpty))
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: SM.a(SM.green, .10), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(SM.green, .4))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (score != null) Text('Score: ${_fmtMarks(score)} / ${_fmtMarks(q['marks'])}', style: const TextStyle(color: SM.green, fontWeight: FontWeight.w800)),
                if (stStr(ans['feedback']).isNotEmpty) Padding(padding: EdgeInsets.only(top: score != null ? 4 : 0), child: Text('Teacher: ${stStr(ans['feedback'])}', style: const TextStyle(color: SM.text, fontSize: 13.5, height: 1.4))),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _bar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SM.a(SM.bg1, 0), SM.a(SM.bg0, .97)]), border: Border(top: BorderSide(color: SM.glassLine))),
        child: Row(children: [
          Expanded(child: SmButton(label: 'Save draft', icon: Icons.save_rounded, outline: true, height: 52, onTap: _saving ? null : () => _save('draft'))),
          const SizedBox(width: 10),
          Expanded(child: SmButton(label: 'Submit', icon: Icons.send_rounded, gradient: SM.mint, glow: SM.green, height: 52, loading: _saving, onTap: () => _save('submit'))),
        ]),
      );
}
