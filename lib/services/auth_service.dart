import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../core/constants/app_constants.dart';
import 'local_database_service.dart';
import 'responder_mode_service.dart';

class AuthService {
  final FirebaseAuth? _injectedAuth;
  final FirebaseFirestore? _injectedFirestore;

  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _injectedAuth = auth,
        _injectedFirestore = firestore;

  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore => _injectedFirestore ?? FirebaseFirestore.instance;

  static const String _localUserKey = 'local_user_profile_v2';
  static const String _guestOfflineKey = 'guest_offline_session_v1';
  static UserModel? _cachedLocalUser;
  static bool? _cachedGuestOfflineSession;

  /// Whether current session is in guest / logged-out offline emergency access mode.
  static Future<bool> isGuestOfflineSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getBool(_guestOfflineKey) ?? false;
      _cachedGuestOfflineSession = val;
      return val;
    } catch (_) {
      return _cachedGuestOfflineSession ?? false;
    }
  }

  /// Synchronous quick check for cached guest offline status (false if unset)
  static bool get isGuestOfflineSessionSync => _cachedGuestOfflineSession ?? false;

  /// Resets in-memory cached state (used in unit tests)
  static void resetCacheForTesting() {
    _cachedLocalUser = null;
    _cachedGuestOfflineSession = null;
  }

  /// Enters guest offline emergency access mode:
  /// - Sets isolated guest session flag.
  /// - Does NOT modify or contaminate `local_user_profile_v2`.
  /// - Returns a deterministic guest ID: `offline_guest_<originDeviceId>`.
  Future<String> enterGuestOfflineMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_guestOfflineKey, true);
    _cachedGuestOfflineSession = true;

    final deviceId = await LocalDatabaseService.getOrCreateLocalDeviceId();
    return 'offline_guest_$deviceId';
  }

  /// Exits guest offline emergency access mode cleanly.
  Future<void> exitGuestOfflineMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_guestOfflineKey);
    } catch (_) {}
    _cachedGuestOfflineSession = false;
  }

  /// Returns the current effective user ID:
  /// - Firebase user UID if logged in.
  /// - `offline_guest_<originDeviceId>` if in guest offline mode.
  /// - 'offline_user' as fallback.
  Future<String> getEffectiveUserId() async {
    final user = currentUser;
    if (user != null) return user.uid;
    final isGuest = await isGuestOfflineSession();
    if (isGuest) {
      final deviceId = await LocalDatabaseService.getOrCreateLocalDeviceId();
      return 'offline_guest_$deviceId';
    }
    return 'offline_user';
  }

  User? get currentUser {
    try {
      return _auth.currentUser;
    } catch (_) {
      return null;
    }
  }

  Stream<User?> get authStateChanges {
    try {
      return _auth.authStateChanges();
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Retrieve user profile from local cache or Firestore.
  /// Strictly ensures that the profile returned matches the requested [uid].
  Future<UserModel?> getUserProfile(String uid) async {
    final currentAuthUid = currentUser?.uid;
    final bool isCurrentAuthUser = currentAuthUid != null && currentAuthUid == uid;

    // 1. Check in-memory cache if it matches the requested UID
    if (_cachedLocalUser != null && _cachedLocalUser!.id == uid) {
      return _cachedLocalUser;
    }

    // 2. Check local persistent storage ONLY if requested UID matches the local user
    try {
      final prefs = await SharedPreferences.getInstance();
      String? localData = prefs.getString(_localUserKey);
      if (localData != null && localData.isNotEmpty) {
        Map<String, dynamic> map = jsonDecode(localData);
        String? storedId = map['id'];

        // Only return if stored profile matches requested UID, or if caller is requesting
        // the current authenticated user and the stored profile matches.
        if (storedId == uid || (isCurrentAuthUser && (storedId == null || storedId.isEmpty))) {
          _cachedLocalUser = UserModel(
            id: storedId ?? uid,
            name: map['name'] ?? 'Responder',
            email: map['email'] ?? '',
            phoneNumber: map['phoneNumber'],
            bloodGroup: map['bloodGroup'],
            userRole: map['userRole'] ?? 'CITIZEN',
            vehicleNumber: map['vehicleNumber'],
            isOnline: true,
            createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
            updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
          );
          return _cachedLocalUser;
        }
      }
    } catch (_) {}

    // 3. Query Firestore for requested UID (works for both current user and other users)
    try {
      DocumentSnapshot snap = await _firestore.collection(AppConstants.usersCollection).doc(uid).get();
      if (snap.exists && snap.data() != null) {
        UserModel profile = UserModel.fromMap(snap.data() as Map<String, dynamic>, uid);
        // ONLY cache locally if the fetched profile belongs to the current authenticated user
        if (isCurrentAuthUser || (currentAuthUid == null && _cachedLocalUser?.id == uid)) {
          await _saveUserLocally(profile);
        }
        return profile;
      }
    } catch (_) {}

    // 4. Never substitute the locally cached profile when uid != requested profile UID.
    // If the requested UID is the current authenticated user and we have a cached copy, return it.
    if (_cachedLocalUser != null && _cachedLocalUser!.id == uid) {
      return _cachedLocalUser;
    }

    return null;
  }

  Future<void> _saveUserLocally(UserModel user) async {
    final currentAuthUid = currentUser?.uid;
    // Safety check: only save to local device storage if the user is the current user or local device profile
    if (currentAuthUid != null && currentAuthUid != user.id) {
      return;
    }
    _cachedLocalUser = user;
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> map = {
        'id': user.id,
        'name': user.name,
        'email': user.email,
        'phoneNumber': user.phoneNumber,
        'bloodGroup': user.bloodGroup,
        'userRole': user.userRole,
        'vehicleNumber': user.vehicleNumber,
        'isOnline': user.isOnline,
        'createdAt': user.createdAt.toIso8601String(),
        'updatedAt': user.updatedAt.toIso8601String(),
      };
      await prefs.setString(_localUserKey, jsonEncode(map));
    } catch (_) {}
  }

  Future<void> updateUserProfile({
    required String name,
    String? phoneNumber,
    String? bloodGroup,
    String? userRole,
    String? vehicleNumber,
  }) async {
    User? user = _auth.currentUser;
    String uid = user?.uid ?? _cachedLocalUser?.id ?? 'local_user';

    UserModel updated = UserModel(
      id: uid,
      name: name,
      email: user?.email ?? _cachedLocalUser?.email ?? '',
      phoneNumber: phoneNumber ?? _cachedLocalUser?.phoneNumber,
      bloodGroup: bloodGroup ?? _cachedLocalUser?.bloodGroup,
      userRole: userRole ?? _cachedLocalUser?.userRole ?? 'CITIZEN',
      vehicleNumber: vehicleNumber ?? _cachedLocalUser?.vehicleNumber,
      isOnline: true,
      createdAt: _cachedLocalUser?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _saveUserLocally(updated);

    try {
      if (user != null) await user.updateDisplayName(name);
      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(uid)
          .set({
        'name': name,
        'phoneNumber': phoneNumber,
        'bloodGroup': bloodGroup,
        if (userRole != null) 'userRole': userRole,
        if (vehicleNumber != null) 'vehicleNumber': vehicleNumber,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  /// Register new user with Email & Password
  Future<UserCredential> registerWithEmailAndPassword({
    required String name,
    required String email,
    required String password,
    String? phoneNumber,
    String? bloodGroup,
    String userRole = 'CITIZEN',
    String? vehicleNumber,
  }) async {
    UserCredential credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (credential.user != null) {
      await credential.user!.updateDisplayName(name);

      UserModel newUser = UserModel(
        id: credential.user!.uid,
        name: name,
        email: email,
        phoneNumber: phoneNumber,
        bloodGroup: bloodGroup,
        userRole: userRole,
        vehicleNumber: vehicleNumber,
        isOnline: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await _saveUserLocally(newUser);

      try {
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(credential.user!.uid)
            .set(newUser.toMap(), SetOptions(merge: true));
      } catch (_) {}
    }

    return credential;
  }

  /// Log in with Email & Password
  Future<UserCredential> loginWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    UserCredential credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    if (credential.user != null) {
      UserModel? profile = await getUserProfile(credential.user!.uid);
      if (profile == null) {
        UserModel newProfile = UserModel(
          id: credential.user!.uid,
          name: credential.user!.displayName ?? 'Citizen Responder',
          email: email,
          phoneNumber: credential.user!.phoneNumber,
          userRole: 'CITIZEN',
          isOnline: true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await _saveUserLocally(newProfile);
        try {
          await _firestore
              .collection(AppConstants.usersCollection)
              .doc(credential.user!.uid)
              .set(newProfile.toMap(), SetOptions(merge: true));
        } catch (_) {}
      } else {
        try {
          await _firestore
              .collection(AppConstants.usersCollection)
              .doc(credential.user!.uid)
              .update({
            'isOnline': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {}
      }
    }

    return credential;
  }

  Future<void> signOut() async {
    try {
      await ResponderModeService.instance.stopResponderMode();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_localUserKey);
      _cachedLocalUser = null;
    } catch (_) {}

    try {
      if (currentUser != null) {
        await _firestore
            .collection(AppConstants.usersCollection)
            .doc(currentUser!.uid)
            .update({
          'isOnline': false,
          'fcmToken': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await _auth.signOut();
    } catch (_) {}
  }
}
