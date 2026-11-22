// lib/repositories/user_profile_repository.dart
//
// SafeReach — UserProfile Repository (local-only, Phase 2)
// Package: com.example.safereach
//
// Persists the current user's profile in a dedicated Hive box.
// Phase 3 will add Firestore sync on top.

import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';

import '../models/user_profile.dart';

// ---------------------------------------------------------------------------
// UserProfileRepository
// ---------------------------------------------------------------------------

/// Local-only persistence for the authenticated user's [UserProfile].
///
/// One instance per app run, owned by [userProfileRepositoryProvider].
/// The Hive box stores a single JSON blob keyed by the user's UID.
class UserProfileRepository {
  static const String _boxName = 'user_profile_box';
  static const String _currentProfileKey = 'current_profile';

  Box? _box;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Opens the Hive box. Must be awaited before any other call.
  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
  }

  /// Closes the Hive box. Called from [ref.onDispose].
  Future<void> dispose() async {
    await _box?.close();
  }

  Box get _opened {
    assert(_box != null,
        'UserProfileRepository.init() must be called before use.');
    return _box!;
  }

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Persists [profile] locally. Overwrites any previously saved profile.
  Future<void> saveProfile(UserProfile profile) async {
    await _opened.put(_currentProfileKey, jsonEncode(profile.toJson()));
  }

  /// Updates only the [isAvailable] flag without loading/saving the whole object.
  /// Used by the responder toggle on the dashboard.
  Future<UserProfile?> setAvailability(bool isAvailable) async {
    final current = getProfile();
    if (current == null) return null;
    final updated = current.copyWith(isAvailable: isAvailable);
    await saveProfile(updated);
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Returns the locally persisted [UserProfile], or `null` if none exists.
  UserProfile? getProfile() {
    final raw = _opened.get(_currentProfileKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw as String) as Map<String, dynamic>;
      return UserProfile.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Clear (e.g., on sign-out)
  // ---------------------------------------------------------------------------

  /// Removes the locally cached profile. Call on user sign-out.
  Future<void> clearProfile() async {
    await _opened.delete(_currentProfileKey);
  }
}
