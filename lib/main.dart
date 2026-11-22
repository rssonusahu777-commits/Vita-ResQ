// lib/main.dart
//
// SafeReach — Application Entry Point
// Package: com.example.safereach
//
// Phase 1: Minimal shell. No Firebase initialisation, no service wiring yet.

import 'package:flutter/material.dart';

void main() {
  runApp(const SafeReachApp());
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
/// Phase 1: stubs only. Full implementations come in Phase 5+.
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
// Placeholder Screen (Phase 1 only — replaced in Phase 5)
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

