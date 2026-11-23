import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/models/triage_assessment_model.dart';
import 'package:jan_sarthi/services/injury_triage_service.dart';

class MockTriageHttpClient implements TriageHttpClient {
  final Future<String> Function(Uri uri, Map<String, dynamic> body) onPost;

  MockTriageHttpClient(this.onPost);

  @override
  Future<String> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 8),
  }) {
    return onPost(uri, body);
  }
}

void main() {
  group('InjuryTriageService Tests', () {
    test('a) Valid mocked Gemini JSON response parses into TriageAssessment with source AI_MULTIMODAL', () async {
      final mockResponse = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text': jsonEncode({
                    'level': 'HIGH',
                    'summary': 'Victim has sustained visible fractures to the lower leg.',
                    'confidence': 'HIGH',
                  }),
                }
              ]
            }
          }
        ]
      });

      final mockClient = MockTriageHttpClient((uri, body) async {
        expect(uri.toString(), contains('gemini-2.5-flash'));
        return mockResponse;
      });

      final service = InjuryTriageService(
        httpClient: mockClient,
        apiKey: 'test-api-key',
      );

      final assessment = await service.assessEmergency(
        jpegFrames: [Uint8List.fromList([1, 2, 3, 4])],
        transcript: 'My leg is fractured',
        isOnline: true,
        wasCrashDetected: false,
      );

      expect(assessment.level, equals('HIGH'));
      expect(assessment.summary, equals('Victim has sustained visible fractures to the lower leg.'));
      expect(assessment.confidence, equals('HIGH'));
      expect(assessment.source, equals('AI_MULTIMODAL'));
      expect(assessment.transcript, equals('My leg is fractured'));
    });

    test('b) Network failure / timeout / invalid JSON gracefully falls back to LOCAL_FALLBACK without throwing', () async {
      final errorClient = MockTriageHttpClient((uri, body) async {
        throw Exception('Network connection timed out');
      });

      final service = InjuryTriageService(
        httpClient: errorClient,
        apiKey: 'test-api-key',
      );

      // Should not throw, should fall back to local keyword assessment
      final assessment = await service.assessEmergency(
        jpegFrames: [Uint8List.fromList([1, 2, 3])],
        transcript: 'I fell down and my arm hurts',
        isOnline: true,
        wasCrashDetected: false,
      );

      expect(assessment.level, equals('HIGH')); // matches 'arm' / 'fell'
      expect(assessment.source, equals('LOCAL_FALLBACK'));
    });

    test('c) Offline keyword triage classifies correctly', () {
      final service = InjuryTriageService();

      // HIGH keyword: 'broken'
      final highAssessment = service.assessLocally(
        transcript: 'my leg is broken',
      );
      expect(highAssessment.level, equals('HIGH'));
      expect(highAssessment.confidence, equals('MEDIUM'));
      expect(highAssessment.source, equals('LOCAL_FALLBACK'));

      // CRITICAL keywords: 'heavy bleeding' and 'not breathing'
      final criticalAssessment = service.assessLocally(
        transcript: 'heavy bleeding and not breathing',
      );
      expect(criticalAssessment.level, equals('CRITICAL'));
      expect(criticalAssessment.confidence, equals('HIGH'));
      expect(criticalAssessment.source, equals('LOCAL_FALLBACK'));

      // Empty / unclear audio
      final unclearAssessment = service.assessLocally(
        transcript: 'hello is anyone there',
      );
      expect(unclearAssessment.level, equals('UNCLEAR'));
      expect(unclearAssessment.confidence, equals('LOW'));
      expect(unclearAssessment.source, equals('LOCAL_FALLBACK'));
    });

    test('d) When wasCrashDetected: true and frames/transcript yield UNCLEAR, escalates to CRITICAL with CRASH_ESCALATION', () async {
      // 1. Offline empty input with wasCrashDetected = true
      final service = InjuryTriageService();
      final offlineEscalated = service.assessLocally(
        transcript: '',
        wasCrashDetected: true,
      );
      expect(offlineEscalated.level, equals('CRITICAL'));
      expect(offlineEscalated.confidence, equals('MEDIUM'));
      expect(offlineEscalated.source, equals('CRASH_ESCALATION'));
      expect(offlineEscalated.summary, contains('High-G crash impact detected'));

      // 2. Online AI returns UNCLEAR with wasCrashDetected = true
      final mockUnclearResponse = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text': jsonEncode({
                    'level': 'UNCLEAR',
                    'summary': 'Camera obstructed, no audible response.',
                    'confidence': 'LOW',
                  }),
                }
              ]
            }
          }
        ]
      });

      final mockClient = MockTriageHttpClient((uri, body) async => mockUnclearResponse);
      final onlineService = InjuryTriageService(
        httpClient: mockClient,
        apiKey: 'test-api-key',
      );

      final onlineEscalated = await onlineService.assessEmergency(
        jpegFrames: [Uint8List.fromList([1, 2, 3])],
        transcript: null,
        isOnline: true,
        wasCrashDetected: true,
      );

      expect(onlineEscalated.level, equals('CRITICAL'));
      expect(onlineEscalated.confidence, equals('MEDIUM'));
      expect(onlineEscalated.source, equals('CRASH_ESCALATION'));
      expect(onlineEscalated.summary, contains('High-G crash impact detected'));
    });

    test('e) EmergencyModel serializes and deserializes both with and without triageAssessment (backward compatibility)', () {
      final now = DateTime.now();

      // 1. Without triageAssessment (legacy emergency)
      final legacyEmergency = EmergencyModel(
        id: 'EM-101',
        victimId: 'user-vic-1',
        latitude: 28.6139,
        longitude: 77.2090,
        status: EmergencyStatus.SEARCHING,
        createdAt: now,
        updatedAt: now,
      );

      final legacyMap = legacyEmergency.toMap();
      expect(legacyMap.containsKey('triageAssessment'), isFalse);

      final deserializedLegacy = EmergencyModel.fromMap(legacyMap, 'EM-101');
      expect(deserializedLegacy.triageAssessment, isNull);
      expect(deserializedLegacy.victimId, equals('user-vic-1'));

      // 2. With triageAssessment
      final triage = TriageAssessment(
        level: 'CRITICAL',
        summary: 'Severe head trauma observed.',
        confidence: 'HIGH',
        source: 'AI_MULTIMODAL',
        transcript: 'help I cannot move my head',
        assessedAt: now,
      );

      final emergencyWithTriage = legacyEmergency.copyWith(
        triageAssessment: triage,
      );

      final mapWithTriage = emergencyWithTriage.toMap();
      expect(mapWithTriage.containsKey('triageAssessment'), isTrue);

      final deserializedWithTriage = EmergencyModel.fromMap(mapWithTriage, 'EM-101');
      expect(deserializedWithTriage.triageAssessment, isNotNull);
      expect(deserializedWithTriage.triageAssessment!.level, equals('CRITICAL'));
      expect(deserializedWithTriage.triageAssessment!.summary, equals('Severe head trauma observed.'));
      expect(deserializedWithTriage.triageAssessment!.confidence, equals('HIGH'));
      expect(deserializedWithTriage.triageAssessment!.source, equals('AI_MULTIMODAL'));
      expect(deserializedWithTriage.triageAssessment!.transcript, equals('help I cannot move my head'));
    });
  });
}

