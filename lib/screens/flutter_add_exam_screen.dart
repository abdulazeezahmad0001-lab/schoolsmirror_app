// flutter_add_exam_screen.dart
// Mirrors add_exam.php 1:1: free-trial / subscription banners, session-term-class filters,
// exam form (MCQ + images + theory), Scientific Tools, All Subjects list, edit details,
// publish / delete / delete all, pagination, How It Works and Flutterwave payment.
//
// pubspec.yaml needs:  http, shared_preferences, image_picker, url_launcher

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api/api_client.dart';

// Your host redirects "*.php" to the extensionless address, and a redirect turns POST into GET
// (the form data is lost -> "Missing token"). So the extensionless URL is tried first and the app
// switches to the other form automatically if one of them fails.
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_add_exam',
  'https://schoolsmirror.com/flutter_add_exam.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

/// Same colour tokens as the :root block of add_exam.php
class _C {
  static const primary = Color(0xFF0083B0);
  static const secondary = Color(0xFF00B4DB);
  static const success = Color(0xFF28A745);
  static const draft = Color(0xFF6C757D);
  static const danger = Color(0xFFDC3545);
  static const warning = Color(0xFFFFC107);
  static const info = Color(0xFF17A2B8);
  static const theory = Color(0xFF8B4513);
  static const sci = Color(0xFF6F42C1);
  static const lightBg = Color(0xFFF8F9FA);
  static const border = Color(0xFFDEE2E6);
  static const text = Color(0xFF333333);
  static const purple1 = Color(0xFF667EEA);
  static const purple2 = Color(0xFF764BA2);
  static const payment = Color(0xFF9C27B0);

  static const headerGradient = LinearGradient(colors: [primary, secondary]);
  static const bannerGradient = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [purple1, purple2]);
}

// ───────────────────────────── API helper ─────────────────────────────
class _Api {
  /// true when the answer means "wrong address / body lost" -> try the other URL form
  static bool shouldRetry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' ||
            m.startsWith('The server received this request as') ||
            m.startsWith('Missing token'));
  }

  static Future<Map<String, dynamic>> post(String token, String action,
      [Map<String, String> fields = const {}]) async {
    Map<String, dynamic> last = {'success': false, 'message': 'Network error. Check your connection.'};
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        // token + action are ALSO sent in the URL so they survive a redirect that drops the body
        final uri = Uri.parse(_apiUrl).replace(queryParameters: {'token': token, 'action': action, ...fields});
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
              body: {'token': token, 'action': action, ...fields},
            )
            .timeout(const Duration(seconds: 40));
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

class _Up {
  final String field;
  final Uint8List bytes;
  final String name;
  const _Up(this.field, this.bytes, this.name);
}

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

int? _toInt(dynamic v) => v == null ? null : int.tryParse('$v');

String _naira(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '₦$b';
}

// ───────────────────────────── form models ─────────────────────────────
class _Q {
  final TextEditingController text = TextEditingController();
  final List<TextEditingController> opts = List.generate(4, (_) => TextEditingController());
  int? answer; // 1..4, same values as the web form / database
  Uint8List? imageBytes;
  String? imageName;
  String? existingImage; // file name kept when editing a draft
  String? existingImageUrl;

  void dispose() {
    text.dispose();
    for (final o in opts) {
      o.dispose();
    }
  }
}

class _TQ {
  final TextEditingController text = TextEditingController();
  final TextEditingController marks = TextEditingController(text: '5');
  void dispose() {
    text.dispose();
    marks.dispose();
  }
}

// ───────────────────────────── SCREEN ─────────────────────────────
class FlutterAddExamScreen extends StatefulWidget {
  final String? token;
  const FlutterAddExamScreen({super.key, this.token});

  @override
  State<FlutterAddExamScreen> createState() => _FlutterAddExamScreenState();
}

class _FlutterAddExamScreenState extends State<FlutterAddExamScreen> with WidgetsBindingObserver {
  String? _token;
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _sessions = [], _terms = [], _classes = [];
  Map<String, dynamic> _status = {};

  // dropdown choices (before pressing Apply Filters) and the applied filters
  int? _pSession, _pTerm, _pClass;
  int? _sessionId, _termId, _classId;

  int _editSubjectId = 0;
  final _titleCtrl = TextEditingController();
  final List<_Q> _questions = [_Q()];
  final List<_TQ> _theory = [_TQ()];
  bool _includeTheory = false;

  // field currently selected for the Scientific Tools
  TextEditingController? _activeCtrl;
  String _activeLabel = '';

  List<Map<String, dynamic>> _subjects = [];
  int _page = 1, _totalPages = 0, _total = 0, _firstSn = 1;
  bool _loadingSubjects = false;

  bool _showHow = false;
  String? _banner;
  bool _bannerError = false;
  String? _pendingRef;

  final _scroll = ScrollController();
  final _subjectsKey = GlobalKey();
  final _picker = ImagePicker();

  // ───── status helpers (same variables as add_exam.php)
  bool get _hasFreeTrial => _status['has_free_trial'] == true;
  bool get _hasActive => _status['has_active_subscription'] == true;
  bool get _canCreate => _status['can_create_subject'] != false;
  bool get _cbtEnabled => _status['cbt_enabled'] != false;
  int get _subjectCount => _toInt(_status['subject_count']) ?? 0;
  int get _trialLimit => _toInt(_status['free_trial_limit']) ?? 5;
  int get _remaining => _toInt(_status['remaining_subjects']) ?? 0;
  String get _trialMsg => '${_status['free_trial_message'] ?? ''}';
  bool get _filtersReady => _sessionId != null && _termId != null && _classId != null;
  bool get _formVisible => _filtersReady;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleCtrl.dispose();
    for (final q in _questions) {
      q.dispose();
    }
    for (final t in _theory) {
      t.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingRef != null) _verifyPayment(silent: true);
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

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(msg), backgroundColor: error ? _C.danger : _C.success, behavior: SnackBarBehavior.floating));
  }

  void _setBanner(String msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _banner = msg;
      _bannerError = error;
    });
  }

  // ───────────────────────────── data loading ─────────────────────────────
  Future<void> _init() async {
    _token = await _getToken();
    if (_token == null) {
      setState(() => _loading = false);
      _toast('Session expired. Please log in again.', error: true);
      return;
    }
    await _loadBootstrap();
    await _loadSubjects();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBootstrap() async {
    final r = await _Api.post(_token!, 'bootstrap');
    if (r['success'] == true && mounted) {
      final d = r['data'] as Map<String, dynamic>;
      setState(() {
        _sessions = _maps(d['sessions']);
        _terms = _maps(d['terms']);
        _classes = _maps(d['classes']);
        _status = Map<String, dynamic>.from(d['status'] ?? {});
      });
    } else {
      _setBanner('${r['message'] ?? 'Failed to load'}', error: true);
    }
  }

  Future<void> _loadSubjects({int? page}) async {
    if (_token == null) return;
    setState(() => _loadingSubjects = true);
    final r = await _Api.post(_token!, 'list_subjects', {
      'page': '${page ?? _page}',
      if (_sessionId != null) 'session_id': '$_sessionId',
      if (_termId != null) 'term_id': '$_termId',
      if (_classId != null) 'class_id': '$_classId',
    });
    if (!mounted) return;
    if (r['success'] == true) {
      final d = r['data'] as Map<String, dynamic>;
      setState(() {
        _subjects = _maps(d['subjects']);
        _total = _toInt(d['total']) ?? 0;
        _page = _toInt(d['page']) ?? 1;
        _totalPages = _toInt(d['total_pages']) ?? 0;
        _firstSn = _toInt(d['first_sn']) ?? 1;
        _loadingSubjects = false;
      });
    } else {
      setState(() => _loadingSubjects = false);
      _setBanner('${r['message']}', error: true);
    }
  }

  Future<void> _refreshAll() async {
    await _loadBootstrap();
    await _loadSubjects();
  }

  /// After saving, show the new subject in the "All Subjects" list below the form.
  void _scrollToSubjects() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      var ctx = _subjectsKey.currentContext;
      if (ctx == null) {
        // list is far below and not built yet -> jump near the end first
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final c = _subjectsKey.currentContext;
          if (mounted && c != null) {
            Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 400), curve: Curves.easeOut, alignment: 0.0);
          }
        });
        return;
      }
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), curve: Curves.easeOut, alignment: 0.0);
    });
  }

  // ───────────────────────────── filters ─────────────────────────────
  void _applyFilters() {
    setState(() {
      _sessionId = _pSession;
      _termId = _pTerm;
      _classId = _pClass;
      _page = 1;
      _banner = null;
    });
    if (_editSubjectId > 0) _resetForm();
    _loadSubjects(page: 1);
  }

  void _clearFilters() {
    setState(() {
      _pSession = _pTerm = _pClass = null;
      _sessionId = _termId = _classId = null;
      _page = 1;
      _banner = null;
    });
    if (_editSubjectId > 0) _resetForm();
    _loadSubjects(page: 1);
  }

  String _nameOf(List<Map<String, dynamic>> list, String idKey, String nameKey, int? id) {
    for (final m in list) {
      if (_toInt(m[idKey]) == id) return '${m[nameKey]}';
    }
    return '';
  }

  // ───────────────────────────── form actions ─────────────────────────────
  void _resetForm() {
    final oldQ = List<_Q>.of(_questions);
    final oldT = List<_TQ>.of(_theory);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final q in oldQ) {
        q.dispose();
      }
      for (final t in oldT) {
        t.dispose();
      }
    });
    setState(() {
      _titleCtrl.clear();
      _questions
        ..clear()
        ..add(_Q());
      _theory
        ..clear()
        ..add(_TQ());
      _includeTheory = false;
      _editSubjectId = 0;
      _activeCtrl = null;
    });
  }

  void _addQuestion() => setState(() => _questions.add(_Q()));

  Future<void> _removeQuestion(int i) async {
    if (_questions.length <= 1) {
      await _alert('Cannot Remove', 'You must have at least one question!', icon: Icons.error, color: _C.danger);
      return;
    }
    final ok = await _confirm('Remove Question?', 'Are you sure you want to remove this question?', yes: 'Yes, remove it!');
    if (ok != true) return;
    setState(() {
      _activeCtrl = null;
      _questions.removeAt(i).dispose();
    });
    _toast('Question has been removed.');
  }

  void _addTheory() => setState(() => _theory.add(_TQ()));

  Future<void> _removeTheory(int i) async {
    if (_theory.length > 1) {
      final ok = await _confirm('Remove Theory Question?', 'Are you sure you want to remove this theory question?',
          yes: 'Yes, remove it!');
      if (ok != true) return;
      setState(() {
        _activeCtrl = null;
        _theory.removeAt(i).dispose();
      });
      _toast('Theory question has been removed.');
    } else {
      _theory[i].text.clear();
      _theory[i].marks.text = '5';
      setState(() {});
    }
  }

  Future<void> _pickImage(_Q q) async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      _toast('Image must be 5MB or less.', error: true);
      return;
    }
    var name = x.name.toLowerCase();
    final okExt = name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.gif');
    if (!okExt) name = 'question.jpg';
    if (!mounted) return;
    setState(() {
      q.imageBytes = bytes;
      q.imageName = name;
    });
  }

  Future<void> _save(String type) async {
    if (!_canCreate && _editSubjectId == 0) {
      _openPayment();
      return;
    }
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      _toast('Please enter the Exam Title / Subject Name.', error: true);
      return;
    }
    for (int i = 0; i < _questions.length; i++) {
      final q = _questions[i];
      if (q.text.text.trim().isEmpty || q.opts.any((o) => o.text.trim().isEmpty) || q.answer == null) {
        _toast('Question ${i + 1}: enter the question, all 4 options and select the correct answer.', error: true);
        return;
      }
    }
    setState(() => _saving = true);
    try {
      final fields = <String, String>{
        'token': _token!,
        'action': 'create_exam',
        'subject-name': title,
        'session_id': '$_sessionId',
        'term_id': '$_termId',
        'class_id': '$_classId',
        'submit': type,
      };
      final uploads = <_Up>[];
      if (_editSubjectId > 0) fields['edit_subject_id'] = '$_editSubjectId';
      for (int i = 0; i < _questions.length; i++) {
        final q = _questions[i];
        fields['questionsportal[$i]'] = q.text.text.trim();
        for (int k = 0; k < 4; k++) {
          fields['optionsportal[$i][$k]'] = q.opts[k].text.trim();
        }
        fields['answers[$i]'] = '${q.answer}';
        if (q.imageBytes != null) {
          uploads.add(_Up('question_images[$i]', q.imageBytes!, q.imageName ?? 'question.jpg'));
        } else if (q.existingImage != null) {
          fields['existing_images[$i]'] = q.existingImage!;
        }
      }
      if (_includeTheory) {
        fields['include_theory'] = '1';
        for (int i = 0; i < _theory.length; i++) {
          fields['theory_questions[$i]'] = _theory[i].text.text.trim();
          fields['theory_marks[$i]'] = _theory[i].marks.text.trim().isEmpty ? '5' : _theory[i].marks.text.trim();
        }
      }

      Map<String, dynamic> r = {'success': false, 'message': 'Network error. Check your connection.'};
      for (var attempt = 0; attempt < _apiUrls.length; attempt++) {
        try {
          // token + action also in the URL (survives a redirect that drops the body)
          final uri = Uri.parse(_apiUrl).replace(queryParameters: {'token': _token!, 'action': 'create_exam'});
          final req = http.MultipartRequest('POST', uri);
          req.fields.addAll(fields);
          for (final u in uploads) {
            req.files.add(http.MultipartFile.fromBytes(u.field, u.bytes, filename: u.name));
          }
          final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 90)));
          r = _Api.decode(res.body);
          if (_Api.shouldRetry(r) && _apiIdx < _apiUrls.length - 1) {
            _apiIdx++;
            continue;
          }
          break;
        } catch (_) {
          if (_apiIdx < _apiUrls.length - 1) {
            _apiIdx++;
            continue;
          }
          break;
        }
      }

      if (r['success'] == true) {
        _toast('${r['message']}');
        _setBanner('${r['message']}');
        _resetForm();
        _page = 1; // newest subject is listed first
        await _refreshAll();
        _scrollToSubjects(); // show the added subject in the list below
      } else {
        _toast('${r['message']}', error: true);
      }
    } catch (e) {
      _toast('Could not save. Check your connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editDraft(int subjectId) async {
    final r = await _Api.post(_token!, 'get_draft', {'subject_id': '$subjectId'});
    if (r['success'] != true) {
      _toast('${r['message']}', error: true);
      return;
    }
    final d = r['data'] as Map<String, dynamic>;
    final oldQ = List<_Q>.of(_questions);
    final oldT = List<_TQ>.of(_theory);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final q in oldQ) {
        q.dispose();
      }
      for (final t in oldT) {
        t.dispose();
      }
    });
    _questions.clear();
    _theory.clear();
    for (final m in _maps(d['questions'])) {
      final q = _Q();
      q.text.text = '${m['text']}';
      q.opts[0].text = '${m['a']}';
      q.opts[1].text = '${m['b']}';
      q.opts[2].text = '${m['c']}';
      q.opts[3].text = '${m['d']}';
      final a = _toInt(m['answer']);
      q.answer = (a != null && a >= 1 && a <= 4) ? a : null;
      q.existingImage = m['image'] == null ? null : '${m['image']}';
      q.existingImageUrl = m['image_url'] == null ? null : '${m['image_url']}';
      _questions.add(q);
    }
    if (_questions.isEmpty) _questions.add(_Q());
    for (final m in _maps(d['theory'])) {
      final t = _TQ();
      t.text.text = '${m['text']}';
      t.marks.text = '${m['marks']}';
      _theory.add(t);
    }
    if (_theory.isEmpty) _theory.add(_TQ());
    setState(() {
      _editSubjectId = subjectId;
      _titleCtrl.text = '${d['subject_name']}';
      _includeTheory = _toInt(d['include_theory']) == 1;
      _sessionId = _pSession = _toInt(d['session_id']);
      _termId = _pTerm = _toInt(d['term_id']);
      _classId = _pClass = _toInt(d['class_id']);
    });
    _loadSubjects(page: 1);
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  }

  Future<void> _publish(int subjectId) async {
    final r = await _Api.post(_token!, 'publish_subject', {'subject_id': '$subjectId'});
    _toast('${r['message']}', error: r['success'] != true);
    await _loadSubjects();
  }

  Future<void> _deleteSubject(int subjectId) async {
    final ok = await _confirm('Delete Subject?',
        'This will delete the subject and ALL its questions. This action cannot be undone!',
        yes: 'Yes, delete it!', destructive: true);
    if (ok != true) return;
    final r = await _Api.post(_token!, 'delete_subject', {'subject_id': '$subjectId'});
    _toast('${r['message']}', error: r['success'] != true);
    if (_editSubjectId == subjectId) _resetForm();
    await _refreshAll();
  }

  Future<void> _deleteAll() async {
    final ok = await _confirm('Delete ALL Subjects?',
        'This will delete ALL your subjects and ALL questions. This is irreversible!',
        yes: 'Yes, delete everything!', destructive: true, icon: Icons.error);
    if (ok != true) return;
    final r = await _Api.post(_token!, 'delete_all');
    _toast('${r['message']}', error: r['success'] != true);
    _resetForm();
    await _refreshAll();
  }

  // ───────────────────────────── dialogs (SweetAlert equivalents) ─────────────────────────────
  Future<bool?> _confirm(String title, String text,
      {String yes = 'Yes', bool destructive = false, IconData icon = Icons.warning_amber_rounded}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(children: [
          Icon(icon, size: 54, color: destructive ? _C.danger : _C.warning),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Text(text, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF3085D6), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDD3333), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(yes)),
        ],
      ),
    );
  }

  Future<void> _alert(String title, String text, {IconData icon = Icons.info, Color color = _C.primary}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(children: [
          Icon(icon, size: 54, color: color),
          const SizedBox(height: 8),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Text(text, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK')),
        ],
      ),
    );
  }

  // ───────────────────────────── small UI helpers ─────────────────────────────
  InputDecoration _dec(String hint, {IconData? icon, String? label}) => InputDecoration(
        hintText: hint,
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 20, color: Colors.grey.shade600),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: Color(0xFFCCCCCC))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: Color(0xFFCCCCCC))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: _C.primary, width: 1.5)),
      );

  Widget _accentCard({
    required Widget child,
    Color bar = _C.primary,
    Color bg = Colors.white,
    EdgeInsets padding = const EdgeInsets.all(16),
    double barWidth = 4,
    double radius = 10,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(children: [
          Padding(padding: EdgeInsets.only(left: barWidth).add(padding), child: child),
          Positioned(left: 0, top: 0, bottom: 0, width: barWidth, child: ColoredBox(color: bar)),
        ]),
      ),
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback? onTap, {bool expand = false, bool small = false}) {
    final b = ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: small ? 16 : 18),
      label: Text(label, style: TextStyle(fontSize: small ? 13 : 14, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color,
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: small ? 10 : 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: b) : b;
  }

  Widget _upgradeBtn(String label, {IconData icon = Icons.workspace_premium}) => InkWell(
        onTap: _openPayment,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)]),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(color: const Color(0xFF9C27B0).withAlpha(77), blurRadius: 15, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Widget _howBtn() => InkWell(
        onTap: () {
          setState(() => _showHow = true);
          Future.delayed(const Duration(milliseconds: 120), () {
            if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent * .45, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
          });
        },
        borderRadius: BorderRadius.circular(30),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_C.info, _C.primary]),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.help, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('How It Works', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ]),
        ),
      );

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withAlpha(51), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      );

  Widget _label(IconData icon, String text, {Color color = _C.text}) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: color))),
        ]),
      );

  void _setActive(TextEditingController c, String label) {
    _activeCtrl = c;
    _activeLabel = label;
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.headerGradient)),
        title: const Text('Add Exam', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      floatingActionButton: (_formVisible && !_loading)
          ? FloatingActionButton.extended(
              onPressed: _openScientific,
              backgroundColor: _C.sci,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.science),
              label: const Text('Scientific Tools', style: TextStyle(fontWeight: FontWeight.w600)),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : RefreshIndicator(
              color: _C.primary,
              onRefresh: _refreshAll,
              child: ListView(
                controller: _scroll,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
                children: [
                  if (_banner != null) _alertBox(),
                  if (_pendingRef != null) _pendingPaymentBox(),
                  if (_hasFreeTrial) _freeTrialBanner(),
                  if (_cbtEnabled && !_hasFreeTrial) _subscriptionBanner(),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.add_circle, color: _C.primary),
                      const SizedBox(width: 8),
                      Text(_editSubjectId > 0 ? 'Edit Draft' : 'Create New Exam',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _C.text)),
                    ]),
                  ),
                  _selectionCard(),
                  const SizedBox(height: 22),
                  _formVisible ? _examForm() : _selectFirstBox(),
                  if (_showHow) ...[const SizedBox(height: 24), _howItWorks()],
                  const SizedBox(height: 28),
                  KeyedSubtree(key: _subjectsKey, child: _subjectsSection()),
                ],
              ),
            ),
    );
  }

  // ───────────────────────────── alerts / banners ─────────────────────────────
  Widget _alertBox() {
    final err = _bannerError;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: err ? const Color(0xFFF8D7DA) : const Color(0xFFD4EDDA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: err ? const Color(0xFFF5C6CB) : const Color(0xFFC3E6CB)),
      ),
      child: Row(children: [
        Icon(err ? Icons.error : Icons.check_circle, color: err ? const Color(0xFF721C24) : const Color(0xFF155724)),
        const SizedBox(width: 10),
        Expanded(child: Text(_banner!, style: TextStyle(color: err ? const Color(0xFF721C24) : const Color(0xFF155724)))),
        InkWell(onTap: () => setState(() => _banner = null), child: const Icon(Icons.close, size: 18)),
      ]),
    );
  }

  Widget _pendingPaymentBox() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFFEAA7))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.schedule, color: Color(0xFF856404)),
            SizedBox(width: 8),
            Expanded(child: Text('Waiting for your payment', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF856404)))),
          ]),
          const SizedBox(height: 6),
          const Text('Finished paying on Flutterwave? Tap verify to activate your plan.', style: TextStyle(color: Color(0xFF856404))),
          const SizedBox(height: 10),
          Row(children: [
            _btn('Verify Payment', Icons.verified, _C.success, () => _verifyPayment(), small: true),
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() => _pendingRef = null), child: const Text('Dismiss')),
          ]),
        ]),
      );

  Widget _freeTrialBanner() {
    final pct = _trialLimit == 0 ? 0.0 : (_subjectCount / _trialLimit).clamp(0.0, 1.0);
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: _C.bannerGradient, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.card_giftcard, color: Colors.white),
          SizedBox(width: 8),
          Text('Free Trial Active!', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        Text(_trialMsg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 20,
            child: LinearProgressIndicator(value: pct, backgroundColor: Colors.white.withAlpha(51), valueColor: const AlwaysStoppedAnimation(Color(0xFF4CAF50))),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          _pill('$_subjectCount / $_trialLimit Subjects'),
          _pill('$_remaining Remaining'),
        ]),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _upgradeBtn('Upgrade Now', icon: Icons.workspace_premium),
          _howBtn(),
        ]),
      ]),
    );
  }

  Widget _subscriptionBanner() {
    final sub = _status['subscription'] is Map ? Map<String, dynamic>.from(_status['subscription']) : null;
    Widget head(IconData i, String t) => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(i, color: Colors.white),
          const SizedBox(width: 8),
          Flexible(child: Text(t, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold))),
        ]);
    final List<Widget> info;
    if (_hasActive && !_hasFreeTrial && sub != null) {
      info = [
        head(Icons.shield, 'CBT Access Active'),
        const SizedBox(height: 8),
        Text('Your ${sub['plan_type']} Plan subscription is valid until ${sub['expires']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        Text('Reference: ${sub['reference']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ];
    } else if (!_canCreate) {
      info = [
        head(Icons.lock, 'Upgrade Required'),
        const SizedBox(height: 8),
        Text(_trialMsg, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        if (_subjectCount >= _trialLimit)
          Text("You've used all $_trialLimit free trial subjects.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
      ];
    } else {
      info = [
        head(Icons.rocket_launch, 'Get Started'),
        const SizedBox(height: 8),
        const Text('Subscribe to a plan to create and manage unlimited exams', textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
      ];
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: _C.bannerGradient, borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        ...info,
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (!_hasActive || _hasFreeTrial) _upgradeBtn(_hasFreeTrial ? 'Upgrade Now' : 'Subscribe Now'),
          _howBtn(),
        ]),
      ]),
    );
  }

  // ───────────────────────────── Select Academic Details ─────────────────────────────
  Widget _dd(String label, IconData icon, int? value, String allLabel, List<Map<String, dynamic>> items, String idKey,
      String nameKey, ValueChanged<int?> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _label(icon, label),
      DropdownButtonFormField<int?>(
        value: value,
        isExpanded: true,
        decoration: _dec(allLabel),
        items: [
          DropdownMenuItem<int?>(value: null, child: Text(allLabel)),
          ...items.map((m) => DropdownMenuItem<int?>(value: _toInt(m[idKey]), child: Text('${m[nameKey]}', overflow: TextOverflow.ellipsis))),
        ],
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _selectionCard() {
    final applied = _sessionId != null || _termId != null || _classId != null;
    return _accentCard(
      bar: const Color(0xFF3498DB),
      barWidth: 5,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.filter_alt, color: _C.text),
          SizedBox(width: 8),
          Text('Select Academic Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.text)),
        ]),
        _dd('Academic Session', Icons.calendar_month, _pSession, '-- All Sessions --', _sessions, 'id', 'session_name', (v) => setState(() => _pSession = v)),
        _dd('Term', Icons.menu_book, _pTerm, '-- All Terms --', _terms, 'id', 'term_name', (v) => setState(() => _pTerm = v)),
        _dd('Class', Icons.groups, _pClass, '-- All Classes --', _classes, 'class_id', 'class_name', (v) => setState(() => _pClass = v)),
        const SizedBox(height: 18),
        Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
          _btn('Apply Filters', Icons.filter_alt, _C.primary, _applyFilters),
          _btn('Clear Filters', Icons.close, _C.draft, _clearFilters),
        ]),
        if (applied) ...[
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(color: _C.lightBg, borderRadius: BorderRadius.circular(8), border: const Border(left: BorderSide(color: Color(0xFF27AE60), width: 4))),
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.check_circle, color: Color(0xFF27AE60), size: 18),
                SizedBox(width: 6),
                Text('Current Filters Applied:', style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              if (_sessionId != null) _infoItem(Icons.calendar_month, 'Session', _nameOf(_sessions, 'id', 'session_name', _sessionId)),
              if (_termId != null) _infoItem(Icons.menu_book, 'Term', _nameOf(_terms, 'id', 'term_name', _termId)),
              if (_classId != null) _infoItem(Icons.groups, 'Class', _nameOf(_classes, 'class_id', 'class_name', _classId)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _infoItem(IconData i, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Icon(i, size: 16, color: _C.primary),
          const SizedBox(width: 8),
          Expanded(child: Text.rich(TextSpan(children: [TextSpan(text: '$k: ', style: const TextStyle(fontWeight: FontWeight.bold)), TextSpan(text: v)]))),
        ]),
      );

  Widget _selectFirstBox() => Container(
        padding: const EdgeInsets.all(34),
        decoration: BoxDecoration(color: _C.lightBg, borderRadius: BorderRadius.circular(10)),
        child: const Column(children: [
          Icon(Icons.filter_alt, size: 48, color: Color(0xFF3498DB)),
          SizedBox(height: 16),
          Text('Select Academic Details First', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text('Please select a session, term, and class above to create exams.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF666666))),
        ]),
      );

  // ───────────────────────────── Exam form ─────────────────────────────
  Widget _examForm() {
    final locked = !_canCreate && _editSubjectId == 0;
    final form = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 10, offset: const Offset(0, 3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(Icons.menu_book, 'Exam Title / Subject Name:'),
        TextField(controller: _titleCtrl, readOnly: locked, decoration: _dec('e.g Biology SS3')),
        const SizedBox(height: 6),
        for (int i = 0; i < _questions.length; i++) _questionCard(i),
        const SizedBox(height: 16),
        Align(alignment: Alignment.centerLeft, child: _btn('Add Another Question', Icons.add, _C.info, _addQuestion)),
        const SizedBox(height: 24),
        _theorySection(),
        const SizedBox(height: 24),
        Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 10, children: [
          _btn(_editSubjectId > 0 ? 'Update Draft' : 'Save as Draft', Icons.save, _C.draft, _saving ? null : () => _save('draft')),
          _btn(_editSubjectId > 0 ? 'Publish Updated Exam' : 'Publish Exam', Icons.send, _C.success, _saving ? null : () => _save('publish')),
        ]),
        if (_saving) const Padding(padding: EdgeInsets.only(top: 14), child: Center(child: CircularProgressIndicator(color: _C.primary))),
      ]),
    );
    if (!locked) return form;
    return Stack(children: [form, Positioned.fill(child: _upgradeOverlay())]);
  }

  Widget _upgradeOverlay() => Container(
        decoration: BoxDecoration(color: Colors.white.withAlpha(242), borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(24),
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.workspace_premium, color: _C.payment),
                SizedBox(width: 8),
                Text('Upgrade Required', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 10),
              Text(_trialMsg, textAlign: TextAlign.center),
              if (_subjectCount >= _trialLimit) ...[
                const SizedBox(height: 8),
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'You have successfully created '),
                  TextSpan(text: '$_subjectCount subjects', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const TextSpan(text: ' during your free trial.'),
                ]), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                const Text('To continue creating exams, please upgrade to a paid plan.', textAlign: TextAlign.center),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: _C.lightBg, borderRadius: BorderRadius.circular(10)),
                  child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Icon(Icons.star, size: 18, color: _C.warning), SizedBox(width: 6), Text('Upgrade Benefits:', style: TextStyle(fontWeight: FontWeight.bold))]),
                    SizedBox(height: 8),
                    Text('•  Create unlimited exam subjects'),
                    Text('•  Add unlimited questions per subject'),
                    Text('•  Include theory questions with images'),
                    Text('•  Priority support'),
                    Text('•  Advanced exam analytics'),
                  ]),
                ),
              ] else if (!_hasActive && !_hasFreeTrial) ...[
                const SizedBox(height: 8),
                Text('Start with our free trial to create up to $_trialLimit subjects!', textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              _upgradeBtn(_hasFreeTrial ? 'Upgrade Now' : 'Get Started'),
              const SizedBox(height: 12),
              _howBtn(),
            ]),
          ),
        ),
      );

  Widget _questionCard(int i) {
    final q = _questions[i];
    final hasPic = q.imageBytes != null || q.existingImageUrl != null;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: _accentCard(
        bg: _C.lightBg,
        radius: 8,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Question ${i + 1} ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.primary)),
            const TextSpan(text: '(Multiple Choice)', style: TextStyle(fontSize: 14, color: Color(0xFF666666))),
          ])),
          const SizedBox(height: 10),
          TextField(
            controller: q.text,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            onTap: () => _setActive(q.text, 'Question ${i + 1}'),
            decoration: _dec('Enter your question here...'),
          ),
          _label(Icons.image, 'Question Image (optional):'),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _pickImage(q),
              icon: const Icon(Icons.upload_file, size: 18),
              label: Text(q.imageBytes != null ? 'Change Image' : 'Choose Image'),
              style: OutlinedButton.styleFrom(foregroundColor: _C.primary, side: const BorderSide(color: _C.primary)),
            ),
            if (hasPic) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() {
                  q.imageBytes = null;
                  q.imageName = null;
                  q.existingImage = null;
                  q.existingImageUrl = null;
                }),
                icon: const Icon(Icons.close, size: 16, color: _C.danger),
                label: const Text('Remove', style: TextStyle(color: _C.danger)),
              ),
            ],
          ]),
          if (hasPic)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.border), borderRadius: BorderRadius.circular(6)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: q.imageBytes != null
                    ? Image.memory(q.imageBytes!, height: 160, fit: BoxFit.contain)
                    : Image.network(q.existingImageUrl!, height: 160, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image)))),
              ),
            ),
          const SizedBox(height: 14),
          for (int k = 0; k < 4; k++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(
                controller: q.opts[k],
                onTap: () => _setActive(q.opts[k], 'Question ${i + 1} · Option ${'ABCD'[k]}'),
                decoration: _dec('Enter option ${'ABCD'[k]}'),
              ),
            ),
          _label(Icons.check_circle, 'Correct Answer:'),
          DropdownButtonFormField<int>(
            value: q.answer,
            isExpanded: true,
            decoration: _dec('Select the correct answer'),
            items: const [
              DropdownMenuItem(value: 1, child: Text('Option A')),
              DropdownMenuItem(value: 2, child: Text('Option B')),
              DropdownMenuItem(value: 3, child: Text('Option C')),
              DropdownMenuItem(value: 4, child: Text('Option D')),
            ],
            onChanged: (v) => setState(() => q.answer = v),
          ),
          const SizedBox(height: 14),
          _btn('Remove Question', Icons.delete, _C.danger, () => _removeQuestion(i)),
        ]),
      ),
    );
  }

  // ───────────────────────────── Theory section ─────────────────────────────
  Widget _theorySection() {
    return _Dashed(
      color: _C.theory,
      background: const Color(0xFFFFF9E6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _includeTheory = !_includeTheory),
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: _C.theory, borderRadius: BorderRadius.circular(5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Checkbox(
                value: _includeTheory,
                onChanged: (v) => setState(() => _includeTheory = v ?? false),
                activeColor: Colors.white,
                checkColor: _C.theory,
                side: const BorderSide(color: Colors.white, width: 2),
              ),
              const Icon(Icons.edit_note, color: Colors.white, size: 20),
              const SizedBox(width: 6),
              const Flexible(child: Text('Include Theory Questions (Optional)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ]),
          ),
        ),
        if (_includeTheory) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.only(bottom: 10),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _C.theory, width: 2))),
            child: const Row(children: [
              Icon(Icons.edit, color: _C.theory),
              SizedBox(width: 8),
              Text('Theory Questions Section', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.theory)),
            ]),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5)),
            child: const Row(children: [
              Icon(Icons.info, size: 18, color: Color(0xFF666666)),
              SizedBox(width: 8),
              Expanded(child: Text('These questions will appear after the multiple-choice questions in the exam.', style: TextStyle(color: Color(0xFF666666)))),
            ]),
          ),
          for (int i = 0; i < _theory.length; i++) _theoryCard(i),
          const SizedBox(height: 14),
          _btn('Add Theory Question', Icons.add, _C.theory, _addTheory),
        ],
      ]),
    );
  }

  Widget _theoryCard(int i) {
    final t = _theory[i];
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: _accentCard(
        bar: _C.theory,
        padding: const EdgeInsets.all(14),
        radius: 8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: 'Theory Question ${i + 1} ', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _C.theory)),
            const TextSpan(text: '(Essay/Theory)', style: TextStyle(fontSize: 14, color: Color(0xFF666666))),
          ])),
          const SizedBox(height: 10),
          TextField(
            controller: t.text,
            minLines: 4,
            maxLines: 8,
            onTap: () => _setActive(t.text, 'Theory Question ${i + 1}'),
            decoration: _dec('Enter theory question here...'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.star, size: 16, color: _C.warning),
            const SizedBox(width: 6),
            const Text('Marks:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 10),
            SizedBox(
              width: 80,
              child: TextField(
                controller: t.marks,
                keyboardType: TextInputType.number,
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 20) t.marks.text = '20';
                },
                decoration: _dec('5'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          _btn('Remove', Icons.delete, _C.danger, () => _removeTheory(i)),
        ]),
      ),
    );
  }

  // ───────────────────────────── How It Works ─────────────────────────────
  Widget _howItWorks() {
    final steps = <List<String>>[
      ['Start Free Trial', 'Create up to $_trialLimit subjects for free to test our system.'],
      ['Choose a Plan', 'Select either Term Plan (3 months) or Session Plan (9 months) based on your needs.'],
      ['Make Payment', 'Pay securely via Flutterwave using Card, Bank Transfer, USSD, or Mobile Money.'],
      ['Get Full Access', 'Once verified, create unlimited exams with multiple choice and theory questions.'],
    ];
    return _accentCard(
      bar: _C.info,
      barWidth: 5,
      bg: _C.lightBg,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.help, color: _C.info),
          SizedBox(width: 8),
          Text('How It Works', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        const Text('Follow these simple steps to get started with the CBT system:'),
        const SizedBox(height: 14),
        for (int i = 0; i < steps.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: _C.info, shape: BoxShape.circle),
                child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(steps[i][0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(steps[i][1], style: const TextStyle(color: Color(0xFF555555))),
              ])),
            ]),
          ),
        const SizedBox(height: 6),
        Center(
          child: Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            _upgradeBtn(_hasFreeTrial ? 'Upgrade Now' : 'Get Started', icon: Icons.rocket_launch),
            OutlinedButton.icon(onPressed: () => setState(() => _showHow = false), icon: const Icon(Icons.close, size: 18), label: const Text('Close')),
          ]),
        ),
      ]),
    );
  }

  // ───────────────────────────── All Subjects ─────────────────────────────
  Widget _subjectsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.list_alt, color: _C.primary),
        SizedBox(width: 8),
        Text('All Subjects', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold, color: _C.text)),
      ]),
      const SizedBox(height: 6),
      Text('Total Subjects: $_total', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF666666))),
      const SizedBox(height: 14),
      if (_subjects.isNotEmpty && _canCreate)
        Padding(padding: const EdgeInsets.only(bottom: 14), child: Center(child: _btn('Delete All Subjects', Icons.delete_sweep, _C.danger, _deleteAll))),
      if (_loadingSubjects)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _C.primary)))
      else if (_subjects.isEmpty)
        _emptySubjects()
      else
        for (int i = 0; i < _subjects.length; i++) Padding(padding: const EdgeInsets.only(bottom: 18), child: _subjectCard(_subjects[i], _firstSn + i)),
      if (_totalPages > 1) _pagination(),
    ]);
  }

  Widget _emptySubjects() => Container(
        padding: const EdgeInsets.all(30),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Icon(Icons.inbox, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('No exam subjects found.', style: TextStyle(color: Color(0xFF666666), fontSize: 16)),
          if (_filtersReady && _canCreate) ...[
            const SizedBox(height: 6),
            const Text('Start by creating your first exam using the form above.'),
          ] else if (!_canCreate) ...[
            const SizedBox(height: 14),
            _upgradeBtn(_hasFreeTrial ? 'Upgrade to Create' : 'Subscribe to Create Exams'),
          ],
        ]),
      );

  Widget _statusBadge(bool draft) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: draft ? const Color(0x20FFC107) : const Color(0x2028A745),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: draft ? _C.warning : _C.success),
        ),
        child: Text(draft ? 'Draft' : 'Published', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: draft ? const Color(0xFF856404) : const Color(0xFF155724))),
      );

  Widget _typeBadge(bool theory) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: theory ? const Color(0xFFFFF3E0) : const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(theory ? Icons.edit_note : Icons.format_list_numbered, size: 16, color: theory ? const Color(0xFFF57C00) : const Color(0xFF1976D2)),
          const SizedBox(width: 5),
          Text(theory ? 'MCQ + Theory' : 'MCQ Only', style: TextStyle(fontWeight: FontWeight.w500, color: theory ? const Color(0xFFF57C00) : const Color(0xFF1976D2))),
        ]),
      );

  Widget _row(String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 100, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF555555)))),
          Expanded(child: Align(alignment: Alignment.centerLeft, child: value)),
        ]),
      );

  Widget _subjectCard(Map<String, dynamic> s, int sn) {
    final id = _toInt(s['subject_id']) ?? 0;
    final draft = _toInt(s['is_draft']) == 1;
    final theory = _toInt(s['include_theory']) == 1;
    final tc = _toInt(s['theory_count']) ?? 0;
    final mc = _toInt(s['mcq_count']) ?? 0;
    return _accentCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _row('S/N', Text('$sn')),
        _row('Name', Text('${s['subject_name']}', style: const TextStyle(fontWeight: FontWeight.bold))),
        _row('Session', Text('${s['session_name']}')),
        _row('Term', Text('${s['term_name']}')),
        _row('Class', Text('${s['class_name']}')),
        _row('Questions', Text(tc > 0 ? '${s['question_count']}  ($mc MCQ, $tc Theory)' : '${s['question_count']}')),
        _row('Status', _statusBadge(draft)),
        _row('Type', _typeBadge(theory)),
        const SizedBox(height: 12),
        _btn('View Questions', Icons.visibility, _C.primary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ViewQuestionsScreen(token: _token!, subjectId: id))), expand: true),
        const SizedBox(height: 8),
        if (draft) ...[
          _btn('Edit Draft', Icons.edit, _C.info, () => _editDraft(id), expand: true),
          const SizedBox(height: 8),
          _btn('Publish Exam', Icons.check, _C.success, () => _publish(id), expand: true),
        ] else
          _btn('Published', Icons.check_circle, _C.success, null, expand: true),
        const SizedBox(height: 8),
        _btn('Edit Details', Icons.edit_outlined, _C.info, () => _openEditDetails(s), expand: true),
        const SizedBox(height: 8),
        _btn('Delete Subject', Icons.delete, _C.danger, () => _deleteSubject(id), expand: true),
      ]),
    );
  }

  Widget _pagination() {
    Widget chip(String label, VoidCallback? onTap, {bool current = false, IconData? lead, IconData? trail}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: current ? _C.primary : Colors.white,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: current ? _C.primary : _C.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (lead != null) Icon(lead, size: 14, color: _C.primary),
              Text(label, style: TextStyle(color: current ? Colors.white : _C.primary, fontWeight: FontWeight.w600)),
              if (trail != null) Icon(trail, size: 14, color: _C.primary),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
        if (_page > 1) chip(' Previous', () => _loadSubjects(page: _page - 1), lead: Icons.chevron_left),
        for (int p = 1; p <= _totalPages; p++) chip('$p', p == _page ? null : () => _loadSubjects(page: p), current: p == _page),
        if (_page < _totalPages) chip('Next ', () => _loadSubjects(page: _page + 1), trail: Icons.chevron_right),
      ]),
    );
  }

  // ───────────────────────────── Edit Details modal ─────────────────────────────
  void _openEditDetails(Map<String, dynamic> s) {
    final nameCtrl = TextEditingController(text: '${s['subject_name']}');
    int? sid = _toInt(s['session_id']), tid = _toInt(s['term_id']), cid = _toInt(s['class_id']);
    bool busy = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 16, 8, 16),
                  decoration: const BoxDecoration(gradient: _C.headerGradient, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
                  child: Row(children: [
                    const Icon(Icons.edit, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Edit Exam Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _label(Icons.menu_book, 'Subject Name'),
                    TextField(controller: nameCtrl, decoration: _dec('Enter subject name')),
                    _dd('Session', Icons.calendar_month, sid, '-- Select Session --', _sessions, 'id', 'session_name', (v) => setM(() => sid = v)),
                    _dd('Term', Icons.menu_book, tid, '-- Select Term --', _terms, 'id', 'term_name', (v) => setM(() => tid = v)),
                    _dd('Class', Icons.groups, cid, '-- Select Class --', _classes, 'class_id', 'class_name', (v) => setM(() => cid = v)),
                    const SizedBox(height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      _btn('Cancel', Icons.close, _C.draft, () => Navigator.pop(ctx)),
                      const SizedBox(width: 10),
                      _btn(busy ? 'Saving...' : 'Update Details', Icons.save, _C.primary, busy
                          ? null
                          : () async {
                              if (nameCtrl.text.trim().isEmpty) {
                                _toast('Subject name is required.', error: true);
                                return;
                              }
                              setM(() => busy = true);
                              final r = await _Api.post(_token!, 'update_exam', {
                                'subject_id': '${s['subject_id']}',
                                'subject_name': nameCtrl.text.trim(),
                                'session_id': '${sid ?? ''}',
                                'term_id': '${tid ?? ''}',
                                'class_id': '${cid ?? ''}',
                              });
                              if (r['success'] == true) {
                                if (ctx.mounted) Navigator.pop(ctx);
                                _setBanner('${r['message']}');
                                await _loadSubjects();
                              } else {
                                if (ctx.mounted) setM(() => busy = false);
                                _toast('${r['message']}', error: true);
                              }
                            }),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── Scientific Tools ─────────────────────────────
  void _insertText(String symbol) {
    final c = _activeCtrl;
    if (c == null) return;
    final t = c.text;
    int a = c.selection.start < 0 ? t.length : c.selection.start;
    int b = c.selection.end < 0 ? t.length : c.selection.end;
    if (a > b) {
      final x = a;
      a = b;
      b = x;
    }
    if (b > t.length) b = t.length;
    if (a > t.length) a = t.length;
    c.value = TextEditingValue(
      text: t.replaceRange(a, b, symbol),
      selection: TextSelection.collapsed(offset: a + symbol.length),
    );
  }

  void _openScientific() {
    if (_activeCtrl == null) {
      _alert('No Field Selected', 'Please click on a question or option field first, then open scientific tools.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SciSheet(
        fieldLabel: _activeLabel,
        onInsert: (s) {
          _insertText(s);
          Navigator.pop(ctx); // same as the web page on mobile: close after inserting
        },
        onFraction: _openFractionDialog,
        onEquation: _openEquationEditor,
        onMatrix: _openMatrixEditor,
      ),
    );
  }

  Future<void> _openFractionDialog() async {
    final n = TextEditingController(), d = TextEditingController();
    String? err;
    final res = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Insert Fraction'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: n, decoration: _dec('Numerator')),
            const SizedBox(height: 10),
            TextField(controller: d, decoration: _dec('Denominator')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: _C.danger))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white),
              onPressed: () {
                if (n.text.isEmpty || d.text.isEmpty) {
                  setD(() => err = 'Both numerator and denominator are required');
                  return;
                }
                Navigator.pop(ctx, [n.text, d.text]);
              },
              child: const Text('Insert'),
            ),
          ],
        ),
      ),
    );
    if (res != null) _insertText('${res[0]}/${res[1]}');
  }

  Future<void> _openEquationEditor() async {
    final eq = TextEditingController();
    String? err;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Equation Editor'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: eq, minLines: 4, maxLines: 6, decoration: _dec('Enter your equation here...')),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in ['x²', '√', 'π', '∫', '∑'])
                OutlinedButton(
                  onPressed: () => eq.text = eq.text + s,
                  style: OutlinedButton.styleFrom(foregroundColor: _C.sci, side: const BorderSide(color: _C.sci), minimumSize: const Size(44, 38)),
                  child: Text(s, style: const TextStyle(fontSize: 16)),
                ),
            ]),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: _C.danger))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white),
              onPressed: () {
                if (eq.text.isEmpty) {
                  setD(() => err = 'Please enter an equation');
                  return;
                }
                Navigator.pop(ctx, eq.text);
              },
              child: const Text('Insert'),
            ),
          ],
        ),
      ),
    );
    if (res != null) _insertText(res);
  }

  Future<void> _openMatrixEditor() async {
    final r = TextEditingController(text: '2'), c = TextEditingController(text: '2');
    String? err;
    final res = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Matrix Editor'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Enter matrix dimensions:'),
            const SizedBox(height: 10),
            TextField(controller: r, keyboardType: TextInputType.number, decoration: _dec('Rows')),
            const SizedBox(height: 10),
            TextField(controller: c, keyboardType: TextInputType.number, decoration: _dec('Columns')),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: _C.danger))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white),
              onPressed: () {
                final rr = int.tryParse(r.text), cc = int.tryParse(c.text);
                if (rr == null || cc == null || rr < 1 || rr > 5 || cc < 1 || cc > 5) {
                  setD(() => err = 'Please enter valid dimensions (1-5)');
                  return;
                }
                Navigator.pop(ctx, [rr, cc]);
              },
              child: const Text('Create Matrix'),
            ),
          ],
        ),
      ),
    );
    if (res == null) return;
    final b = StringBuffer('[');
    for (int i = 0; i < res[0]; i++) {
      b.write('[');
      for (int j = 0; j < res[1]; j++) {
        b.write('a${i + 1}${j + 1}');
        if (j < res[1] - 1) b.write(' ');
      }
      b.write(']');
      if (i < res[0] - 1) b.write('\n');
    }
    b.write(']');
    _insertText(b.toString());
  }

  // ───────────────────────────── Payment (Flutterwave) ─────────────────────────────
  void _openPayment() {
    if (_token == null) return;
    final pid = _toInt(_status['portaladmin_id']) ?? 0;
    final termPrice = _toInt(_status['term_price']) ?? 10000;
    final sessionPrice = _toInt(_status['session_price']) ?? 25000;
    final saving = _toInt(_status['session_saving']) ?? 0;
    String plan = '', ref = '';
    bool busy = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        Widget feat(String t) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.check_circle, size: 16, color: _C.success),
                const SizedBox(width: 8),
                Expanded(child: Text(t)),
              ]),
            );

        Widget planCard(String key, String title, int price, String duration, List<String> feats) {
          final sel = plan == key;
          return GestureDetector(
            onTap: () => setM(() {
              plan = key;
              ref = 'CBT-${DateTime.now().millisecondsSinceEpoch}-$pid';
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(20),
              transform: Matrix4.translationValues(0, sel ? -3 : 0, 0),
              decoration: BoxDecoration(
                color: sel ? const Color(0xFFF0F9FF) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: sel ? _C.primary : const Color(0xFFDDDDDD), width: 2),
                boxShadow: sel ? [BoxShadow(color: _C.primary.withAlpha(51), blurRadius: 20, offset: const Offset(0, 10))] : null,
              ),
              child: Column(children: [
                Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(_naira(price), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _C.primary))),
                Text(duration, style: const TextStyle(color: Color(0xFF666666))),
                const SizedBox(height: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: feats.map(feat).toList()),
              ]),
            ),
          );
        }

        Widget kv(String k, Widget v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(flex: 4, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF555555)))),
                Expanded(flex: 5, child: Align(alignment: Alignment.centerRight, child: v)),
              ]),
            );

        final amount = plan == 'term' ? termPrice : sessionPrice;
        return Container(
          height: MediaQuery.of(ctx).size.height * .93,
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
              child: Row(children: [
                const Icon(Icons.workspace_premium, color: _C.payment),
                const SizedBox(width: 8),
                const Expanded(child: Text('CBT Subscription Plans', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))),
                IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 30), children: [
                const Text('Choose a plan to unlock full CBT system access', style: TextStyle(color: Color(0xFF666666))),
                const SizedBox(height: 16),
                planCard('term', 'Term Plan', termPrice, 'Valid for 3 months (One Term)', [
                  'Unlimited Exam Subjects', 'Unlimited Questions', 'MCQ & Theory Questions', '24/7 Support', 'All Features Included',
                ]),
                planCard('session', 'Session Plan', sessionPrice, 'Valid for 9 months (Full Session)', [
                  'Everything in Term Plan', 'Save ${_naira(saving)} (Bulk Discount)', 'Priority Support', 'Early Access to New Features', 'One-time Setup',
                ]),
                if (plan.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: _C.lightBg, borderRadius: BorderRadius.circular(12)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Icon(Icons.credit_card, color: _C.primary), SizedBox(width: 8), Text('Secure Online Payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold))]),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.primary, width: 2)),
                        child: const Column(children: [
                          Icon(Icons.credit_card, color: _C.primary, size: 30),
                          SizedBox(height: 4),
                          Text('Flutterwave', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Text('Card, Bank Transfer, USSD, etc.', style: TextStyle(color: Color(0xFF666666))),
                          SizedBox(height: 6),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 13, color: _C.success), SizedBox(width: 4), Text('Secure & Encrypted', style: TextStyle(fontSize: 12))]),
                        ]),
                      ),
                      const SizedBox(height: 16),
                      const Row(children: [Icon(Icons.info, size: 18, color: _C.info), SizedBox(width: 6), Text('Payment Details', style: TextStyle(fontWeight: FontWeight.bold))]),
                      const Divider(),
                      kv('Plan Selected:', Text(plan == 'term' ? 'Term Plan (3 Months)' : 'Session Plan (9 Months)', textAlign: TextAlign.right)),
                      kv('Amount to Pay:', Text(_naira(amount), style: const TextStyle(color: Color(0xFFD32F2F), fontWeight: FontWeight.bold))),
                      kv('Payment Reference:', Text(ref, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Icon(Icons.info, size: 17, color: _C.info), SizedBox(width: 6), Expanded(child: Text('Secure Payment via Flutterwave', style: TextStyle(fontWeight: FontWeight.bold)))]),
                          SizedBox(height: 8),
                          Text("You will be redirected to Flutterwave's secure payment page where you can choose your preferred payment method:"),
                          SizedBox(height: 6),
                          Text('•  Credit/Debit Cards (Visa, Mastercard, Verve)'),
                          Text('•  Bank Transfers'),
                          Text('•  USSD (*966* Amount#)'),
                          Text('•  Mobile Money'),
                          Text('•  QR Payments'),
                          SizedBox(height: 8),
                          Row(children: [Icon(Icons.check_circle, size: 15, color: Color(0xFF27AE60)), SizedBox(width: 6), Expanded(child: Text('All payments are secured and encrypted with 256-bit SSL', style: TextStyle(fontSize: 13)))]),
                          Row(children: [Icon(Icons.shield, size: 15, color: Color(0xFF27AE60)), SizedBox(width: 6), Expanded(child: Text('PCI DSS compliant payment processing', style: TextStyle(fontSize: 13)))]),
                        ]),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  setM(() => busy = true);
                                  final r = await _Api.post(_token!, 'init_payment', {'plan_type': plan, 'reference': ref});
                                  if (r['success'] == true) {
                                    final url = '${r['data']['payment_url']}';
                                    if (!mounted) return;
                                    setState(() => _pendingRef = '${r['data']['reference']}');
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                                    if (!ok) _toast('Could not open the payment page.', error: true);
                                  } else {
                                    if (ctx.mounted) setM(() => busy = false);
                                    _toast('${r['message']}', error: true);
                                  }
                                },
                          icon: busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.credit_card),
                          label: Text(busy ? 'PLEASE WAIT...' : 'PROCEED TO SECURE PAYMENT', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _C.payment,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: Column(children: [
                          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.headset_mic, size: 16), SizedBox(width: 6), Text('Need help with payment? Contact support:')]),
                          const SizedBox(height: 6),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.email, size: 14), const SizedBox(width: 6), Text('${_status['contact_email'] ?? ''}')]),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.phone, size: 14), const SizedBox(width: 6), Text('${_status['contact_phone'] ?? ''}')]),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFFEAA7))),
                        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Icon(Icons.schedule, size: 18, color: Color(0xFF856404)), SizedBox(width: 8), Text('What Happens Next?', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF856404)))]),
                          SizedBox(height: 8),
                          Text('1. Tap "Proceed to Secure Payment"\n2. Complete payment on Flutterwave\'s secure page\n3. Return to this app for automatic verification\n4. Start creating unlimited exams immediately!', style: TextStyle(color: Color(0xFF856404), fontSize: 14, height: 1.5)),
                        ]),
                      ),
                    ]),
                  ),
                const SizedBox(height: 18),
                const Divider(),
                const Center(child: Text('🔒 Payments secured by Flutterwave | PCI DSS Compliant', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF666666), fontSize: 13))),
              ]),
            ),
          ]),
        );
      }),
    );
  }

  Future<void> _verifyPayment({bool silent = false}) async {
    final ref = _pendingRef;
    if (ref == null || _token == null) return;
    final r = await _Api.post(_token!, 'verify_payment', {'reference': ref});
    if (!mounted) return;
    if (r['success'] == true) {
      setState(() => _pendingRef = null);
      _setBanner('${r['message']}');
      _toast('${r['message']}');
      await _refreshAll();
    } else if (!silent) {
      _toast('${r['message']}', error: true);
    }
  }


}

// ════════════════════════════════════════════════════════════════════════════
//  Dashed border (the theory section uses `border: 2px dashed` on the web)
// ════════════════════════════════════════════════════════════════════════════
class _Dashed extends StatelessWidget {
  final Widget child;
  final Color color;
  final Color background;
  const _Dashed({required this.child, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedPainter(color),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(8)),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;
  _DashedPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 7), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.color != color;
}

// ════════════════════════════════════════════════════════════════════════════
//  SCIENTIFIC TOOLS — same tabs and symbols as the web modal
// ════════════════════════════════════════════════════════════════════════════
class _SciTool {
  final String label;
  final String insert;
  const _SciTool(this.label, this.insert);
}

List<_SciTool> _plain(List<String> s) => s.map((e) => _SciTool(e, e)).toList();
List<_SciTool> _named(List<List<String>> p) => p.map((e) => _SciTool('${e[0]} (${e[1]})', e[0])).toList();

final Map<String, List<_SciTool>> _sciData = {
  'Math': _plain(['x²', 'x³', '√', '∛', 'π', '∞', '∫', '∑', '∏', '∂', '∇']),
  'Fractions': _plain(['½', '⅓', '¼', '⅔', '¾', '⅕', '⅖', '⅗', '⅘', '⅙', '⅚', '⅛']),
  'Greek': _named([
    ['α', 'alpha'], ['β', 'beta'], ['γ', 'gamma'], ['δ', 'delta'], ['ε', 'epsilon'], ['ζ', 'zeta'], ['η', 'eta'], ['θ', 'theta'],
    ['ι', 'iota'], ['κ', 'kappa'], ['λ', 'lambda'], ['μ', 'mu'], ['ν', 'nu'], ['ξ', 'xi'], ['ο', 'omicron'], ['π', 'pi'],
    ['ρ', 'rho'], ['σ', 'sigma'], ['τ', 'tau'], ['υ', 'upsilon'], ['φ', 'phi'], ['χ', 'chi'], ['ψ', 'psi'], ['ω', 'omega'],
  ]),
  'Logic': _named([
    ['≠', 'not equal'], ['≈', 'approx'], ['≤', 'less/equal'], ['≥', 'greater/equal'], ['±', 'plus/minus'], ['∓', 'minus/plus'],
    ['×', 'times'], ['÷', 'divide'], ['∝', 'prop to'], ['∞', 'infinity'], ['∠', 'angle'], ['⊥', 'perpendicular'], ['∥', 'parallel'],
    ['∧', 'and'], ['∨', 'or'], ['¬', 'not'], ['⇒', 'implies'], ['⇔', 'iff'], ['∀', 'forall'], ['∃', 'exists'],
  ]),
  'Chemistry': _named([
    ['H₂O', 'water'], ['CO₂', 'CO₂'], ['CH₄', 'methane'], ['NH₃', 'ammonia'], ['H₂SO₄', 'sulfuric'], ['C₆H₁₂O₆', 'glucose'],
    ['NaCl', 'salt'], ['HCl', 'acid'], ['NaOH', 'base'], ['C₂H₅OH', 'ethanol'], ['→', 'reaction'], ['⇌', 'equilibrium'],
    ['Δ', 'heat'], ['↑', 'gas'], ['↓', 'precipitate'],
  ]),
  'Physics': _named([
    ['Ω', 'ohm'], ['°C', 'celsius'], ['°F', 'fahrenheit'], ['λ', 'lambda'], ['ν', 'nu'], ['μ', 'micro/mu'], ['α', 'alpha'],
    ['β', 'beta'], ['γ', 'gamma'], ['θ', 'theta'], ['Φ', 'phi'], ['Ψ', 'psi'], ['ħ', 'h-bar'], ['ƒ', 'frequency'],
  ]),
  'Advanced': [
    const _SciTool('^ (superscript)', '^'),
    const _SciTool('_ (subscript)', '_'),
    ..._plain(['(', ')', '[', ']', '{', '}']),
  ],
};

class _SciSheet extends StatefulWidget {
  final String fieldLabel;
  final void Function(String) onInsert;
  final VoidCallback onFraction, onEquation, onMatrix;
  const _SciSheet({
    required this.fieldLabel,
    required this.onInsert,
    required this.onFraction,
    required this.onEquation,
    required this.onMatrix,
  });

  @override
  State<_SciSheet> createState() => _SciSheetState();
}

class _SciSheetState extends State<_SciSheet> {
  String _tab = 'Math';

  Widget _tool(String label, VoidCallback onTap, {double? width, IconData? icon}) => SizedBox(
        width: width,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFDDDDDD)),
              boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 18, color: _C.sci), const SizedBox(width: 6)],
              Flexible(child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: _C.text))),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tools = _sciData[_tab]!;
    return Container(
      height: MediaQuery.of(context).size.height * .82,
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(22, 14, 8, 14),
          decoration: const BoxDecoration(gradient: _C.headerGradient, borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
          child: Row(children: [
            const Icon(Icons.science, color: Colors.white),
            const SizedBox(width: 8),
            const Expanded(child: Text('Scientific Tools', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
          ]),
        ),
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              for (final t in _sciData.keys)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => setState(() => _tab = t),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tab == t ? _C.primary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _tab == t ? _C.primary : const Color(0xFFDDDDDD)),
                      ),
                      child: Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: _tab == t ? Colors.white : _C.text)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth - 32;
            final third = (w - 16) / 3;
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (_tab == 'Fractions') ...[
                  for (final t in tools) _tool(t.label, () => widget.onInsert(t.insert), width: third),
                  _tool('a/b (Custom)', widget.onFraction, width: w),
                ] else if (_tab == 'Advanced') ...[
                  _tool('Equation Editor', widget.onEquation, width: w, icon: Icons.functions),
                  _tool('Matrix Editor', widget.onMatrix, width: w, icon: Icons.grid_on),
                  _tool('Custom Fraction', widget.onFraction, width: w, icon: Icons.percent),
                  for (final t in tools) _tool(t.label, () => widget.onInsert(t.insert), width: t.label.length > 2 ? (w - 8) / 2 : third),
                ] else
                  for (final t in tools) _tool(t.label, () => widget.onInsert(t.insert), width: third),
              ]),
            );
          }),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: const BoxDecoration(color: _C.lightBg, border: Border(top: BorderSide(color: _C.border))),
          child: Row(children: [
            const Icon(Icons.check_circle, size: 17, color: _C.success),
            const SizedBox(width: 6),
            Expanded(child: Text('Selected: ${widget.fieldLabel.isEmpty ? 'Field' : widget.fieldLabel}', maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: _C.draft, foregroundColor: Colors.white),
              child: const Text('Close'),
            ),
          ]),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  VIEW QUESTIONS (opened by "View Questions" on a subject card)
// ════════════════════════════════════════════════════════════════════════════
class _ViewQuestionsScreen extends StatefulWidget {
  final String token;
  final int subjectId;
  const _ViewQuestionsScreen({required this.token, required this.subjectId});

  @override
  State<_ViewQuestionsScreen> createState() => _ViewQuestionsScreenState();
}

class _ViewQuestionsScreenState extends State<_ViewQuestionsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _Api.post(widget.token, 'view_questions', {'subject_id': '${widget.subjectId}'});
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['success'] == true) {
        _data = Map<String, dynamic>.from(r['data']);
      } else {
        _error = '${r['message']}';
      }
    });
  }

  void _zoom(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
          Positioned(top: 4, right: 4, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qs = _maps(_data['questions']);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.headerGradient)),
        title: Text(_data['subject_name'] == null ? 'View Questions' : '${_data['subject_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : ListView(padding: const EdgeInsets.all(14), children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Text('${qs.length} question${qs.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _toInt(_data['is_draft']) == 1 ? const Color(0x20FFC107) : const Color(0x2028A745),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _toInt(_data['is_draft']) == 1 ? _C.warning : _C.success),
                        ),
                        child: Text(_toInt(_data['is_draft']) == 1 ? 'Draft' : 'Published',
                            style: TextStyle(fontWeight: FontWeight.w600, color: _toInt(_data['is_draft']) == 1 ? const Color(0xFF856404) : const Color(0xFF155724))),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  for (int i = 0; i < qs.length; i++) _qCard(i, qs[i]),
                ]),
    );
  }

  Widget _qCard(int i, Map<String, dynamic> q) {
    final theory = q['type'] == 'theory';
    final options = (q['options'] as List?) ?? [];
    final correct = _toInt(q['correct']) ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: theory ? _C.theory : _C.primary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('Question ${i + 1}', style: TextStyle(fontWeight: FontWeight.bold, color: theory ? _C.theory : _C.primary)),
                    const SizedBox(width: 8),
                    Text(theory ? '(Theory · ${q['marks']} marks)' : '(Multiple Choice)', style: const TextStyle(color: Color(0xFF666666), fontSize: 13)),
                  ]),
                  const SizedBox(height: 8),
                  Text('${q['text']}', style: const TextStyle(fontSize: 15, height: 1.4, color: _C.text)),
                  if (q['image_url'] != null) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _zoom('${q['image_url']}'),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFFFAFAFA), border: Border.all(color: const Color(0xFFDDDDDD)), borderRadius: BorderRadius.circular(5)),
                        child: Image.network('${q['image_url']}', height: 110, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                      ),
                    ),
                  ],
                  if (!theory) ...[
                    const SizedBox(height: 10),
                    for (int k = 0; k < options.length; k++)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: correct == k + 1 ? const Color(0xFFE8F5E9) : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(children: [
                          Text('${'ABCD'[k]}.  ', style: TextStyle(fontWeight: FontWeight.bold, color: correct == k + 1 ? Colors.green : _C.text)),
                          Expanded(child: Text('${options[k]}', style: TextStyle(fontWeight: correct == k + 1 ? FontWeight.bold : FontWeight.normal, color: correct == k + 1 ? Colors.green : _C.text))),
                          if (correct == k + 1) const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        ]),
                      ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
