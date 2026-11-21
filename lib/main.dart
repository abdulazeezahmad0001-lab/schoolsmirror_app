import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'api/api_client.dart';

// Screen Imports
import 'screens/login_screen.dart';
import 'screens/student_home.dart';
import 'screens/admin_home.dart';
import 'screens/onboarding_screen.dart'; // <-- ADDED IMPORT
import 'screens/push_notification_service.dart'; // push notifications

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase first
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Push notifications: lets Firebase deliver messages while the app is closed or in the background
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Load saved token (if any)
  await ApiClient.loadToken();

  // Check if user has seen onboarding
  final prefs = await SharedPreferences.getInstance();
  final bool hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

  runApp(SchoolsMirrorApp(hasSeenOnboarding: hasSeenOnboarding));
}

class SchoolsMirrorApp extends StatelessWidget {
  final bool hasSeenOnboarding;

  const SchoolsMirrorApp({super.key, required this.hasSeenOnboarding});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SchoolsMirror',
      debugShowCheckedModeBanner: false,

      // Better scrolling & behavior on web
      scrollBehavior: kIsWeb
          ? const MaterialScrollBehavior().copyWith(
              scrollbars: true,
            )
          : null,

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3A57A5),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A1929),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // If the user has seen onboarding, start at Login '/'
      // If not, start at Onboarding '/onboarding'
      initialRoute: hasSeenOnboarding ? '/' : '/onboarding',

      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/': (context) => const LoginScreen(),
        '/student': (context) => const StudentHome(),
        '/admin': (context) => const AdminHome(),
      },

      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        );
      },
    );
  }
}
