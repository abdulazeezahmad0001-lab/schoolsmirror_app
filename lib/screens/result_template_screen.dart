// flutter_result_template_screen.dart
// Mirrors the School Details / Result Template header management page 1:1:
// Insert School Details form (School Name, Motto, Address, Sub Address),
// live report-card header preview, School Information list with Edit modal
// and Delete confirmation matching the design and patterns of FlutterAddExamScreen.
//
// pubspec.yaml needs:  http, shared_preferences

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// Same redirect-resilient URL fallback pattern as flutter_add_exam_screen.dart
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_result_template',
  'https://schoolsmirror.com/flutter_result_template.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

/// Same colour tokens as FlutterAddExamScreen
class _C {
  static const primary = Color(0xFF0083B0);
  static const secondary = Color(0xFF00B4DB);
  static const success = Color(0xFF28A745);
  static const draft = Color(0xFF6C757D);
  static const danger = Color(0xFFDC3545);
  static const warning = Color(0xFFFFC107);
  static const info = Color(0xFF17A2B8);
  static const lightBg = Color(0xFFF8F9FA);
  static const border = Color(0xFFDEE2E6);
  static const text = Color(0xFF333333);

  static const headerGradient = LinearGradient(colors: [primary, secondary]);
}

// ───────────────────────────── API helper ─────────────────────────────
class _Api {
  static bool shouldRetry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' ||
            m.startsWith('The server received this request as') ||
            m.startsWith('Missing token'));
  }

  static Future<Map<String, dynamic>> post(String token, String action,
      [Map<String, String> fields = const {}]) async {
    Map<String, dynamic> last = {
      'success': false,
      'message': 'Network error. Check your connection.'
    };
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        final uri = Uri.parse(_apiUrl)
            .replace(queryParameters: {'token': token, 'action': action, ...fields});
        final res = await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'
              },
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
        return {
          'success': false,
          'message': 'Network error. Check your connection.'
        };
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

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

int? _toInt(dynamic v) => v == null ? null : int.tryParse('$v');

// ───────────────────────────── SCREEN ─────────────────────────────
class FlutterResultTemplateScreen extends StatefulWidget {
  final String? token;
  const FlutterResultTemplateScreen({super.key, this.token});

  @override
  State<FlutterResultTemplateScreen> createState() =>
      _FlutterResultTemplateScreenState();
}

class _FlutterResultTemplateScreenState
    extends State<FlutterResultTemplateScreen> {
  String? _token;
  bool _loading = true;
  bool _saving = false;

  final _schoolNameCtrl = TextEditingController();
  final _mottoCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _subAddressCtrl = TextEditingController();

  List<Map<String, dynamic>> _schools = [];
  String? _banner;
  bool _bannerError = false;

  final _scroll = ScrollController();
  final _listKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _schoolNameCtrl.dispose();
    _mottoCtrl.dispose();
    _addressCtrl.dispose();
    _subAddressCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<String?> _getToken() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) {
      return widget.token!.trim();
    }
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
        content: Text(msg),
        backgroundColor: error ? _C.danger : _C.success,
        behavior: SnackBarBehavior.floating,
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
    await _loadSchools();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadSchools() async {
    if (_token == null) return;
    final r = await _Api.post(_token!, 'list');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = r['data'] as Map<String, dynamic>;
      setState(() {
        _schools = _maps(d['schools']);
      });
    } else {
      _setBanner('${r['message'] ?? 'Failed to load school information'}',
          error: true);
    }
  }

  void _scrollToList() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ctx = _listKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
          alignment: 0.0,
        );
      }
    });
  }

  // ───────────────────────────── actions ─────────────────────────────
  Future<void> _submitSchool() async {
    final schoolName = _schoolNameCtrl.text.trim();
    final motto = _mottoCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final subAddress = _subAddressCtrl.text.trim();

    if (schoolName.isEmpty ||
        motto.isEmpty ||
        address.isEmpty ||
        subAddress.isEmpty) {
      _toast('Please fill in all required school details.', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final r = await _Api.post(_token!, 'add', {
        'school_name': schoolName,
        'motto': motto,
        'address': address,
        'sub_address': subAddress,
      });

      if (r['success'] == true) {
        _schoolNameCtrl.clear();
        _mottoCtrl.clear();
        _addressCtrl.clear();
        _subAddressCtrl.clear();
        _toast('${r['message']}');
        _setBanner('${r['message']}');
        await _loadSchools();
        _scrollToList();
      } else {
        _toast('${r['message']}', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteSchool(int id) async {
    final ok = await _confirm(
      'Delete School Details?',
      'Are you sure you want to delete this school? This action cannot be undone!',
      yes: 'Yes, delete it!',
      destructive: true,
    );
    if (ok != true) return;

    final r = await _Api.post(_token!, 'delete', {'id': '$id'});
    if (r['success'] == true) {
      _toast('${r['message']}');
      _setBanner('${r['message']}');
      await _loadSchools();
    } else {
      _toast('${r['message']}', error: true);
    }
  }

  Future<bool?> _confirm(String title, String text,
      {String yes = 'Yes',
      bool destructive = false,
      IconData icon = Icons.warning_amber_rounded}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(children: [
          Icon(icon, size: 54, color: destructive ? _C.danger : _C.warning),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Text(text, textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3085D6),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDD3333),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(yes),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────── small UI helpers ─────────────────────────────
  InputDecoration _dec(String hint, {IconData? icon}) => InputDecoration(
        hintText: hint,
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 20, color: Colors.grey.shade600),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFCCCCCC))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: Color(0xFFCCCCCC))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(5),
            borderSide: const BorderSide(color: _C.primary, width: 1.5)),
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withAlpha(26),
              blurRadius: 10,
              offset: const Offset(0, 3))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(children: [
          Padding(
              padding: EdgeInsets.only(left: barWidth).add(padding),
              child: child),
          Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: barWidth,
              child: ColoredBox(color: bar)),
        ]),
      ),
    );
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback? onTap,
      {bool expand = false}) {
    final b = ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color,
        disabledForegroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: b) : b;
  }

  Widget _label(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Row(children: [
          Icon(icon, size: 16, color: _C.text),
          const SizedBox(width: 6),
          Flexible(
              child: Text(text,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, color: _C.text))),
        ]),
      );

  Widget _row(String label, Widget value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 110,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, color: Color(0xFF555555))),
          ),
          Expanded(
              child: Align(alignment: Alignment.centerLeft, child: value)),
        ]),
      );

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F9),
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace:
            Container(decoration: const BoxDecoration(gradient: _C.headerGradient)),
        title: const Text('Result Template',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : RefreshIndicator(
              color: _C.primary,
              onRefresh: _loadSchools,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 60),
                children: [
                  if (_banner != null) _alertBox(),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 14),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance, color: _C.primary),
                          SizedBox(width: 8),
                          Text('Insert School Details',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: _C.text)),
                        ]),
                  ),
                  _formCard(),
                  const SizedBox(height: 28),
                  KeyedSubtree(key: _listKey, child: _schoolInfoSection()),
                ],
              ),
            ),
    );
  }

  Widget _alertBox() {
    final err = _bannerError;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: err ? const Color(0xFFF8D7DA) : const Color(0xFFD4EDDA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: err ? const Color(0xFFF5C6CB) : const Color(0xFFC3E6CB)),
      ),
      child: Row(children: [
        Icon(err ? Icons.error : Icons.check_circle,
            color: err ? const Color(0xFF721C24) : const Color(0xFF155724)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(_banner!,
                style: TextStyle(
                    color: err
                        ? const Color(0xFF721C24)
                        : const Color(0xFF155724)))),
        InkWell(
            onTap: () => setState(() => _banner = null),
            child: const Icon(Icons.close, size: 18)),
      ]),
    );
  }

  Widget _formCard() {
    return _accentCard(
      bar: _C.primary,
      barWidth: 5,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.edit_document, color: _C.primary),
          SizedBox(width: 8),
          Text('Report Card Header Details',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: _C.text)),
        ]),
        _label(Icons.school, 'School Name:'),
        TextField(
          controller: _schoolNameCtrl,
          decoration: _dec('Enter school name', icon: Icons.school_outlined),
        ),
        _label(Icons.format_quote, 'Motto:'),
        TextField(
          controller: _mottoCtrl,
          decoration: _dec('Enter school motto', icon: Icons.auto_awesome),
        ),
        _label(Icons.location_on, 'Address:'),
        TextField(
          controller: _addressCtrl,
          decoration: _dec('Enter school address', icon: Icons.place_outlined),
        ),
        _label(Icons.add_location_alt, 'Sub Address:'),
        TextField(
          controller: _subAddressCtrl,
          decoration:
              _dec('Enter sub address / branch', icon: Icons.map_outlined),
        ),
        const SizedBox(height: 22),
        _btn(
          _saving ? 'Submitting...' : 'Submit School Info',
          Icons.save,
          _C.primary,
          _saving ? null : _submitSchool,
          expand: true,
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: Center(child: CircularProgressIndicator(color: _C.primary)),
          ),
      ]),
    );
  }

  // ───────────────────────────── School Information List ─────────────────────────────
  Widget _schoolInfoSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.info_outline, color: _C.primary),
        SizedBox(width: 8),
        Text('School Information',
            style: TextStyle(
                fontSize: 21, fontWeight: FontWeight.bold, color: _C.text)),
      ]),
      const SizedBox(height: 14),
      if (_schools.isEmpty)
        Container(
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Icon(Icons.school_outlined, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('No school information found.',
                style: TextStyle(color: Color(0xFF666666), fontSize: 16)),
            const SizedBox(height: 6),
            const Text(
              'Fill the form above to configure your school header for result templates.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF888888)),
            ),
          ]),
        )
      else
        for (final school in _schools) ...[
          _reportHeaderPreview(school),
          const SizedBox(height: 14),
          _schoolCard(school),
          const SizedBox(height: 18),
        ],
    ]);
  }

  /// Live preview styled after the `.header` section of the result template CSS
  Widget _reportHeaderPreview(Map<String, dynamic> s) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.border),
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: _C.lightBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _C.border),
          ),
          child: const Text('Report Card Header Preview',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF666666))),
        ),
        const SizedBox(height: 10),
        Text(
          '${s['school_name']}',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: _C.primary),
        ),
        const SizedBox(height: 4),
        Text(
          '"${s['motto']}"',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontStyle: FontStyle.italic, color: Color(0xFF555555)),
        ),
        const SizedBox(height: 4),
        Text(
          '${s['address']}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
        ),
        if ('${s['sub_address']}'.trim().isNotEmpty)
          Text(
            '${s['sub_address']}',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
          ),
        const SizedBox(height: 12),
        const Divider(color: _C.primary, thickness: 2, height: 2),
      ]),
    );
  }

  Widget _schoolCard(Map<String, dynamic> s) {
    final id = _toInt(s['id']) ?? 0;
    return _accentCard(
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _row(
            'School Name',
            Text('${s['school_name']}',
                style: const TextStyle(fontWeight: FontWeight.bold))),
        _row('Motto', Text('${s['motto']}')),
        _row('Address', Text('${s['address']}')),
        _row('Sub Address', Text('${s['sub_address']}')),
        const SizedBox(height: 14),
        _btn('Edit', Icons.edit_outlined, _C.info, () => _openEditModal(s),
            expand: true),
        const SizedBox(height: 8),
        _btn('Delete', Icons.delete, _C.danger, () => _deleteSchool(id),
            expand: true),
      ]),
    );
  }

  // ───────────────────────────── Edit Modal (edit_school.php equivalent) ─────────────────────────────
  void _openEditModal(Map<String, dynamic> s) {
    final nameCtrl = TextEditingController(text: '${s['school_name']}');
    final mottoCtrl = TextEditingController(text: '${s['motto']}');
    final addrCtrl = TextEditingController(text: '${s['address']}');
    final subAddrCtrl = TextEditingController(text: '${s['sub_address']}');
    bool busy = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setM) => Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 16, 8, 16),
                  decoration: const BoxDecoration(
                      gradient: _C.headerGradient,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(18))),
                  child: Row(children: [
                    const Icon(Icons.edit, color: Colors.white),
                    const SizedBox(width: 8),
                    const Expanded(
                        child: Text('Edit School Details',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold))),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _label(Icons.school, 'School Name'),
                        TextField(
                            controller: nameCtrl,
                            decoration: _dec('Enter school name')),
                        _label(Icons.format_quote, 'Motto'),
                        TextField(
                            controller: mottoCtrl,
                            decoration: _dec('Enter school motto')),
                        _label(Icons.location_on, 'Address'),
                        TextField(
                            controller: addrCtrl,
                            decoration: _dec('Enter school address')),
                        _label(Icons.add_location_alt, 'Sub Address'),
                        TextField(
                            controller: subAddrCtrl,
                            decoration: _dec('Enter sub address')),
                        const SizedBox(height: 20),
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          _btn('Cancel', Icons.close, _C.draft,
                              () => Navigator.pop(ctx)),
                          const SizedBox(width: 10),
                          _btn(
                            busy ? 'Saving...' : 'Update Details',
                            Icons.save,
                            _C.primary,
                            busy
                                ? null
                                : () async {
                                    if (nameCtrl.text.trim().isEmpty ||
                                        mottoCtrl.text.trim().isEmpty ||
                                        addrCtrl.text.trim().isEmpty ||
                                        subAddrCtrl.text.trim().isEmpty) {
                                      _toast('All fields are required.',
                                          error: true);
                                      return;
                                    }
                                    setM(() => busy = true);
                                    final r = await _Api.post(_token!, 'update', {
                                      'id': '${s['id']}',
                                      'school_name': nameCtrl.text.trim(),
                                      'motto': mottoCtrl.text.trim(),
                                      'address': addrCtrl.text.trim(),
                                      'sub_address': subAddrCtrl.text.trim(),
                                    });
                                    if (r['success'] == true) {
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      _setBanner('${r['message']}');
                                      _toast('${r['message']}');
                                      await _loadSchools();
                                    } else {
                                      if (ctx.mounted) setM(() => busy = false);
                                      _toast('${r['message']}', error: true);
                                    }
                                  },
                          ),
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
}