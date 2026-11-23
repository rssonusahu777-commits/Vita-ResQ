import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable model representing an AI or fallback emergency triage assessment.
class TriageAssessment {
  final String level; // 'CRITICAL', 'HIGH', 'MODERATE', 'UNCLEAR'
  final String summary; // Concise 1–2 sentence responder briefing
  final String confidence; // 'HIGH', 'MEDIUM', 'LOW'
  final String source; // 'AI_MULTIMODAL', 'LOCAL_FALLBACK', 'CRASH_ESCALATION', 'UNAVAILABLE'
  final String? transcript; // Captured 6-second voice transcript, nullable
  final DateTime assessedAt;

  const TriageAssessment({
    required this.level,
    required this.summary,
    required this.confidence,
    required this.source,
    this.transcript,
    required this.assessedAt,
  });

  static DateTime parseDate(dynamic val) {
    if (val == null) return DateTime.now();
    if (val is Timestamp) return val.toDate();
    if (val is DateTime) return val;
    if (val is String) {
      try {
        return DateTime.parse(val);
      } catch (_) {}
    }
    if (val is int) {
      return DateTime.fromMillisecondsSinceEpoch(val);
    }
    return DateTime.now();
  }

  factory TriageAssessment.fromMap(Map<String, dynamic> map) {
    return TriageAssessment(
      level: (map['level'] ?? 'UNCLEAR').toString().toUpperCase(),
      summary: (map['summary'] ?? '').toString(),
      confidence: (map['confidence'] ?? 'LOW').toString().toUpperCase(),
      source: (map['source'] ?? 'UNAVAILABLE').toString(),
      transcript: map['transcript']?.toString(),
      assessedAt: parseDate(map['assessedAt']),
    );
  }

  factory TriageAssessment.fromJson(Map<String, dynamic> json) =>
      TriageAssessment.fromMap(json);

  Map<String, dynamic> toMap() {
    return {
      'level': level,
      'summary': summary,
      'confidence': confidence,
      'source': source,
      if (transcript != null) 'transcript': transcript,
      'assessedAt': Timestamp.fromDate(assessedAt),
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'level': level,
      'summary': summary,
      'confidence': confidence,
      'source': source,
      if (transcript != null) 'transcript': transcript,
      'assessedAt': assessedAt.toIso8601String(),
    };
  }

  TriageAssessment copyWith({
    String? level,
    String? summary,
    String? confidence,
    String? source,
    String? transcript,
    DateTime? assessedAt,
  }) {
    return TriageAssessment(
      level: level ?? this.level,
      summary: summary ?? this.summary,
      confidence: confidence ?? this.confidence,
      source: source ?? this.source,
      transcript: transcript ?? this.transcript,
      assessedAt: assessedAt ?? this.assessedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TriageAssessment &&
          runtimeType == other.runtimeType &&
          level == other.level &&
          summary == other.summary &&
          confidence == other.confidence &&
          source == other.source &&
          transcript == other.transcript &&
          assessedAt.millisecondsSinceEpoch ==
              other.assessedAt.millisecondsSinceEpoch;

  @override
  int get hashCode =>
      level.hashCode ^
      summary.hashCode ^
      confidence.hashCode ^
      source.hashCode ^
      transcript.hashCode ^
      assessedAt.millisecondsSinceEpoch.hashCode;

  @override
  String toString() {
    return 'TriageAssessment(level: $level, confidence: $confidence, source: $source, summary: $summary, transcript: $transcript, assessedAt: $assessedAt)';
  }
}

