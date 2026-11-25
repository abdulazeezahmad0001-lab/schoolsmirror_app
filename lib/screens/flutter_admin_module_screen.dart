// flutter_admin_module_screen.dart
// Reusable admin module screen, redesigned. Same public API as before (FlutterAdminModuleScreen, ModuleField,
// FieldType, DropdownOption) so admin_home.dart keeps working without changes.
//
//  • Every section gets its OWN header (colour, icon, pattern, wording). It is picked automatically from the
//    endpoint (flutter_classes -> Class, flutter_next_term -> Next Term ...) or passed with `theme:`.
//  • List first: search bar, animated cards with avatar + chips, edit / delete menu, pagination pill.
//  • Add / edit happens in a bottom sheet with inline errors (no more full-page form).
//  • Fixes "FormatException: Unexpected character": every reply is checked before it is decoded, both URL forms
//    (extensionless and .php) are tried, and the real cause (HTTP status + start of the reply) is shown.
//
// pubspec.yaml needs:  http, shared_preferences

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// ═════════════════════════════════════════════════════════════════════════════
//  PUBLIC API (unchanged)
// ═════════════════════════════════════════════════════════════════════════════
class FlutterAdminModuleScreen extends StatefulWidget {
  final String title;
  final String endpoint; // e.g. https://schoolsmirror.com/flutter_classes
  final String? token;
  final List<ModuleField> fields;
  final String idKey;
  final String titleKey; // field used as row title
  final String? subtitleKey;
  final IconData icon;
  final ModuleTheme? theme; // optional: pick one of ModuleTheme.* yourself (default: detected from the endpoint)

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
    this.theme,
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

// ═════════════════════════════════════════════════════════════════════════════
//  THEMES: one look per section
// ═════════════════════════════════════════════════════════════════════════════
enum ModulePattern { dots, rings, ruled, diagonal, waves, grid, plus, blocks }

enum ModuleAvatar { icon, title, key }

class ModuleTheme {
  final Color c1, c2; // header gradient
  final IconData icon;
  final ModulePattern pattern;
  final String singular, plural, tagline, emptyTitle, emptyHint;
  final ModuleAvatar avatar;
  final String? avatarKey;

  const ModuleTheme({
    required this.c1,
    required this.c2,
    required this.icon,
    required this.pattern,
    required this.singular,
    required this.plural,
    required this.tagline,
    required this.emptyTitle,
    required this.emptyHint,
    this.avatar = ModuleAvatar.icon,
    this.avatarKey,
  });

  // indigo + dots
  static const classes = ModuleTheme(
    c1: Color(0xFF3730A3), c2: Color(0xFF6366F1), icon: Icons.meeting_room_rounded, pattern: ModulePattern.dots,
    singular: 'class', plural: 'classes', tagline: 'Set up the classrooms students are placed in.',
    emptyTitle: 'No classes yet', emptyHint: 'Create your first class, e.g. JSS 1 or Primary 3.', avatar: ModuleAvatar.title,
  );
  // teal + grid
  static const departments = ModuleTheme(
    c1: Color(0xFF0F766E), c2: Color(0xFF14B8A6), icon: Icons.account_tree_rounded, pattern: ModulePattern.grid,
    singular: 'department', plural: 'departments', tagline: 'Group senior students into Science, Art and Commercial.',
    emptyTitle: 'No departments yet', emptyHint: 'Add departments such as Science or Arts.',
  );
  // gold + rings
  static const sessions = ModuleTheme(
    c1: Color(0xFFB45309), c2: Color(0xFFF59E0B), icon: Icons.calendar_month_rounded, pattern: ModulePattern.rings,
    singular: 'session', plural: 'sessions', tagline: 'Academic years your results and fees are tied to.',
    emptyTitle: 'No sessions yet', emptyHint: 'Add a session like 2026/2027.',
  );
  // rose + waves
  static const terms = ModuleTheme(
    c1: Color(0xFFBE123C), c2: Color(0xFFFB7185), icon: Icons.timelapse_rounded, pattern: ModulePattern.waves,
    singular: 'term', plural: 'terms', tagline: 'First, second and third term of every session.',
    emptyTitle: 'No terms yet', emptyHint: 'Add First Term, Second Term and Third Term.',
  );
  // sky + diagonal
  static const notices = ModuleTheme(
    c1: Color(0xFF0369A1), c2: Color(0xFF38BDF8), icon: Icons.campaign_rounded, pattern: ModulePattern.diagonal,
    singular: 'notice', plural: 'notices', tagline: 'Announcements for parents, students and staff.',
    emptyTitle: 'No notices yet', emptyHint: 'Post an announcement for a class.',
  );
  // green + plus
  static const grades = ModuleTheme(
    c1: Color(0xFF15803D), c2: Color(0xFF4ADE80), icon: Icons.military_tech_rounded, pattern: ModulePattern.plus,
    singular: 'grade', plural: 'grades', tagline: 'Score ranges, grade points and what each grade means.',
    emptyTitle: 'No grades yet', emptyHint: 'Add a grading scale such as 70 - 100 = A.', avatar: ModuleAvatar.key, avatarKey: 'grade',
  );
  // purple + blocks
  static const nextTerm = ModuleTheme(
    c1: Color(0xFF7E22CE), c2: Color(0xFFD946EF), icon: Icons.event_available_rounded, pattern: ModulePattern.blocks,
    singular: 'date', plural: 'dates', tagline: 'When the next term begins, shown on report cards.',
    emptyTitle: 'No dates yet', emptyHint: 'Set the resumption date for the next term.',
  );
  // orange + ruled lines
  static const subjects = ModuleTheme(
    c1: Color(0xFFC2410C), c2: Color(0xFFFB923C), icon: Icons.menu_book_rounded, pattern: ModulePattern.ruled,
    singular: 'subject', plural: 'subjects', tagline: 'Subjects offered in each class and department.',
    emptyTitle: 'No subjects yet', emptyHint: 'Add subjects such as Mathematics and English.', avatar: ModuleAvatar.title,
  );
  static const fallback = ModuleTheme(
    c1: Color(0xFF4338CA), c2: Color(0xFF8B5CF6), icon: Icons.dashboard_customize_rounded, pattern: ModulePattern.dots,
    singular: 'item', plural: 'items', tagline: 'Manage this section of your school.',
    emptyTitle: 'Nothing here yet', emptyHint: 'Tap the button below to add the first one.',
  );

  /// picks a theme from the endpoint name, then from the title
  static ModuleTheme resolve(String endpoint, String title) {
    final s = '${endpoint.toLowerCase()} ${title.toLowerCase()}';
    if (s.contains('next_term') || s.contains('next-term') || s.contains('next term')) return nextTerm;
    if (s.contains('flutter_classes') || s.contains('class')) return classes;
    if (s.contains('department')) return departments;
    if (s.contains('session')) return sessions;
    if (s.contains('flutter_terms') || s.contains('term')) return terms;
    if (s.contains('notice')) return notices;
    if (s.contains('grade')) return grades;
    if (s.contains('subject')) return subjects;
    return fallback;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ═════════════════════════════════════════════════════════════════════════════
const _ink = Color(0xFF111827);
const _muted = Color(0xFF6B7280);
const _pageBg = Color(0xFFF6F7FB);
const _red = Color(0xFFE11D48);
const _green = Color(0xFF059669);

class _FlutterAdminModuleScreenState extends State<FlutterAdminModuleScreen> {
  late final ModuleTheme _t = widget.theme ?? ModuleTheme.resolve(widget.endpoint, widget.title);
  late final List<String> _urls = _candidateUrls(widget.endpoint);
  int _urlIdx = 0;

  List<Map<String, dynamic>> _items = [];
  Map<String, List<DropdownOption>> _apiOptions = {};
  bool _loading = true;
  String? _error;
  int _page = 1;
  int _totalPages = 1;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _q = '';
  bool _collapsed = false;
  static const double _heroHeight = 262;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final c = _scroll.hasClients && _scroll.offset > _heroHeight - kToolbarHeight - 56;
      if (c != _collapsed) setState(() => _collapsed = c);
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ───────────────────────────── networking ─────────────────────────────
  static List<String> _candidateUrls(String e) {
    final u = e.trim();
    if (u.endsWith('.php')) return [u.substring(0, u.length - 4), u];
    return [u, '$u.php'];
  }

  Future<String?> _token() async {
    if (widget.token != null && widget.token!.trim().isNotEmpty) return widget.token!.trim();
    try {
      await ApiClient.loadToken();
      if (ApiClient.token != null) return ApiClient.token!.trim();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? prefs.getString('token');
  }

  static Map<String, dynamic>? _tryJson(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return null;
  }

  static String _explain(String body, int status) {
    var s = body.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.length > 120) s = '${s.substring(0, 120)}...';
    return 'The server sent an unexpected response (HTTP $status${s.isEmpty ? ', empty reply' : ': $s'}).';
  }

  /// tries the endpoint with and without ".php"; always returns decoded JSON or throws a readable Exception
  Future<Map<String, dynamic>> _call(Map<String, String> fields, {required bool post}) async {
    String? problem;
    var answered = false;
    for (var k = 0; k < _urls.length; k++) {
      final idx = (_urlIdx + k) % _urls.length;
      try {
        final base = Uri.parse(_urls[idx]);
        final http.Response res;
        if (post) {
          final uri = base.replace(queryParameters: {'token': fields['token'] ?? '', 'action': fields['action'] ?? ''});
          res = await http
              .post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: fields)
              .timeout(const Duration(seconds: 25));
        } else {
          res = await http.get(base.replace(queryParameters: fields)).timeout(const Duration(seconds: 20));
        }
        answered = true;
        final parsed = _tryJson(res.body);
        if (parsed != null) {
          _urlIdx = idx;
          return parsed;
        }
        problem = _explain(res.body, res.statusCode);
      } catch (_) {
        // network problem on this address: try the other one
      }
    }
    throw Exception(answered ? (problem ?? 'The server sent an unexpected response.') : 'No internet connection. Check your network and try again.');
  }

  String _clean(Object e) => '$e'.replaceFirst('Exception: ', '');

  // ───────────────────────────── data ─────────────────────────────
  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      final token = await _token();
      if (token == null) throw Exception('Your session has expired. Please log out and log back in.');
      final data = await _call({'token': token, 'action': 'list', 'page': '$page'}, post: false);
      if (data['success'] != true) throw Exception('${data['message'] ?? 'Could not load the list.'}');
      final d = data['data'] is Map ? Map<String, dynamic>.from(data['data'] as Map) : <String, dynamic>{};
      final items = (d['items'] is List ? d['items'] as List : []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      final opts = <String, List<DropdownOption>>{};
      void mapOpts(String key, String idK, String nameK) {
        final list = d[key];
        if (list is List) {
          opts[key] = list.whereType<Map>().map((e) => DropdownOption('${e[idK]}', '${e[nameK]}')).toList();
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
        final tp = int.tryParse('${d['total_pages']}') ?? 1;
        _totalPages = tp < 1 ? 1 : tp;
        _page = int.tryParse('${d['page']}') ?? page;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _clean(e);
        _loading = false;
      });
    }
  }

  List<DropdownOption> _optsFor(ModuleField f) {
    if (f.options != null) return f.options!;
    if (f.optionsFrom != null) return _apiOptions[f.optionsFrom!] ?? [];
    return [];
  }

  Future<String> _save(Map<String, String> values, Map<String, dynamic>? item) async {
    final token = await _token();
    if (token == null) throw Exception('Your session has expired. Please log out and log back in.');
    final editId = item == null ? null : '${item[widget.idKey]}';
    final body = <String, String>{'token': token, 'action': editId == null ? 'add' : 'update'};
    if (editId != null) {
      body[widget.idKey] = editId;
      body['id'] = editId;
      body['class_id'] = editId; // harmless extras for different APIs
      body['subject_id'] = editId;
    }
    body.addAll(values); // dropdown / field values win over the extras above
    final d = await _call(body, post: true);
    if (d['success'] != true) throw Exception('${d['message'] ?? 'Could not save.'}');
    return '${d['message'] ?? 'Saved'}';
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = '${item[widget.idKey]}';
    final name = '${item[widget.titleKey] ?? ''}';
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        icon: Container(width: 58, height: 58, decoration: BoxDecoration(shape: BoxShape.circle, color: _red.withAlpha(24)), child: const Icon(Icons.delete_outline_rounded, color: _red, size: 30)),
        title: Text('Delete ${_t.singular}?', style: const TextStyle(fontWeight: FontWeight.w800, color: _ink)),
        content: Text(name.isEmpty ? 'This cannot be undone.' : '"$name" will be removed permanently. This cannot be undone.', textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.4)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(backgroundColor: _red), child: const Text('Delete')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final token = await _token();
      if (token == null) throw Exception('Your session has expired. Please log out and log back in.');
      final d = await _call({'token': token, 'action': 'delete', 'id': id, widget.idKey: id, 'class_id': id, 'subject_id': id}, post: true);
      if (d['success'] != true) throw Exception('${d['message'] ?? 'Could not delete.'}');
      if (!mounted) return;
      _toast('${d['message'] ?? 'Deleted'}');
      _load(page: (_items.length == 1 && _page > 1) ? _page - 1 : _page);
    } catch (e) {
      if (mounted) _toast(_clean(e), ok: false);
    }
  }

  Future<void> _openForm([Map<String, dynamic>? item]) async {
    HapticFeedback.selectionClick();
    final msg = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FormSheet(
        theme: _t,
        title: item == null ? 'Add ${_t.singular}' : 'Edit ${_t.singular}',
        fields: widget.fields,
        optionsFor: _optsFor,
        item: item,
        onSubmit: (values) => _save(values, item),
      ),
    );
    if (msg != null && mounted) {
      _toast(msg);
      _load(page: item == null ? 1 : _page);
    }
  }

  void _toast(String msg, {bool ok = true}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        backgroundColor: ok ? _ink : _red,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(children: [
          Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded, color: ok ? const Color(0xFF34D399) : Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      ));
  }

  // ───────────────────────────── helpers for rows ─────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    if (_q.isEmpty) return _items;
    final q = _q.toLowerCase();
    return _items.where((it) => it.values.any((v) => '$v'.toLowerCase().contains(q))).toList();
  }

  List<MapEntry<String, String>> _chips(Map<String, dynamic> item) {
    final out = <MapEntry<String, String>>[];
    for (final f in widget.fields) {
      if (f.key == widget.titleKey || f.key == widget.subtitleKey) continue;
      dynamic v = item[f.key];
      if (f.type == FieldType.dropdown) {
        final base = f.key.endsWith('_id') ? f.key.substring(0, f.key.length - 3) : f.key;
        final named = item['${base}_name'];
        if (named != null && '$named'.trim().isNotEmpty) {
          v = named;
        } else {
          final hit = _optsFor(f).where((o) => o.value == '$v');
          if (hit.isNotEmpty) v = hit.first.label;
        }
      }
      var s = v == null ? '' : '$v'.trim();
      if (s.isEmpty || s == 'null') continue;
      if (s.length > 30) s = '${s.substring(0, 30)}...';
      out.add(MapEntry(f.label, s));
    }
    return out.take(4).toList();
  }

  String _avatarText(Map<String, dynamic> item) {
    String src = '';
    if (_t.avatar == ModuleAvatar.key && _t.avatarKey != null) src = '${item[_t.avatarKey] ?? ''}';
    if (src.isEmpty && _t.avatar != ModuleAvatar.icon) src = '${item[widget.titleKey] ?? ''}';
    src = src.replaceAll(RegExp(r'\s+'), '');
    if (src.isEmpty) return '';
    return src.substring(0, math.min(src.length, 3)).toUpperCase();
  }

  // ───────────────────────────── build ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Scaffold(
      backgroundColor: _pageBg,
      floatingActionButton: _fab(),
      body: RefreshIndicator(
        color: _t.c1,
        edgeOffset: _heroHeight - 60,
        onRefresh: () => _load(page: _page),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: _heroHeight,
              backgroundColor: _t.c1,
              foregroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              title: AnimatedOpacity(opacity: _collapsed ? 1 : 0, duration: const Duration(milliseconds: 180), child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w800))),
              actions: [IconButton(onPressed: _loading ? null : () => _load(page: _page), icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh')],
              flexibleSpace: FlexibleSpaceBar(collapseMode: CollapseMode.parallax, background: _hero()),
            ),
            SliverToBoxAdapter(child: _searchBar()),
            if (_loading)
              SliverList(delegate: SliverChildBuilderDelegate((c, i) => const _SkeletonCard(), childCount: 5))
            else if (_error != null)
              SliverToBoxAdapter(child: _errorCard())
            else if (_items.isEmpty)
              SliverToBoxAdapter(child: _emptyCard())
            else if (list.isEmpty)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No match for your search.', style: TextStyle(color: _muted)))))
            else
              SliverList(delegate: SliverChildBuilderDelegate((c, i) => _animated(i, _card(list[i])), childCount: list.length)),
            if (!_loading && _error == null && _totalPages > 1) SliverToBoxAdapter(child: _pager()),
            const SliverToBoxAdapter(child: SizedBox(height: 110)),
          ],
        ),
      ),
    );
  }

  Widget _fab() {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: [_t.c1, _t.c2]), borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: _t.c1.withAlpha(110), blurRadius: 18, offset: const Offset(0, 8))]),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openForm(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Text('Add ${_t.singular}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            ]),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── hero ─────────────────────────────
  Widget _hero() {
    final count = _loading ? '…' : '${_items.length}';
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_t.c1, _t.c2])),
      child: Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _PatternPainter(_t.pattern))),
        Positioned(right: -22, top: 36, child: Transform.rotate(angle: -.2, child: Icon(_t.icon, size: 168, color: Colors.white.withAlpha(34)))),
        Positioned(
          left: 22,
          right: 22,
          bottom: 50,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withAlpha(70))),
              child: Icon(_t.icon, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 14),
            Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.8, height: 1.05)),
            const SizedBox(height: 6),
            Text(_t.tagline, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withAlpha(220), fontSize: 13.5, height: 1.35)),
            const SizedBox(height: 14),
            Row(children: [
              _glass(Icons.layers_rounded, '$count ${_t.plural}'),
              if (_totalPages > 1) ...[const SizedBox(width: 8), _glass(Icons.auto_stories_rounded, 'Page $_page of $_totalPages')],
            ]),
          ]),
        ),
        // rounded "sheet" edge: the page colour rises into the header
        Positioned(left: 0, right: 0, bottom: -1, height: 30, child: Container(decoration: const BoxDecoration(color: _pageBg, borderRadius: BorderRadius.vertical(top: Radius.circular(30))))),
      ]),
    );
  }

  Widget _glass(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withAlpha(60))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
        ]),
      );

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 12),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: _ink.withAlpha(12), blurRadius: 16, offset: const Offset(0, 6))]),
        child: TextField(
          controller: _search,
          onChanged: (v) => setState(() => _q = v.trim()),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search ${_t.plural}',
            hintStyle: const TextStyle(color: _muted),
            prefixIcon: Icon(Icons.search_rounded, color: _t.c1),
            suffixIcon: _q.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => setState(() {
                  _search.clear();
                  _q = '';
                })),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }

  Widget _animated(int i, Widget child) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 280 + math.min(i, 8) * 50),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: c)),
        child: child,
      );

  // ───────────────────────────── cards ─────────────────────────────
  Widget _card(Map<String, dynamic> item) {
    final title = '${item[widget.titleKey] ?? ''}';
    final sub = widget.subtitleKey != null ? '${item[widget.subtitleKey] ?? ''}' : '';
    final chips = _chips(item);
    final av = _avatarText(item);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        elevation: 0,
        shadowColor: _ink,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => _openForm(item),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFEDEFF5)), boxShadow: [BoxShadow(color: _ink.withAlpha(10), blurRadius: 14, offset: const Offset(0, 6))]),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 50,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_t.c1, _t.c2]), borderRadius: BorderRadius.circular(16)),
                child: av.isEmpty ? Icon(_t.icon, color: Colors.white, size: 24) : Text(av, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: av.length > 2 ? 14 : 17, letterSpacing: .2)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title.isEmpty ? '—' : title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: _ink, height: 1.2, letterSpacing: -.2)),
                  if (sub.isNotEmpty && sub != 'null') ...[
                    const SizedBox(height: 4),
                    Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _muted, height: 1.35)),
                  ],
                  if (chips.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final c in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(color: _t.c1.withAlpha(20), borderRadius: BorderRadius.circular(10)),
                          child: RichText(text: TextSpan(children: [
                            TextSpan(text: '${c.key}  ', style: TextStyle(fontSize: 10.5, color: _t.c1.withAlpha(190), fontWeight: FontWeight.w700, letterSpacing: .2)),
                            TextSpan(text: c.value, style: TextStyle(fontSize: 12, color: _t.c1, fontWeight: FontWeight.w800)),
                          ])),
                        ),
                    ]),
                  ],
                ]),
              ),
              PopupMenuButton<String>(
                tooltip: 'Options',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                icon: const Icon(Icons.more_vert_rounded, color: _muted),
                onSelected: (v) => v == 'edit' ? _openForm(item) : _delete(item),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 18), SizedBox(width: 10), Text('Edit')])),
                  PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline_rounded, size: 18, color: _red), SizedBox(width: 10), Text('Delete', style: TextStyle(color: _red))])),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _emptyCard() => Padding(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
        child: Column(children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_t.c1.withAlpha(30), _t.c2.withAlpha(60)])),
            child: Icon(_t.icon, size: 54, color: _t.c1),
          ),
          const SizedBox(height: 20),
          Text(_t.emptyTitle, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink, letterSpacing: -.3)),
          const SizedBox(height: 8),
          Text(_t.emptyHint, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.45, fontSize: 14)),
        ]),
      );

  Widget _errorCard() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: _ink.withAlpha(12), blurRadius: 18, offset: const Offset(0, 8))]),
          child: Column(children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(shape: BoxShape.circle, color: _red.withAlpha(22)), child: const Icon(Icons.cloud_off_rounded, color: _red, size: 32)),
            const SizedBox(height: 14),
            const Text("Couldn't load the list", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
            const SizedBox(height: 8),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: _muted, fontSize: 13, height: 1.45)),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: () => _load(page: _page), icon: const Icon(Icons.refresh_rounded), label: const Text('Try again'), style: FilledButton.styleFrom(backgroundColor: _t.c1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
          ]),
        ),
      );

  Widget _pager() {
    Widget btn(IconData i, bool on, VoidCallback f) => Material(
          color: on ? _t.c1 : const Color(0xFFE5E7EB),
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: on ? f : null, child: Padding(padding: const EdgeInsets.all(11), child: Icon(i, color: on ? Colors.white : _muted, size: 20))),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        btn(Icons.chevron_left_rounded, _page > 1, () => _load(page: _page - 1)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), border: Border.all(color: const Color(0xFFEDEFF5))),
          child: Text('Page $_page of $_totalPages', style: TextStyle(fontWeight: FontWeight.w800, color: _t.c1, fontSize: 13)),
        ),
        btn(Icons.chevron_right_rounded, _page < _totalPages, () => _load(page: _page + 1)),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  ADD / EDIT SHEET
// ═════════════════════════════════════════════════════════════════════════════
class _FormSheet extends StatefulWidget {
  final ModuleTheme theme;
  final String title;
  final List<ModuleField> fields;
  final List<DropdownOption> Function(ModuleField) optionsFor;
  final Map<String, dynamic>? item;
  final Future<String> Function(Map<String, String> values) onSubmit;

  const _FormSheet({required this.theme, required this.title, required this.fields, required this.optionsFor, required this.item, required this.onSubmit});

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final _key = GlobalKey<FormState>();
  final Map<String, TextEditingController> _c = {};
  final Map<String, String?> _dd = {};
  bool _saving = false;
  String? _error;

  ModuleTheme get _t => widget.theme;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final raw = widget.item?[f.key];
      final text = (raw == null || '$raw' == 'null') ? '' : '$raw';
      if (f.type == FieldType.dropdown) {
        _dd[f.key] = text.isEmpty ? null : text;
      } else {
        _c[f.key] = TextEditingController(text: text);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  IconData _iconFor(ModuleField f) {
    final k = f.key.toLowerCase();
    if (f.type == FieldType.date || k.contains('date')) return Icons.event_rounded;
    if (k.contains('class')) return Icons.meeting_room_rounded;
    if (k.contains('session')) return Icons.calendar_month_rounded;
    if (k.contains('term')) return Icons.timelapse_rounded;
    if (k.contains('department')) return Icons.account_tree_rounded;
    if (k.contains('subject')) return Icons.menu_book_rounded;
    if (k.contains('grade')) return Icons.military_tech_rounded;
    if (k.contains('score') || k.contains('point')) return Icons.pin_rounded;
    if (k.contains('status')) return Icons.toggle_on_rounded;
    if (k.contains('header') || k.contains('notice')) return Icons.campaign_rounded;
    if (k.contains('description') || k.contains('meaning')) return Icons.notes_rounded;
    if (k.contains('name')) return Icons.badge_rounded;
    return Icons.edit_note_rounded;
  }

  InputDecoration _dec(ModuleField f) => InputDecoration(
        labelText: f.required ? '${f.label} *' : f.label,
        labelStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
        floatingLabelStyle: TextStyle(color: _t.c1, fontWeight: FontWeight.w800),
        prefixIcon: Icon(_iconFor(f), color: _t.c1, size: 21),
        filled: true,
        fillColor: const Color(0xFFF7F8FC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE5E7EF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: _t.c1, width: 1.8)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _red)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: _red, width: 1.8)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      );

  Future<void> _pickDate(ModuleField f) async {
    final c = _c[f.key]!;
    DateTime initial = DateTime.now();
    final p = c.text.split('-');
    if (p.length == 3) {
      final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
      if (y != null && m != null && d != null) initial = DateTime(y, m, d);
    }
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(2040),
      builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _t.c1)), child: child!),
    );
    if (d != null) c.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  Widget _field(ModuleField f) {
    if (f.type == FieldType.dropdown) {
      final opts = widget.optionsFor(f);
      final cur = _dd[f.key];
      return DropdownButtonFormField<String>(
        value: opts.any((o) => o.value == cur) ? cur : null,
        isExpanded: true,
        borderRadius: BorderRadius.circular(16),
        decoration: _dec(f),
        hint: Text(opts.isEmpty ? 'Nothing to choose from yet' : 'Select ${f.label.toLowerCase()}', style: const TextStyle(color: _muted)),
        items: [for (final o in opts) DropdownMenuItem(value: o.value, child: Text(o.label, overflow: TextOverflow.ellipsis))],
        onChanged: (v) => setState(() => _dd[f.key] = v),
        validator: (v) => f.required && (v == null || v.isEmpty) ? 'Please select ${f.label.toLowerCase()}' : null,
      );
    }
    final isDate = f.type == FieldType.date;
    final multi = f.type == FieldType.multiline || f.maxLines > 1;
    return TextFormField(
      controller: _c[f.key],
      readOnly: isDate,
      onTap: isDate ? () => _pickDate(f) : null,
      maxLines: multi ? (f.maxLines > 1 ? f.maxLines : 4) : 1,
      keyboardType: f.type == FieldType.number ? const TextInputType.numberWithOptions(decimal: true) : (multi ? TextInputType.multiline : TextInputType.text),
      textCapitalization: f.type == FieldType.text || multi ? TextCapitalization.sentences : TextCapitalization.none,
      style: const TextStyle(fontWeight: FontWeight.w700, color: _ink, fontSize: 15),
      decoration: _dec(f),
      validator: (v) {
        final s = (v ?? '').trim();
        if (f.required && s.isEmpty) return '${f.label} is required';
        if (s.isNotEmpty && f.minLength != null && s.length < f.minLength!) return '${f.label} must be at least ${f.minLength} characters';
        if (s.isNotEmpty && f.type == FieldType.number && double.tryParse(s) == null) return 'Enter a number';
        return null;
      },
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_key.currentState!.validate()) {
      HapticFeedback.lightImpact();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final values = <String, String>{};
    for (final f in widget.fields) {
      values[f.key] = f.type == FieldType.dropdown ? (_dd[f.key] ?? '') : (_c[f.key]?.text.trim() ?? '');
    }
    try {
      final msg = await widget.onSubmit(values);
      if (mounted) Navigator.pop(context, msg);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
          child: Form(
            key: _key,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(child: Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFD9DCE6), borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 16),
              Row(children: [
                Container(width: 46, height: 46, decoration: BoxDecoration(gradient: LinearGradient(colors: [_t.c1, _t.c2]), borderRadius: BorderRadius.circular(15)), child: Icon(editing ? Icons.edit_rounded : _t.icon, color: Colors.white, size: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.title[0].toUpperCase() + widget.title.substring(1), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink, letterSpacing: -.4)),
                    Text(editing ? 'Update the details below' : 'Fill in the details below', style: const TextStyle(fontSize: 12.5, color: _muted)),
                  ]),
                ),
                IconButton(onPressed: _saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: _muted)),
              ]),
              const SizedBox(height: 18),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFFFFF1F2), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFFECDD3))),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.error_rounded, color: _red, size: 19),
                    const SizedBox(width: 9),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFF9F1239), fontSize: 13, height: 1.4, fontWeight: FontWeight.w600))),
                  ]),
                ),
              for (final f in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 14), child: _field(f)),
              const SizedBox(height: 4),
              GestureDetector(
                onTap: _saving ? null : _submit,
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [_t.c1, _t.c2]), borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: _t.c1.withAlpha(90), blurRadius: 16, offset: const Offset(0, 8))]),
                  child: _saving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(editing ? Icons.check_rounded : Icons.add_rounded, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(editing ? 'Save changes' : 'Add ${_t.singular}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                        ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  LOADING SKELETON
// ═════════════════════════════════════════════════════════════════════════════
class _SkeletonCard extends StatefulWidget {
  const _SkeletonCard();

  @override
  State<_SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<_SkeletonCard> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) {
        final c = Color.lerp(const Color(0xFFE9ECF4), const Color(0xFFF4F6FB), _a.value)!;
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: Container(
            height: 82,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
            child: Row(children: [
              Container(width: 50, height: 50, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(16))),
              const SizedBox(width: 13),
              Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 13, width: 140, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 9),
                Container(height: 10, width: 90, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6))),
              ])),
            ]),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  HEADER PATTERNS (one per section)
// ═════════════════════════════════════════════════════════════════════════════
class _PatternPainter extends CustomPainter {
  final ModulePattern kind;
  const _PatternPainter(this.kind);

  @override
  void paint(Canvas canvas, Size s) {
    final line = Paint()
      ..color = Colors.white.withAlpha(36)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()
      ..color = Colors.white.withAlpha(44)
      ..style = PaintingStyle.fill;

    switch (kind) {
      case ModulePattern.dots:
        var row = 0;
        for (double y = 14; y < s.height; y += 20) {
          final off = row.isEven ? 14.0 : 24.0;
          for (double x = off; x < s.width; x += 20) {
            canvas.drawCircle(Offset(x, y), 1.7, fill);
          }
          row++;
        }
        break;
      case ModulePattern.rings:
        final c = Offset(s.width * .88, s.height * .22);
        for (double r = 34; r < s.width * 1.2; r += 32) {
          canvas.drawCircle(c, r, line);
        }
        break;
      case ModulePattern.ruled:
        for (double y = 36; y < s.height; y += 24) {
          canvas.drawLine(Offset(0, y), Offset(s.width, y), line);
        }
        canvas.drawLine(const Offset(40, 0), Offset(40, s.height), Paint()
          ..color = Colors.white.withAlpha(70)
          ..strokeWidth = 1.4);
        break;
      case ModulePattern.diagonal:
        for (double x = -s.height; x < s.width; x += 22) {
          canvas.drawLine(Offset(x, s.height), Offset(x + s.height, 0), line);
        }
        break;
      case ModulePattern.waves:
        for (var i = 0; i < 6; i++) {
          final base = s.height * .42 + i * 20;
          final path = Path()..moveTo(0, base);
          for (double x = 0; x <= s.width; x += 6) {
            path.lineTo(x, base + math.sin(x / 34 + i * .8) * 8);
          }
          canvas.drawPath(path, line);
        }
        break;
      case ModulePattern.grid:
        for (double x = 0; x < s.width; x += 28) {
          canvas.drawLine(Offset(x, 0), Offset(x, s.height), line);
        }
        for (double y = 0; y < s.height; y += 28) {
          canvas.drawLine(Offset(0, y), Offset(s.width, y), line);
        }
        break;
      case ModulePattern.plus:
        for (double y = 20; y < s.height; y += 34) {
          for (double x = 20; x < s.width; x += 34) {
            canvas.drawLine(Offset(x - 4, y), Offset(x + 4, y), line..strokeWidth = 1.6);
            canvas.drawLine(Offset(x, y - 4), Offset(x, y + 4), line);
          }
        }
        break;
      case ModulePattern.blocks:
        final rnd = math.Random(11);
        for (var i = 0; i < 16; i++) {
          final size = 14 + rnd.nextDouble() * 30;
          final x = s.width * (.42 + rnd.nextDouble() * .6);
          final y = rnd.nextDouble() * s.height;
          final p = Paint()..color = Colors.white.withAlpha(16 + rnd.nextInt(34));
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, size, size), const Radius.circular(8)), p);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter old) => old.kind != kind;
}
