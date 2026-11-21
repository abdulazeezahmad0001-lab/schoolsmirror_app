import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// ============================================================================
//  MANAGE USERS  –  add Student / Teacher / Subadmin + users table (one page)
//  Design mirrors users.php (gradient stat cards, pill tabs, rounded forms,
//  gradient table header, role/status badges, numbered pagination).
//  Backend: https://schoolsmirror.com/flutter_users.php
// ============================================================================

// Your host redirects "*.php" to the extensionless URL (that's why your old endpoints were
// called without .php) and a redirect turns POST into GET. So the extensionless URL is tried
// first, and the app switches to the other form automatically if one of them fails.
const List<String> _kApiUrls = [
  'https://schoolsmirror.com/flutter_users',
  'https://schoolsmirror.com/flutter_users.php',
];
int _apiIdx = 0;
String get _kApi => _kApiUrls[_apiIdx];

Future<Map<String, dynamic>> _withFallback(Future<Map<String, dynamic>> Function() call) async {
  Object? lastErr;
  for (var i = 0; i < _kApiUrls.length; i++) {
    try {
      final d = await call();
      final msg = '${d['message'] ?? ''}';
      if (d['success'] != true &&
          msg.startsWith('The server received this request as') &&
          _apiIdx < _kApiUrls.length - 1) {
        _apiIdx++;
        continue;
      }
      return d;
    } catch (e) {
      lastErr = e;
      final isHttpErr = e.toString().contains('Server error (HTTP');
      if (isHttpErr && _apiIdx < _kApiUrls.length - 1) {
        _apiIdx++;
        continue;
      }
      rethrow;
    }
  }
  throw lastErr ?? Exception('Request failed');
}

// ---- users.php palette ----
const Color _kP1 = Color(0xFF667eea);
const Color _kP2 = Color(0xFF764ba2);
const LinearGradient _kGrad = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [_kP1, _kP2],
);
const Color _kBorder = Color(0xFFe2e8f0);
const Color _kText = Color(0xFF1f2937);
const Color _kMuted = Color(0xFF64748b);
const Color _kRed = Color(0xFFef4444);
const Color _kGreen = Color(0xFF10b981);

const TextStyle _kFieldStyle = TextStyle(fontSize: 14, color: _kText);

/// The app theme is dark, which made text/dropdown items white-on-white.
/// This page (and its dialogs) always use a light theme so everything is readable.
ThemeData _lightTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFf5f7fa),
    canvasColor: Colors.white,
    cardColor: Colors.white,
    colorScheme: base.colorScheme.copyWith(
      primary: _kP1,
      surface: Colors.white,
      onSurface: _kText,
    ),
    textTheme: base.textTheme.apply(bodyColor: _kText, displayColor: _kText),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: _kP1),
  );
}

List<BoxShadow> get _kShadow => [
      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 30, offset: const Offset(0, 10)),
    ];

// ============================================================================
//  Shared helpers
// ============================================================================

class _Picked {
  final String name;
  final Uint8List bytes;
  const _Picked(this.name, this.bytes);
}

Future<String?> _resolveToken(String? given) async {
  if (given != null && given.trim().isNotEmpty) return given.trim();
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

String _friendly(Object e) {
  final s = e.toString();
  if (e is TimeoutException) return 'Request timed out. Please try again.';
  if (e is http.ClientException || s.contains('Failed to fetch') || s.contains('SocketException')) {
    return 'Cannot reach the server. Check your internet connection and make sure '
        'flutter_users.php is uploaded to schoolsmirror.com.';
  }
  return s.replaceFirst('Exception: ', '');
}

Map<String, dynamic> _decode(http.Response res) {
  final body = res.body;
  try {
    final i = body.indexOf('{');
    final d = jsonDecode(i > 0 ? body.substring(i) : body);
    if (d is Map<String, dynamic>) return d;
  } catch (_) {}
  final snippet = body.length > 160 ? body.substring(0, 160) : body;
  throw Exception('Server error (HTTP ${res.statusCode}): ${snippet.trim()}');
}

Future<Map<String, dynamic>> _apiGet(String token, Map<String, String> query) =>
    _withFallback(() => _apiGetOnce(token, query));

Future<Map<String, dynamic>> _apiPost(
  String token,
  Map<String, String> fields, {
  Uint8List? bytes,
  String? filename,
}) =>
    _withFallback(() => _apiPostOnce(token, fields, bytes: bytes, filename: filename));

Future<Map<String, dynamic>> _apiGetOnce(String token, Map<String, String> query) async {
  final uri = Uri.parse(_kApi).replace(queryParameters: {'token': token, ...query});
  final res = await http.get(uri).timeout(const Duration(seconds: 25));
  return _decode(res);
}

Future<Map<String, dynamic>> _apiPostOnce(
  String token,
  Map<String, String> fields, {
  Uint8List? bytes,
  String? filename,
}) async {
  // token + action are ALSO put in the URL so they survive redirects / proxies
  // that drop the request body (this was the cause of "Missing token").
  final all = {'token': token, ...fields};
  // Everything except passwords is ALSO placed in the URL, so the request still
  // works when a server/redirect drops the POST body ("Invalid user_id" / "Missing token").
  const secret = {'password', 'new_password'};
  final uri = Uri.parse(_kApi).replace(queryParameters: {
    for (final e in all.entries)
      if (!secret.contains(e.key)) e.key: e.value,
  });

  if (bytes == null) {
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
          body: all,
        )
        .timeout(const Duration(seconds: 30));
    return _decode(res);
  }

  final req = http.MultipartRequest('POST', uri);
  req.fields.addAll(all);
  final name = (filename == null || filename.isEmpty) ? 'photo.jpg' : filename;
  final isPng = name.toLowerCase().endsWith('.png');
  req.files.add(http.MultipartFile.fromBytes(
    'image',
    bytes,
    filename: name,
    contentType: MediaType('image', isPng ? 'png' : 'jpeg'),
  ));
  final streamed = await req.send().timeout(const Duration(seconds: 60));
  final res = await http.Response.fromStream(streamed);
  return _decode(res);
}

int _int(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

void _toast(BuildContext context, String msg, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? _kRed : _kGreen,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<_Picked?> _pickImage(BuildContext context) async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 80,
    maxWidth: 1200,
  );
  if (file == null) return null;
  final lower = file.name.toLowerCase();
  final mime = (file.mimeType ?? '').toLowerCase();
  final hasExt = lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png');
  final mimeOk = mime == 'image/jpeg' || mime == 'image/png';
  if (!hasExt && !mimeOk) {
    if (context.mounted) _toast(context, 'Only PNG, JPG and JPEG images are allowed', error: true);
    return null;
  }
  final bytes = await file.readAsBytes();
  if (bytes.length > 2 * 1024 * 1024) {
    if (context.mounted) {
      _toast(context, 'Image must be less than 2MB (yours ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB)', error: true);
    }
    return null;
  }
  var name = file.name;
  if (!hasExt) name = mime == 'image/png' ? 'photo.png' : 'photo.jpg';
  return _Picked(name, bytes);
}

// ---- form look (users.php .form-control) ----
InputDecoration _dec({String? hint, Widget? suffix, bool? ok}) {
  final Color idle = ok == true ? _kGreen : (ok == false ? _kRed : _kBorder);
  final Color focus = ok == true ? _kGreen : (ok == false ? _kRed : _kP1);
  OutlineInputBorder b(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: c, width: 2),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF9ca3af), fontSize: 14),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFFfafafa),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: b(idle),
    focusedBorder: b(focus),
    errorBorder: b(_kRed),
    focusedErrorBorder: b(_kRed),
  );
}

Widget _labeled(String label, Widget field, {bool required = false, String? message, bool? ok}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF333333)),
              children: [
                TextSpan(text: label),
                if (required) const TextSpan(text: ' *', style: TextStyle(color: _kRed)),
              ],
            ),
          ),
        ),
        field,
        if (message != null && message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: ok == true
                    ? _kGreen
                    : ok == false
                        ? _kRed
                        : (message.startsWith('Checking') ? _kMuted : const Color(0xFFd97706)),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Two columns on wide layouts, stacked on phones (users.php .form-row)
Widget _twoCol(List<Widget> kids, {double breakpoint = 560}) {
  return LayoutBuilder(builder: (context, c) {
    if (c.maxWidth >= breakpoint && kids.length > 1) {
      final children = <Widget>[];
      for (var i = 0; i < kids.length; i++) {
        if (i > 0) children.add(const SizedBox(width: 20));
        children.add(Expanded(child: kids[i]));
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: kids);
  });
}

Widget _dropdown<T>({
  required T? value,
  required List<DropdownMenuItem<T>> items,
  required ValueChanged<T?> onChanged,
}) {
  return DropdownButtonFormField<T>(
    value: value,
    items: items,
    onChanged: onChanged,
    isExpanded: true,
    decoration: _dec(),
    style: _kFieldStyle,
    dropdownColor: Colors.white,
    menuMaxHeight: 320,
    icon: const Icon(Icons.keyboard_arrow_down, color: _kMuted),
  );
}

class _GradButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  const _GradButton({required this.label, this.icon, this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: Container(
        decoration: BoxDecoration(
          gradient: _kGrad,
          borderRadius: BorderRadius.circular(10),
          boxShadow: enabled
              ? [BoxShadow(color: _kP1.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 4))]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  else if (icon != null)
                    Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ImageField extends StatelessWidget {
  final _Picked? picked;
  final String existingUrl;
  final VoidCallback onPick;
  final VoidCallback onRemove;
  const _ImageField({this.picked, this.existingUrl = '', required this.onPick, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    Widget? preview;
    if (picked != null) {
      preview = Image.memory(picked!.bytes, width: 90, height: 90, fit: BoxFit.cover);
    } else if (existingUrl.isNotEmpty) {
      preview = Image.network(
        existingUrl,
        width: 90,
        height: 90,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onPick,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFfafafa),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kBorder, width: 2),
            ),
            child: Row(
              children: [
                const Icon(Icons.upload_file, size: 18, color: _kMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    picked?.name ?? 'Choose image…',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: picked == null ? const Color(0xFF9ca3af) : _kText),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (preview != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFf8fafc),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(8), child: preview),
                  const SizedBox(width: 12),
                  if (picked != null)
                    TextButton(
                      onPressed: onRemove,
                      child: const Text('Remove Image', style: TextStyle(color: _kRed, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
//  SCREEN
// ============================================================================

class FlutterUsersScreen extends StatefulWidget {
  final String? token;
  final String initialRole; // student | teacher | subadmin
  const FlutterUsersScreen({super.key, this.token, this.initialRole = 'student'});

  @override
  State<FlutterUsersScreen> createState() => _FlutterUsersScreenState();
}

class _FlutterUsersScreenState extends State<FlutterUsersScreen> {
  final _scroll = ScrollController();
  final _listKey = GlobalKey();
  final _formKey = GlobalKey<FormState>();

  // ---- add form ----
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _password = TextEditingController();
  final _admission = TextEditingController();
  final _phone = TextEditingController();
  final _parentName = TextEditingController();
  final _parentPhone = TextEditingController();
  String _addRole = 'student';
  String _gender = 'Male';
  int? _classId;
  int? _departmentId;
  bool _obscure = true;
  bool _saving = false;
  _Picked? _picked;
  String? _idMsg;
  bool? _idOk;
  String? _admMsg;
  bool? _admOk;
  Timer? _idTimer;
  Timer? _admTimer;

  // ---- list ----
  final _searchCtrl = TextEditingController();
  String _search = '';
  String _roleFilter = '';
  bool _loading = true;
  String? _error;
  List<dynamic> _users = [];
  List<dynamic> _classes = [];
  List<dynamic> _departments = [];
  Map<String, dynamic> _stats = {};
  int _page = 1;
  int _limit = 10;
  int _total = 0;
  int _totalPages = 1;
  int _from = 0;
  int _to = 0;

  static const _tabs = [
    ('student', 'Add Student', Icons.person_add_alt_1_outlined),
    ('teacher', 'Add Teacher', Icons.star_border_rounded),
    ('subadmin', 'Add Subadmin', Icons.admin_panel_settings_outlined),
  ];

  @override
  void initState() {
    super.initState();
    if (['student', 'teacher', 'subadmin'].contains(widget.initialRole)) {
      _addRole = widget.initialRole;
    }
    _load();
  }

  @override
  void dispose() {
    _idTimer?.cancel();
    _admTimer?.cancel();
    _scroll.dispose();
    _name.dispose();
    _id.dispose();
    _password.dispose();
    _admission.dispose();
    _phone.dispose();
    _parentName.dispose();
    _parentPhone.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  //  Data
  // --------------------------------------------------------------------------

  Future<void> _load({int page = 1, bool scrollToList = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _resolveToken(widget.token);
      if (token == null) throw Exception('Session expired. Please log in again.');
      final d = await _apiGet(token, {
        'action': 'list',
        'page': '$page',
        'limit': '10',
        'search': _search,
        'role_filter': _roleFilter,
      });
      if (d['success'] != true) throw Exception(d['message'] ?? 'Failed to load users');
      final data = (d['data'] as Map?) ?? {};
      if (!mounted) return;
      setState(() {
        _users = (data['users'] as List?) ?? [];
        _classes = (data['classes'] as List?) ?? [];
        _departments = (data['departments'] as List?) ?? [];
        _stats = Map<String, dynamic>.from((data['stats'] as Map?) ?? {});
        _page = _int(data['page']) == 0 ? 1 : _int(data['page']);
        _limit = _int(data['limit']) == 0 ? 10 : _int(data['limit']);
        _total = _int(data['total']);
        _totalPages = math.max(1, _int(data['total_pages']));
        _from = _int(data['from']);
        _to = _int(data['to']);
        _loading = false;
      });
      if (scrollToList) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = _listKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendly(e);
        _loading = false;
      });
    }
  }

  void _applyFilters() {
    _search = _searchCtrl.text.trim();
    _load(page: 1);
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _search = '';
    _roleFilter = '';
    _load(page: 1);
  }

  // --------------------------------------------------------------------------
  //  Live duplicate checks
  // --------------------------------------------------------------------------

  void _onIdChanged(String v) {
    _idTimer?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _idMsg = null;
        _idOk = null;
      });
      return;
    }
    setState(() {
      _idMsg = 'Checking…';
      _idOk = null;
    });
    _idTimer = Timer(const Duration(milliseconds: 350), () => _check('idnumber', v.trim()));
  }

  void _onAdmissionChanged(String v) {
    _admTimer?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _admMsg = null;
        _admOk = null;
      });
      return;
    }
    setState(() {
      _admMsg = 'Checking…';
      _admOk = null;
    });
    _admTimer = Timer(const Duration(milliseconds: 350), () => _check('admission_number', v.trim()));
  }

  Future<void> _check(String field, String value) async {
    String msg;
    bool? ok;
    try {
      final token = await _resolveToken(widget.token);
      if (token == null) throw Exception('Session expired. Please log in again.');
      final d = await _apiGet(token, {'action': 'check_field', 'field': field, 'value': value});
      if (d['success'] != true) throw Exception(d['message'] ?? 'Check failed');
      final data = (d['data'] as Map?) ?? {};
      final exists = data['exists'] == true;
      msg = '${data['message'] ?? ''}';
      ok = !exists;
    } catch (e) {
      msg = '⚠ Could not verify: ${_friendly(e)}';
      ok = null;
    }
    if (!mounted) return;
    final current = field == 'idnumber' ? _id.text.trim() : _admission.text.trim();
    if (current != value) return; // user kept typing
    setState(() {
      if (field == 'idnumber') {
        _idMsg = msg;
        _idOk = ok;
      } else {
        _admMsg = msg;
        _admOk = ok;
      }
    });
  }

  // --------------------------------------------------------------------------
  //  Add / delete / edit
  // --------------------------------------------------------------------------

  void _clearForm() {
    _name.clear();
    _id.clear();
    _password.clear();
    _admission.clear();
    _phone.clear();
    _parentName.clear();
    _parentPhone.clear();
    _formKey.currentState?.reset();
    setState(() {
      _gender = 'Male';
      _classId = null;
      _departmentId = null;
      _obscure = true;
      _picked = null;
      _idMsg = null;
      _idOk = null;
      _admMsg = null;
      _admOk = null;
    });
  }

  void _switchRole(String role) {
    if (role == _addRole) return;
    _clearForm();
    setState(() => _addRole = role);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_addRole == 'student' && (_classId == null || _classId! <= 0)) {
      _toast(context, 'Please select a class', error: true);
      return;
    }
    if (_idOk == false || (_addRole == 'student' && _admOk == false)) {
      _toast(context, 'Please fix the highlighted fields', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final token = await _resolveToken(widget.token);
      if (token == null) throw Exception('Session expired. Please log in again.');
      final isStudent = _addRole == 'student';
      final d = await _apiPost(
        token,
        {
          'action': 'add',
          'role': _addRole,
          'fullname': _name.text.trim(),
          'idnumber': _id.text.trim(),
          'gender': _gender,
          'password': _password.text,
          'class_id': '${isStudent ? (_classId ?? 0) : 0}',
          'department_id': '${isStudent ? 0 : (_departmentId ?? 0)}',
          'admission_number': isStudent ? _admission.text.trim() : '',
          'phone': _phone.text.trim(),
          'parent_name': isStudent ? _parentName.text.trim() : '',
          'parent_phone': isStudent ? _parentPhone.text.trim() : '',
        },
        bytes: _picked?.bytes,
        filename: _picked?.name,
      );
      if (d['success'] != true) throw Exception(d['message'] ?? 'Failed to add user');
      if (!mounted) return;
      _toast(context, '${d['message'] ?? 'User added successfully!'}');
      _clearForm();
      await _load(page: 1);
    } catch (e) {
      if (mounted) _toast(context, _friendly(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Map u) async {
    final name = '${u['fullname']}';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: _lightTheme(),
        child: AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete user?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete $name? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRed,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
      ),
    );
    if (confirm != true) return;
    try {
      final token = await _resolveToken(widget.token);
      if (token == null) throw Exception('Session expired. Please log in again.');
      final d = await _apiPost(token, {'action': 'delete', 'user_id': '${u['user_id']}'});
      if (d['success'] != true) throw Exception(d['message'] ?? 'Failed to delete');
      if (!mounted) return;
      _toast(context, '${d['message'] ?? 'User deleted successfully!'}');
      await _load(page: _page);
    } catch (e) {
      if (mounted) _toast(context, _friendly(e), error: true);
    }
  }

  Future<void> _edit(Map u) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Theme(
        data: _lightTheme(),
        child: _EditUserDialog(
          user: u,
          classes: _classes,
          departments: _departments,
          token: widget.token,
        ),
      ),
    );
    if (saved == true) {
      if (mounted) _toast(context, 'User updated successfully!');
      await _load(page: _page);
    }
  }

  // --------------------------------------------------------------------------
  //  BUILD
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _lightTheme(),
      child: Scaffold(
      backgroundColor: const Color(0xFFf5f7fa),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _kText,
        elevation: 0,
        title: const Text('Manage Users', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _load(page: _page),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFf5f7fa), Color(0xFFe4e7eb)],
          ),
        ),
        child: RefreshIndicator(
          onRefresh: () => _load(page: _page),
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStats(),
                    const SizedBox(height: 24),
                    _buildAddCard(),
                    const SizedBox(height: 24),
                    _buildListCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  // ---------------------------- stats ---------------------------------------

  Widget _buildStats() {
    final cards = [
      ('Total Users', _int(_stats['total']), Icons.groups_outlined, const [Color(0xFF667eea), Color(0xFF764ba2)]),
      ('Students', _int(_stats['student']), Icons.person_outline, const [Color(0xFF11998e), Color(0xFF38ef7d)]),
      ('Teachers', _int(_stats['teacher']), Icons.star_border_rounded, const [Color(0xFFf093fb), Color(0xFFf5576c)]),
      ('Active', _int(_stats['active']), Icons.check_circle_outline, const [Color(0xFF4facfe), Color(0xFF00f2fe)]),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 16.0;
      final cols = c.maxWidth >= 900 ? 4 : 2;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final s in cards)
            SizedBox(
              width: w,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: s.$4,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _kShadow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$1, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('${s.$2}',
                              style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(s.$3, color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    });
  }

  // ---------------------------- add card ------------------------------------

  Widget _buildAddCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: _kShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // pill tabs
          Container(
            padding: const EdgeInsets.only(bottom: 15),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFf0f0f0), width: 2))),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final t in _tabs) _tabPill(t.$1, t.$2, t.$3)],
            ),
          ),
          const SizedBox(height: 22),
          Form(key: _formKey, child: _buildForm()),
        ],
      ),
    );
  }

  Widget _tabPill(String role, String label, IconData icon) {
    final active = _addRole == role;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _switchRole(role),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          gradient: active ? _kGrad : null,
          color: active ? null : const Color(0xFFf8f9fa),
          borderRadius: BorderRadius.circular(10),
          boxShadow: active ? [BoxShadow(color: _kP1.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 4))] : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: active ? Colors.white : const Color(0xFF666666)),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: active ? Colors.white : const Color(0xFF666666))),
          ],
        ),
      ),
    );
  }

  String? _req(String? v, String msg) => (v == null || v.trim().isEmpty) ? msg : null;

  Widget _buildForm() {
    final isStudent = _addRole == 'student';
    final roleLabel = _addRole == 'subadmin' ? 'Subadmin' : (isStudent ? 'Student' : 'Teacher');

    final fullName = _labeled(
      'Full Name',
      TextFormField(style: _kFieldStyle, 
        controller: _name,
        textCapitalization: TextCapitalization.words,
        decoration: _dec(),
        validator: (v) => _req(v, 'Full name is required'),
      ),
      required: true,
    );

    final idNumber = _labeled(
      'ID Number',
      TextFormField(style: _kFieldStyle, 
        controller: _id,
        decoration: _dec(ok: _idOk),
        onChanged: _onIdChanged,
        validator: (v) => _req(v, 'ID number is required'),
      ),
      required: true,
      message: _idMsg,
      ok: _idOk,
    );

    final gender = _labeled(
      'Gender',
      _dropdown<String>(
        value: _gender,
        items: const [
          DropdownMenuItem(value: 'Male', child: Text('Male')),
          DropdownMenuItem(value: 'Female', child: Text('Female')),
        ],
        onChanged: (v) => setState(() => _gender = v ?? 'Male'),
      ),
      required: true,
    );

    final password = _labeled(
      'Password',
      TextFormField(style: _kFieldStyle, 
        controller: _password,
        obscureText: _obscure,
        decoration: _dec(
          suffix: IconButton(
            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: _kMuted),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        validator: (v) => (v == null || v.length < 6) ? 'Min 6 characters' : null,
      ),
      required: true,
    );

    final phone = _labeled(
      'Phone',
      TextFormField(style: _kFieldStyle, controller: _phone, keyboardType: TextInputType.phone, decoration: _dec()),
    );

    final image = _labeled(
      'Profile Image (PNG, JPG, max 2MB)',
      _ImageField(
        picked: _picked,
        onPick: () async {
          final p = await _pickImage(context);
          if (p != null && mounted) setState(() => _picked = p);
        },
        onRemove: () => setState(() => _picked = null),
      ),
    );

    final rows = <Widget>[
      _twoCol([fullName, idNumber]),
      _twoCol([gender, password]),
    ];

    if (isStudent) {
      rows.add(_twoCol([
        _labeled(
          'Class',
          _dropdown<int>(
            value: _classes.any((c) => _int(c['class_id']) == _classId) ? _classId : null,
            items: [
              for (final c in _classes)
                DropdownMenuItem(value: _int(c['class_id']), child: Text('${c['class_name']}')),
            ],
            onChanged: (v) => setState(() => _classId = v),
          ),
          required: true,
        ),
        _labeled(
          'Admission Number',
          TextFormField(style: _kFieldStyle, controller: _admission, decoration: _dec(ok: _admOk), onChanged: _onAdmissionChanged),
          message: _admMsg,
          ok: _admOk,
        ),
      ]));
      rows.add(_twoCol([
        phone,
        _labeled('Parent/Guardian Name', TextFormField(style: _kFieldStyle, controller: _parentName, decoration: _dec())),
      ]));
      rows.add(_twoCol([
        _labeled(
            'Parent/Guardian Phone',
            TextFormField(style: _kFieldStyle, controller: _parentPhone, keyboardType: TextInputType.phone, decoration: _dec())),
        image,
      ]));
    } else if (_addRole == 'teacher') {
      rows.add(_twoCol([
        _labeled(
          'Department',
          _dropdown<int>(
            value: _departments.any((d) => _int(d['id']) == _departmentId) ? _departmentId : null,
            items: [
              for (final d in _departments)
                DropdownMenuItem(value: _int(d['id']), child: Text('${d['department_name']}')),
            ],
            onChanged: (v) => setState(() => _departmentId = v),
          ),
        ),
        phone,
      ]));
      rows.add(image);
    } else {
      rows.add(phone);
      rows.add(image);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...rows,
        _GradButton(
          label: 'Add $roleLabel',
          icon: _addRole == 'subadmin' ? Icons.admin_panel_settings_outlined : Icons.person_add_alt_1_outlined,
          loading: _saving,
          onTap: _submit,
        ),
      ],
    );
  }

  // ---------------------------- list card -----------------------------------

  Widget _buildListCard() {
    final hasFilter = _search.isNotEmpty || _roleFilter.isNotEmpty;
    return Container(
      key: _listKey,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: _kShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 14,
            spacing: 14,
            children: [
              const Text('All Users', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1f2937))),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: TextField(style: _kFieldStyle, 
                      controller: _searchCtrl,
                      onSubmitted: (_) => _applyFilters(),
                      decoration: _dec(hint: 'Search by name or ID...'),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: _dropdown<String>(
                      value: _roleFilter,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Roles')),
                        DropdownMenuItem(value: 'student', child: Text('Student')),
                        DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
                        DropdownMenuItem(value: 'subadmin', child: Text('Subadmin')),
                      ],
                      onChanged: (v) {
                        _roleFilter = v ?? '';
                        _search = _searchCtrl.text.trim();
                        _load(page: 1);
                      },
                    ),
                  ),
                  _GradButton(label: 'Search', icon: Icons.search, onTap: _applyFilters),
                  if (hasFilter)
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _clearFilters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: const Color(0xFFf3f4f6), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.close, size: 16, color: Color(0xFF374151)),
                            SizedBox(width: 6),
                            Text('Clear', style: TextStyle(color: Color(0xFF374151))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildListBody(hasFilter),
        ],
      ),
    );
  }

  Widget _buildListBody(bool hasFilter) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(child: CircularProgressIndicator(color: _kP1)),
      );
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFFfef2f2), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: _kRed, size: 40),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _kRed)),
            const SizedBox(height: 14),
            _GradButton(label: 'Retry', icon: Icons.refresh, onTap: () => _load(page: _page)),
          ],
        ),
      );
    }
    if (_users.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        decoration: BoxDecoration(color: const Color(0xFFf8fafc), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            const Icon(Icons.person_search_outlined, size: 60, color: Color(0xFFcbd5e1)),
            const SizedBox(height: 15),
            const Text('No Users Found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            Text(
              hasFilter ? 'No users match your search criteria.' : 'Start by adding your first user using the forms above.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6b7280)),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, c) => _buildTable(c.maxWidth)),
        if (_totalPages > 1) ...[const SizedBox(height: 24), _buildPagination()],
      ],
    );
  }

  // ---------------------------- table ---------------------------------------

  Widget _cell(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: child);

  Widget _th(String t) => _cell(Text(
        t.toUpperCase(),
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: _kMuted),
      ));

  Widget _buildTable(double avail) {
    final width = math.max(avail, 900.0);
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFFf8fafc), Color(0xFFf1f5f9)]),
          border: Border(bottom: BorderSide(color: _kBorder, width: 2)),
        ),
        children: [
          _th('#'),
          _th('User'),
          _th('ID Number'),
          _th('Role'),
          _th('Class/Dept'),
          _th('Status'),
          _th('Actions'),
        ],
      ),
    ];

    for (var i = 0; i < _users.length; i++) {
      final u = Map<String, dynamic>.from(_users[i] as Map);
      final role = '${u['role'] ?? ''}'.toLowerCase();
      final status = '${u['status'] ?? 'Active'}';
      final dept = '${u['department_name'] ?? 'N/A'}';
      final classDept = role == 'student'
          ? '${u['class_name'] ?? 'N/A'}'
          : (dept != 'N/A' && dept.isNotEmpty ? dept : '—');
      final adm = '${u['admission_number'] ?? ''}'.trim();

      rows.add(TableRow(
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFf1f5f9)))),
        children: [
          _cell(Text('${(_page - 1) * _limit + i + 1}', style: const TextStyle(color: _kText))),
          _cell(Row(
            children: [
              _avatar('${u['fullname']}', '${u['image_url'] ?? ''}'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${u['fullname']}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF111827))),
                    Text(adm.isEmpty ? 'N/A' : adm,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF6b7280))),
                  ],
                ),
              ),
            ],
          )),
          _cell(Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: const Color(0xFFf3f4f6), borderRadius: BorderRadius.circular(4)),
              child: Text('${u['idnumber']}',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: _kText)),
            ),
          )),
          _cell(Align(alignment: Alignment.centerLeft, child: _roleBadge(role))),
          _cell(Text(classDept,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: role == 'student' ? _kText : const Color(0xFF6b7280)))),
          _cell(Align(alignment: Alignment.centerLeft, child: _statusBadge(status))),
          _cell(Row(
            children: [
              InkWell(
                onTap: () => _edit(u),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.edit_outlined, size: 20, color: Color(0xFF2563eb)),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _delete(u),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, size: 20, color: Color(0xFFdc2626)),
                ),
              ),
            ],
          )),
        ],
      ));
    }

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: _kShadow),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: width,
          child: Table(
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            columnWidths: const {
              0: FixedColumnWidth(56),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(1.6),
              3: FixedColumnWidth(130),
              4: FlexColumnWidth(1.6),
              5: FixedColumnWidth(110),
              6: FixedColumnWidth(96),
            },
            children: rows,
          ),
        ),
      ),
    );
  }

  Widget _avatar(String name, String url) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((p) => p[0].toUpperCase()).join();
    final fallback = Container(
      color: _kP1,
      alignment: Alignment.center,
      child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
    );
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _kBorder, width: 2)),
      child: ClipOval(
        child: url.isEmpty
            ? fallback
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback),
      ),
    );
  }

  Widget _roleBadge(String role) {
    Color bg, fg;
    switch (role) {
      case 'teacher':
        bg = const Color(0xFFd1fae5);
        fg = const Color(0xFF065f46);
        break;
      case 'subadmin':
        bg = const Color(0xFFede9fe);
        fg = const Color(0xFF5b21b6);
        break;
      default:
        bg = const Color(0xFFdbeafe);
        fg = const Color(0xFF1d4ed8);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(role.toUpperCase(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  Widget _statusBadge(String status) {
    Color bg, fg;
    switch (status.toLowerCase()) {
      case 'pending':
        bg = const Color(0xFFfef3c7);
        fg = const Color(0xFF92400e);
        break;
      case 'archived':
        bg = const Color(0xFFfee2e2);
        fg = const Color(0xFF991b1b);
        break;
      default:
        bg = const Color(0xFFd1fae5);
        fg = const Color(0xFF065f46);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }

  // ---------------------------- pagination ----------------------------------

  Widget _pgBtn({String? label, IconData? icon, VoidCallback? onTap, bool active = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: active ? _kGrad : null,
          color: active ? null : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? _kP1 : _kBorder, width: 2),
        ),
        child: label != null
            ? Text(label,
                style: TextStyle(fontWeight: FontWeight.w500, color: active ? Colors.white : const Color(0xFF4a5568)))
            : Icon(icon, size: 18, color: const Color(0xFF4a5568)),
      ),
    );
  }

  Widget _buildPagination() {
    final start = math.max(1, _page - 2);
    final end = math.min(_totalPages, _page + 2);
    void go(int p) => _load(page: p, scrollToList: true);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 14,
      spacing: 14,
      children: [
        Text('Showing $_from to $_to of $_total entries',
            style: const TextStyle(fontSize: 14, color: Color(0xFF4b5563))),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_page > 1) ...[
              _pgBtn(icon: Icons.keyboard_double_arrow_left, onTap: () => go(1)),
              _pgBtn(icon: Icons.chevron_left, onTap: () => go(_page - 1)),
            ],
            for (var i = start; i <= end; i++) _pgBtn(label: '$i', active: i == _page, onTap: () => go(i)),
            if (_page < _totalPages) ...[
              _pgBtn(icon: Icons.chevron_right, onTap: () => go(_page + 1)),
              _pgBtn(icon: Icons.keyboard_double_arrow_right, onTap: () => go(_totalPages)),
            ],
          ],
        ),
      ],
    );
  }
}

// ============================================================================
//  EDIT DIALOG (users.php "Edit User" modal)
// ============================================================================

class _EditUserDialog extends StatefulWidget {
  final Map user;
  final List classes;
  final List departments;
  final String? token;
  const _EditUserDialog({
    required this.user,
    required this.classes,
    required this.departments,
    this.token,
  });

  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _id;
  late final TextEditingController _pw;
  late final TextEditingController _adm;
  late final TextEditingController _phone;
  late final TextEditingController _pn;
  late final TextEditingController _pp;
  late String _gender;
  late String _status;
  int? _classId;
  int? _deptId;
  bool _obscure = true;
  bool _saving = false;
  _Picked? _picked;
  String? _idMsg;
  bool? _idOk;
  String? _admMsg;
  bool? _admOk;
  Timer? _idTimer;
  Timer? _admTimer;

  String get _role => '${widget.user['role'] ?? 'student'}'.toLowerCase();

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _name = TextEditingController(text: '${u['fullname'] ?? ''}');
    _id = TextEditingController(text: '${u['idnumber'] ?? ''}');
    _pw = TextEditingController();
    _adm = TextEditingController(text: '${u['admission_number'] ?? ''}');
    _phone = TextEditingController(text: '${u['phone'] ?? ''}');
    _pn = TextEditingController(text: '${u['parent_name'] ?? ''}');
    _pp = TextEditingController(text: '${u['parent_phone'] ?? ''}');
    _gender = '${u['gender'] ?? ''}'.toLowerCase().startsWith('f') ? 'Female' : 'Male';
    final s = '${u['status'] ?? 'Active'}'.toLowerCase();
    _status = s == 'pending' ? 'Pending' : (s == 'archived' ? 'Archived' : 'Active');
    final cid = _int(u['class_id']);
    _classId = widget.classes.any((c) => _int(c['class_id']) == cid) ? cid : null;
    final did = _int(u['department_id']);
    _deptId = widget.departments.any((d) => _int(d['id']) == did) ? did : null;
  }

  @override
  void dispose() {
    _idTimer?.cancel();
    _admTimer?.cancel();
    _name.dispose();
    _id.dispose();
    _pw.dispose();
    _adm.dispose();
    _phone.dispose();
    _pn.dispose();
    _pp.dispose();
    super.dispose();
  }

  Future<void> _check(String field, String value) async {
    String msg;
    bool? ok;
    try {
      final token = await _resolveToken(widget.token);
      if (token == null) throw Exception('Session expired. Please log in again.');
      final d = await _apiGet(token, {
        'action': 'check_field',
        'field': field,
        'value': value,
        'exclude_id': '${widget.user['user_id']}',
      });
      if (d['success'] != true) throw Exception(d['message'] ?? 'Check failed');
      final data = (d['data'] as Map?) ?? {};
      final exists = data['exists'] == true;
      msg = '${data['message'] ?? ''}';
      ok = !exists;
    } catch (e) {
      msg = '⚠ Could not verify: ${_friendly(e)}';
      ok = null;
    }
    if (!mounted) return;
    final current = field == 'idnumber' ? _id.text.trim() : _adm.text.trim();
    if (current != value) return;
    setState(() {
      if (field == 'idnumber') {
        _idMsg = msg;
        _idOk = ok;
      } else {
        _admMsg = msg;
        _admOk = ok;
      }
    });
  }

  void _onId(String v) {
    _idTimer?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _idMsg = null;
        _idOk = null;
      });
      return;
    }
    setState(() {
      _idMsg = 'Checking…';
      _idOk = null;
    });
    _idTimer = Timer(const Duration(milliseconds: 350), () => _check('idnumber', v.trim()));
  }

  void _onAdm(String v) {
    _admTimer?.cancel();
    if (v.trim().isEmpty) {
      setState(() {
        _admMsg = null;
        _admOk = null;
      });
      return;
    }
    setState(() {
      _admMsg = 'Checking…';
      _admOk = null;
    });
    _admTimer = Timer(const Duration(milliseconds: 350), () => _check('admission_number', v.trim()));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_role == 'student' && (_classId == null || _classId! <= 0)) {
      _toast(context, 'Please select a class', error: true);
      return;
    }
    if (_idOk == false || _admOk == false) {
      _toast(context, 'Please fix the highlighted fields', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final token = await _resolveToken(widget.token);
      if (token == null) throw Exception('Session expired. Please log in again.');
      final isStudent = _role == 'student';
      final d = await _apiPost(
        token,
        {
          'action': 'update',
          'user_id': '${widget.user['user_id']}',
          'fullname': _name.text.trim(),
          'idnumber': _id.text.trim(),
          'gender': _gender,
          'class_id': '${isStudent ? (_classId ?? 0) : 0}',
          'department_id': '${isStudent ? 0 : (_deptId ?? 0)}',
          'phone': _phone.text.trim(),
          'parent_name': isStudent ? _pn.text.trim() : '',
          'parent_phone': isStudent ? _pp.text.trim() : '',
          'admission_number': isStudent ? _adm.text.trim() : '',
          'status': _status,
          'new_password': _pw.text,
        },
        bytes: _picked?.bytes,
        filename: _picked?.name,
      );
      if (d['success'] != true) throw Exception(d['message'] ?? 'Failed to update user');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _toast(context, _friendly(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isStudent = _role == 'student';
    final existingUrl = '${widget.user['image_url'] ?? ''}';

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(24, 18, 12, 14),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _kBorder))),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Edit User', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _kText)),
                  ),
                  IconButton(onPressed: _saving ? null : () => Navigator.pop(context, false), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _twoCol([
                        _labeled(
                          'Full Name',
                          TextFormField(style: _kFieldStyle, 
                            controller: _name,
                            decoration: _dec(),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
                          ),
                          required: true,
                        ),
                        _labeled(
                          'ID Number',
                          TextFormField(style: _kFieldStyle, 
                            controller: _id,
                            decoration: _dec(ok: _idOk),
                            onChanged: _onId,
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'ID number is required' : null,
                          ),
                          required: true,
                          message: _idMsg,
                          ok: _idOk,
                        ),
                      ]),
                      _twoCol([
                        _labeled(
                          'Gender',
                          _dropdown<String>(
                            value: _gender,
                            items: const [
                              DropdownMenuItem(value: 'Male', child: Text('Male')),
                              DropdownMenuItem(value: 'Female', child: Text('Female')),
                            ],
                            onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                          ),
                        ),
                        _labeled(
                          'New Password (optional)',
                          TextFormField(style: _kFieldStyle, 
                            controller: _pw,
                            obscureText: _obscure,
                            decoration: _dec(
                              hint: 'Min 6 characters to change',
                              suffix: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    size: 20, color: _kMuted),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) => (v != null && v.isNotEmpty && v.length < 6) ? 'Min 6 characters' : null,
                          ),
                        ),
                      ]),
                      if (isStudent)
                        _twoCol([
                          _labeled(
                            'Class',
                            _dropdown<int>(
                              value: _classId,
                              items: [
                                for (final c in widget.classes)
                                  DropdownMenuItem(value: _int(c['class_id']), child: Text('${c['class_name']}')),
                              ],
                              onChanged: (v) => setState(() => _classId = v),
                            ),
                            required: true,
                          ),
                          _labeled(
                            'Admission Number',
                            TextFormField(style: _kFieldStyle, controller: _adm, decoration: _dec(ok: _admOk), onChanged: _onAdm),
                            message: _admMsg,
                            ok: _admOk,
                          ),
                        ])
                      else
                        _twoCol([
                          _labeled(
                            'Department',
                            _dropdown<int>(
                              value: _deptId,
                              items: [
                                for (final d in widget.departments)
                                  DropdownMenuItem(value: _int(d['id']), child: Text('${d['department_name']}')),
                              ],
                              onChanged: (v) => setState(() => _deptId = v),
                            ),
                          ),
                          _labeled('Phone', TextFormField(style: _kFieldStyle, controller: _phone, keyboardType: TextInputType.phone, decoration: _dec())),
                        ]),
                      if (isStudent)
                        _twoCol([
                          _labeled('Phone', TextFormField(style: _kFieldStyle, controller: _phone, keyboardType: TextInputType.phone, decoration: _dec())),
                          _labeled('Parent/Guardian Name', TextFormField(style: _kFieldStyle, controller: _pn, decoration: _dec())),
                        ]),
                      if (isStudent)
                        _twoCol([
                          _labeled('Parent/Guardian Phone',
                              TextFormField(style: _kFieldStyle, controller: _pp, keyboardType: TextInputType.phone, decoration: _dec())),
                          _labeled(
                            'Status',
                            _dropdown<String>(
                              value: _status,
                              items: const [
                                DropdownMenuItem(value: 'Active', child: Text('Active')),
                                DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                                DropdownMenuItem(value: 'Archived', child: Text('Archived')),
                              ],
                              onChanged: (v) => setState(() => _status = v ?? 'Active'),
                            ),
                          ),
                        ])
                      else
                        _labeled(
                          'Status',
                          _dropdown<String>(
                            value: _status,
                            items: const [
                              DropdownMenuItem(value: 'Active', child: Text('Active')),
                              DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                              DropdownMenuItem(value: 'Archived', child: Text('Archived')),
                            ],
                            onChanged: (v) => setState(() => _status = v ?? 'Active'),
                          ),
                        ),
                      _labeled(
                        'Profile Image (PNG, JPG, max 2MB)',
                        _ImageField(
                          picked: _picked,
                          existingUrl: existingUrl,
                          onPick: () async {
                            final p = await _pickImage(context);
                            if (p != null && mounted) setState(() => _picked = p);
                          },
                          onRemove: () => setState(() => _picked = null),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: _kBorder))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 10),
                  _GradButton(label: 'Save Changes', icon: Icons.save_outlined, loading: _saving, onTap: _save),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
