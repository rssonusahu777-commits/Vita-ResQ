// lib/models/user_profile.dart
//
// SafeReach — UserProfile Domain Model
// Package: com.example.safereach
//
// Phase 1: Domain model only. No Firebase, no UI, no network calls.

// ---------------------------------------------------------------------------
// UserProfile
// ---------------------------------------------------------------------------

/// Represents a SafeReach user — either a regular civilian or a verified
/// community responder.
///
/// Responder status ([isVerifiedResponder]) is set server-side after vetting.
/// Clients should treat this field as read-only and never self-assign it.
///
/// The reputation system ([reputationPoints], [badges]) is computed server-side;
/// [responseHistoryCount] and [successfulAssistanceCount] are stored here for
/// offline display only and must be re-validated against Firestore on sync.
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

  /// Total number of emergencies this responder has been assigned to
  /// (regardless of outcome). Read-only on the client; server-managed.
  final int responseHistoryCount;

  /// Number of emergencies this responder has resolved with a positive outcome.
  /// Read-only on the client; server-managed.
  final int successfulAssistanceCount;

  /// Gamified reputation score. Higher = more trusted in the community.
  /// Read-only on the client; server-managed.
  final int reputationPoints;

  /// List of badge identifiers earned by this user.
  /// Example badge IDs: `'first_responder'`, `'ten_assists'`, `'night_hero'`.
  /// Badge metadata (label, icon) is resolved separately via a badge registry.
  final List<String> badges;

  const UserProfile({
    required this.uid,
    required this.displayName,
    this.isVerifiedResponder = false,
    this.isAvailable = false,
    this.responseHistoryCount = 0,
    this.successfulAssistanceCount = 0,
    this.reputationPoints = 0,
    this.badges = const [],
  });

  // -------------------------------------------------------------------------
  // Derived / Computed properties
  // -------------------------------------------------------------------------

  /// Convenience check: user is a responder AND currently accepting jobs.
  bool get isActiveResponder => isVerifiedResponder && isAvailable;

  /// Assistance success rate as a fraction [0.0, 1.0].
  /// Returns 0.0 if [responseHistoryCount] is zero (no division by zero).
  double get successRate => responseHistoryCount == 0
      ? 0.0
      : successfulAssistanceCount / responseHistoryCount;

  // -------------------------------------------------------------------------
  // copyWith
  // -------------------------------------------------------------------------

  /// Returns a new [UserProfile] with the specified fields replaced.
  UserProfile copyWith({
    String? uid,
    String? displayName,
    bool? isVerifiedResponder,
    bool? isAvailable,
    int? responseHistoryCount,
    int? successfulAssistanceCount,
    int? reputationPoints,
    List<String>? badges,
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
    );
  }

  // -------------------------------------------------------------------------
  // Serialization
  // -------------------------------------------------------------------------

  /// Converts this [UserProfile] to a JSON-serialisable [Map].
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
    };
  }

  /// Creates a [UserProfile] from a JSON map (Firestore document or local DB).
  ///
  /// Treats missing optional fields gracefully with sensible defaults so that
  /// older document versions (before a field was added) deserialise correctly.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid'] as String,
      displayName: json['displayName'] as String,
      isVerifiedResponder: (json['isVerifiedResponder'] as bool?) ?? false,
      isAvailable: (json['isAvailable'] as bool?) ?? false,
      responseHistoryCount: (json['responseHistoryCount'] as num?)?.toInt() ?? 0,
      successfulAssistanceCount:
          (json['successfulAssistanceCount'] as num?)?.toInt() ?? 0,
      reputationPoints: (json['reputationPoints'] as num?)?.toInt() ?? 0,
      badges: (json['badges'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
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
          uid == other.uid;

  @override
  int get hashCode => uid.hashCode;

  @override
  String toString() {
    return 'UserProfile('
        'uid: $uid, '
        'displayName: $displayName, '
        'isVerifiedResponder: $isVerifiedResponder, '
        'isAvailable: $isAvailable, '
        'reputationPoints: $reputationPoints, '
        'badges: $badges'
        ')';
  }
}

