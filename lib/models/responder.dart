/// Community First Responder Model
class Responder {
  final String id;
  final String name;
  final int distanceMeters;
  final int etaMinutes;
  final bool isVerified;
  final int points;
  final String badgeLevel;
  final int completedResponses;
  final bool isAvailable;
  final String? phoneNumber;
  final String bloodGroup;
  final String? emergencyNotes;
  final String? knownAllergies;

  const Responder({
    required this.id,
    required this.name,
    required this.distanceMeters,
    required this.etaMinutes,
    required this.isVerified,
    required this.points,
    required this.badgeLevel,
    required this.completedResponses,
    required this.isAvailable,
    this.phoneNumber,
    this.bloodGroup = 'A+',
    this.emergencyNotes,
    this.knownAllergies,
  });

  Responder copyWith({
    String? id,
    String? name,
    int? distanceMeters,
    int? etaMinutes,
    bool? isVerified,
    int? points,
    String? badgeLevel,
    int? completedResponses,
    bool? isAvailable,
    String? phoneNumber,
    String? bloodGroup,
    String? emergencyNotes,
    String? knownAllergies,
  }) {
    return Responder(
      id: id ?? this.id,
      name: name ?? this.name,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      isVerified: isVerified ?? this.isVerified,
      points: points ?? this.points,
      badgeLevel: badgeLevel ?? this.badgeLevel,
      completedResponses: completedResponses ?? this.completedResponses,
      isAvailable: isAvailable ?? this.isAvailable,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      bloodGroup: bloodGroup ?? this.bloodGroup,
      emergencyNotes: emergencyNotes ?? this.emergencyNotes,
      knownAllergies: knownAllergies ?? this.knownAllergies,
    );
  }

  /// Human-friendly distance format
  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '$distanceMeters m';
    }
    final km = (distanceMeters / 1000).toStringAsFixed(1);
    return '$km km';
  }

  /// Human-friendly ETA format
  String get formattedEta => '$etaMinutes min away';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Responder &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          distanceMeters == other.distanceMeters &&
          etaMinutes == other.etaMinutes &&
          isVerified == other.isVerified &&
          points == other.points &&
          badgeLevel == other.badgeLevel &&
          completedResponses == other.completedResponses &&
          isAvailable == other.isAvailable &&
          phoneNumber == other.phoneNumber;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      distanceMeters.hashCode ^
      etaMinutes.hashCode ^
      isVerified.hashCode ^
      points.hashCode ^
      badgeLevel.hashCode ^
      completedResponses.hashCode ^
      isAvailable.hashCode ^
      phoneNumber.hashCode;

  @override
  String toString() {
    return 'Responder(id: $id, name: $name, distance: $formattedDistance, eta: $formattedEta, badge: $badgeLevel)';
  }
}

