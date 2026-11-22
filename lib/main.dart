// lib/main.dart
//
// SafeReach — Application Entry Point
// Package: com.example.safereach
//
// Phase 2: Hive initialisation + ProviderScope added.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  // Required before any async plugin call.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Hive using the Flutter path-provider integration so it stores
  // data in the app's documents directory on both Android and iOS.
  // All boxes are opened lazily by their respective services; we just
  // initialise the root path here.
  await Hive.initFlutter();

  runApp(
    // ProviderScope is the Riverpod dependency-injection container.
    // It must wrap the entire widget tree exactly once (Rule #6 — single
    // lifecycle, never duplicated inside widget subtrees).
    const ProviderScope(
      child: SafeReachApp(),
    ),
  );
}

class SafeReachApp extends StatelessWidget {
  const SafeReachApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeReach',
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

/// Central route table for SafeReach.
/// Phase 2: stubs retained. Full implementations come in Phase 5+.
class AppRoutes {
  AppRoutes._();

  static const String home = '/';
  static const String responderDashboard = '/responder-dashboard';
  static const String emergencyDetail = '/emergency-detail';
  static const String userProfile = '/profile';

  static final Map<String, WidgetBuilder> routes = {
    home: (_) => const _PlaceholderScreen(title: 'SafeReach Home'),
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
