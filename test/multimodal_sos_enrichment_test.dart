import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jan_sarthi/models/triage_assessment_model.dart';
import 'package:jan_sarthi/services/injury_triage_service.dart';
import 'package:jan_sarthi/services/p2p_payload_integrity.dart';
import 'package:jan_sarthi/services/sos_multimodal_capture_service.dart';
import 'package:jan_sarthi/widgets/triage_assessment_card.dart';

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
  group('Phase 5B Multimodal SOS Enrichment Tests', () {
    test('a) When camera/mic permissions are denied or capture throws, capture service returns empty result without crashing', () async {
      // Hook that simulates native camera exception / permission denial
      final failingService = SosMultimodalCaptureService(
        frameCaptureDelegate: () async => throw Exception('CAMERA_PERMISSION_DENIED'),
        audioCaptureDelegate: (duration) async => throw Exception('MIC_PERMISSION_DENIED'),
      );

      final result = await failingService.captureSixSecondBurst();
      expect(result.isEmpty, isTrue);
      expect(result.jpegFrames, isEmpty);
      expect(result.transcript, isNull);
    });

    test('b) Captured mock frames + transcript trigger InjuryTriageService and produce an updated TriageAssessment', () async {
      final mockResponse = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'text': jsonEncode({
                    'level': 'HIGH',
                    'summary': 'Compound fracture visible on right forearm.',
                    'confidence': 'HIGH',
                  }),
                }
              ]
            }
          }
        ]
      });

      final mockClient = MockTriageHttpClient((uri, body) async => mockResponse);
      final triageService = InjuryTriageService(
        httpClient: mockClient,
        apiKey: 'test-gemini-key',
      );

      final captureService = SosMultimodalCaptureService(
        frameCaptureDelegate: () async => [Uint8List.fromList([10, 20, 30])],
        audioCaptureDelegate: (duration) async => 'I fell and my arm is bleeding and broken',
      );

      final captureResult = await captureService.captureSixSecondBurst();
      expect(captureResult.jpegFrames.length, equals(1));
      expect(captureResult.transcript, isNotNull);

      final assessment = await triageService.assessEmergency(
        jpegFrames: captureResult.jpegFrames,
        transcript: captureResult.transcript,
        isOnline: true,
        wasCrashDetected: false,
      );

      expect(assessment.level, equals('HIGH'));
      expect(assessment.summary, equals('Compound fracture visible on right forearm.'));
      expect(assessment.confidence, equals('HIGH'));
      expect(assessment.source, equals('AI_MULTIMODAL'));
    });

    test('c) Crash-triggered SOS with empty capture escalates to CRITICAL with CRASH_ESCALATION', () async {
      final triageService = InjuryTriageService();

      // Empty capture (e.g., phone in pocket, camera obstructed, victim silent/unconscious)
      final assessment = await triageService.assessEmergency(
        jpegFrames: [],
        transcript: null,
        isOnline: false,
        wasCrashDetected: true,
      );

      expect(assessment.level, equals('CRITICAL'));
      expect(assessment.confidence, equals('MEDIUM'));
      expect(assessment.source, equals('CRASH_ESCALATION'));
      expect(assessment.summary, contains('High-G crash impact detected'));
    });

    testWidgets('d) Responder triage card renders cleanly without overflow on 360x640 viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final testAssessments = [
        // CRITICAL state
        TriageAssessment(
          level: 'CRITICAL',
          summary: 'Arterial bleeding and respiratory distress observed. Immediate airway management required.',
          confidence: 'HIGH',
          source: 'AI_MULTIMODAL',
          transcript: 'Help me, I cannot breathe and there is blood everywhere.',
          assessedAt: DateTime.now(),
        ),
        // HIGH state
        TriageAssessment(
          level: 'HIGH',
          summary: 'Suspected compound fracture of right lower leg. Patient conscious and alert.',
          confidence: 'MEDIUM',
          source: 'LOCAL_FALLBACK',
          transcript: 'My leg is broken and I cannot move from the ground.',
          assessedAt: DateTime.now(),
        ),
        // CRASH_ESCALATION state
        TriageAssessment(
          level: 'CRITICAL',
          summary: 'High-G crash impact detected; victim unresponsive or camera obstructed. Treat as critical.',
          confidence: 'MEDIUM',
          source: 'CRASH_ESCALATION',
          transcript: null,
          assessedAt: DateTime.now(),
        ),
        // UNCLEAR state
        TriageAssessment(
          level: 'UNCLEAR',
          summary: 'Unable to determine injury severity from local audio transcript.',
          confidence: 'LOW',
          source: 'LOCAL_FALLBACK',
          transcript: 'Is anyone nearby?',
          assessedAt: DateTime.now(),
        ),
      ];

      for (final assessment in testAssessments) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TriageAssessmentCard(triage: assessment),
                      const SizedBox(height: 16),
                      TriageAssessmentCard(triage: assessment, isCompact: true),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Verify widgets render cleanly and text is present
        expect(find.byType(TriageAssessmentCard), findsNWidgets(2));
        expect(find.text(assessment.level), findsNWidgets(2));
        expect(find.text(assessment.summary), findsNWidgets(2));
      }
    });

    test('e) P2P payload with triageAssessment signs, serializes to JSON bytes, and verifies signature successfully', () {
      final triage = TriageAssessment(
        level: 'HIGH',
        summary: 'Compound fracture detected.',
        confidence: 'HIGH',
        source: 'AI_MULTIMODAL',
        transcript: 'my leg is broken',
        assessedAt: DateTime.now(),
      );

      final payloadMap = {
        'eventType': 'SOS_BROADCAST',
        'emergencyId': 'EM-999',
        'id': 'EM-999',
        'victimId': 'victim-123',
        'latitude': 28.6139,
        'longitude': 77.2090,
        'status': 'SEARCHING',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'createdAt': DateTime.now(),
        'triageAssessment': triage.toMap(),
      };

      // Sign payload with safe conversion
      final signedPayload = P2PPayloadIntegrity.signPayload(payloadMap);
      expect(signedPayload.containsKey('signature'), isTrue);
      expect(signedPayload.containsKey('triageAssessment'), isTrue);

      // Serialize to bytes across P2P network
      final jsonBytes = utf8.encode(jsonEncode(signedPayload));

      // Parse and verify on receiving end
      final verified = P2PPayloadIntegrity.parseAndVerifyBytes(Uint8List.fromList(jsonBytes));
      expect(verified, isNotNull);
      expect(verified!['id'], equals('EM-999'));
      expect(verified['triageAssessment'], isNotNull);
      final receivedTriage = TriageAssessment.fromMap(
        Map<String, dynamic>.from(verified['triageAssessment'] as Map),
      );
      expect(receivedTriage.level, equals('HIGH'));
      expect(receivedTriage.summary, equals('Compound fracture detected.'));
      expect(receivedTriage.confidence, equals('HIGH'));
      expect(receivedTriage.source, equals('AI_MULTIMODAL'));
    });

    test('f) Partial capture resiliency: audio throws but camera succeeds, returns frames without failing', () async {
      final partialService = SosMultimodalCaptureService(
        frameCaptureDelegate: () async => [Uint8List.fromList([1, 2, 3])],
        audioCaptureDelegate: (duration) async => throw Exception('MIC_UNAVAILABLE'),
      );

      final result = await partialService.captureSixSecondBurst();
      // Even if mic delegate throws inside custom capture, captureSixSecondBurst handles safely
      expect(result.jpegFrames.length, equals(1));
    });
  });
}

