// flutter_result_template_screen.dart
// Mirrors ResultTemplateid.php: "Insert School Details" form (name, motto, address, sub address),
// "School Information" list with Edit and Delete (edit_school.php becomes an in-app dialog).
//
// pubspec.yaml needs:  http, shared_preferences

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// extensionless address first (a redirect from "*.php" turns POST into GET and loses the form data)
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_result_template',
  'https://schoolsmirror.com/flutter_result_template.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

/// Same colour tokens as ResultTemplateid.php
class _C {
  static const blue = Color(0xFF007BFF);
  static const blueDark = Color(0xFF0056B3);
  static const bg = Color(0xFFF8F9FA);
  static const text = Color(0xFF333333);
  static const border = Color(0xFFDDDDDD);
  static const red = Color(0xFFDC3545);
  static const green = Color(0xFF28A745);
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
            .timeout(const Duration(seconds: 30));
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

InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.all(12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: _C.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: _C.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(5), borderSide: const BorderSide(color: _C.blue, width: 1.5)),
    );

String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'This field is required' : null;

// ═════════════════════════════════════════════════════════════════════════════
class FlutterResultTemplateScreen extends StatefulWidget {
  final String? token;
  const FlutterResultTemplateScreen({super.key, this.token});

  @override
  State<FlutterResultTemplateScreen> createState() => _FlutterResultTemplateScreenState();
}

class _FlutterResultTemplateScreenState extends State<FlutterResultTemplateScreen> {
  String? _token;
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _schools = [];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _motto = TextEditingController();
  final _address = TextEditingController();
  final _sub = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final c in [_name, _motto, _address, _sub]) {
      c.dispose();
    }
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

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), backgroundColor: error ? _C.red : _C.green, behavior: SnackBarBehavior.floating));
  }

  Future<void> _init() async {
    _token = await _getToken();
    if (_token != null) await _load();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _load() async {
    final r = await _Api.post(_token!, 'list');
    if (!mounted) return;
    if (r['success'] == true) {
      final list = (r['data'] as Map)['schools'];
      setState(() => _schools = (list is List ? list : []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } else {
      _snack('${r['message']}', error: true);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final r = await _Api.post(_token!, 'add', {
      'school_name': _name.text.trim(),
      'motto': _motto.text.trim(),
      'address': _address.text.trim(),
      'sub_address': _sub.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    _snack('${r['message']}', error: r['success'] != true);
    if (r['success'] == true) {
      for (final c in [_name, _motto, _address, _sub]) {
        c.clear();
      }
      await _load();
    }
  }

  Future<void> _edit(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _EditDialog(token: _token!, school: s));
    if (ok == true) {
      _snack('School details updated successfully!');
      _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete School'),
        content: const Text('Are you sure you want to delete this school?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: _C.red, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (yes != true) return;
    final r = await _Api.post(_token!, 'delete', {'id': '${s['id']}'});
    _snack('${r['message']}', error: r['success'] != true);
    if (r['success'] == true) _load();
  }

  // ───────────────────────────── build ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(backgroundColor: _C.blue, foregroundColor: Colors.white, elevation: 0, title: const Text('Result Template', style: TextStyle(fontWeight: FontWeight.w700))),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.blue))
          : _token == null
              ? const Center(child: Text('Session expired. Please log out and log back in.'))
              : RefreshIndicator(
                  color: _C.blue,
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    children: [_formCard(), const SizedBox(height: 4), _listCard()],
                  ),
                ),
    );
  }

  Widget _box({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 10, offset: const Offset(0, 2))]),
        child: child,
      );

  Widget _formCard() => _box(
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Insert School Details', textAlign: TextAlign.center, style: TextStyle(color: _C.blue, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            TextFormField(controller: _name, decoration: _dec('School Name'), validator: _required, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 14),
            TextFormField(controller: _motto, decoration: _dec('Motto'), validator: _required, textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 14),
            TextFormField(controller: _address, decoration: _dec('Address'), validator: _required, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 14),
            TextFormField(controller: _sub, decoration: _dec('Sub Address'), validator: _required, textCapitalization: TextCapitalization.words),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: _C.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5))),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Submit School Info', style: TextStyle(fontSize: 16)),
            ),
          ]),
        ),
      );

  Widget _listCard() => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: _box(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('School Information', textAlign: TextAlign.center, style: TextStyle(color: _C.blue, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            if (_schools.isEmpty)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No school information added yet', style: TextStyle(color: Colors.grey))))
            else
              for (final s in _schools) _schoolRow(s),
          ]),
        ),
      );

  Widget _kv(String k, dynamic v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: const TextStyle(fontWeight: FontWeight.bold, color: _C.text))),
          Expanded(child: Text('${v ?? ''}', style: const TextStyle(color: _C.text))),
        ]),
      );

  Widget _schoolRow(Map<String, dynamic> s) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(border: Border.all(color: _C.border), borderRadius: BorderRadius.circular(6), color: const Color(0xFFFAFAFA)),
        child: Column(children: [
          _kv('School Name', s['school_name']),
          _kv('Motto', s['motto']),
          _kv('Address', s['address']),
          _kv('Sub Address', s['sub_address']),
          const Divider(height: 18),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton.icon(onPressed: () => _edit(s), icon: const Icon(Icons.edit, size: 18), label: const Text('Edit')),
            TextButton.icon(onPressed: () => _delete(s), icon: const Icon(Icons.delete_outline, size: 18, color: _C.red), label: const Text('Delete', style: TextStyle(color: _C.red))),
          ]),
        ]),
      );
}

// ═════════════════════════════════════════════════════════════════════════════
//  Edit dialog (stands in for edit_school.php?id=...)
// ═════════════════════════════════════════════════════════════════════════════
class _EditDialog extends StatefulWidget {
  final String token;
  final Map<String, dynamic> school;
  const _EditDialog({required this.token, required this.school});

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  final _key = GlobalKey<FormState>();
  late final _name = TextEditingController(text: '${widget.school['school_name'] ?? ''}');
  late final _motto = TextEditingController(text: '${widget.school['motto'] ?? ''}');
  late final _address = TextEditingController(text: '${widget.school['address'] ?? ''}');
  late final _sub = TextEditingController(text: '${widget.school['sub_address'] ?? ''}');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _motto, _address, _sub]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await _Api.post(widget.token, 'update', {
      'id': '${widget.school['id']}',
      'school_name': _name.text.trim(),
      'motto': _motto.text.trim(),
      'address': _address.text.trim(),
      'sub_address': _sub.text.trim(),
    });
    if (!mounted) return;
    if (r['success'] == true) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = '${r['message']}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit School', style: TextStyle(color: _C.blue, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Form(
          key: _key,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: _name, decoration: _dec('School Name'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _motto, decoration: _dec('Motto'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _address, decoration: _dec('Address'), validator: _required),
            const SizedBox(height: 12),
            TextFormField(controller: _sub, decoration: _dec('Sub Address'), validator: _required),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: _C.red, fontSize: 13))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: _C.blue, foregroundColor: Colors.white),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
        ),
      ],
    );
  }
}
