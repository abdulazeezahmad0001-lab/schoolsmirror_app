// flutter_add_exam_screen.dart
// Mirrors add_exam.php 1:1: free-trial / subscription banners, session-term-class filters,
// exam form (MCQ + images + theory), Scientific Tools, All Subjects list, edit details,
// publish / delete / delete all, pagination, How It Works and Flutterwave payment.
//
// pubspec.yaml needs:  http, shared_preferences, image_picker, url_launcher

import 'dart:convert';
import 'dart:ui' show ImageFilter;
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

/// Aurora Bento design tokens (see below)
/// "Aurora Bento" design tokens
class _C {
  static const primary = Color(0xFF5B4BFF); // electric indigo
  static const secondary = Color(0xFF22D3EE); // cyan
  static const pink = Color(0xFFEC4899);
  static const success = Color(0xFF10B981);
  static const draft = Color(0xFF64748B);
  static const danger = Color(0xFFF43F5E);
  static const warning = Color(0xFFF59E0B);
  static const info = Color(0xFF0EA5E9);
  static const theory = Color(0xFFF97316);
  static const sci = Color(0xFF8B5CF6);
  static const payment = Color(0xFF7C3AED);
  static const lightBg = Color(0xFFF4F5FF);
  static const field = Color(0xFFF6F7FF);
  static const border = Color(0xFFE3E6F8);
  static const text = Color(0xFF0F172A); // ink
  static const muted = Color(0xFF55627A);
  static const hint = Color(0xFF8590A6);
  static const purple1 = Color(0xFF5B4BFF);
  static const purple2 = Color(0xFF9B5CF6);

  static const headerGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B4BFF), Color(0xFF8B5CF6)]);
  static const ctaGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B4BFF), Color(0xFFA855F7)]);
  static const bannerGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF5B4BFF), Color(0xFF8B5CF6), Color(0xFFEC4899)]);
  static const heroGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1E1B4B), Color(0xFF3730A3), Color(0xFF7C3AED)]);
  static const goGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF10B981), Color(0xFF06B6D4)]);
}

ThemeData _lightTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: _C.lightBg,
    canvasColor: Colors.white,
    cardColor: Colors.white,
    colorScheme: base.colorScheme.copyWith(primary: _C.primary, secondary: _C.secondary, surface: Colors.white, onSurface: _C.text),
    textTheme: base.textTheme.apply(bodyColor: _C.text, displayColor: _C.text),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: _C.primary),
    dividerColor: _C.border,
  );
}

List<BoxShadow> _soft([Color color = const Color(0xFF312E81), double a = 0.09]) =>
    [BoxShadow(color: color.withOpacity(a), blurRadius: 28, offset: const Offset(0, 12))];

Widget _glass({required Widget child, double radius = 20, EdgeInsets padding = const EdgeInsets.all(12), double opacity = 0.14}) => ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(color: Colors.white.withOpacity(opacity), borderRadius: BorderRadius.circular(radius), border: Border.all(color: Colors.white.withOpacity(0.28))),
          child: child,
        ),
      ),
    );

/// soft glowing orbs behind the page
class _AuroraBackdrop extends StatelessWidget {
  const _AuroraBackdrop();
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(children: [
          Positioned(top: 380, left: -130, child: _orb(320, const Color(0xFF22D3EE), 0.16)),
          Positioned(top: 760, right: -140, child: _orb(340, const Color(0xFFA855F7), 0.14)),
          Positioned(top: 1250, left: -120, child: _orb(300, const Color(0xFFEC4899), 0.10)),
        ]),
      );
  Widget _orb(double s, Color c, double a) => Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c.withOpacity(a), c.withOpacity(0)])));
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
    final c = error ? _C.danger : _C.success;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        duration: const Duration(seconds: 4),
        margin: EdgeInsets.fromLTRB(16, 0, 16, _formVisible ? 150 : 24),
        content: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
          decoration: BoxDecoration(color: _C.text, borderRadius: BorderRadius.circular(22), boxShadow: [BoxShadow(color: c.withOpacity(0.35), blurRadius: 24, offset: const Offset(0, 10))]),
          child: Row(children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Icon(error ? Icons.priority_high_rounded : Icons.check_rounded, color: Colors.white, size: 21)),
            const SizedBox(width: 12),
            Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3))),
          ]),
        ),
      ));
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
  // ───────────────────────────── pop-ups (animated) ─────────────────────────────
  Widget _popBtn(String label, VoidCallback onTap, {Color color = _C.primary, bool ghost = false, IconData? icon}) {
    if (ghost) {
      return SizedBox(
        width: double.infinity,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(foregroundColor: _C.muted, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          child: Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
        ),
      );
    }
    return _btn(label, icon ?? Icons.check_rounded, color, onTap, expand: true);
  }

  Future<T?> _popup<T>({
    required IconData icon,
    required Color color,
    required String title,
    required String text,
    required List<Widget> Function(BuildContext) actions,
    Widget? extra,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: const Color(0xFF0F172A).withOpacity(0.58),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (ctx, _, __) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, _, __) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
            child: Center(
              child: Theme(
                data: _lightTheme(),
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: color.withOpacity(0.25), blurRadius: 50, offset: const Offset(0, 20))]),
                      child: SingleChildScrollView(
                        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Center(
                            child: Container(
                              width: 96,
                              height: 96,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.12)),
                              child: Container(
                                width: 70,
                                height: 70,
                                decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, Color.lerp(color, Colors.black, 0.25)!]), boxShadow: [BoxShadow(color: color.withOpacity(0.45), blurRadius: 18, offset: const Offset(0, 8))]),
                                child: Icon(icon, color: Colors.white, size: 34),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _C.text, height: 1.2)),
                          const SizedBox(height: 10),
                          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5, color: _C.muted, height: 1.5)),
                          if (extra != null) ...[const SizedBox(height: 14), extra],
                          const SizedBox(height: 20),
                          ...actions(ctx).expand((w) => [w, const SizedBox(height: 6)]),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _confirm(String title, String text, {String yes = 'Yes', bool destructive = false, IconData icon = Icons.warning_amber_rounded}) {
    final color = destructive ? _C.danger : _C.primary;
    return _popup<bool>(
      icon: icon,
      color: color,
      title: title,
      text: text,
      actions: (ctx) => [
        _popBtn(yes, () => Navigator.pop(ctx, true), color: color, icon: destructive ? Icons.delete_outline_rounded : Icons.check_rounded),
        _popBtn('Cancel', () => Navigator.pop(ctx, false), ghost: true),
      ],
    );
  }

  Future<void> _alert(String title, String text, {IconData icon = Icons.info_rounded, Color color = _C.primary}) {
    return _popup<void>(
      icon: icon,
      color: color,
      title: title,
      text: text,
      actions: (ctx) => [_popBtn('Got it', () => Navigator.pop(ctx), color: color)],
    );
  }

  // ───────────────────────────── small UI helpers ─────────────────────────────
  InputDecoration _dec(String hint, {IconData? icon, String? label}) => InputDecoration(
        hintText: hint,
        labelText: label,
        hintStyle: const TextStyle(color: _C.hint, fontSize: 15.5),
        labelStyle: const TextStyle(color: _C.muted, fontWeight: FontWeight.w600),
        prefixIcon: icon == null ? null : Icon(icon, size: 21, color: _C.primary),
        filled: true,
        fillColor: _C.field,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: _C.border, width: 1.4)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: _C.primary, width: 2)),
      );

  /// white rounded card; [bar] tints the outline + glow
  Widget _accentCard({
    required Widget child,
    Color bar = _C.primary,
    Color bg = Colors.white,
    EdgeInsets padding = const EdgeInsets.all(18),
    double barWidth = 4,
    double radius = 26,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(radius), border: Border.all(color: bar.withOpacity(0.18), width: 1.4), boxShadow: _soft(bar, 0.10)),
      child: child,
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback? onTap, {bool expand = false, bool small = false}) {
    final dark = Color.lerp(color, Colors.black, 0.24)!;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Container(
        width: expand ? double.infinity : null,
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, dark]),
          borderRadius: BorderRadius.circular(small ? 14 : 18),
          boxShadow: onTap == null ? null : [BoxShadow(color: color.withOpacity(0.38), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(small ? 14 : 18),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 14 : 20, vertical: small ? 10 : 15),
              child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: small ? 17 : 20, color: Colors.white),
                SizedBox(width: small ? 6 : 9),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: small ? 13.5 : 15.5))),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ghostBtn(String label, IconData icon, Color color, VoidCallback? onTap, {bool small = false, bool expand = false}) => Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(small ? 14 : 18),
          child: InkWell(
            borderRadius: BorderRadius.circular(small ? 14 : 18),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 14 : 18, vertical: small ? 10 : 13),
              child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: small ? 17 : 19, color: color),
                const SizedBox(width: 7),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: small ? 13.5 : 15))),
              ]),
            ),
          ),
        ),
      );

  Widget _upgradeBtn(String label, {IconData icon = Icons.workspace_premium_rounded}) => _btn(label, icon, _C.payment, _openPayment);

  Widget _howBtn() => _ghostBtn('How it works', Icons.lightbulb_outline_rounded, _C.primary, _openHow, small: true);

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: _C.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: const TextStyle(color: _C.primary, fontWeight: FontWeight.w800, fontSize: 13.5)),
      );

  Widget _label(IconData icon, String text, {Color color = _C.text}) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: _C.primary.withOpacity(0.11), borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 15, color: _C.primary),
          ),
          const SizedBox(width: 9),
          Flexible(child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: color))),
        ]),
      );


  void _setActive(TextEditingController c, String label) {
    _activeCtrl = c;
    _activeLabel = label;
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final showForm = _formVisible && !_loading;
    return Theme(
      data: _lightTheme(),
      child: Scaffold(
        backgroundColor: _C.lightBg,
        body: Stack(children: [
          const Positioned.fill(child: _AuroraBackdrop()),
          if (_loading)
            _loader()
          else
            RefreshIndicator(
              color: _C.primary,
              edgeOffset: 90,
              onRefresh: _refreshAll,
              child: ListView(
                controller: _scroll,
                padding: EdgeInsets.zero,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                children: [
                  _hero(),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 18, 16, showForm ? 170 : 44),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (_banner != null) _alertBox(),
                      if (_pendingRef != null) _pendingPaymentBox(),
                      _planCard(),
                      _steps(),
                      const SizedBox(height: 18),
                      _selectionCard(),
                      const SizedBox(height: 18),
                      _formVisible ? _examForm() : _selectFirstBox(),
                      KeyedSubtree(key: _subjectsKey, child: _subjectsSection()),
                    ]),
                  ),
                ],
              ),
            ),
          if (showForm) Positioned(left: 0, right: 0, bottom: 0, child: _dock()),
          if (showForm) Positioned(right: 16, bottom: 132, child: _sciFab()),
        ]),
      ),
    );
  }

  Widget _loader() => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: _C.ctaGradient, boxShadow: _soft(_C.primary, 0.35)),
            child: const Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(strokeWidth: 4, color: Colors.white)),
          ),
          const SizedBox(height: 18),
          const Text('Loading your workspace…', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _C.muted)),
        ]),
      );

  // ───────────────────────────── hero ─────────────────────────────
  Widget _circleGlass(IconData icon, VoidCallback onTap, {String? tip}) => Tooltip(
        message: tip ?? '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: _glass(radius: 22, padding: const EdgeInsets.all(11), opacity: 0.16, child: Icon(icon, color: Colors.white, size: 22)),
        ),
      );

  Widget _heroStat(IconData icon, String value, String label) => Expanded(
        child: _glass(
          radius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(height: 8),
            Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.82), fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _hero() {
    final top = MediaQuery.of(context).padding.top;
    final canPop = Navigator.of(context).canPop();
    final plan = _hasActive && !_hasFreeTrial ? 'Pro' : (_hasFreeTrial ? 'Trial' : 'No plan');
    final left = _hasFreeTrial ? '$_remaining left' : (_hasActive ? 'Unlimited' : '—');
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(38)),
      child: Container(
        decoration: const BoxDecoration(gradient: _C.heroGradient),
        padding: EdgeInsets.fromLTRB(18, top + 10, 18, 24),
        child: Stack(children: [
          Positioned(top: -70, right: -50, child: Container(width: 220, height: 220, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFF22D3EE).withOpacity(0.55), const Color(0xFF22D3EE).withOpacity(0)])))),
          Positioned(bottom: -60, left: -40, child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [const Color(0xFFEC4899).withOpacity(0.45), const Color(0xFFEC4899).withOpacity(0)])))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (canPop) _circleGlass(Icons.arrow_back_rounded, () => Navigator.of(context).maybePop(), tip: 'Back'),
              const Spacer(),
              _circleGlass(Icons.lightbulb_outline_rounded, _openHow, tip: 'How it works'),
            ]),
            const SizedBox(height: 18),
            Text(_editSubjectId > 0 ? 'Edit draft' : 'Create exam', style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -0.5)),
            const SizedBox(height: 8),
            Text('Set up, write questions and publish — all from your phone.', style: TextStyle(color: Colors.white.withOpacity(0.86), fontSize: 15.5, height: 1.35)),
            const SizedBox(height: 18),
            Row(children: [
              _heroStat(Icons.library_books_rounded, '$_total', 'Exams'),
              const SizedBox(width: 10),
              _heroStat(Icons.workspace_premium_rounded, plan, 'Plan'),
              const SizedBox(width: 10),
              _heroStat(Icons.bolt_rounded, left, 'Allowance'),
            ]),
          ]),
        ]),
      ),
    );
  }

  // ───────────────────────────── notices ─────────────────────────────
  Widget _alertBox() {
    final err = _bannerError;
    final c = err ? _C.danger : _C.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(color: c.withOpacity(0.10), borderRadius: BorderRadius.circular(22), border: Border.all(color: c.withOpacity(0.4), width: 1.4)),
      child: Row(children: [
        Container(width: 38, height: 38, decoration: BoxDecoration(color: c, shape: BoxShape.circle), child: Icon(err ? Icons.priority_high_rounded : Icons.check_rounded, color: Colors.white, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Text(_banner!, style: TextStyle(color: Color.lerp(c, Colors.black, 0.45), fontSize: 15, fontWeight: FontWeight.w700, height: 1.3))),
        IconButton(onPressed: () => setState(() => _banner = null), icon: Icon(Icons.close_rounded, color: Color.lerp(c, Colors.black, 0.45))),
      ]),
    );
  }

  Widget _pendingPaymentBox() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _C.warning.withOpacity(0.12), borderRadius: BorderRadius.circular(24), border: Border.all(color: _C.warning.withOpacity(0.5), width: 1.4)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 38, height: 38, decoration: const BoxDecoration(color: _C.warning, shape: BoxShape.circle), child: const Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            const Expanded(child: Text('Waiting for your payment', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF78350F)))),
          ]),
          const SizedBox(height: 8),
          const Text('Finished paying on Flutterwave? Tap verify to activate your plan.', style: TextStyle(color: Color(0xFF78350F), fontSize: 14.5, height: 1.4)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _btn('Verify payment', Icons.verified_rounded, _C.success, () => _verifyPayment(), small: true),
            _ghostBtn('Dismiss', Icons.close_rounded, _C.draft, () => setState(() => _pendingRef = null), small: true),
          ]),
        ]),
      );

  Widget _planShell({required IconData icon, required Color color, required String title, required String body, String? foot, Widget? leading, required List<Widget> actions}) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color.withOpacity(0.13), Colors.white]),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withOpacity(0.35), width: 1.4),
          boxShadow: _soft(color, 0.12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            leading ?? Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.25)!]), boxShadow: _soft(color, 0.35)), child: Icon(icon, color: Colors.white, size: 28)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _C.text)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 14.5, color: _C.muted, height: 1.4)),
                if (foot != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(foot, style: const TextStyle(fontSize: 12.5, color: _C.hint))),
              ]),
            ),
          ]),
          if (actions.isNotEmpty) ...[const SizedBox(height: 14), Wrap(spacing: 10, runSpacing: 10, children: actions)],
        ]),
      );

  Widget _planCard() {
    if (_hasFreeTrial) {
      final pct = _trialLimit == 0 ? 0.0 : (_subjectCount / _trialLimit).clamp(0.0, 1.0);
      return _planShell(
        icon: Icons.card_giftcard_rounded,
        color: _C.success,
        title: 'Free trial active',
        body: _trialMsg,
        leading: SizedBox(
          width: 64,
          height: 64,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 64, height: 64, child: CircularProgressIndicator(value: pct, strokeWidth: 7, backgroundColor: _C.border, color: _C.success, strokeCap: StrokeCap.round)),
            Text('$_subjectCount/$_trialLimit', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: _C.text)),
          ]),
        ),
        foot: '$_remaining subject${_remaining == 1 ? '' : 's'} remaining',
        actions: [_upgradeBtn('Upgrade now'), _howBtn()],
      );
    }
    if (!_cbtEnabled) return const SizedBox.shrink();
    final sub = _status['subscription'] is Map ? Map<String, dynamic>.from(_status['subscription']) : null;
    if (_hasActive && sub != null) {
      return _planShell(
        icon: Icons.verified_user_rounded,
        color: _C.success,
        title: 'CBT access active',
        body: 'Your ${sub['plan_type']} plan is valid until ${sub['expires']}.',
        foot: 'Reference: ${sub['reference']}',
        actions: [_howBtn()],
      );
    }
    if (!_canCreate) {
      return _planShell(
        icon: Icons.lock_rounded,
        color: _C.payment,
        title: 'Upgrade required',
        body: _subjectCount >= _trialLimit ? "$_trialMsg You've used all $_trialLimit free trial subjects." : _trialMsg,
        actions: [_upgradeBtn('Subscribe now'), _howBtn()],
      );
    }
    return _planShell(
      icon: Icons.rocket_launch_rounded,
      color: _C.primary,
      title: 'Get started',
      body: 'Subscribe to a plan to create and manage unlimited exams.',
      actions: [_upgradeBtn('Subscribe now'), _howBtn()],
    );
  }

  // ───────────────────────────── step rail ─────────────────────────────
  int get _stepIndex {
    if (!_formVisible) return 0;
    final hasQ = _questions.any((q) => q.text.text.trim().isNotEmpty);
    return (_titleCtrl.text.trim().isNotEmpty && hasQ) ? 2 : 1;
  }

  Widget _steps() {
    const labels = ['Setup', 'Questions', 'Publish'];
    const icons = [Icons.tune_rounded, Icons.edit_note_rounded, Icons.rocket_launch_rounded];
    final cur = _stepIndex;
    Widget node(int i) {
      final done = i < cur, now = i == cur;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: done ? _C.goGradient : (now ? _C.ctaGradient : null),
            color: (done || now) ? null : Colors.white,
            border: (done || now) ? null : Border.all(color: _C.border, width: 1.8),
            boxShadow: now ? _soft(_C.primary, 0.4) : null,
          ),
          child: Icon(done ? Icons.check_rounded : icons[i], color: (done || now) ? Colors.white : _C.hint, size: 22),
        ),
        const SizedBox(height: 6),
        Text(labels[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: (done || now) ? _C.text : _C.hint)),
      ]);
    }

    Widget bar(int i) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: AnimatedContainer(duration: const Duration(milliseconds: 260), height: 5, decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), gradient: i < cur ? _C.goGradient : null, color: i < cur ? null : _C.border)),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: _C.border, width: 1.4), boxShadow: _soft()),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [node(0), bar(0), node(1), bar(1), node(2)]),
    );
  }

  // ───────────────────────────── setup (session · term · class) ─────────────────────────────
  Widget _pickTile(IconData icon, String label, int? value, List<Map<String, dynamic>> items, String idKey, String nameKey, ValueChanged<int?> onPick, Color color) {
    final name = value == null ? null : _nameOf(items, idKey, nameKey, value);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: () => _openPicker(label, icon, items, idKey, nameKey, value, onPick, color),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: name != null ? color.withOpacity(0.07) : _C.field, borderRadius: BorderRadius.circular(22), border: Border.all(color: name != null ? color.withOpacity(0.55) : _C.border, width: 1.6)),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [color, Color.lerp(color, Colors.black, 0.25)!]), boxShadow: _soft(color, 0.3)),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: _C.muted, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(name ?? 'Tap to choose', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: name != null ? _C.text : _C.hint)),
            ]),
          ),
          Icon(name != null ? Icons.check_circle_rounded : Icons.unfold_more_rounded, color: name != null ? color : _C.hint),
        ]),
      ),
    );
  }

  void _openPicker(String title, IconData icon, List<Map<String, dynamic>> items, String idKey, String nameKey, int? current, ValueChanged<int?> onPick, Color color) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, sc) {
          Widget row(String text, int? id, {bool clear = false}) {
            final sel = id == current && !clear || (clear && current == null);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Navigator.pop(ctx);
                  onPick(id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(color: sel ? color.withOpacity(0.10) : _C.field, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? color : _C.border, width: sel ? 2 : 1.4)),
                  child: Row(children: [
                    Expanded(child: Text(text, style: TextStyle(fontSize: 17, fontWeight: sel ? FontWeight.w900 : FontWeight.w700, color: clear ? _C.muted : _C.text))),
                    if (sel) Icon(Icons.check_circle_rounded, color: color) else Icon(clear ? Icons.close_rounded : Icons.radio_button_unchecked_rounded, color: _C.hint, size: 22),
                  ]),
                ),
              ),
            );
          }

          return Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
            child: Column(children: [
              const SizedBox(height: 10),
              Container(width: 46, height: 5, decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(3))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Select $title', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
              ),
              Expanded(
                child: ListView(controller: sc, padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), children: [
                  row('No selection', null, clear: true),
                  for (final m in items) row('${m[nameKey]}', _toInt(m[idKey])),
                  if (items.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nothing available yet.', textAlign: TextAlign.center, style: TextStyle(color: _C.muted, fontSize: 15.5))),
                ]),
              ),
            ]),
          );
        },
      ),
    );
  }

  Widget _selectionCard() {
    return _accentCard(
      bar: _C.primary,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(gradient: _C.ctaGradient, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.tune_rounded, color: Colors.white)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Exam setup', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)), Text('Where does this exam belong?', style: TextStyle(fontSize: 14, color: _C.muted))])),
          _pill('Step 1'),
        ]),
        const SizedBox(height: 16),
        _pickTile(Icons.calendar_month_rounded, 'Session', _pSession, _sessions, 'id', 'session_name', (v) => setState(() => _pSession = v), _C.primary),
        const SizedBox(height: 10),
        _pickTile(Icons.auto_stories_rounded, 'Term', _pTerm, _terms, 'id', 'term_name', (v) => setState(() => _pTerm = v), _C.sci),
        const SizedBox(height: 10),
        _pickTile(Icons.groups_rounded, 'Class', _pClass, _classes, 'class_id', 'class_name', (v) => setState(() => _pClass = v), _C.info),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(flex: 3, child: _btn('Apply', Icons.check_circle_rounded, _C.primary, _applyFilters, expand: true)),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: _ghostBtn('Reset', Icons.restart_alt_rounded, _C.draft, _clearFilters, expand: true)),
        ]),
        if (!(_pSession != null && _pTerm != null && _pClass != null))
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Row(children: [Icon(Icons.info_outline_rounded, size: 17, color: _C.hint), SizedBox(width: 6), Expanded(child: Text('Choose a session, term and class to start writing questions.', style: TextStyle(fontSize: 13.5, color: _C.muted)))]),
          ),
        if (_formVisible) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: _C.success.withOpacity(0.09), borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.success.withOpacity(0.35))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.check_circle_rounded, color: _C.success, size: 19), SizedBox(width: 7), Text('Ready to write for', style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF065F46), fontSize: 14.5))]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _ctxChip(Icons.calendar_month_rounded, _nameOf(_sessions, 'id', 'session_name', _sessionId)),
                _ctxChip(Icons.auto_stories_rounded, _nameOf(_terms, 'id', 'term_name', _termId)),
                _ctxChip(Icons.groups_rounded, _nameOf(_classes, 'class_id', 'class_name', _classId)),
              ]),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _ctxChip(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 16, color: _C.primary), const SizedBox(width: 6), Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))]),
      );

  Widget _selectFirstBox() => Container(
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 34),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.8), borderRadius: BorderRadius.circular(30), border: Border.all(color: _C.border, width: 1.4)),
        child: Column(children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: _C.ctaGradient, boxShadow: _soft(_C.primary, 0.4)),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 44),
          ),
          const SizedBox(height: 20),
          const Text('Start with the setup', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          const Text('Pick a session, term and class above and your exam editor will unlock right here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15.5, color: _C.muted, height: 1.45)),
        ]),
      );

  // ───────────────────────────── exam form ─────────────────────────────
  Widget _numBadge(String n, Gradient g) => Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(16), boxShadow: _soft(const Color(0xFF5B4BFF), 0.3)),
        child: Text(n, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20)),
      );

  Widget _iconBtn(IconData i, Color c, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(width: 42, height: 42, decoration: BoxDecoration(color: c.withOpacity(0.11), borderRadius: BorderRadius.circular(14)), child: Icon(i, color: c, size: 22)),
      );

  Widget _addTile(String label, IconData icon, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: _Dashed(
          color: color,
          background: color.withOpacity(0.06),
          radius: 26,
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: 36, height: 36, decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(icon, color: Colors.white, size: 22)),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: color)),
          ]),
        ),
      );

  Widget _examForm() {
    final locked = !_canCreate && _editSubjectId == 0;
    final form = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _accentCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [_numBadge('2', _C.ctaGradient), const SizedBox(width: 12), const Expanded(child: Text('Exam title', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)))]),
          const SizedBox(height: 14),
          TextField(
            controller: _titleCtrl,
            readOnly: locked,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _C.text),
            decoration: _dec('e.g. Biology SS3', icon: Icons.menu_book_rounded),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      for (int i = 0; i < _questions.length; i++) _questionCard(i),
      _addTile('Add question', Icons.add_rounded, _C.primary, _addQuestion),
      const SizedBox(height: 16),
      _theorySection(),
    ]);
    if (!locked) return form;
    return Stack(children: [
      Opacity(opacity: 0.3, child: IgnorePointer(child: form)),
      Positioned.fill(child: _upgradeOverlay()),
    ]);
  }

  Widget _upgradeOverlay() => Container(
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.93), borderRadius: BorderRadius.circular(30), border: Border.all(color: _C.payment.withOpacity(0.3), width: 1.4)),
        padding: const EdgeInsets.all(22),
        child: Center(
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, gradient: _C.ctaGradient, boxShadow: _soft(_C.payment, 0.4)), child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 38)),
              const SizedBox(height: 14),
              const Text('Upgrade required', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(_trialMsg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5, color: _C.muted, height: 1.4)),
              if (_subjectCount >= _trialLimit) ...[
                const SizedBox(height: 10),
                Text('You created $_subjectCount subjects during your free trial. Upgrade to keep creating exams.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, height: 1.4)),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: _C.field, borderRadius: BorderRadius.circular(20)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final t in ['Unlimited exam subjects', 'Unlimited questions per subject', 'Theory questions with images', 'Priority support', 'Advanced exam analytics'])
                      Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [const Icon(Icons.check_circle_rounded, size: 19, color: _C.success), const SizedBox(width: 9), Expanded(child: Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)))])),
                  ]),
                ),
              ] else if (!_hasActive && !_hasFreeTrial) ...[
                const SizedBox(height: 8),
                Text('Start with our free trial to create up to $_trialLimit subjects!', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5)),
              ],
              const SizedBox(height: 16),
              _upgradeBtn(_hasFreeTrial ? 'Upgrade now' : 'Get started'),
              const SizedBox(height: 10),
              _howBtn(),
            ]),
          ),
        ),
      );

  Widget _toolChip(String label, IconData icon, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: color.withOpacity(0.10), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.35))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 19, color: color), const SizedBox(width: 7), Text(label, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color.lerp(color, Colors.black, 0.2)))]),
        ),
      );

  Widget _optionRow(_Q q, int i, int k) {
    final sel = q.answer == k + 1;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: sel ? _C.success.withOpacity(0.10) : _C.field, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? _C.success : _C.border, width: sel ? 2 : 1.4)),
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: GestureDetector(
            onTap: () => setState(() => q.answer = sel ? null : k + 1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, gradient: sel ? _C.goGradient : null, color: sel ? null : Colors.white, border: sel ? null : Border.all(color: _C.border, width: 1.8), boxShadow: sel ? _soft(_C.success, 0.4) : null),
              child: sel ? const Icon(Icons.check_rounded, color: Colors.white, size: 24) : Text('ABCD'[k], style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: _C.primary)),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: q.opts[k],
            onTap: () => _setActive(q.opts[k], 'Question ${i + 1} · Option ${'ABCD'[k]}'),
            style: const TextStyle(fontSize: 16.5, color: _C.text, fontWeight: FontWeight.w600),
            minLines: 1,
            maxLines: 4,
            decoration: InputDecoration(hintText: 'Option ${'ABCD'[k]}', hintStyle: const TextStyle(color: _C.hint, fontSize: 16), border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4)),
          ),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _questionCard(int i) {
    final q = _questions[i];
    final hasPic = q.imageBytes != null || q.existingImageUrl != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: _C.border, width: 1.4), boxShadow: _soft()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _numBadge('${i + 1}', _C.ctaGradient),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Question ${i + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)), const Text('Multiple choice', style: TextStyle(fontSize: 13.5, color: _C.muted, fontWeight: FontWeight.w600))])),
          if (q.answer != null) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: _C.success.withOpacity(0.12), borderRadius: BorderRadius.circular(14)), child: Text('Answer ${'ABCD'[q.answer! - 1]}', style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.w900, fontSize: 13.5))),
          _iconBtn(Icons.delete_outline_rounded, _C.danger, () => _removeQuestion(i)),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: q.text,
          minLines: 3,
          maxLines: 8,
          textInputAction: TextInputAction.newline,
          onTap: () => _setActive(q.text, 'Question ${i + 1}'),
          onChanged: (_) {},
          style: const TextStyle(fontSize: 16.5, color: _C.text, height: 1.4, fontWeight: FontWeight.w600),
          decoration: _dec('Type question ${i + 1} here…'),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _toolChip(hasPic ? 'Change image' : 'Add image', Icons.add_photo_alternate_rounded, _C.info, () => _pickImage(q)),
          _toolChip('Symbols', Icons.functions_rounded, _C.sci, _openScientific),
        ]),
        if (hasPic)
          Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(color: _C.field, borderRadius: BorderRadius.circular(22), border: Border.all(color: _C.border)),
            child: Stack(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox(
                  width: double.infinity,
                  height: 180,
                  child: q.imageBytes != null
                      ? Image.memory(q.imageBytes!, fit: BoxFit.contain)
                      : Image.network(q.existingImageUrl!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_rounded, size: 36, color: _C.hint))),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  onTap: () => setState(() {
                    q.imageBytes = null;
                    q.imageName = null;
                    q.existingImage = null;
                    q.existingImageUrl = null;
                  }),
                  child: Container(width: 36, height: 36, decoration: const BoxDecoration(color: _C.danger, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 20)),
                ),
              ),
            ]),
          ),
        const SizedBox(height: 18),
        Row(children: [
          const Text('Answer options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(width: 8),
          Expanded(child: Text(q.answer == null ? 'Tap a letter to mark the correct one' : 'Tap the green tick to change', style: TextStyle(fontSize: 12.5, color: q.answer == null ? _C.warning : _C.muted, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 10),
        for (int k = 0; k < 4; k++) _optionRow(q, i, k),
      ]),
    );
  }

  // ───────────────────────────── theory ─────────────────────────────
  Widget _theorySection() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_C.theory.withOpacity(_includeTheory ? 0.14 : 0.07), Colors.white]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: _C.theory.withOpacity(_includeTheory ? 0.55 : 0.3), width: 1.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _includeTheory = !_includeTheory),
          child: Row(children: [
            Container(width: 50, height: 50, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFB923C), Color(0xFFEA580C)]), borderRadius: BorderRadius.circular(17), boxShadow: _soft(_C.theory, 0.35)), child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 28)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Theory questions', style: TextStyle(fontSize: 18.5, fontWeight: FontWeight.w900)), Text('Essay questions shown after the MCQs', style: TextStyle(fontSize: 13.5, color: _C.muted))])),
            Switch(value: _includeTheory, onChanged: (v) => setState(() => _includeTheory = v), activeColor: Colors.white, activeTrackColor: _C.theory, inactiveTrackColor: _C.border, inactiveThumbColor: Colors.white),
          ]),
        ),
        if (_includeTheory) ...[
          const SizedBox(height: 14),
          for (int i = 0; i < _theory.length; i++) _theoryCard(i),
          _addTile('Add theory question', Icons.add_rounded, _C.theory, _addTheory),
        ],
      ]),
    );
  }

  Widget _theoryCard(int i) {
    final t = _theory[i];
    final n = (int.tryParse(t.marks.text) ?? 5).clamp(1, 20);
    Widget step(IconData ic, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(width: 40, height: 40, decoration: BoxDecoration(color: onTap == null ? _C.border : _C.theory.withOpacity(0.14), borderRadius: BorderRadius.circular(14)), child: Icon(ic, color: onTap == null ? _C.hint : _C.theory, size: 22)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _C.theory.withOpacity(0.3), width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _numBadge('${i + 1}', const LinearGradient(colors: [Color(0xFFFB923C), Color(0xFFEA580C)])),
          const SizedBox(width: 12),
          const Expanded(child: Text('Theory question', style: TextStyle(fontSize: 17.5, fontWeight: FontWeight.w900))),
          _iconBtn(Icons.delete_outline_rounded, _C.danger, () => _removeTheory(i)),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: t.text,
          minLines: 4,
          maxLines: 9,
          onTap: () => _setActive(t.text, 'Theory Question ${i + 1}'),
          style: const TextStyle(fontSize: 16.5, color: _C.text, height: 1.4, fontWeight: FontWeight.w600),
          decoration: _dec('Write the essay question here…'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          const Icon(Icons.star_rounded, color: _C.warning, size: 22),
          const SizedBox(width: 6),
          const Text('Marks', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const Spacer(),
          step(Icons.remove_rounded, n > 1 ? () => setState(() => t.marks.text = '${n - 1}') : null),
          Container(width: 54, alignment: Alignment.center, child: Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
          step(Icons.add_rounded, n < 20 ? () => setState(() => t.marks.text = '${n + 1}') : null),
        ]),
      ]),
    );
  }

  // ───────────────────────────── floating dock ─────────────────────────────
  Widget _dock() {
    final mcq = _questions.length;
    final th = _includeTheory ? _theory.length : 0;
    final bottom = MediaQuery.of(context).padding.bottom;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.92), border: const Border(top: BorderSide(color: _C.border, width: 1.2)), boxShadow: [BoxShadow(color: const Color(0xFF312E81).withOpacity(0.12), blurRadius: 30, offset: const Offset(0, -8))]),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: _C.primary.withOpacity(0.10), borderRadius: BorderRadius.circular(12)), child: Text('$mcq MCQ', style: const TextStyle(color: _C.primary, fontWeight: FontWeight.w900, fontSize: 13))),
              if (th > 0) Container(margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: _C.theory.withOpacity(0.12), borderRadius: BorderRadius.circular(12)), child: Text('$th theory', style: const TextStyle(color: Color(0xFFC2410C), fontWeight: FontWeight.w900, fontSize: 13))),
              const Spacer(),
              if (_saving) const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.4, color: _C.primary)), SizedBox(width: 8), Text('Saving…', style: TextStyle(fontWeight: FontWeight.w800, color: _C.primary))]),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 2, child: _ghostBtn(_editSubjectId > 0 ? 'Update draft' : 'Save draft', Icons.save_rounded, _C.draft, _saving ? null : () => _save('draft'), expand: true)),
              const SizedBox(width: 10),
              Expanded(flex: 3, child: _btn(_editSubjectId > 0 ? 'Publish update' : 'Publish exam', Icons.rocket_launch_rounded, _C.success, _saving ? null : () => _save('publish'), expand: true)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _sciFab() => Tooltip(
        message: 'Scientific tools',
        child: InkWell(
          onTap: _openScientific,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA855F7), Color(0xFF6D28D9)]), boxShadow: _soft(_C.sci, 0.5)),
            child: const Icon(Icons.functions_rounded, color: Colors.white, size: 30),
          ),
        ),
      );

  // ───────────────────────────── how it works (sheet) ─────────────────────────────
  void _openHow() {
    final steps = <List<String>>[
      ['Start free trial', 'Create up to $_trialLimit subjects for free to test the system.'],
      ['Choose a plan', 'Term plan (3 months) or Session plan (9 months) — pick what fits.'],
      ['Pay securely', 'Flutterwave: card, bank transfer, USSD or mobile money.'],
      ['Get full access', 'Once verified, create unlimited exams with MCQ and theory questions.'],
    ];
    final icons = [Icons.card_giftcard_rounded, Icons.view_carousel_rounded, Icons.lock_rounded, Icons.rocket_launch_rounded];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(3)))),
            const SizedBox(height: 18),
            Row(children: [
              Container(width: 52, height: 52, decoration: BoxDecoration(gradient: _C.ctaGradient, borderRadius: BorderRadius.circular(18)), child: const Icon(Icons.lightbulb_rounded, color: Colors.white, size: 28)),
              const SizedBox(width: 14),
              const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('How it works', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)), Text('Four quick steps to get going', style: TextStyle(fontSize: 14.5, color: _C.muted))])),
              IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
            ]),
            const SizedBox(height: 20),
            for (int i = 0; i < steps.length; i++)
              IntrinsicHeight(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Column(children: [
                    Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, gradient: _C.ctaGradient, boxShadow: _soft(_C.primary, 0.3)), child: Icon(icons[i], color: Colors.white, size: 23)),
                    if (i < steps.length - 1) Expanded(child: Container(width: 3, margin: const EdgeInsets.symmetric(vertical: 4), decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(3)))),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${i + 1}. ${steps[i][0]}', style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(steps[i][1], style: const TextStyle(fontSize: 15, color: _C.muted, height: 1.4)),
                      ]),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 4),
            _btn(_hasFreeTrial ? 'Upgrade now' : 'Get started', Icons.rocket_launch_rounded, _C.payment, () {
              Navigator.pop(ctx);
              _openPayment();
            }, expand: true),
          ]),
        ),
      ),
    );
  }

  // ───────────────────────────── your exams (library) ─────────────────────────────
  Widget _subjectsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 30),
      Row(children: [
        Container(width: 46, height: 46, decoration: BoxDecoration(gradient: _C.ctaGradient, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.collections_bookmark_rounded, color: Colors.white)),
        const SizedBox(width: 12),
        const Expanded(child: Text('Your exams', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, letterSpacing: -0.3))),
        _pill('$_total'),
      ]),
      const SizedBox(height: 14),
      if (_subjects.isNotEmpty && _canCreate)
        Align(alignment: Alignment.centerRight, child: _ghostBtn('Delete all', Icons.delete_sweep_rounded, _C.danger, _deleteAll, small: true)),
      const SizedBox(height: 10),
      if (_loadingSubjects)
        const Padding(padding: EdgeInsets.all(34), child: Center(child: CircularProgressIndicator(color: _C.primary)))
      else if (_subjects.isEmpty)
        _emptySubjects()
      else
        for (int i = 0; i < _subjects.length; i++) _subjectCard(_subjects[i], _firstSn + i),
      if (_totalPages > 1) _pagination(),
    ]);
  }

  Widget _emptySubjects() => Container(
        padding: const EdgeInsets.fromLTRB(24, 34, 24, 30),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: _C.border, width: 1.4), boxShadow: _soft()),
        child: Column(children: [
          Container(width: 84, height: 84, decoration: BoxDecoration(shape: BoxShape.circle, color: _C.primary.withOpacity(0.10)), child: const Icon(Icons.inbox_rounded, size: 42, color: _C.primary)),
          const SizedBox(height: 16),
          const Text('No exams yet', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(_filtersReady && _canCreate ? 'Write your first exam in the editor above — it will appear here.' : 'Exams you create will show up here.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15.5, color: _C.muted, height: 1.4)),
          if (!_canCreate) ...[const SizedBox(height: 16), _upgradeBtn(_hasFreeTrial ? 'Upgrade to create' : 'Subscribe to create exams')],
        ]),
      );

  Widget _statusBadge(bool draft) {
    final c = draft ? _C.warning : _C.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: c.withOpacity(0.14), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(draft ? 'Draft' : 'Live', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: draft ? const Color(0xFF92400E) : const Color(0xFF047857))),
      ]),
    );
  }

  Widget _typeBadge(bool theory) {
    final c = theory ? _C.theory : _C.info;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: c.withOpacity(0.11), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(theory ? Icons.edit_note_rounded : Icons.checklist_rounded, size: 17, color: c),
        const SizedBox(width: 5),
        Text(theory ? 'MCQ + Theory' : 'MCQ only', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color.lerp(c, Colors.black, 0.25))),
      ]),
    );
  }

  Widget _miniAction(String label, IconData icon, Color color, VoidCallback onTap) => _ghostBtn(label, icon, color, onTap, small: true);

  Widget _subjectCard(Map<String, dynamic> s, int sn) {
    final id = _toInt(s['subject_id']) ?? 0;
    final draft = _toInt(s['is_draft']) == 1;
    final theory = _toInt(s['include_theory']) == 1;
    final tc = _toInt(s['theory_count']) ?? 0;
    final mc = _toInt(s['mcq_count']) ?? 0;
    final name = '${s['subject_name']}';
    final initials = name.trim().isEmpty ? '?' : name.trim().split(RegExp(r'\s+')).take(2).map((e) => e[0].toUpperCase()).join();
    final tint = draft ? _C.warning : _C.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: _C.border, width: 1.4), boxShadow: _soft()),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(19), gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [tint, Color.lerp(tint, Colors.black, 0.28)!]), boxShadow: _soft(tint, 0.35)),
            child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, height: 1.2)),
              const SizedBox(height: 4),
              Text('Exam #$sn', style: const TextStyle(fontSize: 13.5, color: _C.muted, fontWeight: FontWeight.w600)),
            ]),
          ),
          const SizedBox(width: 8),
          _statusBadge(draft),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _ctxChip(Icons.calendar_month_rounded, '${s['session_name']}'),
          _ctxChip(Icons.auto_stories_rounded, '${s['term_name']}'),
          _ctxChip(Icons.groups_rounded, '${s['class_name']}'),
        ]),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: _C.field, borderRadius: BorderRadius.circular(20)),
          child: Row(children: [
            const Icon(Icons.quiz_rounded, color: _C.primary, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(tc > 0 ? '${s['question_count']} questions  ·  $mc MCQ, $tc theory' : '${s['question_count']} questions', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
            _typeBadge(theory),
          ]),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _miniAction('View', Icons.visibility_rounded, _C.info, () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ViewQuestionsScreen(token: _token!, subjectId: id)))),
          if (draft) _miniAction('Edit', Icons.edit_rounded, _C.primary, () => _editDraft(id)),
          if (draft) _miniAction('Publish', Icons.rocket_launch_rounded, _C.success, () => _publish(id)),
          _miniAction('Details', Icons.tune_rounded, _C.sci, () => _openEditDetails(s)),
          _miniAction('Delete', Icons.delete_outline_rounded, _C.danger, () => _deleteSubject(id)),
        ]),
      ]),
    );
  }

  Widget _pagination() {
    Widget circle(IconData i, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(width: 46, height: 46, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border, width: 1.4)), child: Icon(i, color: _C.primary)),
        );
    Widget num(int p) {
      final cur = p == _page;
      return InkWell(
        onTap: cur ? null : () => _loadSubjects(page: p),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(gradient: cur ? _C.ctaGradient : null, color: cur ? null : Colors.white, borderRadius: BorderRadius.circular(16), border: cur ? null : Border.all(color: _C.border, width: 1.4), boxShadow: cur ? _soft(_C.primary, 0.35) : null),
          child: Text('$p', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cur ? Colors.white : _C.text)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
        if (_page > 1) circle(Icons.chevron_left_rounded, () => _loadSubjects(page: _page - 1)),
        for (int p = 1; p <= _totalPages; p++) num(p),
        if (_page < _totalPages) circle(Icons.chevron_right_rounded, () => _loadSubjects(page: _page + 1)),
      ]),
    );
  }

  // ───────────────────────────── edit details (sheet) ─────────────────────────────
  void _openEditDetails(Map<String, dynamic> s) {
    final nameCtrl = TextEditingController(text: '${s['subject_name']}');
    int? sid = _toInt(s['session_id']), tid = _toInt(s['term_id']), cid = _toInt(s['class_id']);
    bool busy = false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.92),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(3)))),
                const SizedBox(height: 16),
                Row(children: [
                  Container(width: 50, height: 50, decoration: BoxDecoration(gradient: _C.ctaGradient, borderRadius: BorderRadius.circular(17)), child: const Icon(Icons.tune_rounded, color: Colors.white)),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Edit exam details', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                ]),
                const SizedBox(height: 14),
                TextField(controller: nameCtrl, style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800), decoration: _dec('Enter subject name', icon: Icons.menu_book_rounded, label: 'Subject name')),
                const SizedBox(height: 12),
                _pickTile(Icons.calendar_month_rounded, 'Session', sid, _sessions, 'id', 'session_name', (v) => setM(() => sid = v), _C.primary),
                const SizedBox(height: 10),
                _pickTile(Icons.auto_stories_rounded, 'Term', tid, _terms, 'id', 'term_name', (v) => setM(() => tid = v), _C.sci),
                const SizedBox(height: 10),
                _pickTile(Icons.groups_rounded, 'Class', cid, _classes, 'class_id', 'class_name', (v) => setM(() => cid = v), _C.info),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: _ghostBtn('Cancel', Icons.close_rounded, _C.draft, () => Navigator.pop(ctx), expand: true)),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: _btn(busy ? 'Saving…' : 'Update details', Icons.save_rounded, _C.primary, busy
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
                          }, expand: true),
                  ),
                ]),
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
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          titleTextStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: _C.text),
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
              style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
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
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          titleTextStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: _C.text),
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
              style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
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
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          titleTextStyle: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: _C.text),
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
              style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontWeight: FontWeight.w800)),
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

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setM) {
        Widget feat(String t, bool on) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 22, height: 22, decoration: BoxDecoration(color: _C.success.withOpacity(0.14), shape: BoxShape.circle), child: const Icon(Icons.check_rounded, size: 15, color: _C.success)),
                const SizedBox(width: 10),
                Expanded(child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: on ? _C.text : _C.muted))),
              ]),
            );

        Widget planCard(String key, String title, int price, String duration, List<String> feats, {String? ribbon, required IconData icon}) {
          final sel = plan == key;
          return GestureDetector(
            onTap: () => setM(() {
              plan = key;
              ref = 'CBT-${DateTime.now().millisecondsSinceEpoch}-$pid';
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: sel ? LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_C.primary.withOpacity(0.12), Colors.white]) : null,
                color: sel ? null : Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: sel ? _C.primary : _C.border, width: sel ? 2.4 : 1.4),
                boxShadow: sel ? _soft(_C.primary, 0.25) : null,
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(width: 48, height: 48, decoration: BoxDecoration(gradient: sel ? _C.ctaGradient : null, color: sel ? null : _C.field, borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: sel ? Colors.white : _C.primary, size: 25)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), Text(duration, style: const TextStyle(fontSize: 13.5, color: _C.muted))])),
                  if (ribbon != null) Container(margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFEF4444)]), borderRadius: BorderRadius.circular(12)), child: Text(ribbon, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w900))),
                  Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: sel ? _C.primary : _C.hint, size: 27),
                ]),
                const SizedBox(height: 12),
                Text(_naira(price), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: _C.primary, letterSpacing: -0.5)),
                const SizedBox(height: 8),
                for (final f in feats) feat(f, true),
              ]),
            ),
          );
        }

        Widget kv(String k, Widget v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Expanded(flex: 4, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700, color: _C.muted, fontSize: 14.5))),
                Expanded(flex: 5, child: Align(alignment: Alignment.centerRight, child: v)),
              ]),
            );

        final amount = plan == 'term' ? termPrice : sessionPrice;
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.94,
          decoration: const BoxDecoration(color: Color(0xFFF8F8FF), borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
          child: Column(children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(22, 14, 10, 22),
                decoration: const BoxDecoration(gradient: _C.heroGradient),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Center(child: Container(width: 46, height: 5, decoration: BoxDecoration(color: Colors.white.withOpacity(0.4), borderRadius: BorderRadius.circular(3))))),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: Colors.white)),
                  ]),
                  Row(children: [
                    _glass(radius: 20, padding: const EdgeInsets.all(12), child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 30)),
                    const SizedBox(width: 14),
                    const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Choose your plan', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)), SizedBox(height: 2), Text('Unlock the full CBT system', style: TextStyle(color: Colors.white70, fontSize: 15))])),
                  ]),
                ]),
              ),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 18, 18, 34), children: [
                planCard('term', 'Term plan', termPrice, 'Valid for 3 months (one term)', ['Unlimited exam subjects', 'Unlimited questions', 'MCQ & theory questions', '24/7 support', 'All features included'], icon: Icons.event_available_rounded),
                planCard('session', 'Session plan', sessionPrice, 'Valid for 9 months (full session)', ['Everything in Term plan', 'Save ${_naira(saving)} (bulk discount)', 'Priority support', 'Early access to new features', 'One-time setup'], ribbon: 'BEST VALUE', icon: Icons.workspace_premium_rounded),
                if (plan.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: _C.border, width: 1.4), boxShadow: _soft()),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Container(width: 44, height: 44, decoration: BoxDecoration(color: _C.payment.withOpacity(0.12), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.lock_rounded, color: _C.payment)),
                        const SizedBox(width: 12),
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Secure checkout', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900)), Text('Powered by Flutterwave', style: TextStyle(fontSize: 13.5, color: _C.muted))])),
                      ]),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: _C.field, borderRadius: BorderRadius.circular(20)),
                        child: Column(children: [
                          kv('Plan', Text(plan == 'term' ? 'Term · 3 months' : 'Session · 9 months', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
                          const Divider(height: 1),
                          kv('Amount', Text(_naira(amount), style: const TextStyle(color: _C.danger, fontWeight: FontWeight.w900, fontSize: 19))),
                          const Divider(height: 1),
                          kv('Reference', Text(ref, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.w700))),
                        ]),
                      ),
                      const SizedBox(height: 14),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final m in [('Cards', Icons.credit_card_rounded), ('Bank transfer', Icons.account_balance_rounded), ('USSD', Icons.dialpad_rounded), ('Mobile money', Icons.phone_android_rounded), ('QR', Icons.qr_code_2_rounded)])
                          Container(padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8), decoration: BoxDecoration(color: _C.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(14)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$2, size: 17, color: _C.primary), const SizedBox(width: 6), Text(m.$1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))])),
                      ]),
                      const SizedBox(height: 16),
                      _btn(busy ? 'Please wait…' : 'Pay ${_naira(amount)} securely', Icons.lock_rounded, _C.payment, busy
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
                            }, expand: true),
                      const SizedBox(height: 14),
                      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.verified_user_rounded, size: 17, color: _C.success), SizedBox(width: 6), Flexible(child: Text('256-bit SSL encryption · PCI DSS compliant', style: TextStyle(fontSize: 13, color: _C.muted, fontWeight: FontWeight.w700)))]),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: _C.warning.withOpacity(0.11), borderRadius: BorderRadius.circular(24), border: Border.all(color: _C.warning.withOpacity(0.4))),
                    child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Icon(Icons.route_rounded, color: Color(0xFF92400E), size: 21), SizedBox(width: 8), Text('What happens next', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF92400E)))]),
                      SizedBox(height: 8),
                      Text('1. Tap “Pay securely”\n2. Complete payment on Flutterwave\n3. Come back to this app — it verifies automatically\n4. Start creating unlimited exams!', style: TextStyle(color: Color(0xFF78350F), fontSize: 14.5, height: 1.6)),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _C.border)),
                    child: Column(children: [
                      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.headset_mic_rounded, size: 19, color: _C.primary), SizedBox(width: 7), Text('Need help with payment?', style: TextStyle(fontWeight: FontWeight.w900))]),
                      const SizedBox(height: 8),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.email_rounded, size: 16, color: _C.muted), const SizedBox(width: 6), Flexible(child: Text('${_status['contact_email'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)))]),
                      const SizedBox(height: 4),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.phone_rounded, size: 16, color: _C.muted), const SizedBox(width: 6), Text('${_status['contact_phone'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700))]),
                    ]),
                  ),
                ],
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
  final double radius;
  final EdgeInsets padding;
  const _Dashed({required this.child, required this.color, required this.background, this.radius = 8, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedPainter(color, radius),
      child: Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(radius)),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedPainter(this.color, this.radius);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)));
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 8), paint);
        d += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.color != color || old.radius != radius;
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
  static const _tabIcons = <String, IconData>{
    'Math': Icons.calculate_rounded,
    'Fractions': Icons.percent_rounded,
    'Greek': Icons.translate_rounded,
    'Logic': Icons.account_tree_rounded,
    'Chemistry': Icons.science_rounded,
    'Physics': Icons.bolt_rounded,
    'Advanced': Icons.auto_awesome_rounded,
  };

  Widget _tool(String label, VoidCallback onTap, {double? width, IconData? icon}) {
    final glyph = label.length <= 3 && icon == null;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            constraints: BoxConstraints(minHeight: glyph ? 62 : 56),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: _C.border, width: 1.4), boxShadow: _soft(_C.sci, 0.06)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: 21, color: _C.sci), const SizedBox(width: 9)],
              Flexible(child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: glyph ? 25 : 15.5, fontWeight: glyph ? FontWeight.w700 : FontWeight.w800, color: _C.text))),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tools = _sciData[_tab]!;
    return Container(
      height: MediaQuery.of(context).size.height * 0.84,
      decoration: const BoxDecoration(color: Color(0xFFF8F8FF), borderRadius: BorderRadius.vertical(top: Radius.circular(34))),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 46, height: 5, decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(3))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 10, 8),
          child: Row(children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(17), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA855F7), Color(0xFF6D28D9)]), boxShadow: _soft(_C.sci, 0.4)),
              child: const Icon(Icons.functions_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Scientific tools', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                Text('Inserting into: ${widget.fieldLabel.isEmpty ? 'field' : widget.fieldLabel}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13.5, color: _C.muted, fontWeight: FontWeight.w600)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        SizedBox(
          height: 56,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
            for (final t in _sciData.keys)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: () => setState(() => _tab = t),
                  borderRadius: BorderRadius.circular(18),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: _tab == t ? _C.ctaGradient : null, color: _tab == t ? null : Colors.white, borderRadius: BorderRadius.circular(18), border: _tab == t ? null : Border.all(color: _C.border, width: 1.4)),
                    child: Row(children: [
                      Icon(_tabIcons[t] ?? Icons.category_rounded, size: 18, color: _tab == t ? Colors.white : _C.primary),
                      const SizedBox(width: 7),
                      Text(t, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: _tab == t ? Colors.white : _C.text)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth - 32;
            final quarter = (w - 30) / 4;
            final half = (w - 10) / 2;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                if (_tab == 'Fractions') ...[
                  for (final t in tools) _tool(t.label, () => widget.onInsert(t.insert), width: quarter),
                  _tool('a/b  Custom fraction', widget.onFraction, width: w, icon: Icons.percent_rounded),
                ] else if (_tab == 'Advanced') ...[
                  _tool('Equation editor', widget.onEquation, width: w, icon: Icons.functions_rounded),
                  _tool('Matrix editor', widget.onMatrix, width: w, icon: Icons.grid_on_rounded),
                  _tool('Custom fraction', widget.onFraction, width: w, icon: Icons.percent_rounded),
                  for (final t in tools) _tool(t.label, () => widget.onInsert(t.insert), width: t.label.length > 2 ? half : quarter),
                ] else
                  for (final t in tools) _tool(t.label, () => widget.onInsert(t.insert), width: t.label.length <= 3 ? quarter : half),
              ]),
            );
          }),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _C.border))),
          child: Row(children: [
            const Icon(Icons.touch_app_rounded, size: 20, color: _C.sci),
            const SizedBox(width: 8),
            const Expanded(child: Text('Tap a symbol to insert it', style: TextStyle(fontWeight: FontWeight.w700, color: _C.muted))),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          ]),
        ),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  VIEW QUESTIONS (opened by "View" on an exam card)
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
    final draft = _toInt(_data['is_draft']) == 1;
    final mcq = qs.where((q) => q['type'] != 'theory').length;
    final th = qs.length - mcq;
    return Theme(
      data: _lightTheme(),
      child: Scaffold(
        backgroundColor: _C.lightBg,
        body: Stack(children: [
          const Positioned.fill(child: _AuroraBackdrop()),
          ListView(padding: EdgeInsets.zero, children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(34)),
              child: Container(
                decoration: const BoxDecoration(gradient: _C.heroGradient),
                padding: EdgeInsets.fromLTRB(18, MediaQuery.of(context).padding.top + 10, 18, 22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: () => Navigator.of(context).maybePop(),
                    borderRadius: BorderRadius.circular(22),
                    child: _glass(radius: 22, padding: const EdgeInsets.all(11), opacity: 0.16, child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22)),
                  ),
                  const SizedBox(height: 16),
                  Text(_data['subject_name'] == null ? 'Questions' : '${_data['subject_name']}', style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, height: 1.1)),
                  const SizedBox(height: 14),
                  if (!_loading && _error == null)
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _vChip(Icons.quiz_rounded, '${qs.length} question${qs.length == 1 ? '' : 's'}'),
                      _vChip(Icons.checklist_rounded, '$mcq MCQ'),
                      if (th > 0) _vChip(Icons.edit_note_rounded, '$th theory'),
                      _vChip(draft ? Icons.edit_rounded : Icons.bolt_rounded, draft ? 'Draft' : 'Live'),
                    ]),
                ]),
              ),
            ),
            if (_loading)
              const Padding(padding: EdgeInsets.all(60), child: Center(child: CircularProgressIndicator(color: _C.primary)))
            else if (_error != null)
              Padding(padding: const EdgeInsets.all(28), child: Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: _C.danger, fontWeight: FontWeight.w700))))
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 40),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (int i = 0; i < qs.length; i++) _qCard(i, qs[i])]),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _vChip(IconData i, String t) => _glass(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 16, color: Colors.white), const SizedBox(width: 6), Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13.5))]),
      );

  Widget _qCard(int i, Map<String, dynamic> q) {
    final theory = q['type'] == 'theory';
    final options = (q['options'] as List?) ?? [];
    final correct = _toInt(q['correct']) ?? 0;
    final accent = theory ? _C.theory : _C.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: accent.withOpacity(0.2), width: 1.4), boxShadow: _soft(accent, 0.09)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), gradient: theory ? const LinearGradient(colors: [Color(0xFFFB923C), Color(0xFFEA580C)]) : _C.ctaGradient),
            child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 19)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(theory ? 'Theory · ${q['marks']} marks' : 'Multiple choice', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5, color: Color.lerp(accent, Colors.black, 0.2)))),
        ]),
        const SizedBox(height: 14),
        Text('${q['text']}', style: const TextStyle(fontSize: 17, height: 1.45, color: _C.text, fontWeight: FontWeight.w600)),
        if (q['image_url'] != null) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _zoom('${q['image_url']}'),
            child: Container(
              decoration: BoxDecoration(color: _C.field, borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.border)),
              padding: const EdgeInsets.all(6),
              child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network('${q['image_url']}', height: 150, width: double.infinity, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox(height: 70, child: Center(child: Icon(Icons.broken_image_rounded))))),
            ),
          ),
        ],
        if (!theory) ...[
          const SizedBox(height: 14),
          for (int k = 0; k < options.length; k++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: correct == k + 1 ? _C.success.withOpacity(0.11) : _C.field, borderRadius: BorderRadius.circular(18), border: Border.all(color: correct == k + 1 ? _C.success : _C.border, width: correct == k + 1 ? 2 : 1.3)),
              child: Row(children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: correct == k + 1 ? _C.goGradient : null, color: correct == k + 1 ? null : Colors.white, border: correct == k + 1 ? null : Border.all(color: _C.border, width: 1.6)),
                  child: correct == k + 1 ? const Icon(Icons.check_rounded, color: Colors.white, size: 21) : Text('ABCD'[k], style: const TextStyle(fontWeight: FontWeight.w900, color: _C.primary)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('${options[k]}', style: TextStyle(fontSize: 16, fontWeight: correct == k + 1 ? FontWeight.w900 : FontWeight.w600, color: correct == k + 1 ? const Color(0xFF047857) : _C.text))),
              ]),
            ),
        ],
      ]),
    );
  }
}
