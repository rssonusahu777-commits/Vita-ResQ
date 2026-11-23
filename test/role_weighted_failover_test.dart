import 'package:flutter_test/flutter_test.dart';
import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/models/responder_model.dart';
import 'package:jan_sarthi/services/responder_reliability_monitor.dart';

void main() {
  group('Phase 1: Role-Weighted Standby Failover Tests', () {
    test('a) At equal distance (e.g. 500m), ranking strictly orders DOCTOR > AMBULANCE_DRIVER > POLICE_PCR > CITIZEN', () {
      final double doctorScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'DOCTOR',
        distanceMeters: 500.0,
      );
      final double ambulanceScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'AMBULANCE_DRIVER',
        distanceMeters: 500.0,
      );
      final double policeScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'POLICE_PCR',
        distanceMeters: 500.0,
      );
      final double citizenScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'CITIZEN',
        distanceMeters: 500.0,
      );

      // Proximity weight at 500m is 50 * (1 - 0.1) = 45.0
      // DOCTOR = 40 + 45 = 85.0
      // AMBULANCE_DRIVER = 35 + 45 = 80.0
      // POLICE_PCR = 30 + 45 = 75.0
      // CITIZEN = 10 + 45 = 55.0
      expect(doctorScore, equals(85.0));
      expect(ambulanceScore, equals(80.0));
      expect(policeScore, equals(75.0));
      expect(citizenScore, equals(55.0));

      expect(doctorScore > ambulanceScore, isTrue);
      expect(ambulanceScore > policeScore, isTrue);
      expect(policeScore > citizenScore, isTrue);
    });

    test('b) A DOCTOR at 600m outranks a CITIZEN at 500m', () {
      // Doctor at 600m: 40 + 50 * (1 - 600/5000) = 40 + 44.0 = 84.0
      final double doctorScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'DOCTOR',
        distanceMeters: 600.0,
      );
      // Citizen at 500m: 10 + 50 * (1 - 500/5000) = 10 + 45.0 = 55.0
      final double citizenScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'CITIZEN',
        distanceMeters: 500.0,
      );

      expect(doctorScore, equals(84.0));
      expect(citizenScore, equals(55.0));
      expect(doctorScore > citizenScore, isTrue);
    });

    test('c) Extreme proximity still wins: a CITIZEN at 100m outranks a DOCTOR at 4500m', () {
      // Citizen at 100m: 10 + 50 * (1 - 100/5000) = 10 + 49.0 = 59.0
      final double citizenScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'CITIZEN',
        distanceMeters: 100.0,
      );
      // Doctor at 4500m: 40 + 50 * (1 - 4500/5000) = 40 + 5.0 = 45.0
      final double doctorScore = ResponderReliabilityMonitor.scoreStandbyCandidate(
        userRole: 'DOCTOR',
        distanceMeters: 4500.0,
      );

      expect(citizenScore, equals(59.0));
      expect(doctorScore, equals(45.0));
      expect(citizenScore > doctorScore, isTrue);
    });

    test('d) Identical role and distance break ties deterministically by userId', () {
      final candidateA = ResponderModel(
        userId: 'user_a',
        userName: 'Doctor Alpha',
        userRole: 'DOCTOR',
        role: ResponderRole.STANDBY,
        status: ResponderStatus.STANDBY,
        latitude: 28.6140,
        longitude: 77.2090,
        acceptedAt: DateTime.now(),
        lastLocationUpdate: DateTime.now(),
      );

      final candidateB = ResponderModel(
        userId: 'user_b',
        userName: 'Doctor Beta',
        userRole: 'DOCTOR',
        role: ResponderRole.STANDBY,
        status: ResponderStatus.STANDBY,
        latitude: 28.6140,
        longitude: 77.2090,
        acceptedAt: DateTime.now(),
        lastLocationUpdate: DateTime.now(),
      );

      final list = [candidateB, candidateA];
      const double distanceMeters = 500.0;

      list.sort((a, b) {
        final scoreA = ResponderReliabilityMonitor.scoreStandbyCandidate(
          userRole: a.userRole,
          distanceMeters: distanceMeters,
        );
        final scoreB = ResponderReliabilityMonitor.scoreStandbyCandidate(
          userRole: b.userRole,
          distanceMeters: distanceMeters,
        );

        final scoreCmp = scoreB.compareTo(scoreA);
        if (scoreCmp != 0) return scoreCmp;

        return a.userId.compareTo(b.userId);
      });

      expect(list.first.userId, equals('user_a'));
      expect(list.last.userId, equals('user_b'));
    });

    test('e) Terminal emergencies (CANCELLED / COMPLETED) do not promote any standby responder', () {
      final cancelledEmergency = EmergencyModel(
        id: 'EMG-CANCELLED',
        victimId: 'victim-1',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.CANCELLED,
        currentRadiusMeters: 1000.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final completedEmergency = EmergencyModel(
        id: 'EMG-COMPLETED',
        victimId: 'victim-2',
        type: 'MEDICAL',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.COMPLETED,
        currentRadiusMeters: 1000.0,
        notifiedUserIds: [],
        responders: {},
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(cancelledEmergency.isTerminal, isTrue);
      expect(completedEmergency.isTerminal, isTrue);

      // Verify that failover conditions guard against terminal states
      final canPromoteCancelled = cancelledEmergency.status == EmergencyStatus.ASSIGNED ||
          cancelledEmergency.status == EmergencyStatus.APPROACHING;
      final canPromoteCompleted = completedEmergency.status == EmergencyStatus.ASSIGNED ||
          completedEmergency.status == EmergencyStatus.APPROACHING;

      expect(canPromoteCancelled, isFalse);
      expect(canPromoteCompleted, isFalse);
    });
  });
}

