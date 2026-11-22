// lib/router/app_router.dart
//
// Vindara — App Router & Deep-Link Integration
// Package: com.vindara.app
//
// Configures GoRouter and deep-link lifecycle handling (Rules #4, #5, #6).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/providers.dart';
import '../screens/emergency_detail_screen.dart';
import '../screens/home_screen.dart';
import '../screens/profile_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
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
    ],
  );
});

/// Root wrapper that consumes pending cold-start deep links and listens
/// to incoming background/foreground notification events cleanly (Rule #5 & #6).
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
    // Cold-start pending deep-link check after frame renders
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
    // Listen to background notification taps
    ref.listen<AsyncValue<String>>(deepLinkStreamProvider, (prev, next) {
      next.whenData((targetPath) {
        if (targetPath.isNotEmpty && mounted) {
          context.push(targetPath);
        }
      });
    });

    // Listen to foreground heads-up banners
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

    return widget.child;
  }
}
