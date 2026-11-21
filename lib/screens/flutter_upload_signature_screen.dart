// flutter_upload_signature_screen.dart
// Mirrors upload_signature.php 1:1: "Signature Management" header + role pill, "Manage Signatures" /
// "Add New Signature" tabs, signature cards (role badge, image, class -> current class, department,
// Edit / Delete), tap-to-enlarge, add / edit form (role, original + current class, department, image,
// 2MB JPG/PNG/GIF check), SweetAlert-style delete confirmation, top toast messages and the floating + button.
//
// pubspec.yaml needs:  http, shared_preferences, image_picker
//   iOS Info.plist: NSPhotoLibraryUsageDescription, NSCameraUsageDescription

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// extensionless address first (a redirect from "*.php" turns POST into GET and loses the form data)
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_upload_signature',
  'https://schoolsmirror.com/flutter_upload_signature.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

/// Same colour tokens as upload_signature.php
class _C {
  static const purple = Color(0xFF667EEA);
  static const purpleDark = Color(0xFF764BA2);
  static const violet = Color(0xFF8B5CF6);
  static const indigo = Color(0xFF6366F1);
  static const amber = Color(0xFFF59E0B);
  static const amberDark = Color(0xFFD97706);
  static const red = Color(0xFFEF4444);
  static const redDark = Color(0xFFDC2626);
  static const green = Color(0xFF10B981);
  static const border = Color(0xFFE2E8F0);
  static const slate = Color(0xFF64748B);
  static const light = Color(0xFFF8FAFC);
  static const text = Color(0xFF1F2937);
  static const label = Color(0xFF374151);

  static const primaryGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [purple, purpleDark]);
  static const dangerGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [red, redDark]);
}

// ───────────────────────────── API helper ─────────────────────────────
class _Api {
  static bool shouldRetry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' ||
            m == 'Signature image is required.' ||
            m.startsWith('The server received this request as') ||
            m.startsWith('Missing token'));
  }

  /// Every call is multipart so the same helper serves list / delete (no file) and upload / edit (file).
  /// token, action and the small fields are also put in the URL so they survive a redirect that drops the body.
  static Future<Map<String, dynamic>> call(String token, String action,
      {Map<String, String> fields = const {}, Uint8List? bytes, String? filename}) async {
    Map<String, dynamic> last = {'success': false, 'message': 'Network error. Check your connection.'};
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        final uri = Uri.parse(_apiUrl).replace(queryParameters: {'token': token, 'action': action, ...fields});
        final req = http.MultipartRequest('POST', uri)..fields.addAll({'token': token, 'action': action, ...fields});
        if (bytes != null) req.files.add(http.MultipartFile.fromBytes('signature', bytes, filename: filename ?? 'signature.jpg'));
        final res = await http.Response.fromStream(await req.send().timeout(const Duration(seconds: 90)));
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
String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
String? _idStr(dynamic v) {
  final s = '${v ?? ''}';
  return (s.isEmpty || s == 'null' || s == '0') ? null : s;
}

// ═════════════════════════════════════════════════════════════════════════════
class FlutterUploadSignatureScreen extends StatefulWidget {
  final String? token;
  const FlutterUploadSignatureScreen({super.key, this.token});

  @override
  State<FlutterUploadSignatureScreen> createState() => _FlutterUploadSignatureScreenState();
}

class _FlutterUploadSignatureScreenState extends State<FlutterUploadSignatureScreen> {
  String? _token;
  bool _loading = true;
  String _role = 'portaladmin';
  List<Map<String, dynamic>> _signatures = [];
  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _departments = [];

  int _tab = 0; // 0 = Manage Signatures, 1 = Add / Edit
  Map<String, dynamic>? _editing;

  // form
  String _formRole = 'teacher';
  String? _origClass, _currClass, _dept;
  Uint8List? _picked;
  String? _pickedName;
  bool _saving = false;

  // toast (top-end SweetAlert toast on the web page)
  String? _toastText;
  bool _toastOk = true;
  Timer? _toastTimer;

  bool get _isTeacher => _role == 'teacher';
  bool get _isEdit => _editing != null;

  /// same condition as the PHP form: class + department fields only for teacher signatures
  bool get _showClassFields => (_isTeacher && _formRole == 'teacher') || (!_isTeacher && _isEdit && _editing!['role'] == 'teacher');

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
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

  void _notify(String msg, {bool ok = true}) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() {
      _toastText = msg;
      _toastOk = ok;
    });
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastText = null);
    });
  }

  Future<void> _init() async {
    _token = await _getToken();
    if (_token != null) await _load();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _load() async {
    final r = await _Api.call(_token!, 'list');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = Map<String, dynamic>.from(r['data'] as Map);
      setState(() {
        _role = '${d['role'] ?? 'portaladmin'}';
        _signatures = _maps(d['signatures']);
        _classes = _maps(d['classes']);
        _departments = _maps(d['departments']);
      });
    } else {
      _notify('${r['message']}', ok: false);
    }
  }

  // ───────────────────────────── tabs / form state ─────────────────────────────
  void _resetForm() {
    _editing = null;
    _formRole = 'teacher';
    _origClass = _currClass = _dept = null;
    _picked = null;
    _pickedName = null;
  }

  void _openAdd() {
    setState(() {
      _resetForm();
      _tab = 1;
    });
  }

  void _openEdit(Map<String, dynamic> s) {
    setState(() {
      _resetForm();
      _editing = s;
      _formRole = '${s['role']}' == 'proprietor' ? 'proprietor' : 'teacher';
      _origClass = _idStr(s['original_class_id']);
      _currClass = _idStr(s['current_class_id']);
      _dept = _idStr(s['department_id']);
      _tab = 1;
    });
  }

  void _cancel() => setState(() {
        _resetForm();
        _tab = 0;
      });

  // ───────────────────────────── pick / save / delete ─────────────────────────────
  Future<void> _pick() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_library), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(c, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text('Take a photo'), onTap: () => Navigator.pop(c, ImageSource.camera)),
        ]),
      ),
    );
    if (src == null) return;
    try {
      final x = await ImagePicker().pickImage(source: src);
      if (x == null) return;
      final name = x.name.toLowerCase();
      final okType = name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.gif');
      if (!okType) {
        _notify('Invalid file type. Only JPG, PNG, GIF allowed.', ok: false);
        return;
      }
      final bytes = await x.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) {
        _notify('File too large. Max 2MB.', ok: false);
        return;
      }
      setState(() {
        _picked = bytes;
        _pickedName = x.name;
      });
    } catch (_) {
      _notify('Could not open the picker.', ok: false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_showClassFields && _origClass == null) {
      _notify('Please select the Original Class.', ok: false);
      return;
    }
    if (!_isEdit && _picked == null) {
      _notify('Please choose a signature image.', ok: false);
      return;
    }
    // role sent like the PHP form: teachers choose; admins always send "proprietor" (an edited teacher signature keeps its role)
    final role = _isTeacher ? _formRole : (_isEdit && _editing!['role'] == 'teacher' ? 'teacher' : 'proprietor');
    setState(() => _saving = true);
    final r = await _Api.call(
      _token!,
      _isEdit ? 'edit' : 'upload',
      fields: {
        'role': role,
        if (_isEdit) 'signature_id': '${_editing!['id']}',
        if (_showClassFields) ...{
          'original_class_id': _origClass ?? '',
          'current_class_id': _currClass ?? '',
          'department_id': _dept ?? '',
        },
      },
      bytes: _picked,
      filename: _pickedName,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _notify('${r['message']}', ok: r['success'] == true);
    if (r['success'] == true) {
      setState(() {
        _resetForm();
        _tab = 0;
      });
      _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.warning_amber_rounded, size: 56, color: _C.amber),
        title: const Text('Delete Signature?', textAlign: TextAlign.center),
        content: const Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('This action cannot be undone!', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text('The signature will be permanently deleted from the system.', style: TextStyle(fontSize: 13, color: Color(0xFF4B5563))),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(backgroundColor: _C.red, foregroundColor: Colors.white),
            child: const Text('Yes, delete it'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final r = await _Api.call(_token!, 'delete', fields: {'signature_id': '${s['id']}'});
    _notify('${r['message']}', ok: r['success'] == true);
    if (r['success'] == true) _load();
  }

  void _enlarge(Widget image) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(217),
      builder: (c) => GestureDetector(
        onTap: () => Navigator.pop(c),
        child: Center(child: InteractiveViewer(child: Padding(padding: const EdgeInsets.all(16), child: image))),
      ),
    );
  }

  // ───────────────────────────── build ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF5F7FA), Color(0xFFE4E7EB)])),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.primaryGradient)),
          title: const Text('Signature Management', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        floatingActionButton: _loading || _token == null || _tab == 1
            ? null
            : Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(gradient: _C.primaryGradient, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _C.purple.withAlpha(102), blurRadius: 30, offset: const Offset(0, 10))]),
                child: IconButton(onPressed: _openAdd, tooltip: 'Add New Signature', icon: const Icon(Icons.add, color: Colors.white, size: 28)),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _C.purple))
            : _token == null
                ? const Center(child: Text('Session expired. Please log out and log back in.'))
                : Stack(children: [
                    RefreshIndicator(
                      color: _C.purple,
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 90),
                        children: [_header(), const SizedBox(height: 16), _pageCard()],
                      ),
                    ),
                    if (_toastText != null) Positioned(top: 10, left: 14, right: 14, child: _toast()),
                  ]),
      ),
    );
  }

  Widget _toast() => Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: _toastOk ? _C.green : _C.red, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withAlpha(51), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Row(children: [
            Icon(_toastOk ? Icons.check_circle_outline : Icons.error_outline, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(child: Text(_toastText!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ]),
        ),
      );

  Widget _header() => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.draw, size: 30, color: Color(0xFF9333EA)),
              SizedBox(width: 10),
              Flexible(child: Text('Signature Management', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF111827)))),
            ]),
            const SizedBox(height: 6),
            const Text('Manage teacher & principal signatures', style: TextStyle(color: Color(0xFF4B5563), fontSize: 13)),
          ]),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.verified_user_outlined, size: 16, color: Color(0xFF3B82F6)),
            const SizedBox(width: 6),
            Text(_cap(_role), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ]);

  Widget _pageCard() => Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 30, offset: const Offset(0, 10))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _tabs(),
            Padding(padding: const EdgeInsets.all(18), child: _tab == 0 ? _manageTab() : _formTab()),
          ]),
        ),
      );

  Widget _tabs() => Container(
        decoration: const BoxDecoration(color: _C.light, border: Border(bottom: BorderSide(color: _C.border, width: 2))),
        child: Row(children: [
          _tabBtn('Manage Signatures', Icons.checklist, 0),
          _tabBtn(_isEdit ? 'Edit Signature' : 'Add New Signature', Icons.add_circle_outline, 1),
        ]),
      );

  Widget _tabBtn(String label, IconData icon, int idx) {
    final active = _tab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => idx == 1 ? (_isEdit ? setState(() => _tab = 1) : _openAdd()) : setState(() => _tab = 0),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(color: active ? Colors.white : null, border: Border(bottom: BorderSide(color: active ? _C.purple : Colors.transparent, width: 3))),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: active ? _C.purple : _C.slate),
            const SizedBox(width: 6),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: active ? _C.purple : _C.slate))),
          ]),
        ),
      ),
    );
  }

  // ───────────────────────────── manage tab ─────────────────────────────
  Widget _manageTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Row(children: [
          Icon(Icons.checklist, color: Color(0xFF9333EA)),
          SizedBox(width: 8),
          Text('All Signatures', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
        ]),
        Text('${_signatures.length} total', style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
      ]),
      const SizedBox(height: 18),
      if (_signatures.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(children: [
            const Icon(Icons.draw, size: 64, color: Color(0xFFCBD5E1)),
            const SizedBox(height: 14),
            const Text('No Signatures Yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
            const SizedBox(height: 8),
            const Text('Start by adding your first signature.', style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
            const SizedBox(height: 22),
            _gradBtn('Add Signature', Icons.add, _C.primaryGradient, _openAdd),
          ]),
        )
      else
        for (final s in _signatures) _sigCard(s),
    ]);
  }

  Widget _roleBadge(String role) {
    final teacher = role == 'teacher';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: teacher ? [_C.violet, _C.indigo] : [_C.amber, _C.amberDark]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: (teacher ? _C.violet : _C.amber).withAlpha(77), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(teacher ? Icons.stars : Icons.verified_user, size: 14, color: Colors.white),
        const SizedBox(width: 6),
        Text(_cap(role).toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .5)),
      ]),
    );
  }

  Widget _detailRow(IconData icon, String label, Widget value) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 32, height: 32, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 16, color: _C.purple)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: const TextStyle(fontSize: 11, letterSpacing: .5, color: Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
              value,
            ]),
          ),
        ]),
      );

  Widget _sigCard(Map<String, dynamic> s) {
    final role = '${s['role']}';
    final url = s['image_url'];
    final missing = s['image_missing'] == true || url == null;
    final orig = '${s['original_class_name'] ?? '—'}';
    final curr = s['current_class_name'];
    final transferred = curr != null && '$curr' != '${s['original_class_name']}';
    final dept = s['department_name'];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFF1F5F9)), boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 15, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Align(alignment: Alignment.centerLeft, child: _roleBadge(role)),
        const SizedBox(height: 14),
        if (missing)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: const Color(0xFFFEF2F2), border: Border.all(color: const Color(0xFFFECACA)), borderRadius: BorderRadius.circular(12)),
            child: const Column(children: [
              Icon(Icons.error_outline, color: _C.red, size: 26),
              SizedBox(height: 4),
              Text('Image Missing', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          )
        else
          GestureDetector(
            onTap: () => _enlarge(Image.network('$url', fit: BoxFit.contain)),
            child: Container(
              height: 120,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: _C.light, border: Border.all(color: _C.border), borderRadius: BorderRadius.circular(12)),
              child: Image.network(
                '$url',
                fit: BoxFit.contain,
                loadingBuilder: (c, child, p) => p == null ? child : const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _C.purple))),
                errorBuilder: (c, e, st) => const Center(child: Icon(Icons.broken_image, color: _C.red)),
              ),
            ),
          ),
        if (role == 'teacher')
          _detailRow(
            Icons.menu_book,
            'Class',
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(orig, style: const TextStyle(fontWeight: FontWeight.w600, color: _C.text, fontSize: 14)),
              if (transferred) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('→', style: TextStyle(color: _C.violet, fontWeight: FontWeight.w700))),
                Text('$curr', style: const TextStyle(fontWeight: FontWeight.w600, color: _C.text, fontSize: 14)),
              ],
            ]),
          ),
        if (dept != null && '$dept'.isNotEmpty) _detailRow(Icons.apartment, 'Department', Text('$dept', style: const TextStyle(fontWeight: FontWeight.w600, color: _C.text, fontSize: 14))),
        const Divider(height: 24, color: Color(0xFFF1F5F9)),
        Row(children: [
          Expanded(child: _gradBtn('Edit', Icons.edit_outlined, _C.primaryGradient, () => _openEdit(s), small: true)),
          const SizedBox(width: 10),
          Expanded(child: _gradBtn('Delete', Icons.delete_outline, _C.dangerGradient, () => _delete(s), small: true)),
        ]),
      ]),
    );
  }

  // ───────────────────────────── form tab ─────────────────────────────
  InputDecoration _dec([String? hint]) => InputDecoration(
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.border, width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _C.purple, width: 2)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  Widget _label(String text, {bool required = false, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: text, style: const TextStyle(fontWeight: FontWeight.w600, color: _C.label, fontSize: 14)),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: _C.red, fontWeight: FontWeight.w600)),
          if (hint != null) TextSpan(text: ' $hint', style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
        ])),
      );

  Widget _classDropdown(String? value, String emptyLabel, ValueChanged<String?> onChanged) {
    final ok = value != null && _classes.any((c) => '${c['class_id']}' == value);
    return DropdownButtonFormField<String>(
      value: ok ? value : null,
      isExpanded: true,
      decoration: _dec(),
      items: [
        DropdownMenuItem<String>(value: null, child: Text(emptyLabel, style: const TextStyle(color: Color(0xFF6B7280)))),
        for (final c in _classes) DropdownMenuItem(value: '${c['class_id']}', child: Text('${c['class_name']}')),
      ],
      onChanged: onChanged,
    );
  }

  Widget _formTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.cloud_upload_outlined, color: Color(0xFF9333EA)),
        const SizedBox(width: 8),
        Text('${_isEdit ? 'Edit' : 'Add New'} Signature', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111827))),
      ]),
      const SizedBox(height: 20),
      if (_isTeacher) ...[
        _label('Role'),
        DropdownButtonFormField<String>(
          value: _formRole,
          isExpanded: true,
          decoration: _dec(),
          items: const [
            DropdownMenuItem(value: 'teacher', child: Text('Teacher')),
            DropdownMenuItem(value: 'proprietor', child: Text('Principal/Proprietor')),
          ],
          onChanged: (v) => setState(() => _formRole = v ?? 'teacher'),
        ),
        const SizedBox(height: 20),
      ] else ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFEFF6FF), border: Border.all(color: const Color(0xFFBFDBFE)), borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(Icons.info_outline, color: Color(0xFF3B82F6)),
            SizedBox(width: 10),
            Expanded(child: Text('Principal/Proprietor Signature', style: TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.w600, fontSize: 13))),
          ]),
        ),
        const SizedBox(height: 20),
      ],
      if (_showClassFields) ...[
        _label('Original Class', required: true),
        _classDropdown(_origClass, '-- Select Class --', (v) => setState(() => _origClass = v)),
        const SizedBox(height: 20),
        _label('Current Class (Optional)'),
        _classDropdown(_currClass, '-- Same as Original --', (v) => setState(() => _currClass = v)),
        const SizedBox(height: 20),
        _label('Department (Optional)'),
        DropdownButtonFormField<String>(
          value: _dept != null && _departments.any((d) => '${d['id']}' == _dept) ? _dept : null,
          isExpanded: true,
          decoration: _dec(),
          items: [
            const DropdownMenuItem<String>(value: null, child: Text('-- None --', style: TextStyle(color: Color(0xFF6B7280)))),
            for (final d in _departments) DropdownMenuItem(value: '${d['id']}', child: Text('${d['department_name']}')),
          ],
          onChanged: (v) => setState(() => _dept = v),
        ),
        const SizedBox(height: 20),
      ],
      _label('Signature Image', required: !_isEdit, hint: _isEdit ? '(Leave blank to keep current)' : null),
      InkWell(
        onTap: _pick,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(border: Border.all(color: _C.border, width: 2), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.image_outlined, color: _C.purple),
            const SizedBox(width: 10),
            Expanded(child: Text(_pickedName ?? 'Choose image (JPG, PNG, GIF — max 2MB)', overflow: TextOverflow.ellipsis, style: TextStyle(color: _pickedName == null ? const Color(0xFF6B7280) : _C.text))),
            const Icon(Icons.chevron_right, color: _C.slate),
          ]),
        ),
      ),
      if (_picked != null) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _enlarge(Image.memory(_picked!, fit: BoxFit.contain)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 250),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.border, width: 2), borderRadius: BorderRadius.circular(12)),
            child: Image.memory(_picked!, fit: BoxFit.contain),
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('New signature (will replace the current one)', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
      ] else if (_isEdit && _editing!['image_url'] != null) ...[
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () => _enlarge(Image.network('${_editing!['image_url']}', fit: BoxFit.contain)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 250),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _C.border, width: 2), borderRadius: BorderRadius.circular(12)),
            child: Image.network('${_editing!['image_url']}', fit: BoxFit.contain, errorBuilder: (c, e, s) => const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image, color: _C.red)))),
          ),
        ),
        const Padding(padding: EdgeInsets.only(top: 6), child: Text('Current signature (will be replaced if new file uploaded)', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)))),
      ],
      const SizedBox(height: 24),
      Row(children: [
        Expanded(flex: 2, child: _gradBtn(_saving ? 'Saving...' : 'Save Signature', Icons.save_outlined, _C.primaryGradient, _saving ? null : _save, busy: _saving)),
        const SizedBox(width: 10),
        Expanded(child: _gradBtn('Cancel', Icons.close, const LinearGradient(colors: [Color(0xFF6B7280), Color(0xFF4B5563)]), _saving ? null : _cancel)),
      ]),
    ]);
  }

  Widget _gradBtn(String label, IconData icon, Gradient g, VoidCallback? onTap, {bool small = false, bool busy = false}) {
    return Opacity(
      opacity: onTap == null ? .6 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(small ? 10 : 12),
        child: Ink(
          padding: EdgeInsets.symmetric(horizontal: small ? 14 : 22, vertical: small ? 10 : 13),
          decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(small ? 10 : 12), boxShadow: [BoxShadow(color: Colors.black.withAlpha(38), blurRadius: 12, offset: const Offset(0, 4))]),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(icon, size: small ? 16 : 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: small ? 13 : 14))),
          ]),
        ),
      ),
    );
  }
}
