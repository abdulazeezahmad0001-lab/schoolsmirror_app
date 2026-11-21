import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

class FlutterManageUsersScreen extends StatefulWidget {
  final String? token;
  final String initialRole; // student | teacher | subadmin
  const FlutterManageUsersScreen({
    super.key,
    this.token,
    this.initialRole = 'student',
  });

  @override
  State<FlutterManageUsersScreen> createState() => _FlutterManageUsersScreenState();
}

class _FlutterManageUsersScreenState extends State<FlutterManageUsersScreen>
    with SingleTickerProviderStateMixin {
  static const _primary = Color(0xFF4361ee);
  static const _violet = Color(0xFF7c3aed);
  static const _bg = Color(0xFFf0f4ff);
  static const _dark = Color(0xFF0f172a);
  static const _muted = Color(0xFF64748b);
  static const _border = Color(0xFFe2e8f0);
  static const _green = Color(0xFF10b981);
  static const _amber = Color(0xFFf59e0b);
  static const _rose = Color(0xFFef4444);

  late TabController _tab;
  final _searchCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _id = TextEditingController();
  final _password = TextEditingController();
  final _admission = TextEditingController();
  final _phone = TextEditingController();
  final _parentName = TextEditingController();
  final _parentPhone = TextEditingController();

  String _gender = 'Male';
  int? _classId;
  int? _departmentId;
  bool _obscure = true;
  bool _saving = false;
  XFile? _picked;
  Uint8List? _bytes;

  bool _loading = true;
  String? _error;
  List<dynamic> _users = [];
  List<dynamic> _classes = [];
  List<dynamic> _departments = [];
  Map<String, dynamic> _stats = {};
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;
  String _listRoleFilter = ''; // empty = all

  final _roles = const [
    ('student', 'Student', Icons.school_outlined),
    ('teacher', 'Teacher', Icons.person_outline),
    ('subadmin', 'Subadmin', Icons.admin_panel_settings_outlined),
  ];

  String get _addRole => _roles[_tab.index].$1;

  Future<String?> _token() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) {
      return widget.token!.trim();
    }
    try {
      await ApiClient.loadToken();
      if (ApiClient.token != null && ApiClient.token!.isNotEmpty) {
        return ApiClient.token!.trim();
      }
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString('auth_token') ?? p.getString('token');
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    final idx = _roles.indexWhere((r) => r.$1 == widget.initialRole);
    _tab = TabController(length: 3, vsync: this, initialIndex: idx < 0 ? 0 : idx);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _name.dispose();
    _id.dispose();
    _password.dispose();
    _admission.dispose();
    _phone.dispose();
    _parentName.dispose();
    _parentPhone.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      final token = await _token();
      if (token == null) throw Exception('Missing token. Log out and log back in.');
      final uri = Uri.parse('https://schoolsmirror.com/flutter_manage_users').replace(
        queryParameters: {
          'token': token,
          'action': 'list',
          'page': '$page',
          'limit': '10',
          if (_listRoleFilter.isNotEmpty) 'role_filter': _listRoleFilter,
          if (_searchCtrl.text.trim().isNotEmpty) 'search': _searchCtrl.text.trim(),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (data['success'] != true) throw Exception(data['message'] ?? 'Load failed');
      final d = data['data'] ?? {};
      if (!mounted) return;
      setState(() {
        _users = List.from(d['users'] ?? []);
        _classes = List.from(d['classes'] ?? []);
        _departments = List.from(d['departments'] ?? []);
        _stats = Map<String, dynamic>.from(d['stats'] ?? {});
        _page = d['page'] ?? page;
        _totalPages = d['total_pages'] ?? 1;
        _total = d['total'] ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _name.clear();
    _id.clear();
    _password.clear();
    _admission.clear();
    _phone.clear();
    _parentName.clear();
    _parentPhone.clear();
    setState(() {
      _gender = 'Male';
      _classId = null;
      _departmentId = null;
      _obscure = true;
      _picked = null;
      _bytes = null;
    });
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1200,
    );
    if (file == null) return;
    final lower = file.name.toLowerCase();
    if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png'))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only JPG/PNG allowed'), backgroundColor: _rose),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 500 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Max 500 KB (yours ${(bytes.length / 1024).toStringAsFixed(0)} KB)'),
          backgroundColor: _rose,
        ),
      );
      return;
    }
    setState(() {
      _picked = file;
      _bytes = bytes;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_addRole == 'student' && (_classId == null || _classId! <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a class'), backgroundColor: _rose),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final token = await _token();
      if (token == null) throw Exception('Missing token');
      final fields = <String, String>{
        'token': token,
        'role': _addRole,
        'fullname': _name.text.trim(),
        'idnumber': _id.text.trim(),
        'gender': _gender,
        'password': _password.text,
        'class_id': '${_classId ?? 0}',
        'department_id': '${_departmentId ?? 0}',
        'admission_number': _admission.text.trim(),
        'phone': _phone.text.trim(),
        'parent_name': _parentName.text.trim(),
        'parent_phone': _parentPhone.text.trim(),
      };
      final uri = Uri.parse('https://schoolsmirror.com/flutter_add_student')
          .replace(queryParameters: {'token': token});
      final req = http.MultipartRequest('POST', uri);
      req.fields.addAll(fields);
      if (_bytes != null) {
        final fname = _picked?.name ?? 'photo.jpg';
        final isPng = fname.toLowerCase().endsWith('.png');
        req.files.add(http.MultipartFile.fromBytes(
          'image',
          _bytes!,
          filename: fname,
          contentType: MediaType('image', isPng ? 'png' : 'jpeg'),
        ));
      }
      final streamed = await req.send().timeout(const Duration(seconds: 40));
      final res = await http.Response.fromStream(streamed);
      final data = jsonDecode(res.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? 'Failed to add');
      }
      if (!mounted) return;
      final label = _roles[_tab.index].$2;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('$label added'),
          content: Text('${_name.text.trim()} was registered successfully.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _clearForm();
              },
              child: const Text('Add another'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _clearForm();
                setState(() => _listRoleFilter = _addRole);
                _load(page: 1);
              },
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
              child: const Text('View list'),
            ),
          ],
        ),
      );
      _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: _rose),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatus(Map u, String status) async {
    try {
      final token = await _token();
      if (token == null) return;
      final uri = Uri.parse('https://schoolsmirror.com/flutter_manage_users')
          .replace(queryParameters: {'token': token});
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'token': token,
          'action': 'set_status',
          'user_id': '${u['user_id']}',
          'status': status,
        },
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) throw Exception(data['message']);
      _load(page: _page);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: _rose));
    }
  }

  Future<void> _delete(Map u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete user?'),
        content: Text('Delete ${u['fullname']} permanently?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _rose, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final token = await _token();
      if (token == null) return;
      final uri = Uri.parse('https://schoolsmirror.com/flutter_manage_users')
          .replace(queryParameters: {'token': token});
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'token': token, 'action': 'delete', 'user_id': '${u['user_id']}'},
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) throw Exception(data['message']);
      _load(page: _page);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: _rose));
    }
  }

  String _imgUrl(Map u) {
    final direct = '${u['image_url'] ?? ''}'.trim();
    if (direct.startsWith('http')) return direct;
    final raw = '${u['image'] ?? ''}'.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('http')) return raw;
    final name = raw.split('/').last;
    return 'https://schoolsmirror.com/schooladmin/uploads/$name';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _dark,
        title: const Text('Manage Users', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: () => _load(page: _page), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _statsRow(),
          const SizedBox(height: 14),
          _addCard(),
          const SizedBox(height: 16),
          _listHeader(),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: _rose))
          else if (_users.isEmpty)
            _empty()
          else ...[
            ..._users.map((u) => _userTile(Map<String, dynamic>.from(u))),
            if (_totalPages > 1) _pager(),
          ],
        ],
      ),
    );
  }

  Widget _statsRow() {
    Widget tile(String label, String value, Color c) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c)),
                Text(label, style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('Students', '${_stats['student'] ?? 0}', _primary),
        const SizedBox(width: 8),
        tile('Teachers', '${_stats['teacher'] ?? 0}', _violet),
        const SizedBox(width: 8),
        tile('Subadmins', '${_stats['subadmin'] ?? 0}', _amber),
      ],
    );
  }

  Widget _addCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_primary, _violet]),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: TabBar(
              controller: _tab,
              indicatorColor: Colors.white,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              tabs: [
                for (final r in _roles) Tab(icon: Icon(r.$3, size: 18), text: r.$2),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _saving ? null : _pickImage,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: _primary.withOpacity(0.1),
                      backgroundImage: _bytes != null ? MemoryImage(_bytes!) : null,
                      child: _bytes == null
                          ? const Icon(Icons.add_a_photo_outlined, color: _primary)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('JPG/PNG · max 500 KB', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  const SizedBox(height: 14),
                  _field(_name, 'Full name *', Icons.person_outline, required: true),
                  const SizedBox(height: 10),
                  _field(_id, 'ID number *', Icons.badge_outlined, required: true),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _gender,
                          decoration: _dec('Gender'),
                          items: const [
                            DropdownMenuItem(value: 'Male', child: Text('Male')),
                            DropdownMenuItem(value: 'Female', child: Text('Female')),
                          ],
                          onChanged: (v) => setState(() => _gender = v ?? 'Male'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          decoration: _dec('Password *').copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (v.length < 6) return 'Min 6 chars';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_addRole == 'student') ...[
                    DropdownButtonFormField<int>(
                      value: _classId,
                      isExpanded: true,
                      decoration: _dec('Class *'),
                      items: _classes
                          .map((c) => DropdownMenuItem(
                                value: int.tryParse('${c['class_id']}'),
                                child: Text('${c['class_name']}'),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _classId = v),
                    ),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<int>(
                    value: _departmentId,
                    isExpanded: true,
                    decoration: _dec('Department'),
                    items: [
                      const DropdownMenuItem(value: 0, child: Text('None')),
                      ..._departments.map((d) => DropdownMenuItem(
                            value: int.tryParse('${d['id']}'),
                            child: Text('${d['department_name']}'),
                          )),
                    ],
                    onChanged: (v) => setState(() => _departmentId = v),
                  ),
                  const SizedBox(height: 10),
                  _field(_phone, 'Phone', Icons.phone_outlined, keyboard: TextInputType.phone),
                  if (_addRole == 'student') ...[
                    const SizedBox(height: 10),
                    _field(_admission, 'Admission no.', Icons.numbers),
                    const SizedBox(height: 10),
                    _field(_parentName, 'Parent name', Icons.family_restroom),
                    const SizedBox(height: 10),
                    _field(_parentPhone, 'Parent phone', Icons.phone_android, keyboard: TextInputType.phone),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.person_add_alt_1),
                      label: Text(_saving ? 'Saving...' : 'Add ${_roles[_tab.index].$2}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _listHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Users', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: _dark)),
            const Spacer(),
            Text('$_total total', style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _searchCtrl,
          decoration: _dec('Search name / ID / admission').copyWith(
            suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: () => _load(page: 1)),
          ),
          onSubmitted: (_) => _load(page: 1),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _filterChip('All', ''),
              _filterChip('Students', 'student'),
              _filterChip('Teachers', 'teacher'),
              _filterChip('Subadmins', 'subadmin'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _listRoleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: _primary.withOpacity(0.15),
        labelStyle: TextStyle(
          color: selected ? _primary : _muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
        onSelected: (_) {
          setState(() => _listRoleFilter = value);
          _load(page: 1);
        },
      ),
    );
  }

  Widget _userTile(Map<String, dynamic> u) {
    final url = _imgUrl(u);
    final status = '${u['status']}'.toLowerCase();
    final active = status == 'active';
    final role = '${u['role'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: _primary.withOpacity(0.1),
            backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
            onBackgroundImageError: url.isNotEmpty ? (_, __) {} : null,
            child: url.isEmpty
                ? Text(
                    '${u['fullname']}'.isNotEmpty ? '${u['fullname']}'[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.w800, color: _primary),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${u['fullname']}', style: const TextStyle(fontWeight: FontWeight.w800, color: _dark)),
                Text('ID: ${u['idnumber']}', style: const TextStyle(fontSize: 12, color: _muted)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  children: [
                    _chip(role, _violet),
                    _chip(active ? 'Active' : 'Pending', active ? _green : _amber),
                    if (role == 'student') _chip('${u['class_name'] ?? 'N/A'}', _primary),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'active' || v == 'pending') _setStatus(u, v);
              if (v == 'delete') _delete(u);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'active', child: Text('Set Active')),
              PopupMenuItem(value: 'pending', child: Text('Set Pending')),
              PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: _rose))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
      );

  Widget _pager() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: _page > 1 ? () => _load(page: _page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Text('Page $_page / $_totalPages', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            onPressed: _page < _totalPages ? () => _load(page: _page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      );

  Widget _empty() => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: const Column(
          children: [
            Icon(Icons.people_outline, size: 42, color: _muted),
            SizedBox(height: 8),
            Text('No users found', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      );

  Widget _field(TextEditingController c, String label, IconData icon,
      {bool required = false, TextInputType? keyboard}) {
    return TextFormField(
      controller: c,
      keyboardType: keyboard,
      decoration: _dec(label).copyWith(prefixIcon: Icon(icon, size: 18, color: _muted)),
      validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
    );
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFf8fafc),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _primary, width: 1.5)),
      );
}
