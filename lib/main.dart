import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'core/theme/app_theme.dart';
import 'data/mock_emergency_repository.dart';
import 'data/firebase_emergency_repository.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/main_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  EmergencyRepository repository;
  bool firebaseConnected = false;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final fbRepo = FirebaseEmergencyRepository();
    await fbRepo.init();
    repository = fbRepo;
    firebaseConnected = true;
  } catch (e) {
    debugPrint('Firebase not initialized or running in local demo mode: $e');
    repository = MockEmergencyRepository();
  }

  runApp(VindaraApp(
    repository: repository,
    isFirebaseConnected: firebaseConnected,
  ));
}

/// Root Application Widget for Vindara
class VindaraApp extends StatefulWidget {
  final EmergencyRepository repository;
  final bool isFirebaseConnected;

  const VindaraApp({
    super.key,
    required this.repository,
    this.isFirebaseConnected = false,
  });

  @override
  State<VindaraApp> createState() => _VindaraAppState();
}

class _VindaraAppState extends State<VindaraApp> {
  bool _offlineBypass = false;

  User? _safeCurrentUser() {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance.currentUser;
      }
    } catch (_) {}
    return null;
  }

  Stream<User?> _safeAuthStateChanges() {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance.authStateChanges();
      }
    } catch (_) {}
    return Stream.value(null);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vindara',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: _buildHomeGate(),
    );
  }

  Widget _buildHomeGate() {
    if (_offlineBypass) {
      return MainShell(repository: widget.repository);
    }

    // Stream-based gate on FirebaseAuth
    return StreamBuilder<User?>(
      stream: _safeAuthStateChanges(),
      initialData: _safeCurrentUser(),
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user != null) {
          return MainShell(repository: widget.repository);
        }

        return AuthScreen(
          repository: widget.repository,
          onOfflineAccess: () {
            setState(() {
              _offlineBypass = true;
            });
          },
        );
      },
    );
  }
}
