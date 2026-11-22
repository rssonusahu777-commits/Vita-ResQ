// lib/providers/providers.dart
//
// Vindara — Riverpod Providers (Phase 3)
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #1 — Real reachability stream exposed.
//   Rule #3 — Firestore emergency service with atomic claims.
//   Rule #6 — Every provider registers ref.onDispose to close streams/boxes.
//              Single-lifecycle listeners without duplication.
//   Rule #8 — Offline sync queue auto-drains when online.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emergency.dart';
import '../models/user_profile.dart';
import '../repositories/emergency_repository.dart';
import '../repositories/user_profile_repository.dart';
import '../services/connectivity_service.dart';
import '../services/firestore_emergency_service.dart';
import '../services/local_emergency_store.dart';
import '../services/location_service.dart';
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
}

// ---------------------------------------------------------------------------
// 9. Emergency streams (Local & Remote)
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
