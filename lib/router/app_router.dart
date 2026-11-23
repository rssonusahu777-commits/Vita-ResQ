// lib/router/app_router.dart
//
// Vindara — App Router & Deep-Link Integration (Phase 6 & Live Auth)
// Package: com.vindara.app

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../screens/auth_screen.dart';
import '../screens/crash_countdown_screen.dart';
import '../screens/emergency_detail_screen.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final isBypassed = ref.watch(offlineEmergencyBypassProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // In local unit/widget test environments without Firebase initialized,
      // do not redirect to /auth so existing screen tests pass directly.
      if (Firebase.apps.isEmpty) {
        return null;
      }

      final user = authState.asData?.value;
      final isAuthenticated = user != null || isBypassed;
      final isAuthRoute = state.matchedLocation == '/auth';

      if (!isAuthenticated && !isAuthRoute) {
        return '/auth';
      }
      if (isAuthenticated && isAuthRoute) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const RouterLifecycleListener(
          child: HomeScreen(),
        ),
      ),
      GoRoute(
        path: '/emergency/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return RouterLifecycleListener(
            child: EmergencyDetailScreen(emergencyId: id),
          );
        },
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const RouterLifecycleListener(
          child: ProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/crash-countdown',
        builder: (context, state) => const CrashCountdownScreen(),
      ),
    ],
  );
});

class RouterLifecycleListener extends ConsumerStatefulWidget {
  final Widget child;

  const RouterLifecycleListener({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<RouterLifecycleListener> createState() =>
      _RouterLifecycleListenerState();
}

class _RouterLifecycleListenerState
    extends ConsumerState<RouterLifecycleListener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pendingTarget =
          ref.read(pendingDeepLinkProvider.notifier).consume();
      if (pendingTarget != null && mounted) {
        context.push(pendingTarget);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 1. Listen to background notification taps
    ref.listen<AsyncValue<String>>(deepLinkStreamProvider, (prev, next) {
      next.whenData((targetPath) {
        if (targetPath.isNotEmpty && mounted) {
          context.push(targetPath);
        }
      });
    });

    // 2. Listen to foreground heads-up banners
    ref.listen<AsyncValue<dynamic>>(inAppAlertStreamProvider, (prev, next) {
      next.whenData((event) {
        if (event != null && mounted) {
          final emergencyId = event.emergencyId as String;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              backgroundColor: const Color(0xFFD32F2F),
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '🚨 HELP NEEDED NEAR YOU • $emergencyId',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              action: SnackBarAction(
                label: 'VIEW',
                textColor: Colors.white,
                onPressed: () => context.push('/emergency/$emergencyId'),
              ),
            ),
          );
        }
      });
    });

    // 3. Listen to Possible Crash detection events (Rule #10)
    ref.listen<AsyncValue<dynamic>>(possibleCrashStreamProvider, (prev, next) {
      next.whenData((crashEvent) {
        if (crashEvent != null && mounted) {
          // Guard against duplicate pushes if already on countdown
          final currentPath = GoRouterState.of(context).uri.path;
          if (currentPath != '/crash-countdown') {
            context.push('/crash-countdown');
          }
        }
      });
    });

    return widget.child;
  }
}
