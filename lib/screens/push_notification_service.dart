// push_notification_service.dart
//
// Push notifications for the SchoolsMirror app (Firebase Cloud Messaging).
//   * asks for notification permission
//   * registers this phone's FCM token with flutter_push.php (and again whenever Firebase renews it)
//   * shows a notification when a message arrives while the app is OPEN (Android does not do this by itself)
//   * tells the app which screen to open when a notification is tapped
//   * exposes the in-app inbox (fetchNotifications / unreadCount / markAllRead)
//
// pubspec.yaml needs (all already in your pubspec): firebase_core, firebase_messaging,
// flutter_local_notifications, http, shared_preferences
//
// ONE-TIME APP SETUP (see the notes that came with this file):
//   1. main.dart:  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);   (before runApp)
//   2. AndroidManifest.xml: POST_NOTIFICATIONS permission + default channel meta-data
//   3. admin_home.dart already calls PushNotificationService.instance.start(...) after login (patched copy included)

import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';

/// must match PUSH_CHANNEL_ID in flutter_lib.php
const String kPushChannelId = 'schoolsmirror_results';
const String kPushChannelName = 'Results and school updates';

const List<String> _pushUrls = [
  'https://schoolsmirror.com/flutter_push',
  'https://schoolsmirror.com/flutter_push.php',
];

/// Register this in main():  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
/// Messages that carry a "notification" block are shown by Android/iOS by themselves while the app is
/// closed, so this only has to make sure Firebase is ready.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {}
}

class AppNotification {
  final int id;
  final String type, title, body, createdAt;
  final bool isRead;
  final Map<String, dynamic> data;
  const AppNotification(this.id, this.type, this.title, this.body, this.createdAt, this.isRead, this.data);

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        int.tryParse('${j['id']}') ?? 0,
        '${j['type'] ?? ''}',
        '${j['title'] ?? ''}',
        '${j['body'] ?? ''}',
        '${j['created_at'] ?? ''}',
        j['is_read'] == true,
        j['data'] is Map ? Map<String, dynamic>.from(j['data']) : <String, dynamic>{},
      );
}

class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  final List<StreamSubscription> _subs = [];
  bool _started = false;
  String? _authToken;
  String? _lastFcmToken;
  void Function(Map<String, dynamic> data)? _onOpen;
  Map<String, dynamic>? _pendingOpen;

  /// Last FCM token (useful for debugging)
  String? get fcmToken => _lastFcmToken;

  /// Call after login with the app's auth token. Safe to call many times.
  /// [onOpen] receives the "data" of a notification the user tapped, e.g. {screen: 'published-results', ...}
  Future<void> start({required String authToken, void Function(Map<String, dynamic> data)? onOpen}) async {
    _authToken = authToken;
    if (onOpen != null) setOnOpen(onOpen);
    if (_started) {
      await _syncToken();
      return;
    }
    _started = true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      await _initLocal();
      final m = FirebaseMessaging.instance;
      await m.requestPermission(alert: true, badge: true, sound: true);
      await m.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);

      _subs.add(m.onTokenRefresh.listen((t) {
        _lastFcmToken = t;
        _register(t);
      }));
      _subs.add(FirebaseMessaging.onMessage.listen(_onForeground));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen((msg) => _dispatch(msg.data)));

      // app was closed and the user opened it by tapping a notification
      final initial = await m.getInitialMessage();
      if (initial != null) _dispatch(initial.data);

      await _syncToken();
    } catch (e) {
      debugPrint('Push start failed: $e');
      _started = false; // try again on the next start()
    }
  }

  void setOnOpen(void Function(Map<String, dynamic> data) cb) {
    _onOpen = cb;
    final p = _pendingOpen;
    if (p != null) {
      _pendingOpen = null;
      cb(p);
    }
  }

  /// Call on logout so this phone stops receiving this user's notifications.
  Future<void> unregister() async {
    final auth = _authToken;
    final t = _lastFcmToken;
    _authToken = null;
    try {
      if (auth != null && t != null) await _PushApi.post(auth, 'unregister_device', {'fcm_token': t});
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
    _lastFcmToken = null;
  }

  // ───────────────────────────── in-app inbox ─────────────────────────────
  Future<List<AppNotification>> fetchNotifications(String authToken, {int page = 1}) async {
    final r = await _PushApi.post(authToken, 'my_notifications', {'page': '$page'});
    if (r['success'] != true) return [];
    final d = r['data'] is Map ? Map<String, dynamic>.from(r['data']) : <String, dynamic>{};
    return (d['notifications'] is List ? d['notifications'] as List : [])
        .map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<int> unreadCount(String authToken) async {
    final r = await _PushApi.post(authToken, 'unread_count');
    if (r['success'] != true) return 0;
    final d = r['data'] is Map ? Map<String, dynamic>.from(r['data']) : <String, dynamic>{};
    return int.tryParse('${d['unread']}') ?? 0;
  }

  Future<void> markAllRead(String authToken) => _PushApi.post(authToken, 'mark_read', {'all': '1'});

  /// Sends a test push to this user's own devices. Returns the server's message.
  Future<String> sendTest(String authToken) async {
    final r = await _PushApi.post(authToken, 'send_test');
    return '${r['message'] ?? 'No answer from the server'}';
  }

  // ───────────────────────────── internals ─────────────────────────────
  Future<void> _initLocal() async {
    const android = AndroidInitializationSettings('@mipmap/launcher_icon');
    const ios = DarwinInitializationSettings(
        requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false);
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (resp) {
        final p = resp.payload;
        if (p == null || p.isEmpty) return;
        try {
          _dispatch(Map<String, dynamic>.from(jsonDecode(p)));
        } catch (_) {}
      },
    );
    final androidImpl = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
      kPushChannelId,
      kPushChannelName,
      description: 'Result publishing and other school updates',
      importance: Importance.high,
    ));
  }

  Future<void> _onForeground(RemoteMessage message) async {
    final n = message.notification;
    final title = n?.title ?? message.data['title']?.toString();
    final body = n?.body ?? message.data['body']?.toString();
    if (title == null && body == null) return;
    try {
      await _local.show(
        message.hashCode & 0x7fffffff,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(kPushChannelId, kPushChannelName,
              importance: Importance.high, priority: Priority.high),
          iOS: DarwinNotificationDetails(),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('Local notification failed: $e');
    }
  }

  void _dispatch(Map<String, dynamic> data) {
    final cb = _onOpen;
    if (cb == null) {
      _pendingOpen = data; // the app is still starting: deliver as soon as a listener exists
      return;
    }
    cb(data);
  }

  Future<void> _syncToken() async {
    try {
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) {
        _lastFcmToken = t;
        await _register(t);
      }
    } catch (e) {
      debugPrint('FCM token failed: $e');
    }
  }

  Future<void> _register(String fcmToken) async {
    final auth = _authToken;
    if (auth == null || auth.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'push_registered_${auth.hashCode}';
    // skip the request when this exact token was already sent for this login
    if (prefs.getString(key) == fcmToken) return;
    final r = await _PushApi.post(auth, 'register_device', {
      'fcm_token': fcmToken,
      'platform': defaultTargetPlatform.name,
      'device_name': defaultTargetPlatform.name,
    });
    if (r['success'] == true) await prefs.setString(key, fcmToken);
  }
}

class _PushApi {
  static Future<Map<String, dynamic>> post(String token, String action, [Map<String, String> fields = const {}]) async {
    var net = false;
    Map<String, dynamic> last = {'success': false, 'message': 'Unexpected server response'};
    for (final base in _pushUrls) {
      try {
        final q = {'token': token, 'action': action, ...fields};
        final res = await http
            .post(Uri.parse(base).replace(queryParameters: q),
                headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: q)
            .timeout(const Duration(seconds: 20));
        final i = res.body.indexOf('{');
        final d = jsonDecode(i > 0 ? res.body.substring(i) : res.body);
        if (d is Map<String, dynamic>) {
          last = d;
          final m = '${d['message'] ?? ''}';
          // redirected address lost the data -> try the other form of the URL
          if (d['success'] != true && (m.startsWith('Missing token') || m.startsWith('The server received'))) continue;
          return d;
        }
      } catch (_) {
        net = true;
      }
    }
    return net ? {'success': false, 'network': true, 'message': 'No internet connection.'} : last;
  }
}
