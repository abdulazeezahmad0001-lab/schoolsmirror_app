// flutter_teacher_in_out_screen.dart
// Mirrors teacherinOut.php 1:1: header with server time + GPS status, teacher card (schedule, location,
// school-area status, late warning), salary progress, camera + GPS face verification (Verify In / Verify Out),
// result card, 30-day attendance history (cards instead of the wide table) with In/Out location, area status
// and verification images, image viewer, 30-second auto refresh, admin-access notice for non-teachers.
//
// pubspec.yaml needs:  http, shared_preferences, camera, geolocator, image
//   Android: <uses-permission android:name="android.permission.CAMERA"/>
//            <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
//            <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>   (minSdkVersion 21+)
//   iOS Info.plist: NSCameraUsageDescription, NSLocationWhenInUseUsageDescription

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// Your host redirects "*.php" to the extensionless address, and a redirect turns POST into GET
// (the form data is lost -> "Missing token"). So the extensionless URL is tried first and the app
// switches to the other form automatically if one of them fails.
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_teacher_in_out',
  'https://schoolsmirror.com/flutter_teacher_in_out.php',
];
int _apiIdx = 0;
String get _apiUrl => _apiUrls[_apiIdx];

/// Same colour tokens as the :root block of teacherinOut.php
class _C {
  static const primary = Color(0xFF4361EE);
  static const primaryDark = Color(0xFF3A56D4);
  static const secondary = Color(0xFF7209B7);
  static const success = Color(0xFF4CC9F0);
  static const warning = Color(0xFFFFC107);
  static const danger = Color(0xFFF72585);
  static const light = Color(0xFFF8F9FA);
  static const dark = Color(0xFF212529);
  static const green = Color(0xFF28A745);
  static const red = Color(0xFFDC3545);
  static const grey = Color(0xFF95A5A6);
  static const border = Color(0xFFE9ECEF);

  static const headerGradient = LinearGradient(colors: [primary, secondary]);
  static const inGradient = LinearGradient(colors: [success, primary]);
  static const outGradient = LinearGradient(colors: [danger, Color(0xFFB5179E)]);
}

// ───────────────────────────── API helper ─────────────────────────────
class _Api {
  /// true when the answer means "wrong address / body lost" -> try the other URL form
  static bool shouldRetry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' ||
            m == 'No image received. Please try again.' ||
            m.startsWith('The server received this request as') ||
            m.startsWith('Missing token'));
  }

  /// [fields] are sent in the URL AND the body (so they survive a redirect that drops the body).
  /// [big] (the captured photo) is only sent in the body.
  static Future<Map<String, dynamic>> post(String token, String action,
      [Map<String, String> fields = const {}, Map<String, String> big = const {}]) async {
    Map<String, dynamic> last = {'success': false, 'message': 'Network error. Check your connection.'};
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        final uri = Uri.parse(_apiUrl).replace(queryParameters: {'token': token, 'action': action, ...fields});
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
              body: {'token': token, 'action': action, ...fields, ...big},
            )
            .timeout(const Duration(seconds: 90));
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

List<Map<String, dynamic>> _maps(dynamic v) =>
    (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
int? _toInt(dynamic v) => v == null ? null : int.tryParse('$v');
double? _toDouble(dynamic v) => v == null ? null : double.tryParse('$v');

String _two(int n) => n.toString().padLeft(2, '0');
String _hms12(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${_two(h)}:${_two(d.minute)}:${_two(d.second)} ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String _hms24(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
String _dateLabel(String ymd) {
  final p = ymd.split('-');
  if (p.length != 3) return ymd;
  final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  return '${_wd[d.weekday - 1]}, ${_mo[d.month - 1]} ${d.day}';
}

Uint8List? _bytesOf(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  try {
    final i = dataUrl.indexOf(',');
    return base64Decode(i >= 0 ? dataUrl.substring(i + 1) : dataUrl);
  } catch (_) {
    return null;
  }
}

// ───────────────────────────── photo processing (runs in an isolate) ─────────────────────────────
class _PhotoJob {
  final Uint8List bytes;
  final bool flip;
  final String line1;
  final String? line2;
  const _PhotoJob(this.bytes, this.flip, this.line1, this.line2);
}

/// Same as capture() in the web page: mirrored selfie, timestamp + GPS watermark, JPEG 85%.
String _processPhoto(_PhotoJob j) {
  var im = img.decodeImage(j.bytes);
  if (im == null) return 'data:image/jpeg;base64,${base64Encode(j.bytes)}';
  im = img.bakeOrientation(im);
  if (j.flip) im = img.flipHorizontal(im);
  final white = img.ColorRgb8(255, 255, 255);
  img.drawString(im, j.line1, font: img.arial24, x: 20, y: 12, color: white);
  if (j.line2 != null) img.drawString(im, j.line2!, font: img.arial24, x: 20, y: 44, color: white);
  return 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(im, quality: 85))}';
}

enum _NoteKind { success, error, warning }

class _Result {
  final String kind; // success | warn | error
  final String text;
  final String? time, address, areaLine, lateLine;
  final Color? areaColor;
  const _Result(this.kind, this.text, {this.time, this.address, this.areaLine, this.areaColor, this.lateLine});
}

// ───────────────────────────── SCREEN ─────────────────────────────
class FlutterTeacherInOutScreen extends StatefulWidget {
  final String? token;
  const FlutterTeacherInOutScreen({super.key, this.token});

  @override
  State<FlutterTeacherInOutScreen> createState() => _FlutterTeacherInOutScreenState();
}

class _FlutterTeacherInOutScreenState extends State<FlutterTeacherInOutScreen> with WidgetsBindingObserver {
  String? _token;
  bool _loading = true;
  Map<String, dynamic> _boot = {};

  // camera + GPS
  CameraController? _cam;
  bool _cameraReady = false;
  bool _wantCamera = false;
  bool _showPermission = true;
  bool _camDenied = false;
  bool _spinner = false;
  String _spinnerText = 'Processing face verification...';
  bool _processing = false;
  Position? _pos;
  StreamSubscription<Position>? _posSub;
  String _gpsStatus = 'Checking...';
  bool _gpsActive = false;
  String _locText = 'Detecting...';
  String _accText = 'Accuracy: --';
  bool _showLocationInfo = false;
  String _locAddress = 'Address will appear here';
  String? _areaText;
  Color _areaColor = _C.green;

  // verification state
  bool _inDone = false, _outDone = false;
  int _daysVerified = 0;
  double _progress = 0;
  _Result? _result;
  Timer? _resultTimer;

  // history
  List<Map<String, dynamic>> _records = [];
  bool _historyLoaded = false;
  String _serverToday = '';
  final Map<int, Uint8List> _imgCache = {};

  // toast
  String? _note;
  _NoteKind _noteKind = _NoteKind.success;
  Timer? _noteTimer;

  final _clock = ValueNotifier<DateTime>(DateTime.now());
  Timer? _tick, _refresh;
  final _scroll = ScrollController();

  bool get _isTeacher => _boot['is_teacher'] == true;
  String get _schedIn => '${_boot['scheduled_in_time'] ?? '08:00:00'}';
  String get _todayIn => '${_boot['today_knock_in_time'] ?? '08:00 AM'}';
  String get _todayOut => '${_boot['today_knock_out_time'] ?? '04:00 PM'}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _clock.value = DateTime.now());
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    _refresh?.cancel();
    _noteTimer?.cancel();
    _resultTimer?.cancel();
    _posSub?.cancel();
    _cam?.dispose();
    _clock.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _cam;
    if (state == AppLifecycleState.inactive && c != null && c.value.isInitialized) {
      _cam = null;
      _cameraReady = false;
      c.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed && _wantCamera && _cam == null) {
      _openCamera().catchError((_) {});
    }
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

  // same as showNotification() on the web page (top card, auto-hides after 5 seconds)
  void _notify(String msg, [_NoteKind kind = _NoteKind.success]) {
    if (!mounted) return;
    _noteTimer?.cancel();
    setState(() {
      _note = msg;
      _noteKind = kind;
    });
    _noteTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _note = null);
    });
  }

  // ───────────────────────────── data loading ─────────────────────────────
  Future<void> _init() async {
    _token = await _getToken();
    if (_token == null) {
      setState(() => _loading = false);
      _notify('Session expired. Please log in again.', _NoteKind.error);
      return;
    }
    await _loadBootstrap();
    if (_isTeacher) {
      await _loadHistory();
      _refresh = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!_processing) _loadHistory(silent: true);
      });
      _initialGps();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadBootstrap() async {
    final r = await _Api.post(_token!, 'bootstrap');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = Map<String, dynamic>.from(r['data'] as Map);
      setState(() {
        _boot = d;
        _daysVerified = _toInt(d['days_verified']) ?? 0;
        _progress = _toDouble(d['salary_progress']) ?? 0;
        _inDone = d['in_done'] == true;
        _outDone = d['out_done'] == true;
        _serverToday = '${d['server_date'] ?? ''}';
      });
    } else {
      _notify('${r['message'] ?? 'Failed to load'}', _NoteKind.error);
    }
  }

  Future<void> _loadHistory({bool silent = false}) async {
    if (_token == null) return;
    final r = await _Api.post(_token!, 'fetch_attendance');
    if (!mounted) return;
    if (r['success'] == true) {
      final recs = _maps((r['data'] as Map)['records']);
      setState(() {
        _records = recs;
        _historyLoaded = true;
        for (final rec in recs) {
          if ('${rec['date']}' == _serverToday) {
            if (rec['verification_status_in'] == 'verified') _inDone = true;
            if (rec['verification_status_out'] == 'verified') _outDone = true;
          }
        }
      });
    } else if (!silent) {
      setState(() => _historyLoaded = true);
      _notify('${r['message'] ?? 'Error loading attendance'}', _NoteKind.error);
    }
  }

  Future<void> _refreshAll() async {
    await _loadBootstrap();
    if (_isTeacher) await _loadHistory();
  }

  // ───────────────────────────── GPS ─────────────────────────────
  void _setPos(Position p) {
    if (!mounted) return;
    setState(() {
      _pos = p;
      _gpsActive = true;
      _gpsStatus = 'Active ✓';
      _locText = '${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
      _accText = 'Accuracy: ${p.accuracy.toStringAsFixed(1)} meters';
      _locAddress = _locText;
    });
  }

  void _gpsFailed(String status, String text) {
    if (!mounted) return;
    setState(() {
      _gpsActive = false;
      _gpsStatus = status;
      _locText = text;
    });
  }

  Future<Position> _getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) throw Exception('Location services are disabled');
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        throw Exception('Location access denied');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 10)),
      );
      _setPos(p);
      return p;
    } catch (e) {
      _gpsFailed('Not Available', 'Location access denied');
      rethrow;
    }
  }

  void _startWatching() {
    _posSub?.cancel();
    _posSub = Geolocator.getPositionStream(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best)).listen(
      _setPos,
      onError: (e) => _gpsFailed('Error', 'GPS error: $e'),
    );
  }

  /// like the first getCurrentPosition() call in initialize() on the web page
  Future<void> _initialGps() async {
    try {
      await _getCurrentPosition();
    } catch (_) {}
  }

  // ───────────────────────────── camera ─────────────────────────────
  Future<void> _openCamera() async {
    await _cam?.dispose();
    _cam = null;
    final cams = await availableCameras();
    if (cams.isEmpty) throw Exception('No camera found');
    final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
    final c = CameraController(front, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() {
      _cam = c;
      _cameraReady = true;
      _wantCamera = true;
    });
  }

  Future<void> _initCamera() async {
    setState(() {
      _showPermission = false;
      _camDenied = false;
      _spinner = true;
      _spinnerText = 'Requesting camera and GPS access...';
    });
    try {
      try {
        await _getCurrentPosition();
        _startWatching();
        _notify('GPS location tracking activated');
      } catch (_) {
        _notify('GPS access denied. Attendance will be recorded without location.', _NoteKind.warning);
      }
      await _openCamera();
      _notify('Camera and GPS ready for verification');
    } catch (_) {
      if (mounted) {
        setState(() {
          _showPermission = true;
          _camDenied = true;
        });
      }
      _notify('Camera/GPS access denied. Please allow access.', _NoteKind.error);
    } finally {
      if (mounted) setState(() => _spinner = false);
    }
  }

  /// same as capture(): mirrored frame + timestamp + GPS watermark, returned as a JPEG data URL
  Future<String> _capture() async {
    final c = _cam;
    if (c == null || !_cameraReady) throw Exception('Camera not ready');
    final x = await c.takePicture();
    final bytes = await x.readAsBytes();
    final now = DateTime.now();
    final line1 = '${now.month}/${now.day}/${now.year}, ${_hms12(now)}';
    final p = _pos;
    final line2 = p == null ? null : 'GPS: ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)}';
    // Android front-camera files are not mirrored, so flip them to match the selfie preview (and the web page).
    // If your stored photos come out reversed on a device, set this to false.
    final flip = defaultTargetPlatform == TargetPlatform.android && c.description.lensDirection == CameraLensDirection.front;
    return compute(_processPhoto, _PhotoJob(bytes, flip, line1, line2));
  }

  // ───────────────────────────── verification ─────────────────────────────
  Future<void> _verify(String type) async {
    if (_processing) {
      _notify('Please wait, verification in progress...', _NoteKind.error);
      return;
    }
    if (!_cameraReady) {
      _notify('Camera not ready. Please allow camera access first.', _NoteKind.error);
      return;
    }
    if (_pos != null) {
      setState(() {
        _showLocationInfo = true;
        _locAddress = '${_pos!.latitude.toStringAsFixed(6)}, ${_pos!.longitude.toStringAsFixed(6)}';
      });
    }
    setState(() {
      _processing = true;
      _spinner = true;
      _spinnerText = 'Capturing image with GPS...';
    });
    try {
      final photo = await _capture();
      if (mounted) setState(() => _spinnerText = 'Processing face verification...');
      final p = _pos;
      final r = await _Api.post(
        _token!,
        'face_verification',
        {
          'verification_type': type,
          if (p != null) 'latitude': '${p.latitude}',
          if (p != null) 'longitude': '${p.longitude}',
        },
        {'image_data': photo},
      );
      if (!mounted) return;
      if (r['success'] == true) {
        _onVerified(type, Map<String, dynamic>.from(r['data'] as Map));
      } else {
        _showResult(_Result('error', '${r['message']}'));
        _notify('${r['message']}', _NoteKind.error);
      }
    } catch (e) {
      if (mounted) {
        _showResult(const _Result('error', 'Failed to capture image. Please try again.'));
        _notify('Failed to capture image. Please try again.', _NoteKind.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _processing = false;
          _spinner = false;
        });
      }
    }
  }

  void _onVerified(String type, Map<String, dynamic> d) {
    final loc = '${d['location_status']}';
    final late = '${d['attendance_status']}' == 'late';
    var kind = 'success';
    String? areaLine;
    Color? areaColor;
    if (loc == 'within_school_area') {
      areaLine = 'Within school area ✓';
      areaColor = _C.green;
    } else if (loc == 'outside_school_area') {
      kind = 'warn';
      areaLine = 'Outside school area ⚠';
      areaColor = _C.warning;
    }
    if (late) kind = 'warn';
    final lateMin = late ? (_toInt(d['late_minutes']) ?? 0) : 0;

    setState(() {
      _locAddress = '${d['address'] ?? _locAddress}';
      if (areaLine != null) {
        _areaText = areaLine;
        _areaColor = areaColor!;
      }
      if (type == 'in') {
        _inDone = true;
      } else {
        _outDone = true;
      }
      if (d['days_verified'] != null) {
        _daysVerified = _toInt(d['days_verified']) ?? _daysVerified;
        _progress = _toDouble(d['salary_progress']) ?? (_daysVerified / 22 * 100).clamp(0, 100).toDouble();
      }
    });
    _showResult(_Result(
      kind,
      '${d['message']}',
      time: '${d['verification_time']}',
      address: '${d['address']}',
      areaLine: areaLine,
      areaColor: areaColor,
      lateLine: lateMin > 0 ? 'Late by $lateMin minutes (Scheduled: ${d['scheduled_time']})' : null,
    ));
    _notify('${d['message']}', loc == 'outside_school_area' ? _NoteKind.warning : _NoteKind.success);
    _loadHistory(silent: true);
  }

  void _showResult(_Result r) {
    _resultTimer?.cancel();
    setState(() => _result = r);
    _resultTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _result = null);
    });
  }

  // ───────────────────────────── image viewer ─────────────────────────────
  Uint8List? _cached(String? url) {
    if (url == null || url.isEmpty || url == 'null') return null;
    final b = _imgCache.putIfAbsent(url.hashCode, () => _bytesOf(url) ?? Uint8List(0));
    return b.isEmpty ? null : b;
  }

  void _openImage(Map<String, dynamic> r, String type) {
    final isIn = type == 'in';
    final tu = r[isIn ? 'thumb_in' : 'thumb_out'];
    final thumb = tu == null ? null : _cached('$tu');
    final time = '${r[isIn ? 'verification_in' : 'verification_out']}';
    final addr = r[isIn ? 'in_address' : 'out_address'];
    final lat = r[isIn ? 'in_latitude' : 'out_latitude'];
    final lng = r[isIn ? 'in_longitude' : 'out_longitude'];
    final area = r[isIn ? 'in_location_status' : 'out_location_status'];
    final gps = (addr != null && '$addr'.isNotEmpty)
        ? 'Location: $addr'
        : (lat != null ? 'GPS: ${_toDouble(lat)!.toStringAsFixed(6)}, ${_toDouble(lng)!.toStringAsFixed(6)}' : 'Location not recorded');
    final areaTxt = area == 'within_school_area'
        ? '✓ Within school area'
        : area == 'outside_school_area'
            ? '⚠ Outside school area'
            : '? Area status unknown';
    showDialog(
      context: context,
      barrierColor: Colors.black.withAlpha(230),
      builder: (_) => _ImageViewer(
        thumb: thumb,
        info: '${isIn ? 'Verified In' : 'Verified Out'}: $time',
        gps: gps,
        area: areaTxt,
        loadFull: () async {
          final res = await _Api.post(_token!, 'get_image', {'date': '${r['date']}', 'type': type});
          if (res['success'] == true) return _bytesOf('${(res['data'] as Map)['image']}');
          return null;
        },
      ),
    );
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFF5F7FA), Color(0xFFE4E8F0)]),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: _C.headerGradient)),
          title: const Text('Face Verification', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: _C.primary))
            : Stack(children: [
                RefreshIndicator(
                  color: _C.primary,
                  onRefresh: _refreshAll,
                  child: ListView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 30, offset: const Offset(0, 10))]),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            _header(),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: _boot.isEmpty ? _loadFailed() : (_isTeacher ? _teacherBody() : _adminNotice()),
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_note != null) Positioned(top: 10, left: 14, right: 14, child: _noteCard()),
              ]),
      ),
    );
  }

  Widget _noteCard() {
    final c = _noteKind == _NoteKind.error ? _C.danger : (_noteKind == _NoteKind.warning ? _C.warning : _C.success);
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withAlpha(38), blurRadius: 30, offset: const Offset(0, 10))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: 5, color: c),
              Expanded(child: Padding(padding: const EdgeInsets.all(16), child: Text(_note!, style: const TextStyle(color: _C.dark)))),
            ]),
          ),
        ),
      ),
    );
  }

  // ───────────────────────────── helpers ─────────────────────────────
  /// card with a coloured bar on one edge (the web page's border-left / border-top)
  Widget _card({
    required Widget child,
    required Color bar,
    bool top = false,
    double barW = 5,
    Color bg = Colors.white,
    double radius = 15,
    EdgeInsets padding = const EdgeInsets.all(18),
    bool shadow = true,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow ? [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 15, offset: const Offset(0, 5))] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(children: [
          Padding(padding: (top ? EdgeInsets.only(top: barW) : EdgeInsets.only(left: barW)).add(padding), child: child),
          if (top)
            Positioned(left: 0, right: 0, top: 0, height: barW, child: ColoredBox(color: bar))
          else
            Positioned(left: 0, top: 0, bottom: 0, width: barW, child: ColoredBox(color: bar)),
        ]),
      ),
    );
  }

  Widget _whiteBox({required Widget child, Color? leftBar}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10, offset: const Offset(0, 3))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (leftBar != null) Container(width: 4, color: leftBar),
              Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), child: child)),
            ]),
          ),
        ),
      );

  Widget _gpsPill(String text, bool active) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: (active ? _C.success : const Color(0xFF6C757D)).withAlpha(38), borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: TextStyle(fontSize: 11, color: active ? _C.success : const Color(0xFF6C757D))),
      );

  // ───────────────────────────── header ─────────────────────────────
  Widget _header() {
    return Container(
      decoration: const BoxDecoration(gradient: _C.headerGradient),
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_boot['school_name'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        const Text('Teacher Face Verification Portal', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.15)),
        const SizedBox(height: 6),
        Text('Secure biometric attendance system with AI verification & GPS tracking', style: TextStyle(color: Colors.white.withAlpha(230), fontWeight: FontWeight.w300)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: Colors.white.withAlpha(26), borderRadius: BorderRadius.circular(5), border: Border(left: BorderSide(color: Colors.white.withAlpha(77), width: 3))),
          child: Wrap(spacing: 16, runSpacing: 4, children: [
            ValueListenableBuilder<DateTime>(
              valueListenable: _clock,
              builder: (_, t, __) => Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.access_time, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text('Server Time: ${_hms12(t)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
              ]),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_on, size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text('GPS Status: $_gpsStatus', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _loadFailed() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          const Icon(Icons.cloud_off, size: 54, color: _C.grey),
          const SizedBox(height: 14),
          const Text('Could not load your details.', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 18),
          _gradBtn('Try Again', Icons.refresh, _C.inGradient, () async {
            setState(() => _loading = true);
            await _init();
          }),
        ]),
      );

  // ───────────────────────────── admin notice ─────────────────────────────
  Widget _adminNotice() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          const Icon(Icons.info, size: 54, color: _C.primary),
          const SizedBox(height: 18),
          const Text('Admin Access', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          const Text('This portal is for teacher face verification. Admin functionality is available in the main dashboard.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Color(0xFF666666))),
          const SizedBox(height: 28),
          _backButton(),
        ]),
      );

  Widget _backButton() => Center(
        child: InkWell(
          onTap: () => Navigator.maybePop(context),
          borderRadius: BorderRadius.circular(15),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            decoration: BoxDecoration(color: _C.light, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 15, offset: const Offset(0, 5))]),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.arrow_back, size: 18, color: _C.dark),
              SizedBox(width: 8),
              Text('Back to Dashboard', style: TextStyle(color: _C.dark, fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      );

  // ───────────────────────────── teacher body ─────────────────────────────
  Widget _teacherBody() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _teacherInfo(),
      const SizedBox(height: 22),
      _salaryProgress(),
      const SizedBox(height: 22),
      _verificationSection(),
      const SizedBox(height: 22),
      _historySection(),
      const SizedBox(height: 22),
      _backButton(),
    ]);
  }

  Widget _scheduleBox(IconData icon, String title, Widget body) => _whiteBox(
        child: Row(children: [
          Icon(icon, color: _C.primary),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), body])),
        ]),
      );

  Widget _teacherInfo() {
    return _card(
      bar: _C.primary,
      bg: _C.light,
      padding: const EdgeInsets.all(18),
      shadow: false,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${_boot['teacher_name'] ?? ''}', style: const TextStyle(fontSize: 22, color: _C.dark, fontWeight: FontWeight.w600)),
        _scheduleBox(Icons.login, 'Scheduled Knock-In', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_todayIn, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Text('Late if after this time', style: TextStyle(fontSize: 12, color: Color(0xFF666666))),
        ])),
        _scheduleBox(Icons.logout, 'Scheduled Knock-Out', Text(_todayOut, style: const TextStyle(fontWeight: FontWeight.bold))),
        _scheduleBox(Icons.location_on, 'Current Location', Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_locText, style: const TextStyle(fontSize: 12)),
          Text(_accText, style: const TextStyle(fontSize: 12, color: Color(0xFF666666))),
        ])),
        if (_showLocationInfo)
          _whiteBox(
            leftBar: _C.success,
            child: Row(children: [
              const Icon(Icons.location_on, color: _C.success),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Location Verified', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_locAddress, style: const TextStyle(fontSize: 12)),
              ])),
            ]),
          ),
        if (_areaText != null)
          _whiteBox(
            leftBar: _C.green,
            child: Row(children: [
              const Icon(Icons.school, color: _C.green),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('School Area Status', style: TextStyle(fontWeight: FontWeight.bold)),
                Text(_areaText!, style: TextStyle(fontSize: 12, color: _areaColor, fontWeight: FontWeight.w600)),
              ])),
            ]),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: _C.border, borderRadius: BorderRadius.circular(5)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.access_time, size: 13),
              const SizedBox(width: 4),
              ValueListenableBuilder<DateTime>(
                valueListenable: _clock,
                builder: (_, t, __) => Text('Current Time: ${_hms12(t)}', style: const TextStyle(fontSize: 12)),
              ),
              _gpsPill(_gpsActive ? 'GPS: Active ✓' : (_gpsStatus == 'Error' ? 'GPS: Error' : 'GPS: Offline'), _gpsActive),
            ]),
          ),
        ),
        // late warning (same rule as the PHP: current time after scheduled knock-in)
        ValueListenableBuilder<DateTime>(
          valueListenable: _clock,
          builder: (_, t, __) {
            final sched = _schedIn.length >= 8 ? _schedIn.substring(0, 8) : '${_schedIn}:00';
            if (_hms24(t).compareTo(sched) <= 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 15),
              child: _PulseBox(
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: const Color(0xFFFFF3CD), border: Border.all(color: _C.warning), borderRadius: BorderRadius.circular(10)),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
                    const SizedBox(width: 10),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text("You're running late!", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF856404))),
                      Text('Scheduled: $_todayIn | Current: ${_hms12(t)}', style: const TextStyle(fontSize: 12, color: Color(0xFF856404))),
                    ])),
                  ]),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }

  Widget _salaryProgress() {
    return _card(
      bar: _C.success,
      top: true,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Salary Progress', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            height: 16,
            color: _C.border,
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: (_progress / 100).clamp(0.0, 1.0).toDouble()),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutBack,
              builder: (_, v, __) => FractionallySizedBox(
                widthFactor: v.clamp(0.0, 1.0).toDouble(),
                child: Container(decoration: BoxDecoration(gradient: const LinearGradient(colors: [_C.success, _C.primary]), borderRadius: BorderRadius.circular(10))),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Days Verified: $_daysVerified/${_toInt(_boot['salary_days']) ?? 22}'),
          Text('${_progress.toStringAsFixed(1)}%'),
        ]),
        const SizedBox(height: 10),
        const Text('Salary will be processed after verification of attendance'),
      ]),
    );
  }

  // ───────────────────────────── verification section ─────────────────────────────
  Widget _verificationSection() {
    return _card(
      bar: _C.primary,
      top: true,
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Text('Face Verification', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          _gpsPill(_gpsActive ? 'GPS: Active ✓' : 'GPS Required', _gpsActive),
        ]),
        const SizedBox(height: 16),
        if (_showPermission) _permissionBox(),
        if (_cameraReady && _cam != null) _cameraBox(),
        if (_spinner)
          Padding(
            padding: const EdgeInsets.all(26),
            child: Column(children: [
              const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(strokeWidth: 5, color: _C.primary)),
              const SizedBox(height: 18),
              Text(_spinnerText),
            ]),
          ),
        const SizedBox(height: 14),
        Wrap(alignment: WrapAlignment.center, spacing: 20, runSpacing: 14, children: [
          _verifyBtn('in'),
          _verifyBtn('out'),
        ]),
        if (_result != null) _resultBox(_result!),
      ]),
    );
  }

  Widget _permissionBox() {
    return _Dashed(
      color: const Color(0xFFADB5BD),
      background: _C.light,
      child: Column(children: [
        Icon(_camDenied ? Icons.no_photography : Icons.photo_camera, size: 48, color: _camDenied ? _C.danger : _C.primary),
        const SizedBox(height: 12),
        Text(_camDenied ? 'Camera/GPS Access Denied' : 'Camera Access Required', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(_camDenied ? 'Please allow camera and GPS access to use face verification.' : 'Click "Allow Camera Access" to start face verification with GPS tracking',
            textAlign: TextAlign.center),
        if (_camDenied) ...[
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Tips:\n•  Check if your camera and location services are enabled\n•  Make sure camera is not being used by another application\n•  Close this screen and open it again',
                style: TextStyle(color: Color(0xFF666666), fontSize: 14, height: 1.5)),
          ),
        ] else ...[
          Container(
            margin: const EdgeInsets.symmetric(vertical: 18),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(8)),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info, size: 18, color: Color(0xFF1976D2)),
              SizedBox(width: 8),
              Expanded(child: Text("GPS location will be captured along with your photo for attendance verification. System will check if you're within school area.", style: TextStyle(fontSize: 13))),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        _gradBtn(_camDenied ? 'Try Again' : 'Allow Camera & GPS Access', _camDenied ? Icons.refresh : Icons.photo_camera, _C.inGradient, _initCamera),
      ]),
    );
  }

  Widget _cameraBox() {
    final c = _cam!;
    final ar = c.value.aspectRatio == 0 ? 0.75 : 1 / c.value.aspectRatio;
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 640),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withAlpha(38), blurRadius: 30, offset: const Offset(0, 10))]),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: AspectRatio(
            aspectRatio: ar,
            child: Stack(fit: StackFit.expand, children: [
              CameraPreview(c),
              const IgnorePointer(child: CustomPaint(painter: _GuidePainter())),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _gradBtn(String label, IconData icon, Gradient g, VoidCallback? onTap, {bool busy = false}) {
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200),
        child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
          decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: Colors.black.withAlpha(26), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Flexible(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
          ]),
        ),
        ),
      ),
    );
  }

  Widget _verifyBtn(String type) {
    final isIn = type == 'in';
    final done = isIn ? _inDone : _outDone;
    final enabled = _cameraReady && !_processing && !done;
    final label = _processing ? 'Processing...' : (done ? (isIn ? 'Verified In Today' : 'Verified Out Today') : (isIn ? 'Verify In' : 'Verify Out'));
    final icon = done ? Icons.check : (isIn ? Icons.login : Icons.logout);
    return _gradBtn(label, icon, isIn ? _C.inGradient : _C.outGradient, enabled ? () => _verify(type) : null, busy: _processing);
  }

  Widget _resultBox(_Result r) {
    final err = r.kind == 'error';
    final warn = r.kind == 'warn';
    final colors = err
        ? [const Color(0xFFF8D7DA), const Color(0xFFF5C6CB)]
        : warn
            ? [const Color(0xFFFFF3CD), const Color(0xFFFFEAA7)]
            : [const Color(0xFFD4EDDA), const Color(0xFFC3E6CB)];
    final bar = err ? _C.red : (warn ? _C.warning : _C.green);
    return Container(
      margin: const EdgeInsets.only(top: 26),
      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors), borderRadius: BorderRadius.circular(15)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(25, 22, 20, 22),
            child: SizedBox(
              width: double.infinity,
              child: Column(children: [
                Icon(err ? Icons.cancel : (warn ? Icons.warning_amber_rounded : Icons.check_circle), size: 48, color: bar),
                const SizedBox(height: 14),
                Text(r.text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                if (r.time != null) ...[const SizedBox(height: 12), Text('Time: ${r.time}', style: const TextStyle(fontSize: 14, color: Color(0xFF666666)))],
                if (r.address != null && r.address!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Location: ${r.address}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: _C.success)),
                ],
                if (r.areaLine != null) ...[
                  const SizedBox(height: 10),
                  Text(r.areaLine!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: r.areaColor)),
                ],
                if (r.lateLine != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(5)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.warning_amber_rounded, size: 16),
                      const SizedBox(width: 6),
                      Flexible(child: Text(r.lateLine!)),
                    ]),
                  ),
                ],
              ]),
            ),
          ),
          Positioned(left: 0, top: 0, bottom: 0, width: 5, child: ColoredBox(color: bar)),
        ]),
      ),
    );
  }

  // ───────────────────────────── attendance history ─────────────────────────────
  Widget _historySection() {
    return _card(
      bar: _C.secondary,
      top: true,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Recent Attendance & Verification', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFFFF3CD), border: Border.all(color: const Color(0xFFFFEAA7)), borderRadius: BorderRadius.circular(8)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info, size: 16, color: Color(0xFF856404)),
            SizedBox(width: 8),
            Expanded(child: Text('Verification images are automatically deleted after 7 days for privacy.', style: TextStyle(fontSize: 13, color: Color(0xFF856404)))),
          ]),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFE3F2FD), border: Border.all(color: const Color(0xFFBBDEFB)), borderRadius: BorderRadius.circular(8)),
          child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.location_on, size: 16, color: Color(0xFF1565C0)),
            SizedBox(width: 8),
            Expanded(child: Text('GPS locations are recorded with each verification. System checks if within 500m of school.', style: TextStyle(fontSize: 13, color: Color(0xFF1565C0)))),
          ]),
        ),
        const SizedBox(height: 18),
        if (!_historyLoaded)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('Loading attendance data...', style: TextStyle(color: _C.grey))))
        else if (_records.isEmpty)
          const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No attendance records found for the last 30 days', textAlign: TextAlign.center, style: TextStyle(color: _C.grey))))
        else
          for (final r in _records) Padding(padding: const EdgeInsets.only(bottom: 14), child: _recordCard(r)),
      ]),
    );
  }

  Widget _statusBadge(String status, {int lateMin = 0}) {
    final s = status.isEmpty ? 'absent' : status;
    final c = s == 'verified' ? _C.success : s == 'present' ? _C.green : s == 'late' ? _C.warning : _C.red;
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: c.withAlpha(38), borderRadius: BorderRadius.circular(20)),
        child: Text(s[0].toUpperCase() + s.substring(1), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c)),
      ),
      if (lateMin > 0) Padding(padding: const EdgeInsets.only(left: 5), child: Text('$lateMin min', style: const TextStyle(fontSize: 12, color: _C.warning))),
    ]);
  }

  Widget _timeBlock(String v, bool isIn) {
    if (v == '--:--') return const Text('--:--', style: TextStyle(color: _C.grey));
    final parts = v.split(' ');
    final hhmm = parts[0].length >= 5 ? parts[0].substring(0, 5) : parts[0];
    final ampm = parts.length > 1 ? parts[1] : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isIn ? Icons.login : Icons.logout, size: 14, color: isIn ? _C.green : _C.red),
        const SizedBox(width: 4),
        Text('$hhmm $ampm', style: TextStyle(fontWeight: FontWeight.w600, color: isIn ? _C.green : _C.red)),
      ]),
      Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.access_time, size: 12, color: _C.primary),
        const SizedBox(width: 4),
        Text(v, style: const TextStyle(fontSize: 12, color: _C.primary)),
      ]),
    ]);
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
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(color: _C.light, borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.location_on, size: 14, color: _C.success),
              const SizedBox(width: 5),
              Flexible(child: Text(a.length > 25 ? '${a.substring(0, 25)}...' : a, style: const TextStyle(fontSize: 12))),
            ]),
          ),
        ),
        if (la != null && lo != null)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('GPS: ${la.toStringAsFixed(6)}, ${lo.toStringAsFixed(6)}', style: const TextStyle(fontSize: 10, color: Color(0xFF666666)))),
      ]);
    }
    if (la != null && lo != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(color: _C.light, borderRadius: BorderRadius.circular(4)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.location_on, size: 14, color: Color(0xFF6C757D)),
            SizedBox(width: 5),
            Text('Coordinates', style: TextStyle(fontSize: 12)),
          ]),
        ),
        Padding(padding: const EdgeInsets.only(top: 2), child: Text('${la.toStringAsFixed(6)}, ${lo.toStringAsFixed(6)}', style: const TextStyle(fontSize: 10, color: Color(0xFF666666)))),
      ]);
    }
    return const Text('No location', style: TextStyle(color: _C.grey, fontSize: 12));
  }

  Widget _areaBadge(dynamic status) {
    Color bg, fg;
    IconData icon;
    String text;
    switch ('$status') {
      case 'within_school_area':
        bg = _C.green;
        fg = _C.green;
        icon = Icons.check_circle;
        text = 'Within Area';
        break;
      case 'outside_school_area':
        bg = _C.warning;
        fg = const Color(0xFF856404);
        icon = Icons.warning_amber_rounded;
        text = 'Outside Area';
        break;
      case 'address_available':
        bg = const Color(0xFF6C757D);
        fg = const Color(0xFF6C757D);
        icon = Icons.location_on;
        text = 'Address Available';
        break;
      default:
        bg = const Color(0xFF6C757D);
        fg = const Color(0xFF6C757D);
        icon = Icons.help;
        text = 'Unknown';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg.withAlpha(38), borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: fg),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }

  Widget _imgBlock(Map<String, dynamic> r, String type) {
    final isIn = type == 'in';
    final thumbUrl = r[isIn ? 'thumb_in' : 'thumb_out'];
    final time = '${r[isIn ? 'verification_in' : 'verification_out']}';
    final bytes = thumbUrl == null ? null : _cached('$thumbUrl');
    if (bytes != null) {
      return Column(children: [
        InkWell(
          onTap: () => _openImage(r, type),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(border: Border.all(color: _C.border, width: 2), borderRadius: BorderRadius.circular(8)),
            child: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)),
          ),
        ),
        const SizedBox(height: 2),
        Text('Captured: $time', style: const TextStyle(fontSize: 11, color: _C.green, fontWeight: FontWeight.w600)),
      ]);
    }
    if (r[isIn ? 'image_status_in' : 'image_status_out'] == 'expired') {
      return const Column(children: [
        Icon(Icons.schedule, size: 20, color: Color(0xFFFF9800)),
        SizedBox(height: 4),
        Text('Expired (7+ days)', style: TextStyle(fontSize: 11, color: Color(0xFFFF9800), fontStyle: FontStyle.italic)),
      ]);
    }
    return const Text('No image', style: TextStyle(color: _C.grey, fontSize: 12));
  }

  Widget _inOutPart(Map<String, dynamic> r, String type) {
    final isIn = type == 'in';
    final color = isIn ? _C.green : _C.red;
    final time = '${r[isIn ? 'verification_in' : 'verification_out']}';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _C.light, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(isIn ? 'VERIFY IN' : 'VERIFY OUT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: .6, color: color)),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _timeBlock(time, isIn),
              const SizedBox(height: 8),
              _locBlock(r[isIn ? 'in_address' : 'out_address'], r[isIn ? 'in_latitude' : 'out_latitude'], r[isIn ? 'in_longitude' : 'out_longitude']),
              const SizedBox(height: 6),
              _areaBadge(r[isIn ? 'in_location_status' : 'out_location_status']),
            ]),
          ),
          const SizedBox(width: 10),
          _imgBlock(r, type),
        ]),
      ]),
    );
  }

  Widget _recordCard(Map<String, dynamic> r) {
    final today = '${r['date']}' == _serverToday;
    final late = r['is_late'] == true;
    return _card(
      bar: today ? _C.primary : Colors.transparent,
      barW: today ? 3 : 0,
      bg: today ? _C.success.withAlpha(26) : Colors.white,
      radius: 12,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_dateLabel('${r['date']}'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text('${r['date']}', style: const TextStyle(fontSize: 12, color: _C.grey)),
            ]),
          ),
          _statusBadge('${r['status']}', lateMin: late ? (_toInt(r['late_minutes']) ?? 0) : 0),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Text('Scheduled: ', style: TextStyle(fontSize: 13, color: Color(0xFF555555))),
          Text('${r['scheduled_in_time']}', style: const TextStyle(fontWeight: FontWeight.w600, color: _C.primary)),
          const SizedBox(width: 6),
          const Text('Late threshold', style: TextStyle(fontSize: 11, color: _C.grey)),
        ]),
        _inOutPart(r, 'in'),
        _inOutPart(r, 'out'),
      ]),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Late-warning pulse (the web page's @keyframes pulse)
// ════════════════════════════════════════════════════════════════════════════
class _PulseBox extends StatefulWidget {
  final Widget child;
  const _PulseBox({required this.child});

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final t = _c.value;
        final k = t < .7 ? t / .7 : 1.0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [BoxShadow(color: _C.warning.withAlpha(((1 - k) * 102).round()), spreadRadius: 10 * k, blurRadius: 0)],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Face guide on the camera (.face-guide: 280px rounded square, dimmed outside)
// ════════════════════════════════════════════════════════════════════════════
class _GuidePainter extends CustomPainter {
  const _GuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = (size.shortestSide * .7).clamp(0.0, 280.0).toDouble();
    final rect = RRect.fromRectAndRadius(Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side), const Radius.circular(20));
    final dim = Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rect));
    canvas.drawPath(dim, Paint()..color = Colors.black.withAlpha(102));
    canvas.drawRRect(rect, Paint()..color = Colors.white.withAlpha(179)..style = PaintingStyle.stroke..strokeWidth = 3);
  }

  @override
  bool shouldRepaint(covariant _GuidePainter old) => false;
}

// ════════════════════════════════════════════════════════════════════════════
//  Dashed border (.camera-permission uses `border: 2px dashed`)
// ════════════════════════════════════════════════════════════════════════════
class _Dashed extends StatelessWidget {
  final Widget child;
  final Color color;
  final Color background;
  const _Dashed({required this.child, required this.color, required this.background});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedPainter(color),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(15)),
        child: child,
      ),
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;
  _DashedPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(15)));
    for (final m in path.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 7), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) => old.color != color;
}

// ════════════════════════════════════════════════════════════════════════════
//  Image viewer (the web page's .verification-image-modal)
// ════════════════════════════════════════════════════════════════════════════
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
      if (mounted) {
        setState(() {
          _full = b;
          _loading = false;
        });
      }
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
        SizedBox(width: double.infinity, child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: shown == null
                ? const Padding(padding: EdgeInsets.all(40), child: Text('Image not available', style: TextStyle(color: Colors.white)))
                : ClipRRect(borderRadius: BorderRadius.circular(10), child: InteractiveViewer(child: Image.memory(shown, fit: BoxFit.contain, gaplessPlayback: true))),
          ),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: SizedBox(height: 3, width: 120, child: LinearProgressIndicator())),
          const SizedBox(height: 10),
          Text(widget.info, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 5),
          Text(widget.gps, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 12)),
          Text(widget.area, textAlign: TextAlign.center, style: TextStyle(color: areaColor, fontSize: 12)),
        ])),
        Positioned(top: 0, right: 0, child: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white, size: 30))),
      ]),
    );
  }
}
