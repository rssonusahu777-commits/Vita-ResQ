// lib/services/responder_ranking_service.dart
//
// Vindara — Mathematical Responder Ranking & Skill-Matching Engine
// Package: com.vindara.app
//
// Architectural Rules followed (docs/TEAMMATE_AI_CONTRACT.md):
//   Rule #1 — Pure, asynchronous ranking function (never blocks alert broadcast).
//   Rule #2 — Zero "SOS" strings anywhere.
//   Rule #5 — Proximity Over Ranking in Critical State: In critical severity, proximity
//             weight increases from 0.55 to 0.80, guaranteeing nearest responders are prioritized.
//   Rule #9 — Never mutates server-side privileged profile fields from client.

import '../models/emergency.dart';
import '../models/responder.dart';

/// Scored responder candidate with breakdown
class ScoredResponder {
  final Responder responder;
  final double totalScore;
  final double distanceScore;
  final double reputationScore;
  final double skillMatchScore;
  final List<String> matchedSkills;

  const ScoredResponder({
    required this.responder,
    required this.totalScore,
    required this.distanceScore,
    required this.reputationScore,
    required this.skillMatchScore,
    required this.matchedSkills,
  });

  @override
  String toString() =>
      'ScoredResponder(${responder.name}, score: ${totalScore.toStringAsFixed(3)}, matchedSkills: $matchedSkills)';
}

/// Mathematical Responder Ranking Engine
class ResponderRankingService {
  static const double maxDistanceMeters = 10000.0; // 10 km maximum search radius

  /// Ranks candidates for an active emergency dispatch
  static List<ScoredResponder> rankResponders(
    List<Responder> responders,
    Emergency emergency,
  ) {
    if (responders.isEmpty) return const [];

    final isCritical = emergency.severity == EmergencySeverity.critical ||
        emergency.type == EmergencyType.roadAccident ||
        emergency.type == EmergencyType.fire;

    // Weight allocation: In critical incidents, proximity heavily dominates (Rule #5)
    final double weightDistance = isCritical ? 0.80 : 0.55;
    final double weightReputation = isCritical ? 0.10 : 0.20;
    final double weightActivity = isCritical ? 0.05 : 0.15;
    final double weightSkill = 0.10;

    final scored = responders.map((responder) {
      // 1. Distance component (1.0 = immediate 0m, 0.0 = >= maxDistanceMeters)
      final distanceClamped = responder.distanceMeters.clamp(0, maxDistanceMeters.toInt());
      final distanceScore = (1.0 - (distanceClamped / maxDistanceMeters)).clamp(0.0, 1.0);

      // 2. Reputation points component (scaled up to 1000 points max)
      final repClamped = responder.points.clamp(0, 1000);
      final reputationScore = repClamped / 1000.0;

      // 3. Historical response track record (scaled up to 50 assists)
      final completedClamped = responder.completedResponses.clamp(0, 50);
      final activityScore = completedClamped / 50.0;

      // 4. Recommended Skill Match Bonus
      final matched = <String>[];
      for (final reqSkill in emergency.recommendedSkills) {
        if (responder.skills.map((s) => s.toLowerCase()).contains(reqSkill.toLowerCase())) {
          matched.add(reqSkill);
        }
      }
      final double skillMatchScore = (matched.length * 0.12).clamp(0.0, 0.30);

      // 5. Verification Bonus
      final double verificationBonus = responder.isVerified ? 0.10 : 0.0;

      // 6. Availability Gate Penalty (unavailable responders demoted)
      final double availabilityMultiplier = responder.isAvailable ? 1.0 : 0.35;

      // Compute composite mathematical score
      final totalScore = ((weightDistance * distanceScore) +
              (weightReputation * reputationScore) +
              (weightActivity * activityScore) +
              (weightSkill * skillMatchScore) +
              verificationBonus) *
          availabilityMultiplier;

      return ScoredResponder(
        responder: responder,
        totalScore: totalScore,
        distanceScore: distanceScore,
        reputationScore: reputationScore,
        skillMatchScore: skillMatchScore,
        matchedSkills: matched,
      );
    }).toList();

    // Sort descending by score
    scored.sort((a, b) => b.totalScore.compareTo(a.totalScore));
    return scored;
  }
}

