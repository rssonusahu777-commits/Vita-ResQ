// test/models/user_profile_test.dart
//
// SafeReach — UserProfile model unit tests (Phase 1)

import 'package:flutter_test/flutter_test.dart';
import 'package:safereach/models/user_profile.dart';

void main() {
  group('UserProfile toJson / fromJson', () {
    test('round-trips correctly with all fields', () {
      const profile = UserProfile(
        uid: 'uid-123',
        displayName: 'Priya Sharma',
        isVerifiedResponder: true,
        isAvailable: true,
        responseHistoryCount: 20,
        successfulAssistanceCount: 18,
        reputationPoints: 450,
        badges: ['first_responder', 'ten_assists'],
      );

      final json = profile.toJson();
      final restored = UserProfile.fromJson(json);

      expect(restored.uid, equals(profile.uid));
      expect(restored.displayName, equals(profile.displayName));
      expect(restored.isVerifiedResponder, isTrue);
      expect(restored.isAvailable, isTrue);
      expect(restored.responseHistoryCount, equals(20));
      expect(restored.successfulAssistanceCount, equals(18));
      expect(restored.reputationPoints, equals(450));
      expect(restored.badges, containsAll(['first_responder', 'ten_assists']));
    });

    test('fromJson applies defaults for missing optional fields', () {
      final json = {'uid': 'u', 'displayName': 'Test'};
      final profile = UserProfile.fromJson(json);
      expect(profile.isVerifiedResponder, isFalse);
      expect(profile.isAvailable, isFalse);
      expect(profile.responseHistoryCount, equals(0));
      expect(profile.reputationPoints, equals(0));
      expect(profile.badges, isEmpty);
    });
  });

  group('UserProfile computed properties', () {
    test('successRate is 0 when responseHistoryCount is 0', () {
      const p = UserProfile(uid: 'u', displayName: 'D');
      expect(p.successRate, equals(0.0));
    });

    test('successRate computes correctly', () {
      const p = UserProfile(
        uid: 'u',
        displayName: 'D',
        responseHistoryCount: 10,
        successfulAssistanceCount: 8,
      );
      expect(p.successRate, closeTo(0.8, 0.0001));
    });

    test('isActiveResponder requires both verified AND available', () {
      const verified = UserProfile(
          uid: 'u', displayName: 'D', isVerifiedResponder: true);
      expect(verified.isActiveResponder, isFalse);

      const active = UserProfile(
          uid: 'u',
          displayName: 'D',
          isVerifiedResponder: true,
          isAvailable: true);
      expect(active.isActiveResponder, isTrue);
    });
  });

  group('UserProfile.copyWith()', () {
    const base = UserProfile(uid: 'u', displayName: 'Base');

    test('unchanged fields are preserved', () {
      final copy = base.copyWith(displayName: 'Updated');
      expect(copy.uid, equals(base.uid));
    });

    test('changed fields are applied', () {
      final copy = base.copyWith(reputationPoints: 100);
      expect(copy.reputationPoints, equals(100));
    });
  });
}

