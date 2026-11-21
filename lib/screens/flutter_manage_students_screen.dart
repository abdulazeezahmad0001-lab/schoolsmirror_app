import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

class FlutterManageStudentsScreen extends StatefulWidget {
  final String? token;
  final String initialRoleFilter;
  const FlutterManageStudentsScreen({super.key, this.token, this.initialRoleFilter = 'student'});

  @override
  State<FlutterManageStudentsScreen> createState() => _FlutterManageStudentsScreenState();
}

class _FlutterManageStudentsScreenState extends State<FlutterManageStudentsScreen> {
  static const _primary = Color(0xFF4361ee);
  static const _violet = Color(0xFF7c3aed);
  static const _bg = Color(0xFFf0f4ff);
  static const _dark = Color(0xFF0f172a);
  static const _muted = Color(0xFF64748b);
  static const _border = Color(0xFFe2e8f0);
  static const _green = Color(0xFF10b981);
  static const _rose = Color(0xFFef4444);

  final _searchCtrl = TextEditingController();
  String _roleFilter = 'student';
  
  List<dynamic> _users = [];
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _roleFilter = widget.initialRoleFilter;
    _load();
  }

  Future<String?> _getToken() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) return widget.token!.trim();
    try { await ApiClient.loadToken(); if (ApiClient.token != null) return ApiClient.token!.trim(); } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  Future<void> _load({int page = 1}) async {
    setState(() { _loading = true; _error = null; _page = page; });
    try {
      final token = await _getToken();
      if (token == null) throw Exception('Session expired. Log in again.');

      // Using the exact PHP logic
      final uri = Uri.parse('https://schoolsmirror.com/flutter_manage_students.php').replace(queryParameters: {
        'token': token, 
        'action': 'list', 
        'role_filter': _roleFilter == 'all' ? '' : _roleFilter,
        'search': _searchCtrl.text.trim(), 
        'page': '$page', 
        'limit': '15',
      });

      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);

      if (data['success'] != true) throw Exception(data['message'] ?? 'Failed to load');

      if (!mounted) return;
      setState(() {
        _users = data['data']?['users'] as List? ?? [];
        _totalPages = data['data']?['total_pages'] as int? ?? 1;
        _total = data['data']?['total'] as int? ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _delete(dynamic user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User?'),
        content: Text('Permanently delete ${user['fullname']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _rose), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final token = await _getToken();
      final res = await http.post(Uri.parse('https://schoolsmirror.com/flutter_manage_students.php'), body: {'token': token, 'action': 'delete', 'user_id': '${user['user_id']}'});
      final data = jsonDecode(res.body);
      if (data['success'] == true) _load(page: _page);
      else throw Exception(data['message']);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: _rose));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white, foregroundColor: _dark, elevation: 0,
        title: const Text('Manage Users', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [IconButton(onPressed: () => _load(page: _page), icon: const Icon(Icons.refresh))],
      ),
      body: Column(
        children: [
          // Header & Search
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _border))),
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl, onSubmitted: (_) => _load(page: 1),
                  decoration: InputDecoration(
                    hintText: 'Search name, ID, or admission...', prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: () => _load(page: 1)),
                    filled: true, fillColor: const Color(0xFFf8fafc),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                // Filter Tabs
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip('All', 'all'),
                      _filterChip('Students', 'student'),
                      _filterChip('Teachers', 'teacher'),
                      _filterChip('Subadmins', 'subadmin'),
                    ],
                  ),
                )
              ],
            ),
          ),
          
          // List
          Expanded(
            child: _loading 
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                ? Center(child: Text(_error!, style: const TextStyle(color: _rose)))
                : _users.isEmpty
                  ? const Center(child: Text('No users found.', style: TextStyle(color: _muted)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final u = _users[index];
                        return _userCard(u);
                      },
                    ),
          ),
          
          // Pagination
          if (_totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: Colors.white,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(onPressed: _page > 1 ? () => _load(page: _page - 1) : null, icon: const Icon(Icons.chevron_left)),
                  Text('Page $_page of $_totalPages', style: const TextStyle(fontWeight: FontWeight.bold)),
                  IconButton(onPressed: _page < _totalPages ? () => _load(page: _page + 1) : null, icon: const Icon(Icons.chevron_right)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _roleFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        selectedColor: _primary,
        labelStyle: TextStyle(color: selected ? Colors.white : _dark, fontWeight: FontWeight.bold),
        onSelected: (val) {
          if (val) {
            setState(() => _roleFilter = value);
            _load(page: 1);
          }
        },
      ),
    );
  }

  Widget _userCard(dynamic u) {
    final status = (u['status'] ?? 'active').toString().toLowerCase();
    final isActive = status == 'active';
    final img = '${u['image_url'] ?? ''}';
    final role = '${u['role'] ?? ''}'.toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16), 
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: _primary.withOpacity(0.1),
            backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
            child: img.isEmpty ? const Icon(Icons.person, color: _primary) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${u['fullname']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: _dark)),
                const SizedBox(height: 4),
                Text('ID: ${u['idnumber']} • ${u['class_name']}', style: const TextStyle(fontSize: 12, color: _muted)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: _violet.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(role, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _violet)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: isActive ? _green.withOpacity(0.1) : Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(isActive ? 'ACTIVE' : 'PENDING', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isActive ? _green : Colors.orange)),
                    ),
                  ],
                )
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: _rose),
            onPressed: () => _delete(u),
          )
        ],
      ),
    );
  }
}