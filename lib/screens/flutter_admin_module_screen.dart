import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

/// Reusable admin module screen: form on top + list below, success dialog, no full-page reload.
class FlutterAdminModuleScreen extends StatefulWidget {
  final String title;
  final String endpoint; // e.g. https://schoolsmirror.com/flutter_classes.php
  final String? token;
  final List<ModuleField> fields;
  final String idKey;
  final String titleKey; // field used as row title
  final String? subtitleKey;
  final IconData icon;

  const FlutterAdminModuleScreen({
    super.key,
    required this.title,
    required this.endpoint,
    required this.fields,
    this.token,
    this.idKey = 'id',
    this.titleKey = 'name',
    this.subtitleKey,
    this.icon = Icons.list_alt,
  });

  @override
  State<FlutterAdminModuleScreen> createState() => _FlutterAdminModuleScreenState();
}

class ModuleField {
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<DropdownOption>? options; // for dropdown; can be filled from API
  final String? optionsFrom; // 'classes' | 'sessions' | 'terms' | 'departments'
  final int maxLines;
  final int? minLength;

  const ModuleField({
    required this.key,
    required this.label,
    this.type = FieldType.text,
    this.required = true,
    this.options,
    this.optionsFrom,
    this.maxLines = 1,
    this.minLength,
  });
}

enum FieldType { text, multiline, number, dropdown, date }

class DropdownOption {
  final String value;
  final String label;
  const DropdownOption(this.value, this.label);
}

class _FlutterAdminModuleScreenState extends State<FlutterAdminModuleScreen> {
  static const _primary = Color(0xFF4361ee);
  static const _violet = Color(0xFF7c3aed);
  static const _bg = Color(0xFFf0f4ff);
  static const _dark = Color(0xFF0f172a);
  static const _muted = Color(0xFF64748b);
  static const _border = Color(0xFFe2e8f0);
  static const _green = Color(0xFF10b981);
  static const _rose = Color(0xFFef4444);

  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, String?> _dropdown = {};
  List<dynamic> _items = [];
  Map<String, List<DropdownOption>> _apiOptions = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _editId;
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      if (f.type != FieldType.dropdown) {
        _ctrls[f.key] = TextEditingController();
      }
    }
    _load();
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<String?> _token() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) return widget.token!.trim();
    try {
      await ApiClient.loadToken();
      if (ApiClient.token != null && ApiClient.token!.isNotEmpty) return ApiClient.token!.trim();
    } catch (_) {}
    try {
      final p = await SharedPreferences.getInstance();
      return p.getString('auth_token') ?? p.getString('token');
    } catch (_) {}
    return null;
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
      final uri = Uri.parse(widget.endpoint).replace(queryParameters: {
        'token': token,
        'action': 'list',
        'page': '$page',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (data['success'] != true) throw Exception(data['message'] ?? 'Load failed');
      final d = data['data'] ?? {};
      final items = List.from(d['items'] ?? []);
      final opts = <String, List<DropdownOption>>{};
      void mapOpts(String key, String idK, String nameK) {
        final list = d[key];
        if (list is List) {
          opts[key] = list
              .map((e) => DropdownOption('${e[idK]}', '${e[nameK]}'))
              .toList();
        }
      }
      mapOpts('classes', 'class_id', 'class_name');
      mapOpts('sessions', 'id', 'session_name');
      mapOpts('terms', 'id', 'term_name');
      mapOpts('departments', 'id', 'department_name');
      if (!mounted) return;
      setState(() {
        _items = items;
        _apiOptions = opts;
        _totalPages = d['total_pages'] ?? 1;
        _page = d['page'] ?? page;
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
    for (final c in _ctrls.values) {
      c.clear();
    }
    for (final f in widget.fields) {
      if (f.type == FieldType.dropdown) _dropdown[f.key] = null;
    }
    setState(() => _editId = null);
  }

  void _fillEdit(Map item) {
    setState(() {
      _editId = '${item[widget.idKey]}';
      for (final f in widget.fields) {
        final v = item[f.key];
        if (f.type == FieldType.dropdown) {
          _dropdown[f.key] = v == null ? null : '$v';
        } else {
          _ctrls[f.key]?.text = v?.toString() ?? '';
        }
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    for (final f in widget.fields) {
      if (f.type == FieldType.dropdown && f.required) {
        if (_dropdown[f.key] == null || _dropdown[f.key]!.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Select ${f.label}'), backgroundColor: _rose),
          );
          return;
        }
      }
    }
    setState(() => _saving = true);
    try {
      final token = await _token();
      if (token == null) throw Exception('Missing token');
      final body = <String, String>{
        'token': token,
        'action': _editId == null ? 'add' : 'update',
      };
      if (_editId != null) {
        body[widget.idKey] = _editId!;
        body['id'] = _editId!;
        body['class_id'] = _editId!; // harmless extras for different APIs
        body['subject_id'] = _editId!;
      }
      for (final f in widget.fields) {
        if (f.type == FieldType.dropdown) {
          body[f.key] = _dropdown[f.key] ?? '';
        } else {
          body[f.key] = _ctrls[f.key]?.text.trim() ?? '';
        }
      }
      final uri = Uri.parse(widget.endpoint).replace(queryParameters: {'token': token});
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: body,
      ).timeout(const Duration(seconds: 25));
      final data = jsonDecode(res.body);
      if (data['success'] != true) throw Exception(data['message'] ?? 'Failed');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: _green),
              const SizedBox(width: 8),
              Text(_editId == null ? 'Success' : 'Updated'),
            ],
          ),
          content: Text('${data['message']}'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: _primary, foregroundColor: Colors.white),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      _clearForm();
      await _load(page: 1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: _rose));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Map item) async {
    final id = '${item[widget.idKey]}';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete?'),
        content: Text('Delete "${item[widget.titleKey]}" permanently?'),
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
      final uri = Uri.parse(widget.endpoint).replace(queryParameters: {'token': token});
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'token': token,
          'action': 'delete',
          'id': id,
          widget.idKey: id,
          'class_id': id,
          'subject_id': id,
        },
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) throw Exception(data['message']);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${data['message']}'), backgroundColor: _green),
      );
      _load(page: _page);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: _rose));
    }
  }

  List<DropdownOption> _optsFor(ModuleField f) {
    if (f.options != null) return f.options!;
    if (f.optionsFrom != null) return _apiOptions[f.optionsFrom!] ?? [];
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: _dark,
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(onPressed: () => _load(page: _page), icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _formCard(),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(widget.icon, color: _primary, size: 20),
              const SizedBox(width: 8),
              Text('${widget.title} list', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              Text('${_items.length} shown', style: const TextStyle(color: _muted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: _rose))
          else if (_items.isEmpty)
            _empty()
          else ...[
            ..._items.map((e) => _row(Map<String, dynamic>.from(e))),
            if (_totalPages > 1) _pager(),
          ],
        ],
      ),
    );
  }

  Widget _formCard() {
    final editing = _editId != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: editing ? const [Color(0xFFf59e0b), Color(0xFFd97706)] : const [_primary, _violet],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                editing ? 'Edit ${widget.title}' : 'Add ${widget.title}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 14),
            for (final f in widget.fields) ...[
              _buildField(f),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                if (editing)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _clearForm,
                      child: const Text('Cancel'),
                    ),
                  ),
                if (editing) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 46,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(editing ? Icons.save : Icons.add),
                      label: Text(_saving ? 'Saving...' : (editing ? 'Update' : 'Add')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(ModuleField f) {
    if (f.type == FieldType.dropdown) {
      final opts = _optsFor(f);
      return DropdownButtonFormField<String>(
        value: _dropdown[f.key],
        isExpanded: true,
        decoration: _dec(f.label),
        items: opts.map((o) => DropdownMenuItem(value: o.value, child: Text(o.label))).toList(),
        onChanged: (v) => setState(() => _dropdown[f.key] = v),
        validator: f.required ? (v) => (v == null || v.isEmpty) ? 'Required' : null : null,
      );
    }
    return TextFormField(
      controller: _ctrls[f.key],
      maxLines: f.type == FieldType.multiline ? f.maxLines : 1,
      keyboardType: f.type == FieldType.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : f.type == FieldType.date
              ? TextInputType.datetime
              : TextInputType.text,
      decoration: _dec(f.label + (f.type == FieldType.date ? ' (YYYY-MM-DD)' : '')),
      validator: (v) {
        if (f.required && (v == null || v.trim().isEmpty)) return 'Required';
        if (f.minLength != null && (v?.trim().length ?? 0) < f.minLength!) {
          return 'Min ${f.minLength} characters';
        }
        return null;
      },
      onTap: f.type == FieldType.date
          ? () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(now.year - 1),
                lastDate: DateTime(now.year + 5),
              );
              if (d != null) {
                _ctrls[f.key]?.text =
                    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
              }
            }
          : null,
      readOnly: f.type == FieldType.date,
    );
  }

  Widget _row(Map<String, dynamic> item) {
    final title = '${item[widget.titleKey] ?? ''}';
    final sub = widget.subtitleKey != null ? '${item[widget.subtitleKey] ?? ''}' : '';
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
            backgroundColor: _primary.withOpacity(0.12),
            child: Icon(widget.icon, color: _primary, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: _dark)),
                if (sub.isNotEmpty) Text(sub, style: const TextStyle(fontSize: 12, color: _muted), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: _primary),
            onPressed: () => _fillEdit(item),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: _rose),
            onPressed: () => _delete(item),
          ),
        ],
      ),
    );
  }

  Widget _pager() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: _page > 1 ? () => _load(page: _page - 1) : null, icon: const Icon(Icons.chevron_left)),
          Text('Page $_page / $_totalPages', style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(onPressed: _page < _totalPages ? () => _load(page: _page + 1) : null, icon: const Icon(Icons.chevron_right)),
        ],
      );

  Widget _empty() => Container(
        padding: const EdgeInsets.all(28),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: const Text('No records yet. Add the first one above.', style: TextStyle(color: _muted)),
      );

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
