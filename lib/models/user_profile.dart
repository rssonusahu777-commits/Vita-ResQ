// lib/models/user_profile.dart
//
// Vindara — UserProfile Domain Model
// Package: com.vindara.app
//
// Design notes:
//   - Includes fcmToken for device push notification addressing.
//   - Responder status and reputation points are authoritative in Firestore.

class UserProfile {
  /// Firebase Auth UID. Immutable after account creation.
  final String uid;

  /// User-chosen display name shown in the app UI.
  final String displayName;

  /// Whether this user has been vetted and verified as a community responder.
  /// Set server-side only. Clients must NOT modify this field locally.
  final bool isVerifiedResponder;

  /// Whether the responder is currently accepting emergency assignments.
  /// Only meaningful when [isVerifiedResponder] is `true`.
  final bool isAvailable;

  /// Total number of emergencies this responder has been assigned to.
  final int responseHistoryCount;

  /// Number of emergencies this responder has resolved with a positive outcome.
  final int successfulAssistanceCount;

  /// Gamified reputation score.
  final int reputationPoints;

  /// List of badge identifiers earned by this user.
  final List<String> badges;

  /// Device Firebase Cloud Messaging (FCM) registration token for alerts.
  final String? fcmToken;

  const UserProfile({
    required this.uid,
    required this.displayName,
    this.isVerifiedResponder = false,
    this.isAvailable = false,
    this.responseHistoryCount = 0,
    this.successfulAssistanceCount = 0,
    this.reputationPoints = 0,
    this.badges = const [],
    this.fcmToken,
  });

  // -------------------------------------------------------------------------
  // Derived / Computed properties
  // -------------------------------------------------------------------------

  bool get isActiveResponder => isVerifiedResponder && isAvailable;

  double get successRate => responseHistoryCount == 0
      ? 0.0
      : successfulAssistanceCount / responseHistoryCount;

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  UserProfile copyWith({
    String? uid,
    String? displayName,
    bool? isVerifiedResponder,
    bool? isAvailable,
    int? responseHistoryCount,
    int? successfulAssistanceCount,
    int? reputationPoints,
    List<String>? badges,
    String? fcmToken,
    bool clearFcmToken = false,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      isVerifiedResponder: isVerifiedResponder ?? this.isVerifiedResponder,
      isAvailable: isAvailable ?? this.isAvailable,
      responseHistoryCount: responseHistoryCount ?? this.responseHistoryCount,
      successfulAssistanceCount:
          successfulAssistanceCount ?? this.successfulAssistanceCount,
      reputationPoints: reputationPoints ?? this.reputationPoints,
      badges: badges ?? List.unmodifiable(this.badges),
      fcmToken: clearFcmToken ? null : (fcmToken ?? this.fcmToken),
    );
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'displayName': displayName,
      'isVerifiedResponder': isVerifiedResponder,
      'isAvailable': isAvailable,
      'responseHistoryCount': responseHistoryCount,
      'successfulAssistanceCount': successfulAssistanceCount,
      'reputationPoints': reputationPoints,
      'badges': List<String>.from(badges),
      'fcmToken': fcmToken,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid'] as String,
      displayName: json['displayName'] as String,
      isVerifiedResponder: (json['isVerifiedResponder'] as bool?) ?? false,
      isAvailable: (json['isAvailable'] as bool?) ?? false,
      responseHistoryCount:
          (json['responseHistoryCount'] as num?)?.toInt() ?? 0,
      successfulAssistanceCount:
          (json['successfulAssistanceCount'] as num?)?.toInt() ?? 0,
      reputationPoints: (json['reputationPoints'] as num?)?.toInt() ?? 0,
      badges: (json['badges'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      fcmToken: json['fcmToken'] as String?,
    );
  }

  // -------------------------------------------------------------------------
  // Equality & Debug
  // -------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          uid == other.uid &&
          fcmToken == other.fcmToken;

  @override
  int get hashCode => Object.hash(uid, fcmToken);

  @override
  String toString() {
    return 'UserProfile('
        'uid: $uid, '
        'displayName: $displayName, '
        'isVerifiedResponder: $isVerifiedResponder, '
        'isAvailable: $isAvailable, '
        'reputationPoints: $reputationPoints, '
        'badges: $badges, '
        'fcmToken: $fcmToken'
        ')';
  }
}
