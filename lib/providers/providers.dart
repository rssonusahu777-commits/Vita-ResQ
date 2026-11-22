// lib/providers/providers.dart
//
// SafeReach — Riverpod Providers (Phase 2)
// Package: com.example.safereach
//
// All providers are defined in one file for discoverability in Phase 2.
// Phase 3+ may split this into domain-specific files.
//
// Design rules followed:
//   Rule #6 — Every provider registers ref.onDispose to close streams/boxes.
//              No stream listener is ever created more than once per provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/emergency.dart';
import '../models/user_profile.dart';
import '../repositories/emergency_repository.dart';
import '../repositories/user_profile_repository.dart';
import '../services/local_emergency_store.dart';
import '../services/location_service.dart';

// ---------------------------------------------------------------------------
// 1. LocalEmergencyStore — opened once, lives for app lifetime
// ---------------------------------------------------------------------------

/// Provides the initialised [LocalEmergencyStore] singleton.
///
/// [FutureProvider] is used because Hive box opening is async.
/// All downstream providers depend on this via [ref.watch].
final localStoreProvider = FutureProvider<LocalEmergencyStore>((ref) async {
  final store = LocalEmergencyStore();
  await store.init();

  // Rule #6: close Hive boxes and stream controllers when provider is disposed.
  ref.onDispose(store.dispose);

  return store;
});

// ---------------------------------------------------------------------------
// 2. LocationService — depends on the store for the GPS cache
// ---------------------------------------------------------------------------

/// Provides the [LocationService] once the local store is ready.
final locationServiceProvider = Provider<LocationService?>((ref) {
  final storeAsync = ref.watch(localStoreProvider);

  return storeAsync.when(
    data: (store) {
      final service = LocationService(store);
      // LocationService itself has no dispose logic in Phase 2;
      // the stream subscription lifecycle is the caller's responsibility (Rule #6).
      return service;
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// ---------------------------------------------------------------------------
// 3. EmergencyRepository
// ---------------------------------------------------------------------------

/// Provides [EmergencyRepository] once both the store and location service
/// are ready. Returns null while either dependency is initialising.
final emergencyRepositoryProvider = Provider<EmergencyRepository?>((ref) {
  final storeAsync = ref.watch(localStoreProvider);
  final locationService = ref.watch(locationServiceProvider);

  return storeAsync.when(
    data: (store) {
      if (locationService == null) return null;
      return EmergencyRepository(
        store: store,
        locationService: locationService,
      );
    },
    loading: () => null,
    error: (_, __) => null,
  );
});

// ---------------------------------------------------------------------------
// 4. UserProfileRepository
// ---------------------------------------------------------------------------

/// Provides the initialised [UserProfileRepository].
final userProfileRepositoryProvider =
    FutureProvider<UserProfileRepository>((ref) async {
  final repo = UserProfileRepository();
  await repo.init();

  // Rule #6: close Hive box on dispose.
  ref.onDispose(repo.dispose);

  return repo;
});

// ---------------------------------------------------------------------------
// 5. Current UserProfile state (AsyncNotifier)
// ---------------------------------------------------------------------------

/// Mutable provider for the current user's [UserProfile].
///
/// Loads from [UserProfileRepository] on first access.
/// UI can call [ref.read(currentUserProfileProvider.notifier).save(profile)]
/// to persist changes.
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

  /// Persists [profile] locally and updates provider state.
  Future<void> save(UserProfile profile) async {
    state = const AsyncLoading();
    final repo = await ref.read(userProfileRepositoryProvider.future);
    await repo.saveProfile(profile);
    state = AsyncData(profile);
  }

  /// Toggles the responder availability flag and persists.
  Future<void> setAvailability(bool isAvailable) async {
    final repo = await ref.read(userProfileRepositoryProvider.future);
    final updated = await repo.setAvailability(isAvailable);
    if (updated != null) {
      state = AsyncData(updated);
    }
  }
}

// ---------------------------------------------------------------------------
// 6. Emergency stream — per-id family (Rule #6: single stream per id)
// ---------------------------------------------------------------------------

/// Family provider that returns a [Stream<Emergency?>] for a single emergency
/// identified by [id].
///
/// Each unique [id] gets exactly one [StreamController] inside
/// [LocalEmergencyStore.watchEmergency] — never duplicated (Rule #6).
///
/// Usage in a widget:
/// ```dart
/// final emergencyAsync = ref.watch(emergencyStreamProvider('EMG-2026-ABCD1234'));
/// ```
final emergencyStreamProvider =
    StreamProvider.family<Emergency?, String>((ref, id) {
  final storeAsync = ref.watch(localStoreProvider);

  return storeAsync.when(
    data: (store) => store.watchEmergency(id),
    // Emit a loading state until the store is ready.
    loading: () => const Stream.empty(),
    error: (e, _) => Stream.error(e),
  );
});

// ---------------------------------------------------------------------------
// 7. All emergencies list (simple read — no live stream in Phase 2)
// ---------------------------------------------------------------------------

/// Returns all locally persisted emergencies as an async snapshot.
/// Invalidated manually after mutations (Phase 2 — no live Firestore stream yet).
final allEmergenciesProvider = FutureProvider<List<Emergency>>((ref) async {
  final store = await ref.watch(localStoreProvider.future);
  return store.getAllEmergencies();
});
