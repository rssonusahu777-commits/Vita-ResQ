// lib/main.dart
//
// Vindara — Application Entry Point
// Package: com.vindara.app
//
// Phase 3: Firebase safe initialization wrapper + Hive + ProviderScope.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  // Required before any async plugin call.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive using Flutter path integration.
  await Hive.initFlutter();

  // Initialize Firebase with a safe fallback wrapper so offline mode,
  // desktop testing, or environments without firebase_options.dart boot cleanly.
  await _initFirebaseSafely();

  runApp(
    // ProviderScope is the Riverpod dependency-injection container.
    // Wrapped at root (Rule #6 — single lifecycle, never duplicated).
    const ProviderScope(
      child: VindaraApp(),
    ),
  );
}

/// Safely initializes default Firebase app, capturing missing options or offline boot.
Future<void> _initFirebaseSafely() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    // Graceful fallback: Firebase services will operate in offline/mock mode or defer
    // until cloud configuration is supplied.
    debugPrint('Firebase not initialized or missing configuration: $e');
  }
}

class VindaraApp extends StatelessWidget {
  const VindaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vindara',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F), // Emergency red
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: AppRoutes.routes,
    );
  }
}

// ---------------------------------------------------------------------------
// Route Registry
// ---------------------------------------------------------------------------

/// Central route table for Vindara.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String responderDashboard = '/responder-dashboard';
  static const String emergencyDetail = '/emergency-detail';
  static const String userProfile = '/profile';

  static final Map<String, WidgetBuilder> routes = {
    home: (_) => const _PlaceholderScreen(title: 'Vindara Home'),
    responderDashboard: (_) =>
        const _PlaceholderScreen(title: 'Responder Dashboard'),
    emergencyDetail: (_) =>
        const _PlaceholderScreen(title: 'Emergency Detail'),
    userProfile: (_) => const _PlaceholderScreen(title: 'User Profile'),
  };
}

// ---------------------------------------------------------------------------
// Placeholder Screen (replaced in Phase 5)
// ---------------------------------------------------------------------------

class _PlaceholderScreen extends StatelessWidget {
  final String title;

  const _PlaceholderScreen({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.construction_rounded,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Coming in a future phase.',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
