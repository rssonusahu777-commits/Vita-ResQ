// lib/main.dart
//
// Vindara — Application Entry Point
// Package: com.vindara.app
//
// Phase 5: High-Contrast Accessible Vindara Theme + GoRouter Integration.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'router/app_router.dart';
import 'theme/vindara_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Hive
  await Hive.initFlutter();

  // Safe fallback Firebase initialization
  await _initFirebaseSafely();

  runApp(
    const ProviderScope(
      child: VindaraApp(),
    ),
  );
}

Future<void> _initFirebaseSafely() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    debugPrint('Firebase not initialized or missing configuration: $e');
  }
}

class VindaraApp extends ConsumerWidget {
  const VindaraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Vindara',
      debugShowCheckedModeBanner: false,
      theme: VindaraTheme.lightTheme(),
      routerConfig: router,
    );
  }
}
