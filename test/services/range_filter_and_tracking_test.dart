import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/models/emergency.dart';

void main() {
  group('Range Filtering & Mutual Live Location Tracking Tests', () {
    test('distanceTo calculates accurate distance between two GPS coordinates', () {
      final emergency = Emergency(
        id: 'em-test-1',
        victimName: 'Karan Test',
        latitude: 21.1619,
        longitude: 81.7869,
        timestamp: DateTime.now(),
        type: EmergencyType.medical,
        severity: EmergencySeverity.high,
        status: EmergencyStatus.active,
        communicationMode: CommunicationMode.online,
        locationLabel: 'Sector 4, Raipur',
        timeline: [],
      );

      // Same coordinate => 0 meters
      expect(emergency.distanceTo(21.1619, 81.7869), closeTo(0.0, 1.0));

      // Roughly 1.1 km north in Raipur (0.01 deg lat is approx 1110 meters)
      final distance = emergency.distanceTo(21.1719, 81.7869);
      expect(distance, greaterThan(1000.0));
      expect(distance, lessThan(1200.0));
    });

    test('Emergency filter by radius (1km, 3km, 5km, 10km)', () {
      final baseLat = 21.1619;
      final baseLng = 81.7869;

      final nearEmergency = Emergency(
        id: 'em-near',
        victimName: 'Near Victim',
        latitude: 21.1630, // ~120m away
        longitude: 81.7869,
        timestamp: DateTime.now(),
        type: EmergencyType.medical,
        severity: EmergencySeverity.high,
        status: EmergencyStatus.active,
        communicationMode: CommunicationMode.online,
        locationLabel: 'Near Point',
        timeline: [],
      );

      final farEmergency = Emergency(
        id: 'em-far',
        victimName: 'Far Victim',
        latitude: 21.2100, // ~5.3 km away
        longitude: 81.7869,
        timestamp: DateTime.now(),
        type: EmergencyType.fire,
        severity: EmergencySeverity.critical,
        status: EmergencyStatus.active,
        communicationMode: CommunicationMode.online,
        locationLabel: 'Far Point',
        timeline: [],
      );

      final list = [nearEmergency, farEmergency];

      // 1 km filter: only nearEmergency
      final within1Km = list.where((e) => e.distanceTo(baseLat, baseLng) <= 1000.0).toList();
      expect(within1Km.length, equals(1));
      expect(within1Km.first.id, equals('em-near'));

      // 5 km filter: only nearEmergency (5.3km exceeds 5km)
      final within5Km = list.where((e) => e.distanceTo(baseLat, baseLng) <= 5000.0).toList();
      expect(within5Km.length, equals(1));

      // 10 km filter: both emergencies
      final within10Km = list.where((e) => e.distanceTo(baseLat, baseLng) <= 10000.0).toList();
      expect(within10Km.length, equals(2));
    });

    test('Mutual location serialization, responder distance, and copyWith', () {
      final now = DateTime.now();
      final emergency = Emergency(
        id: 'em-tracking-1',
        victimName: 'Aarav Patel',
        latitude: 21.1619,
        longitude: 81.7869,
        lastLocationUpdatedAt: now,
        responderLatitude: 21.1650,
        responderLongitude: 81.7880,
        responderLocationUpdatedAt: now,
        timestamp: now,
        type: EmergencyType.crash,
        severity: EmergencySeverity.critical,
        status: EmergencyStatus.claimed,
        communicationMode: CommunicationMode.online,
        locationLabel: 'Main Road',
        timeline: [],
      );

      expect(emergency.hasLiveResponderLocation, isTrue);
      expect(emergency.distanceToResponderMeters, isNotNull);
      expect(emergency.distanceToResponderMeters!, greaterThan(100.0));

      final json = emergency.toJson();
      expect(json['responderLatitude'], equals(21.1650));
      expect(json['responderLongitude'], equals(81.7880));
      expect(json['lastLocationUpdatedAt'], isNotNull);
      expect(json['responderLocationUpdatedAt'], isNotNull);

      final revived = Emergency.fromJson(json);
      expect(revived.responderLatitude, equals(21.1650));
      expect(revived.responderLongitude, equals(81.7880));
      expect(revived.hasLiveResponderLocation, isTrue);

      final updated = revived.copyWith(
        responderLatitude: 21.1660,
      );
      expect(updated.responderLatitude, equals(21.1660));
      expect(updated.responderLongitude, equals(81.7880));
    });
  });
}
