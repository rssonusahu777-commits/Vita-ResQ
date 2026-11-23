// lib/providers/providers.dart
//
// Vindara — Riverpod Providers (Phase 6)
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #1 — Real reachability stream exposed.
//   Rule #3 — Firestore emergency service with atomic claims.
//   Rule #4 — Deep link navigation passes only emergencyId (source of truth is Firestore).
//   Rule #5 — FCM lifecycle handling for foreground, background, and cold start.
//   Rule #6 — Every provider registers ref.onDispose to close streams/boxes.
//              Single-lifecycle listeners without duplication.
//   Rule #8 — Offline sync queue auto-drains when online.
//   Rule #9 — Minimal push payloads without sensitive PII.
//   Rule #10 — Possible crash detection with 10s countdown.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emergency.dart';
import '../models/user_profile.dart';
import '../repositories/emergency_repository.dart';
import '../repositories/user_profile_repository.dart';
import '../services/connectivity_service.dart';
import '../services/crash_detection_service.dart';
import '../services/firestore_emergency_service.dart';
import '../services/local_emergency_store.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';

// ---------------------------------------------------------------------------
// 1. LocalEmergencyStore — opened once, lives for app lifetime
// ---------------------------------------------------------------------------

final localStoreProvider = FutureProvider<LocalEmergencyStore>((ref) async {
  final store = LocalEmergencyStore();
  await store.init();
  ref.onDispose(store.dispose);
  return store;
});

// ---------------------------------------------------------------------------
// 2. ConnectivityService & Online Stream
// ---------------------------------------------------------------------------

final connectivityServiceProvider =
    FutureProvider<ConnectivityService>((ref) async {
  final service = ConnectivityService();
  await service.init();
  ref.onDispose(service.dispose);
  return service;
});

/// Stream of real internet reachability (Rule #1).
final isOnlineStreamProvider = StreamProvider<bool>((ref) {
  final connectivityAsync = ref.watch(connectivityServiceProvider);
  return connectivityAsync.when(
    data: (service) => service.isOnline,
    loading: () => const Stream.empty(),
    error: (e, _) => Stream.error(e),
  );
});

// ---------------------------------------------------------------------------
// 3. LocationService
// ---------------------------------------------------------------------------

final locationServiceProvider = Provider<LocationService?>((ref) {
  final storeAsync = ref.watch(localStoreProvider);

  return storeAsync.when(
    data: (store) => LocationService(store),
    loading: () => null,
    error: (_, __) => null,
  );
});

// ---------------------------------------------------------------------------
// 4. FirestoreEmergencyService
// ---------------------------------------------------------------------------

final firestoreEmergencyServiceProvider =
    Provider<FirestoreEmergencyService>((ref) {
  return FirestoreEmergencyService();
});

// ---------------------------------------------------------------------------
// 5. SyncService (drains pending queue whenever online)
// ---------------------------------------------------------------------------

final syncServiceProvider = FutureProvider<SyncService?>((ref) async {
  final store = await ref.watch(localStoreProvider.future);
  final connectivity = await ref.watch(connectivityServiceProvider.future);
  final firestoreService = ref.watch(firestoreEmergencyServiceProvider);

  final syncService = SyncService(
    localStore: store,
    firestoreService: firestoreService,
    connectivityService: connectivity,
  );

  await syncService.init();
  ref.onDispose(syncService.dispose);
  return syncService;
});

// ---------------------------------------------------------------------------
// 6. EmergencyRepository
// ---------------------------------------------------------------------------

final emergencyRepositoryProvider = Provider<EmergencyRepository?>((ref) {
  final storeAsync = ref.watch(localStoreProvider);
  final locationService = ref.watch(locationServiceProvider);
  final connectivityAsync = ref.watch(connectivityServiceProvider);
  final firestoreService = ref.watch(firestoreEmergencyServiceProvider);

  return storeAsync.when(
    data: (store) {
      if (locationService == null) return null;
      final connectivity = connectivityAsync.asData?.value;

      return EmergencyRepository(
        store: store,
        locationService: locationService,
        connectivityService: connectivity,
        firestoreService: firestoreService,
      );
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// ---------------------------------------------------------------------------
// 7. UserProfileRepository
// ---------------------------------------------------------------------------

final userProfileRepositoryProvider =
    FutureProvider<UserProfileRepository>((ref) async {
  final repo = UserProfileRepository();
  await repo.init();
  ref.onDispose(repo.dispose);
  return repo;
});

// ---------------------------------------------------------------------------
// 8. Current UserProfile state
// ---------------------------------------------------------------------------

final currentUserProfileProvider =
    AsyncNotifierProvider<CurrentUserProfileNotifier, UserProfile?>(
  CurrentUserProfileNotifier.new,
);

class CurrentUserProfileNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final repoAsync = await ref.watch(userProfileRepositoryProvider.future);
    return repoAsync.getProfile();
  }

  Future<void> save(UserProfile profile) async {
    state = const AsyncLoading();
    final repo = await ref.read(userProfileRepositoryProvider.future);
    await repo.saveProfile(profile);
    state = AsyncData(profile);
  }

  Future<void> setAvailability(bool isAvailable) async {
    final repo = await ref.read(userProfileRepositoryProvider.future);
    final updated = await repo.setAvailability(isAvailable);
    if (updated != null) {
      state = AsyncData(updated);
    }
  }

  Future<void> updateFcmToken(String token) async {
    final current = state.asData?.value;
    if (current != null && current.fcmToken != token) {
      final updated = current.copyWith(fcmToken: token);
      await save(updated);
    }
  }
}

// ---------------------------------------------------------------------------
// 9. NotificationService & Deep Linking (Phase 4 — Rules #4, #5, #6, #9)
// ---------------------------------------------------------------------------

final pendingDeepLinkProvider =
    StateNotifierProvider<PendingDeepLinkNotifier, String?>((ref) {
  return PendingDeepLinkNotifier();
});

class PendingDeepLinkNotifier extends StateNotifier<String?> {
  PendingDeepLinkNotifier([super.initial]);

  void setPending(String? target) {
    state = target;
  }

  String? consume() {
    final target = state;
    state = null;
    return target;
  }
}

final notificationServiceProvider =
    FutureProvider<NotificationService>((ref) async {
  final service = NotificationService();
  final coldStartTarget = await service.init();

  if (coldStartTarget != null && coldStartTarget.isNotEmpty) {
    ref.read(pendingDeepLinkProvider.notifier).setPending('/emergency/$coldStartTarget');
  }

  final token = service.fcmToken;
  if (token != null && token.isNotEmpty) {
    ref.read(currentUserProfileProvider.notifier).updateFcmToken(token);
  }

  ref.onDispose(service.dispose);
  return service;
});

final deepLinkStreamProvider = StreamProvider<String>((ref) {
  final serviceAsync = ref.watch(notificationServiceProvider);
  return serviceAsync.when(
    data: (service) => service.deepLinkStream,
    loading: () => const Stream.empty(),
    error: (e, _) => Stream.error(e),
  );
});

final inAppAlertStreamProvider = StreamProvider<InAppAlertEvent>((ref) {
  final serviceAsync = ref.watch(notificationServiceProvider);
  return serviceAsync.when(
    data: (service) => service.inAppAlertStream,
    loading: () => const Stream.empty(),
    error: (e, _) => Stream.error(e),
  );
});

// ---------------------------------------------------------------------------
// 10. Crash Detection Service & Toggle (Phase 6 — Rules #6 & #10)
// ---------------------------------------------------------------------------

/// State provider for enabling / disabling motion crash monitoring.
final crashMonitoringEnabledProvider =
    StateNotifierProvider<CrashMonitoringNotifier, bool>((ref) {
  return CrashMonitoringNotifier();
});

class CrashMonitoringNotifier extends StateNotifier<bool> {
  CrashMonitoringNotifier() : super(true); // Enabled by default

  void toggle(bool enabled) {
    state = enabled;
  }
}

/// Single-lifecycle CrashDetectionService (Rule #6).
final crashDetectionServiceProvider = Provider<CrashDetectionService>((ref) {
  final service = CrashDetectionService();

  // Watch monitoring state to start / stop sensor subscriptions
  final isEnabled = ref.watch(crashMonitoringEnabledProvider);
  if (isEnabled) {
    service.startMonitoring();
  } else {
    service.stopMonitoring();
  }

  ref.onDispose(service.dispose);
  return service;
});

/// Stream of possible crash events.
final possibleCrashStreamProvider = StreamProvider<PossibleCrashEvent>((ref) {
  final service = ref.watch(crashDetectionServiceProvider);
  return service.possibleCrashStream;
});

// ---------------------------------------------------------------------------
// 11. Emergency streams (Local & Remote)
// ---------------------------------------------------------------------------

final emergencyStreamProvider =
    StreamProvider.family<Emergency?, String>((ref, id) {
  final storeAsync = ref.watch(localStoreProvider);

  return storeAsync.when(
    data: (store) => store.watchEmergency(id),
    loading: () => const Stream.empty(),
    error: (e, _) => Stream.error(e),
  );
});

final remoteEmergencyStreamProvider =
    StreamProvider.family<Emergency?, String>((ref, id) {
  final firestoreService = ref.watch(firestoreEmergencyServiceProvider);
  return firestoreService.watchRemoteEmergency(id);
});

final allEmergenciesProvider = FutureProvider<List<Emergency>>((ref) async {
  final store = await ref.watch(localStoreProvider.future);
  return store.getAllEmergencies();
});
