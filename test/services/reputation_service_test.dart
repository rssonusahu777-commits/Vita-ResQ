// test/services/reputation_service_test.dart
//
// Vindara — Verified Responder Reputation & Trust System Tests (Phase 7)
// Design rules followed:
//   Anti-Gaming Rule — Zero points awarded merely for tapping "Accept".
//   Self-Farming Protection — Zero points awarded if primary responder == victim.
//   Resolution-Gated Rewards — Points and assist counters increment ONLY upon transition to resolved.

import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/models/emergency.dart';
import 'package:vindara/models/user_profile.dart';
import 'package:vindara/services/reputation_service.dart';

void main() {
  final baseEmergency = Emergency(
    id: 'EMG-2026-REW00001',
    victimId: 'victim-user-123',
    latitude: 19.0760,
    longitude: 72.8777,
    accuracyMeters: 5.0,
    type: EmergencyType.medical,
    createdAt: DateTime.utc(2026, 6, 1),
    detectionSource: DetectionSource.manualHelp,
    status: EmergencyStatus.inProgress,
    primaryResponderId: 'responder-primary-456',
    standbyResponderId: 'responder-standby-789',
    communicationMode: CommunicationMode.online,
    version: 3,
  );

  group('ReputationService — Anti-Gaming Rules', () {
    test('Zero points awarded on accepted status', () {
      final points = ReputationService.calculateResolutionPoints(
        emergency: baseEmergency,
        responderId: 'responder-primary-456',
        newStatus: EmergencyStatus.accepted,
      );
      expect(points, equals(0));
    });

    test('Zero points awarded on inProgress status', () {
      final points = ReputationService.calculateResolutionPoints(
        emergency: baseEmergency,
        responderId: 'responder-primary-456',
        newStatus: EmergencyStatus.inProgress,
      );
      expect(points, equals(0));
    });

    test('Self-Farming Protection: Zero points when responder == victimId', () {
      final selfFarmingEmergency = baseEmergency.copyWith(
        primaryResponderId: 'victim-user-123',
      );

      final points = ReputationService.calculateResolutionPoints(
        emergency: selfFarmingEmergency,
        responderId: 'victim-user-123',
        newStatus: EmergencyStatus.resolved,
      );
      expect(points, equals(0));
    });

    test('Primary responder receives +50 points upon resolved status', () {
      final points = ReputationService.calculateResolutionPoints(
        emergency: baseEmergency,
        responderId: 'responder-primary-456',
        newStatus: EmergencyStatus.resolved,
      );
      expect(points, equals(50));
    });

    test('Standby responder receives +20 points upon resolved status', () {
      final points = ReputationService.calculateResolutionPoints(
        emergency: baseEmergency,
        responderId: 'responder-standby-789',
        newStatus: EmergencyStatus.resolved,
      );
      expect(points, equals(20));
    });

    test('Unrelated third-party user receives 0 points upon resolved status', () {
      final points = ReputationService.calculateResolutionPoints(
        emergency: baseEmergency,
        responderId: 'stranger-999',
        newStatus: EmergencyStatus.resolved,
      );
      expect(points, equals(0));
    });
  });

  group('ReputationService — Milestone Badges & Rank Progression', () {
    test('0 assists unlocks no badges', () {
      final badges = ReputationService.calculateUnlockedBadges(
        successfulAssistanceCount: 0,
      );
      expect(badges, isEmpty);
    });

    test('1 assist unlocks First Responder badge', () {
      final badges = ReputationService.calculateUnlockedBadges(
        successfulAssistanceCount: 1,
      );
      expect(badges, contains(ReputationService.badgeFirstResponder));
      expect(badges.length, equals(1));
    });

    test('5 assists unlocks Community Guardian badge', () {
      final badges = ReputationService.calculateUnlockedBadges(
        successfulAssistanceCount: 5,
      );
      expect(badges, contains(ReputationService.badgeFirstResponder));
      expect(badges, contains(ReputationService.badgeCommunityGuardian));
      expect(badges.length, equals(2));
    });

    test('15 assists unlocks Vindara Vanguard badge', () {
      final badges = ReputationService.calculateUnlockedBadges(
        successfulAssistanceCount: 15,
      );
      expect(badges, contains(ReputationService.badgeFirstResponder));
      expect(badges, contains(ReputationService.badgeCommunityGuardian));
      expect(badges, contains(ReputationService.badgeVindaraVanguard));
      expect(badges.length, equals(3));
    });

    test('Rank titles scale with reputation points', () {
      expect(ReputationService.getRankTitle(50), equals('Novice Responder'));
      expect(ReputationService.getRankTitle(150), equals('Active Guardian'));
      expect(ReputationService.getRankTitle(350), equals('Senior Guardian'));
      expect(ReputationService.getRankTitle(800), equals('Master Guardian'));
    });

    test('applyResolutionReward updates profile points, assists, and badges', () {
      const initialProfile = UserProfile(
        uid: 'responder-primary-456',
        displayName: 'Aarav Patel',
        isVerifiedResponder: true,
        isAvailable: true,
        successfulAssistanceCount: 0,
        reputationPoints: 20,
        badges: [],
      );

      final updatedProfile = ReputationService.applyResolutionReward(
        profile: initialProfile,
        emergency: baseEmergency,
        newStatus: EmergencyStatus.resolved,
      );

      expect(updatedProfile.reputationPoints, equals(70)); // 20 + 50
      expect(updatedProfile.successfulAssistanceCount, equals(1));
      expect(updatedProfile.badges, contains(ReputationService.badgeFirstResponder));
    });
  });
}
