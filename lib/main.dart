import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'data/mock_emergency_repository.dart';
import 'data/firebase_emergency_repository.dart';
import 'firebase_options.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  EmergencyRepository repository;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final fbRepo = FirebaseEmergencyRepository();
    await fbRepo.init();
    repository = fbRepo;
  } catch (e) {
    debugPrint('Firebase not initialized or running in local demo mode: $e');
    repository = MockEmergencyRepository();
  }

  runApp(VindaraApp(repository: repository));
}

/// Root Application Widget for Vindara
class VindaraApp extends StatelessWidget {
  final EmergencyRepository repository;

  const VindaraApp({
    super.key,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vindara',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: MainShell(repository: repository),
    );
  }
}
