// flutter_all_attendance_screen.dart
// Mirrors Allattendance.php 1:1 (portaladmin / subadmin): today's stats, "How it works", date + class + search
// filters, teachers list with schedule / knock times / GPS / area status / images, per-teacher attendance history
// by date range (with delete record), time settings (add / edit / delete / delete all), bulk time settings
// for selected teachers, image viewer, 7-day image cleanup notice.
//
// pubspec.yaml needs:  http, shared_preferences

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// extensionless address first (a redirect from "*.php" turns POST into GET and loses the form data)
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_all_attendance',
  'https://schoolsmirror.com/flutter_all_attendance.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

/// Same colour tokens as the :root block of Allattendance.php
class _C {
  static const primary = Color(0xFF4A6FC0);
  static const primaryDark = Color(0xFF3A5CA9);
  static const green = Color(0xFF28A745);
  static const red = Color(0xFFDC3545);
  static const warning = Color(0xFFFFC107);
  static const info = Color(0xFF17A2B8);
  static const grey = Color(0xFF6C757D);
  static const light = Color(0xFFF8F9FA);
  static const dark = Color(0xFF343A40);
  static const bg = Color(0xFFF5F5F5);
  static const border = Color(0xFFE9ECEF);
  static const navGradient = LinearGradient(colors: [primary, primaryDark]);
}

// ───────────────────────────── API helper ─────────────────────────────
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
            .timeout(const Duration(seconds: 60));
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
int _toInt(dynamic v) => int.tryParse('$v') ?? 0;
double? _toDouble(dynamic v) => v == null ? null : double.tryParse('$v');
String _two(int n) => n.toString().padLeft(2, '0');
String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
DateTime _parseYmd(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _dateLabel(String ymd) {
  try {
    final d = _parseYmd(ymd);
    return '${_wd[d.weekday - 1]}, ${_mo[d.month - 1]} ${d.day}, ${d.year}';
  } catch (_) {
    return ymd;
  }
}

String _time12(String? hms) {
  if (hms == null || hms.length < 5) return '--:--';
  final h = int.tryParse(hms.substring(0, 2)) ?? 0;
  return '${_two(h % 12 == 0 ? 12 : h % 12)}:${hms.substring(3, 5)} ${h >= 12 ? 'PM' : 'AM'}';
}

Uint8List? _bytesOf(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty || dataUrl == 'null') return null;
  try {
    final i = dataUrl.indexOf(',');
    return base64Decode(i >= 0 ? dataUrl.substring(i + 1) : dataUrl);
  } catch (_) {
    return null;
  }
}

final Map<int, Uint8List> _imgCache = {};
Uint8List? _cached(dynamic url) {
  if (url == null) return null;
  final u = '$url';
  if (u.isEmpty || u == 'null') return null;
  final b = _imgCache.putIfAbsent(u.hashCode, () => _bytesOf(u) ?? Uint8List(0));
  return b.isEmpty ? null : b;
}

void _toast(BuildContext c, String msg, {bool error = false}) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Text(msg),
    backgroundColor: error ? _C.red : _C.green,
    behavior: SnackBarBehavior.floating,
  ));
}

Future<bool> _confirm(BuildContext c, String title, String msg, {String yes = 'Delete'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(yes, style: const TextStyle(color: _C.red, fontWeight: FontWeight.bold))),
      ],
    ),
  );
  return r == true;
}

// ───────────────────────────── small shared widgets ─────────────────────────────
Widget _pill(String text, Color c, {IconData? icon}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withAlpha(38), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      ]),
    );

Widget _statusBadge(String status, int lateMin) {
  final s = status.isEmpty ? 'absent' : status;
  final c = s == 'present' ? _C.green : (s == 'late' ? const Color(0xFF856404) : (s == 'halfday' ? _C.info : _C.red));
  return Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
    _pill(s[0].toUpperCase() + s.substring(1), c),
    if (lateMin > 0) Text('$lateMin min late', style: const TextStyle(fontSize: 11, color: Color(0xFF856404))),
  ]);
}

Widget _areaBadge(dynamic status) {
  switch ('$status') {
    case 'within_school_area':
      return _pill('Within Area', _C.green, icon: Icons.check_circle);
    case 'outside_school_area':
      return _pill('Outside Area', const Color(0xFF856404), icon: Icons.warning_amber_rounded);
    case 'address_available':
      return _pill('Address Available', _C.grey, icon: Icons.location_on);
    default:
      return _pill('Unknown', _C.grey, icon: Icons.help);
  }
}

Widget _locBlock(dynamic address, dynamic lat, dynamic lng) {
  final a = address == null ? '' : '$address';
  final la = _toDouble(lat), lo = _toDouble(lng);
  if (a.isNotEmpty) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Tooltip(
        message: a,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.location_on, size: 14, color: _C.info),
          const SizedBox(width: 4),
          Flexible(child: Text(a.length > 30 ? '${a.substring(0, 30)}...' : a, style: const TextStyle(fontSize: 12))),
        ]),
      ),
      if (la != null && lo != null) Text('GPS: ${la.toStringAsFixed(6)}, ${lo.toStringAsFixed(6)}', style: const TextStyle(fontSize: 10, color: _C.grey)),
    ]);
  }
  if (la != null && lo != null) {
    return Text('Coordinates: ${la.toStringAsFixed(6)}, ${lo.toStringAsFixed(6)}', style: const TextStyle(fontSize: 11, color: _C.grey));
  }
  return const Text('No location', style: TextStyle(fontSize: 12, color: _C.grey));
}

Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16), Color? bg, Color? leftBar}) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: bg ?? Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 10, offset: const Offset(0, 2))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (leftBar != null) Container(width: 4, color: leftBar),
            Expanded(child: Padding(padding: padding, child: child)),
          ]),
        ),
      ),
    );

// ───────────────────────────── image viewer ─────────────────────────────
void _openImage(BuildContext context, String token, Map<String, dynamic> r, String type, dynamic teacherId, String date) {
  final isIn = type == 'in';
  final time = '${r[isIn ? 'knock_in_formatted' : 'knock_out_formatted']}';
  final addr = r[isIn ? 'in_address' : 'out_address'];
  final lat = r[isIn ? 'in_latitude' : 'out_latitude'];
  final lng = r[isIn ? 'in_longitude' : 'out_longitude'];
  final area = r[isIn ? 'in_location_status' : 'out_location_status'];
  final gps = (addr != null && '$addr'.isNotEmpty)
      ? 'Location: $addr'
      : (_toDouble(lat) != null ? 'GPS: ${_toDouble(lat)!.toStringAsFixed(6)}, ${_toDouble(lng)?.toStringAsFixed(6)}' : 'Location not recorded');
  final areaTxt = area == 'within_school_area' ? '✓ Within school area' : (area == 'outside_school_area' ? '⚠ Outside school area' : '? Area status unknown');
  showDialog(
    context: context,
    barrierColor: Colors.black.withAlpha(230),
    builder: (_) => _ImageViewer(
      thumb: _cached(r[isIn ? 'thumb_in' : 'thumb_out']),
      info: '${r['fullname'] ?? ''} ${isIn ? 'Knock In' : 'Knock Out'}: $time  •  $date'.trim(),
      gps: gps,
      area: areaTxt,
      loadFull: () async {
        final res = await _Api.post(token, 'get_image', {'teacher_id': '$teacherId', 'date': date, 'type': type});
        return res['success'] == true ? _bytesOf('${(res['data'] as Map)['image']}') : null;
      },
    ),
  );
}

class _ImageViewer extends StatefulWidget {
  final Uint8List? thumb;
  final String info, gps, area;
  final Future<Uint8List?> Function() loadFull;
  const _ImageViewer({required this.thumb, required this.info, required this.gps, required this.area, required this.loadFull});

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  Uint8List? _full;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.loadFull().then((b) {
      if (mounted) setState(() {
        _full = b;
        _loading = false;
      });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _full ?? widget.thumb;
    final areaColor = widget.area.startsWith('✓') ? Colors.greenAccent : (widget.area.startsWith('⚠') ? Colors.amber : Colors.white70);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(children: [
        SizedBox(
          width: double.infinity,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: shown == null
                  ? const Padding(padding: EdgeInsets.all(40), child: Text('Image not available', style: TextStyle(color: Colors.white)))
                  : ClipRRect(borderRadius: BorderRadius.circular(10), child: InteractiveViewer(child: Image.memory(shown, fit: BoxFit.contain, gaplessPlayback: true))),
            ),
            if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: SizedBox(height: 3, width: 120, child: LinearProgressIndicator())),
            const SizedBox(height: 10),
            Text(widget.info, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 4),
            Text(widget.gps, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
            Text(widget.area, textAlign: TextAlign.center, style: TextStyle(color: areaColor, fontSize: 12)),
          ]),
        ),
        Positioned(top: 0, right: 0, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 30))),
      ]),
    );
  }
}

// ───────────────────────────── one attendance day (used by list + history) ─────────────────────────────
class _DayCard extends StatelessWidget {
  final String token;
  final Map<String, dynamic> r;
  final dynamic teacherId;
  final String date;
  final Widget? header;
  final Widget? footer;
  const _DayCard({required this.token, required this.r, required this.teacherId, required this.date, this.header, this.footer});

  Widget _thumb(BuildContext c, String type) {
    final isIn = type == 'in';
    final bytes = _cached(r[isIn ? 'thumb_in' : 'thumb_out']);
    if (bytes != null) {
      return InkWell(
        onTap: () => _openImage(c, token, r, type, teacherId, date),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(border: Border.all(color: _C.border, width: 2), borderRadius: BorderRadius.circular(8)),
          child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)),
        ),
      );
    }
    if (r[isIn ? 'image_in_available' : 'image_out_available'] == false) {
      return const Column(children: [
        Icon(Icons.schedule, size: 18, color: Color(0xFFFF9800)),
        Text('Expired', style: TextStyle(fontSize: 10, color: Color(0xFFFF9800), fontStyle: FontStyle.italic)),
      ]);
    }
    return const Text('No image', style: TextStyle(fontSize: 11, color: _C.grey));
  }

  Widget _part(BuildContext c, String type) {
    final isIn = type == 'in';
    final color = isIn ? _C.green : _C.red;
    final t = '${r[isIn ? 'knock_in_formatted' : 'knock_out_formatted']}';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: _C.light, borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isIn ? 'KNOCK IN' : 'KNOCK OUT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .6, color: color)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isIn ? Icons.login : Icons.logout, size: 14, color: t == '--:--' ? _C.grey : color),
              const SizedBox(width: 4),
              Text(t, style: TextStyle(fontWeight: FontWeight.w600, color: t == '--:--' ? _C.grey : color)),
            ]),
            if (t != '--:--') ...[
              const SizedBox(height: 6),
              _locBlock(r[isIn ? 'in_address' : 'out_address'], r[isIn ? 'in_latitude' : 'out_latitude'], r[isIn ? 'in_longitude' : 'out_longitude']),
              const SizedBox(height: 5),
              _areaBadge(r[isIn ? 'in_location_status' : 'out_location_status']),
            ],
          ]),
        ),
        const SizedBox(width: 8),
        if (t != '--:--') _thumb(c, type),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = '${r['calculated_status'] ?? r['status'] ?? 'absent'}';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (header != null) header!,
      Row(children: [
        Expanded(child: _statusBadge(status, _toInt(r['late_minutes']))),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 14, children: [
        Text('Scheduled In: ${r['scheduled_in_formatted']}', style: const TextStyle(fontSize: 12, color: _C.primary, fontWeight: FontWeight.w600)),
        Text('Out: ${r['scheduled_out_formatted']}', style: const TextStyle(fontSize: 12, color: _C.primary, fontWeight: FontWeight.w600)),
      ]),
      _part(context, 'in'),
      _part(context, 'out'),
      if (footer != null) footer!,
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ═════════════════════════════════════════════════════════════════════════════
class FlutterAllAttendanceScreen extends StatefulWidget {
  final String? token;
  const FlutterAllAttendanceScreen({super.key, this.token});

  @override
  State<FlutterAllAttendanceScreen> createState() => _FlutterAllAttendanceScreenState();
}

class _FlutterAllAttendanceScreenState extends State<FlutterAllAttendanceScreen> {
  String? _token;
  bool _loading = true;
  bool _listLoading = false;
  Map<String, dynamic> _boot = {};
  List<Map<String, dynamic>> _teachers = [];
  List<Map<String, dynamic>> _classes = [];
  final Set<int> _selected = {};

  late DateTime _date = DateTime.now();
  String _classFilter = '';
  final _search = TextEditingController();

  Map<String, dynamic> get _stats => Map<String, dynamic>.from((_boot['stats'] ?? {}) as Map);

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _search.dispose();
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

  Future<void> _init() async {
    _token = await _getToken();
    if (_token == null) {
      setState(() => _loading = false);
      return;
    }
    await _loadBootstrap();
    await _loadTeachers();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBootstrap() async {
    final r = await _Api.post(_token!, 'bootstrap');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = Map<String, dynamic>.from(r['data'] as Map);
      final first = _boot.isEmpty;
      setState(() {
        _boot = d;
        _classes = _maps(d['classes']);
        if (first && d['today'] != null) _date = _parseYmd('${d['today']}'); // server date (Lagos) on first load only
      });
    } else {
      _toast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _loadTeachers() async {
    setState(() => _listLoading = true);
    final r = await _Api.post(_token!, 'list_teachers_attendance', {
      'date': _ymd(_date),
      'class_filter': _classFilter,
      'search_term': _search.text.trim(),
    });
    if (!mounted) return;
    setState(() => _listLoading = false);
    if (r['success'] == true) {
      setState(() {
        _teachers = _maps((r['data'] as Map)['teachers']);
        _selected.removeWhere((id) => !_teachers.any((t) => _toInt(t['user_id']) == id));
      });
    } else {
      _toast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _refreshAll() async {
    await _loadBootstrap();
    await _loadTeachers();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) {
      setState(() => _date = d);
      _loadTeachers();
    }
  }

  void _reset() {
    setState(() {
      _date = DateTime.now();
      _classFilter = '';
      _search.clear();
    });
    _loadTeachers();
  }

  // ───────────── sheets / dialogs ─────────────
  void _openHistory(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _C.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _HistorySheet(token: _token!, teacher: t, defaultStart: '${_boot['default_start'] ?? _ymd(DateTime.now().subtract(const Duration(days: 7)))}', onChanged: _loadTeachers),
    );
  }

  void _openSettings(Map<String, dynamic> t) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _C.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SettingsSheet(token: _token!, teacher: t, onChanged: _loadTeachers),
    );
  }

  Future<void> _bulk() async {
    if (_selected.isEmpty) {
      _toast(context, 'Select at least one teacher', error: true);
      return;
    }
    final ok = await showDialog<bool>(context: context, builder: (_) => _TimeSettingDialog(token: _token!, bulkIds: _selected.toList(), title: 'Bulk Time Settings (${_selected.length} teachers)'));
    if (ok == true) {
      setState(() => _selected.clear());
      _loadTeachers();
    }
  }

  void _help() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('How It Works'),
        content: const SingleChildScrollView(
          child: Text(
            '1. Set each teacher\'s knock-in and knock-out time with an effective date (Time Settings). The setting with the latest effective date on or before a day applies to that day.\n\n'
            '2. Teachers verify in and out with their face and GPS. A knock-in after the scheduled time is marked Late, and the minutes late are shown.\n\n'
            '3. Each verification records the address and whether the teacher was within the school area.\n\n'
            '4. Verification images are deleted automatically after 7 days for privacy; attendance records stay.\n\n'
            '5. Use Bulk Time Settings to apply one schedule to many teachers at once.',
            style: TextStyle(height: 1.4),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
      ),
    );
  }

  // ───────────── build ─────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      appBar: AppBar(
        elevation: 0,
        foregroundColor: Colors.white,
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.navGradient)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Teacher Attendance', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          if ('${_boot['school_name'] ?? ''}'.isNotEmpty) Text('${_boot['school_name']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400)),
        ]),
        actions: [IconButton(onPressed: _help, icon: const Icon(Icons.help_outline), tooltip: 'How it works')],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _C.primary))
          : _token == null
              ? const Center(child: Text('Session expired. Please log in again.'))
              : RefreshIndicator(
                  color: _C.primary,
                  onRefresh: _refreshAll,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    children: [
                      if (_toInt(_boot['images_cleaned']) > 0)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFFD1ECF1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFBEE5EB))),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.info, size: 18, color: Color(0xFF0C5460)),
                            const SizedBox(width: 8),
                            Expanded(child: Text('Automatic cleanup: ${_boot['images_cleaned']} verification image(s) older than 7 days have been removed.', style: const TextStyle(color: Color(0xFF0C5460), fontSize: 13))),
                          ]),
                        ),
                      _statsRow(),
                      _filters(),
                      _bulkBar(),
                      if (_listLoading)
                        const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: _C.primary)))
                      else if (_teachers.isEmpty)
                        const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No teachers found', style: TextStyle(color: _C.grey))))
                      else
                        for (final t in _teachers) _teacherCard(t),
                    ],
                  ),
                ),
    );
  }

  Widget _statTile(String label, dynamic value, Color color, IconData icon) => Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 8, offset: const Offset(0, 2))]),
          child: Column(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text('${value ?? 0}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: _C.grey)),
          ]),
        ),
      );

  Widget _statsRow() {
    final s = _stats;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(children: [
        Row(children: [_statTile('Total Teachers', s['total'], _C.primary, Icons.people), _statTile('Present Today', s['present'], _C.green, Icons.check_circle)]),
        Row(children: [_statTile('Late Today', s['late'], const Color(0xFFE0A800), Icons.schedule), _statTile('Absent Today', s['absent'], _C.red, Icons.cancel)]),
      ]),
    );
  }

  Widget _filters() {
    return _card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Search & Filter', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder(), isDense: true, suffixIcon: Icon(Icons.calendar_today, size: 18)),
            child: Text(_ymd(_date)),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _classFilter.isEmpty || !_classes.any((c) => '${c['class_name']}' == _classFilter) ? '' : _classFilter,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class', border: OutlineInputBorder(), isDense: true),
          items: [
            const DropdownMenuItem(value: '', child: Text('All Classes')),
            for (final c in _classes) DropdownMenuItem(value: '${c['class_name']}', child: Text('${c['class_name']}')),
          ],
          onChanged: (v) {
            setState(() => _classFilter = v ?? '');
            _loadTeachers();
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _loadTeachers(),
          decoration: const InputDecoration(labelText: 'Search by name or ID', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: ElevatedButton.icon(onPressed: _loadTeachers, icon: const Icon(Icons.search, size: 18), label: const Text('Search'), style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh, size: 18), label: const Text('Reset'))),
        ]),
      ]),
    );
  }

  Widget _bulkBar() {
    final all = _teachers.isNotEmpty && _selected.length == _teachers.length;
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Checkbox(
          value: all,
          activeColor: _C.primary,
          onChanged: _teachers.isEmpty
              ? null
              : (v) => setState(() {
                    _selected.clear();
                    if (v == true) _selected.addAll(_teachers.map((t) => _toInt(t['user_id'])));
                  }),
        ),
        Expanded(child: Text(_selected.isEmpty ? 'Select all' : '${_selected.length} selected', style: const TextStyle(fontSize: 13))),
        ElevatedButton.icon(
          onPressed: _selected.isEmpty ? null : _bulk,
          icon: const Icon(Icons.schedule, size: 16),
          label: const Text('Bulk Time Settings'),
          style: ElevatedButton.styleFrom(backgroundColor: _C.info, foregroundColor: Colors.white),
        ),
      ]),
    );
  }

  Widget _teacherCard(Map<String, dynamic> t) {
    final id = _toInt(t['user_id']);
    return _card(
      leftBar: _selected.contains(id) ? _C.primary : null,
      child: _DayCard(
        token: _token!,
        r: t,
        teacherId: id,
        date: _ymd(_date),
        header: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 28,
              child: Checkbox(
                value: _selected.contains(id),
                activeColor: _C.primary,
                visualDensity: VisualDensity.compact,
                onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['fullname']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('ID: ${t['idnumber'] ?? 'N/A'}  •  ${t['class'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: _C.grey)),
              ]),
            ),
          ]),
        ),
        footer: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _openHistory(t), icon: const Icon(Icons.history, size: 16), label: const Text('History'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _openSettings(t), icon: const Icon(Icons.schedule, size: 16), label: const Text('Time Settings'))),
          ]),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  HISTORY SHEET (view attendance by date range + delete a day's record)
// ═════════════════════════════════════════════════════════════════════════════
class _HistorySheet extends StatefulWidget {
  final String token, defaultStart;
  final Map<String, dynamic> teacher;
  final Future<void> Function() onChanged;
  const _HistorySheet({required this.token, required this.teacher, required this.defaultStart, required this.onChanged});

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  late DateTime _start = _parseYmd(widget.defaultStart);
  DateTime _end = DateTime.now();
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;

  int get _tid => _toInt(widget.teacher['user_id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _Api.post(widget.token, 'get_teacher_attendance', {'teacher_id': '$_tid', 'start_date': _ymd(_start), 'end_date': _ymd(_end)});
    if (!mounted) return;
    setState(() => _loading = false);
    if (r['success'] == true) {
      setState(() => _records = _maps((r['data'] as Map)['records']));
    } else {
      _toast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _pick(bool isStart) async {
    final d = await showDatePicker(context: context, initialDate: isStart ? _start : _end, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d == null) return;
    setState(() => isStart ? _start = d : _end = d);
    _load();
  }

  Future<void> _delete(String date) async {
    if (!await _confirm(context, 'Delete Attendance Record', 'Delete ${_dateLabel(date)} attendance, knock and verification records for ${widget.teacher['fullname']}? This cannot be undone.')) return;
    final r = await _Api.post(widget.token, 'delete_attendance_record', {'teacher_id': '$_tid', 'date': date});
    if (!mounted) return;
    _toast(context, '${r['message']}', error: r['success'] != true);
    if (r['success'] == true) {
      _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .92,
      minChildSize: .5,
      maxChildSize: .96,
      builder: (_, sc) => Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 14),
          decoration: const BoxDecoration(gradient: _C.navGradient, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.teacher['fullname']}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('Attendance History', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.calendar_today, size: 14), label: Text('From ${_ymd(_start)}', style: const TextStyle(fontSize: 12)))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.calendar_today, size: 14), label: Text('To ${_ymd(_end)}', style: const TextStyle(fontSize: 12)))),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _C.primary))
              : _records.isEmpty
                  ? const Center(child: Text('No attendance records found for this period', style: TextStyle(color: _C.grey)))
                  : ListView(controller: sc, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                      for (final r in _records)
                        _card(
                          child: _DayCard(
                            token: widget.token,
                            r: {...r, 'fullname': widget.teacher['fullname']},
                            teacherId: _tid,
                            date: '${r['date']}',
                            header: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(children: [
                                Expanded(child: Text(_dateLabel('${r['date']}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                IconButton(
                                  onPressed: () => _delete('${r['date']}'),
                                  icon: const Icon(Icons.delete_outline, color: _C.red, size: 22),
                                  tooltip: 'Delete record',
                                  visualDensity: VisualDensity.compact,
                                ),
                              ]),
                            ),
                          ),
                        ),
                    ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  TIME SETTINGS SHEET (list / add / edit / delete / delete all)
// ═════════════════════════════════════════════════════════════════════════════
class _SettingsSheet extends StatefulWidget {
  final String token;
  final Map<String, dynamic> teacher;
  final Future<void> Function() onChanged;
  const _SettingsSheet({required this.token, required this.teacher, required this.onChanged});

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  int get _tid => _toInt(widget.teacher['user_id']);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _Api.post(widget.token, 'get_time_settings', {'teacher_id': '$_tid'});
    if (!mounted) return;
    setState(() => _loading = false);
    if (r['success'] == true) {
      setState(() => _items = _maps((r['data'] as Map)['settings']));
    } else {
      _toast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _addEdit([Map<String, dynamic>? existing]) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _TimeSettingDialog(token: widget.token, teacherId: _tid, existing: existing, title: existing == null ? 'Add Time Setting' : 'Edit Time Setting'),
    );
    if (ok == true) {
      _load();
      widget.onChanged();
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    if (!await _confirm(context, 'Delete Time Setting', 'Delete the setting effective ${s['effective_date']}?')) return;
    final r = await _Api.post(widget.token, 'delete_time_setting', {'setting_id': '${s['id']}'});
    if (!mounted) return;
    _toast(context, '${r['message']}', error: r['success'] != true);
    if (r['success'] == true) {
      _load();
      widget.onChanged();
    }
  }

  Future<void> _deleteAll() async {
    if (!await _confirm(context, 'Delete All Time Settings', 'Delete ALL time settings for ${widget.teacher['fullname']}? The default 8:00 AM / 4:00 PM will apply.', yes: 'Delete All')) return;
    final r = await _Api.post(widget.token, 'delete_all_time_settings', {'teacher_id': '$_tid'});
    if (!mounted) return;
    _toast(context, '${r['message']}', error: r['success'] != true);
    if (r['success'] == true) {
      _load();
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      minChildSize: .5,
      maxChildSize: .95,
      builder: (_, sc) => Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 16, 8, 14),
          decoration: const BoxDecoration(gradient: _C.navGradient, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${widget.teacher['fullname']}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const Text('Time Settings', style: TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: ElevatedButton.icon(onPressed: () => _addEdit(), icon: const Icon(Icons.add, size: 18), label: const Text('Add Setting'), style: ElevatedButton.styleFrom(backgroundColor: _C.green, foregroundColor: Colors.white))),
            const SizedBox(width: 8),
            Expanded(child: ElevatedButton.icon(onPressed: _items.isEmpty ? null : _deleteAll, icon: const Icon(Icons.delete_sweep, size: 18), label: const Text('Delete All'), style: ElevatedButton.styleFrom(backgroundColor: _C.red, foregroundColor: Colors.white))),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _C.primary))
              : _items.isEmpty
                  ? const Center(child: Padding(padding: EdgeInsets.all(30), child: Text('No time settings yet. Default: 8:00 AM in, 4:00 PM out.', textAlign: TextAlign.center, style: TextStyle(color: _C.grey))))
                  : ListView(controller: sc, padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
                      for (final s in _items)
                        _card(
                          leftBar: _C.primary,
                          child: Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Effective ${s['effective_date']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text('In: ${_time12('${s['knock_in_time']}')}   •   Out: ${_time12('${s['knock_out_time']}')}', style: const TextStyle(color: _C.primary, fontWeight: FontWeight.w600)),
                                Text('Created by: ${s['created_by_label'] ?? 'System'}', style: const TextStyle(fontSize: 11, color: _C.grey)),
                              ]),
                            ),
                            IconButton(onPressed: () => _addEdit(s), icon: const Icon(Icons.edit, color: _C.primary, size: 20)),
                            IconButton(onPressed: () => _delete(s), icon: const Icon(Icons.delete_outline, color: _C.red, size: 22)),
                          ]),
                        ),
                    ]),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  ADD / EDIT / BULK TIME SETTING DIALOG
// ═════════════════════════════════════════════════════════════════════════════
class _TimeSettingDialog extends StatefulWidget {
  final String token, title;
  final int? teacherId;
  final List<int>? bulkIds;
  final Map<String, dynamic>? existing;
  const _TimeSettingDialog({required this.token, required this.title, this.teacherId, this.bulkIds, this.existing});

  @override
  State<_TimeSettingDialog> createState() => _TimeSettingDialogState();
}

class _TimeSettingDialogState extends State<_TimeSettingDialog> {
  late TimeOfDay _in = _parse(widget.existing?['knock_in_time'], const TimeOfDay(hour: 8, minute: 0));
  late TimeOfDay _out = _parse(widget.existing?['knock_out_time'], const TimeOfDay(hour: 16, minute: 0));
  late DateTime _eff = widget.existing != null ? _parseYmd('${widget.existing!['effective_date']}') : DateTime.now();
  bool _saving = false;

  static TimeOfDay _parse(dynamic v, TimeOfDay fallback) {
    final s = '${v ?? ''}';
    if (s.length < 5) return fallback;
    return TimeOfDay(hour: int.tryParse(s.substring(0, 2)) ?? fallback.hour, minute: int.tryParse(s.substring(3, 5)) ?? fallback.minute);
  }

  String _hhmm(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  Future<void> _save() async {
    setState(() => _saving = true);
    final f = {'knock_in_time': _hhmm(_in), 'knock_out_time': _hhmm(_out), 'effective_date': _ymd(_eff)};
    Map<String, dynamic> r;
    if (widget.bulkIds != null) {
      r = await _Api.post(widget.token, 'bulk_time_settings', {...f, 'teacher_ids': jsonEncode(widget.bulkIds)});
    } else if (widget.existing != null) {
      r = await _Api.post(widget.token, 'update_time_setting', {...f, 'setting_id': '${widget.existing!['id']}'});
    } else {
      r = await _Api.post(widget.token, 'add_time_setting', {...f, 'teacher_id': '${widget.teacherId}'});
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _toast(context, '${r['message']}', error: r['success'] != true);
    if (r['success'] == true) Navigator.pop(context, true);
  }

  Widget _field(String label, String value, IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true, suffixIcon: Icon(icon, size: 18)),
          child: Text(value),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field('Knock In Time', _time12('${_hhmm(_in)}:00'), Icons.access_time, () async {
            final t = await showTimePicker(context: context, initialTime: _in);
            if (t != null) setState(() => _in = t);
          }),
          const SizedBox(height: 12),
          _field('Knock Out Time', _time12('${_hhmm(_out)}:00'), Icons.access_time, () async {
            final t = await showTimePicker(context: context, initialTime: _out);
            if (t != null) setState(() => _out = t);
          }),
          const SizedBox(height: 12),
          _field('Effective Date', _ymd(_eff), Icons.calendar_today, () async {
            final d = await showDatePicker(context: context, initialDate: _eff, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 730)));
            if (d != null) setState(() => _eff = d);
          }),
          const SizedBox(height: 10),
          const Text('A knock-in after the knock-in time is marked Late from the effective date onward.', style: TextStyle(fontSize: 12, color: _C.grey)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: _C.primary, foregroundColor: Colors.white),
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save'),
        ),
      ],
    );
  }
}
