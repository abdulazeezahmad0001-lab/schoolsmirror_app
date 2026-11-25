// lib/services/auth_helper.dart
import 'package:flutter/material.dart';
import '../api/api_client.dart'; // lib/api/api_client.dart
import '../screens/push_notification_service.dart'; // lib/screens/push_notification_service.dart

/// Logout for ANY role (student, teacher, admin).
/// The "welcome back" login memory and the onboarding flag are kept (they live in AppFlags, not here).
Future<void> logoutUser(BuildContext context) async {
  // 1. stop this phone receiving this user's notifications
  try {
    await PushNotificationService.instance.unregister();
  } catch (_) {}

  // 2. clear the login token
  await ApiClient.logout();

  // 3. back to login (remove all previous screens)
  if (context.mounted) {
    Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
  }
}
