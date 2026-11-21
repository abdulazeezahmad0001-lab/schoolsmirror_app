import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

class FlutterAddHomeworkScreen extends StatefulWidget {
  final String? token;
  const FlutterAddHomeworkScreen({super.key, this.token});

  @override
  State<FlutterAddHomeworkScreen> createState() => _FlutterAddHomeworkScreenState();
}

class _FlutterAddHomeworkScreenState extends State<FlutterAddHomeworkScreen> {
  static const _primary = Color(0xFF4361ee);
  static const _violet = Color(0xFF7c3aed);
  static const _bg = Color(0xFFf0f4ff);
  static const _dark = Color(0xFF0f172a);
  static const _muted = Color(0xFF64748b);
  static const _border = Color(0xFFe2e8f0);
  static const _green = Color(0xFF10b981);
  static const _rose = Color(0xFFef4444);

  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _dueCtrl = TextEditingController();
  final _notifyCtrl = TextEditingController(text: 'Please complete this homework.');

  int? _classId;
  int? _subjectId;
  List<dynamic> _classes = [];
  List<dynamic> _subjects = [];
  bool _loading = true;
  bool _saving = false;

  Future<String?> _getToken() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) return widget.token!.trim();
    try { await ApiClient.loadToken(); if (ApiClient.token != null) return ApiClient.token!.trim(); } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleCtrl.dispose(); _descCtrl.dispose(); _dueCtrl.dispose(); _notifyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final token = await _getToken();
      final res = await http.get(Uri.parse('https://schoolsmirror.com/flutter_manage_students.php?token=$token&action=list&limit=1')).timeout(const Duration(seconds: 20));
      final d = jsonDecode(res.body);
      
      if (d['success'] == true) {
        setState(() {
          _classes = d['data']['classes'] ?? [];
          // If your server doesn't return subjects here, you'll need to adjust this to fetch subjects
          _subjects = d['data']['subjects'] ?? []; 
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select a class'), backgroundColor: _rose));
      return;
    }
    
    setState(() => _saving = true);
    try {
      final token = await _getToken();
      final body = {
        'token': token!, 'action': 'add',
        'class_id': '$_classId', 
        'subject_id': _subjectId != null ? '$_subjectId' : '',
        'title': _titleCtrl.text.trim(), 
        'description': _descCtrl.text.trim(),
        'due_date': _dueCtrl.text.trim(), 
        'notify_message': _notifyCtrl.text.trim(), 
        'send_push': '1', 
      };

      http.Response? res;
      try {
        res = await http.post(Uri.parse('https://schoolsmirror.com/flutter_homework.php'), body: body).timeout(const Duration(seconds: 25));
      } catch (_) {}

      if (res == null) {
        // Offline fallback
        final p = await SharedPreferences.getInstance();
        final raw = p.getString('homework_offline_queue') ?? '[]';
        final list = jsonDecode(raw) as List..add(body);
        await p.setString('homework_offline_queue', jsonEncode(list));
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Offline — homework saved. Auto-syncs later.'), backgroundColor: Colors.orange));
        Navigator.pop(context);
        return;
      }

      final d = jsonDecode(res.body);
      if (d['success'] != true) throw Exception(d['message'] ?? 'Save failed');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Homework posted + push sent!'), backgroundColor: _green));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: _rose));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0, backgroundColor: Colors.white, foregroundColor: _dark,
        title: const Text('Add Homework', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: _loading 
        ? const Center(child: CircularProgressIndicator())
        : Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                _hero(),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
                  child: Column(
                    children: [
                      DropdownButtonFormField<int>(
                        value: _classId, isExpanded: true, decoration: _inputDec('Class *', Icons.class_),
                        items: _classes.map((c) => DropdownMenuItem(value: int.tryParse('${c['class_id']}'), child: Text('${c['class_name']}'))).toList(),
                        onChanged: (v) => setState(() => _classId = v),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _subjectId, isExpanded: true, decoration: _inputDec('Subject (Optional)', Icons.book),
                        items: _subjects.map((s) => DropdownMenuItem(value: int.tryParse('${s['subject_id'] ?? s['id']}'), child: Text('${s['subject_name'] ?? s['name']}'))).toList(),
                        onChanged: (v) => setState(() => _subjectId = v),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _titleCtrl, decoration: _inputDec('Title *', Icons.title),
                        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl, maxLines: 4, decoration: _inputDec('Description *', Icons.description),
                        validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _dueCtrl, readOnly: true, decoration: _inputDec('Due date *', Icons.calendar_today),
                        onTap: () async {
                          final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                          if (d != null) _dueCtrl.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                        },
                        validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notifyCtrl, decoration: _inputDec('Push Notification Message', Icons.notifications_active),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send),
                    label: Text(_saving ? 'Posting...' : 'Post + Notify Students', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary, foregroundColor: Colors.white, 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_primary, _violet]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _primary.withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 24, backgroundColor: Colors.white24, child: Icon(Icons.assignment, color: Colors.white)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Create Homework', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                SizedBox(height: 4),
                Text('Post homework and send a push notification.', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 20, color: _muted),
      filled: true,
      fillColor: const Color(0xFFf8fafc),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
    );
  }
}