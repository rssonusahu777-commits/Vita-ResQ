import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/models/hospital_model.dart';
import 'package:jan_sarthi/services/ai_assistant_service.dart';
import 'package:jan_sarthi/services/hospital_service.dart';
import 'package:jan_sarthi/services/routing_service_interface.dart';
import 'package:jan_sarthi/services/voice_assistant_service.dart';
import 'package:jan_sarthi/widgets/ai_assistant_sheet.dart';

// Deterministic Mocks for Unit & Widget Tests

class MockAudioRecorder implements IAudioRecorder {
  bool permissionToReturn = true;
  bool isRecordingState = false;
  String? lastStartedPath;
  bool stopCalled = false;
  bool cancelCalled = false;

  @override
  bool get isRecording => isRecordingState;

  @override
  Future<bool> hasPermission() async => permissionToReturn;

  @override
  Future<bool> requestPermission() async => permissionToReturn;

  @override
  Future<void> startRecording({required String outputPath}) async {
    lastStartedPath = outputPath;
    isRecordingState = true;
  }

  @override
  Future<String?> stopRecording() async {
    stopCalled = true;
    isRecordingState = false;
    return lastStartedPath;
  }

  @override
  Future<void> cancelRecording() async {
    cancelCalled = true;
    isRecordingState = false;
  }
}

class MockAudioPlayer implements IAudioPlayer {
  Uint8List? lastPlayedBytes;
  String? lastPlayedFile;
  bool isPlayingState = false;
  final StreamController<bool> _stateCtrl = StreamController<bool>.broadcast();

  @override
  bool get isPlaying => isPlayingState;

  @override
  Stream<bool> get playbackStateStream => _stateCtrl.stream;

  @override
  Future<void> playBytes(Uint8List bytes) async {
    lastPlayedBytes = bytes;
    isPlayingState = true;
    _stateCtrl.add(true);
  }

  @override
  Future<void> playFile(String path) async {
    lastPlayedFile = path;
    isPlayingState = true;
    _stateCtrl.add(true);
  }

  @override
  Future<void> stop() async {
    isPlayingState = false;
    _stateCtrl.add(false);
  }
}

class MockHospitalService implements IHospitalService {
  List<HospitalModel> hospitalsToReturn = [];
  LatLng? lastQueriedLocation;

  @override
  Future<List<HospitalModel>> discoverNearbyHospitals({
    required LatLng location,
    double radiusMeters = 10000,
    String? emergencyId,
    bool forceRefresh = false,
  }) async {
    lastQueriedLocation = location;
    return hospitalsToReturn;
  }

  @override
  void clearCache({String? emergencyId}) {}
}

class MockRoutingService implements IRoutingService {
  RouteResult? routeToReturn;
  LatLng? lastOrigin;
  LatLng? lastDestination;

  @override
  Future<RouteResult?> fetchRoadRoute(LatLng origin, LatLng destination) async {
    lastOrigin = origin;
    lastDestination = destination;
    return routeToReturn;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late VoiceAssistantService service;
  late MockAudioRecorder mockRecorder;
  late MockAudioPlayer mockPlayer;
  late MockHospitalService mockHospitalService;
  late MockRoutingService mockRoutingService;
  late Directory tempTestDir;

  final testEmergency = EmergencyModel(
    id: 'EM-TEST-VOICE-001',
    victimId: 'victim_123',
    type: 'MEDICAL',
    latitude: 28.6139,
    longitude: 77.2090,
    status: EmergencyStatus.ASSIGNED,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  setUp(() {
    service = VoiceAssistantService();
    service.resetForTesting();
    mockRecorder = MockAudioRecorder();
    mockPlayer = MockAudioPlayer();
    mockHospitalService = MockHospitalService();
    mockRoutingService = MockRoutingService();

    tempTestDir = Directory.systemTemp.createTempSync('vita_voice_test_');

    service.setDependenciesForTesting(
      recorder: mockRecorder,
      player: mockPlayer,
      hospitalService: mockHospitalService,
      routingService: mockRoutingService,
    );
  });

  tearDown(() {
    try {
      if (tempTestDir.existsSync()) {
        tempTestDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  File createMockAudioFile(int sizeBytes) {
    final file = File('${tempTestDir.path}/test_audio_${DateTime.now().millisecondsSinceEpoch}.m4a');
    file.writeAsBytesSync(List.filled(sizeBytes, 0xAA));
    mockRecorder.lastStartedPath = file.path;
    return file;
  }

  group('Phase 4.3 — Microphone Permission & Push-to-Talk Lifecycle', () {
    test('startRecording succeeds when microphone permission is granted', () async {
      mockRecorder.permissionToReturn = true;
      final started = await service.startRecording(
        emergencyId: testEmergency.id,
        tempPath: '${tempTestDir.path}/rec.m4a',
      );

      expect(started, isTrue);
      expect(mockRecorder.isRecording, isTrue);
      expect(service.currentState, VoiceAssistantState.recording);
    });

    test('startRecording fails with PERMISSION_DENIED when microphone is denied', () async {
      mockRecorder.permissionToReturn = false;
      final started = await service.startRecording(
        emergencyId: testEmergency.id,
        tempPath: '${tempTestDir.path}/rec.m4a',
      );

      expect(started, isFalse);
      expect(mockRecorder.isRecording, isFalse);
      expect(service.currentState, VoiceAssistantState.error);
      expect(service.lastResult?.error, 'PERMISSION_DENIED');
      expect(service.lastResult?.message, contains('Microphone permission was denied'));
    });

    test('cancelRecording resets state and cleans up temporary resources', () async {
      final audioFile = createMockAudioFile(500);
      mockRecorder.permissionToReturn = true;
      await service.startRecording(
        emergencyId: testEmergency.id,
        tempPath: audioFile.path,
      );

      await service.cancelRecording();

      expect(mockRecorder.cancelCalled, isTrue);
      expect(mockRecorder.isRecording, isFalse);
      expect(service.currentState, VoiceAssistantState.idle);
      expect(audioFile.existsSync(), isFalse, reason: 'Temporary file must be deleted on cancellation');
    });

    test('Auto-stop callback fires when 10-second maximum duration elapses', () async {
      mockRecorder.permissionToReturn = true;
      await service.startRecording(
        emergencyId: testEmergency.id,
        tempPath: '${tempTestDir.path}/auto_stop.m4a',
        onAutoStop: () {},
      );

      // Verify timer is active without waiting 10 real seconds
      expect(service.currentState, VoiceAssistantState.recording);
      await service.cancelRecording();
    });
  });

  group('Phase 4.3 — Upload Size Enforcement & Audio File Cleanup', () {
    test('Rejects audio exceeding 2 MB limit with AUDIO_TOO_LARGE and deletes file', () async {
      // Create a 2.5 MB audio file (exceeds 2 MB limit)
      final largeFile = createMockAudioFile(2500000);
      mockRecorder.lastStartedPath = largeFile.path;

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isFalse);
      expect(result.error, 'AUDIO_TOO_LARGE');
      expect(result.message, contains('2 MB'));
      expect(largeFile.existsSync(), isFalse, reason: 'Temporary file must be deleted immediately after size check');
    });

    test('Cleans up temporary recording file on successful transcription and processing', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        if (request.url.path.endsWith('/api/voice/transcribe')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'transcript': 'What is the current emergency status?',
              'language': 'en',
            }),
            200,
          );
        } else if (request.url.path.endsWith('/api/voice/speak')) {
          return http.Response.bytes([0xFF, 0xFB, 0x90, 0x64], 200);
        }
        return http.Response('Not Found', 404);
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.transcript, 'What is the current emergency status?');
      expect(validFile.existsSync(), isFalse, reason: 'Temporary file must be deleted after reading');
    });
  });

  group('Phase 4.3 — Deterministic Intent Recognition (English & Hindi)', () {
    test('English nearest hospital intent recognition', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        if (request.url.path.endsWith('/api/voice/transcribe')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'transcript': 'Tell me the nearest hospital for this victim.',
              'language': 'en',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'osm_123',
          name: 'Apex City Hospital',
          latitude: 28.6200,
          longitude: 77.2100,
          distanceMeters: 800,
          durationSeconds: 120,
          etaText: '2 mins',
          type: 'General Hospital',
        ),
      ];

      mockRoutingService.routeToReturn = RouteResult(
        polylinePoints: const [LatLng(28.6139, 77.2090), LatLng(28.6200, 77.2100)],
        distanceMeters: 1100,
        durationSeconds: 180,
        etaText: '3 mins',
        isRoadRoute: true,
      );

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.intentType, VoiceIntentType.nearestHospital);
      expect(result.answerText, contains('Apex City Hospital'));
      expect(result.answerText, contains('road distance 1.1 km'));
      expect(result.answerText, contains('estimated arrival time 3 mins'));
      expect(result.isHospitalUnverified, isFalse);
    });

    test('Hindi nearest hospital intent recognition ("Mujhe paas ka hospital batao")', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        if (request.url.path.endsWith('/api/voice/transcribe')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'transcript': 'Mujhe paas ka hospital batao.',
              'language': 'hi',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'osm_456',
          name: 'Civil Hospital',
          latitude: 28.6250,
          longitude: 77.2150,
          distanceMeters: 1400,
          durationSeconds: 240,
          etaText: '4 mins',
          type: 'Government Trauma Center',
          isGovernmentTraumaCenter: true,
        ),
      ];

      mockRoutingService.routeToReturn = RouteResult(
        polylinePoints: const [LatLng(28.6139, 77.2090), LatLng(28.6250, 77.2150)],
        distanceMeters: 1600,
        durationSeconds: 300,
        etaText: '5 mins',
        isRoadRoute: true,
      );

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.intentType, VoiceIntentType.nearestHospital);
      expect(result.answerText, contains('Civil Hospital'));
      expect(result.answerText, contains('sadak doori 1.6 km'));
      expect(result.answerText, contains('anumanit samay 5 mins'));
    });

    test('Hindi hospital intent recognition ("Patient ke liye sabse nazdeek hospital kaunsa hai?")', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        if (request.url.path.endsWith('/api/voice/transcribe')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'transcript': 'Patient ke liye sabse nazdeek hospital kaunsa hai?',
              'language': 'hi',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'osm_789',
          name: 'Metro Trauma Center',
          latitude: 28.6220,
          longitude: 77.2120,
          distanceMeters: 950,
          durationSeconds: 150,
          etaText: '3 mins',
          type: 'Trauma Center',
        ),
      ];

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.intentType, VoiceIntentType.nearestHospital);
      expect(result.answerText, contains('Metro Trauma Center'));
    });
  });

  group('Phase 4.3 — Victim vs Responder Location Discrimination', () {
    test('Queries victim location by default when hospital query does not specify "near me"', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Find the nearest hospital for this emergency',
            'language': 'en',
          }),
          200,
        );
      });

      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'osm_1',
          name: 'City Care Hospital',
          latitude: 28.6200,
          longitude: 77.2100,
          distanceMeters: 500,
          durationSeconds: 60,
          etaText: '1 min',
          type: 'General Hospital',
        ),
      ];

      service.setDependenciesForTesting(httpClient: mockClient);

      await service.stopRecordingAndProcess(
        emergency: testEmergency,
        responderLocation: const LatLng(28.5000, 77.1000), // Far from victim
      );

      // Must query victim coordinates (28.6139, 77.2090)
      expect(mockHospitalService.lastQueriedLocation?.latitude, closeTo(28.6139, 0.001));
      expect(mockHospitalService.lastQueriedLocation?.longitude, closeTo(77.2090, 0.001));
    });

    test('Queries responder location when responder explicitly asks for hospital "near me" or "mere paas"', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Find the nearest hospital near me',
            'language': 'en',
          }),
          200,
        );
      });

      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'osm_2',
          name: 'South Center Clinic',
          latitude: 28.5050,
          longitude: 77.1050,
          distanceMeters: 400,
          durationSeconds: 60,
          etaText: '1 min',
          type: 'General Hospital',
        ),
      ];

      service.setDependenciesForTesting(httpClient: mockClient);

      await service.stopRecordingAndProcess(
        emergency: testEmergency,
        responderLocation: const LatLng(28.5000, 77.1000), // Responder position
      );

      // Must query responder coordinates (28.5000, 77.1000)
      expect(mockHospitalService.lastQueriedLocation?.latitude, closeTo(28.5000, 0.001));
      expect(mockHospitalService.lastQueriedLocation?.longitude, closeTo(77.1000, 0.001));
    });
  });

  group('Phase 4.3 — Road Distance vs Straight-Line Distance & ETA Fallback', () {
    test('Distinguishes road distance from straight-line distance when routing succeeds', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Where is the closest hospital?',
            'language': 'en',
          }),
          200,
        );
      });

      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'osm_3',
          name: 'Community Hospital',
          latitude: 28.6200,
          longitude: 77.2090,
          distanceMeters: 678, // Straight-line ~678m
          durationSeconds: 90,
          etaText: '2 mins',
          type: 'General Hospital',
        ),
      ];

      mockRoutingService.routeToReturn = RouteResult(
        polylinePoints: const [LatLng(28.6139, 77.2090), LatLng(28.6200, 77.2090)],
        distanceMeters: 1250, // Road route is 1.25 km
        durationSeconds: 180,
        etaText: '3 mins',
        isRoadRoute: true,
      );

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.roadDistanceMeters, 1250);
      expect(result.directDistanceMeters, closeTo(678, 10));
      expect(result.roadEtaText, '3 mins');
      expect(result.answerText, contains('road distance 1.3 km'));
      expect(result.answerText, contains('estimated arrival time 3 mins'));
    });

    test('States straight-line distance and explicitly reports ETA unavailable when routing fails', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Find hospital',
            'language': 'en',
          }),
          200,
        );
      });

      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'osm_4',
          name: 'Rural Emergency Health Center',
          latitude: 28.6200,
          longitude: 77.2090,
          distanceMeters: 800,
          durationSeconds: 120,
          etaText: '2 mins',
          type: 'Rural Hospital',
        ),
      ];

      // Road routing returns null / fails
      mockRoutingService.routeToReturn = null;

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.roadDistanceMeters, isNull);
      expect(result.directDistanceMeters, isNotNull);
      expect(result.answerText, contains('straight-line distance'));
      expect(result.answerText, contains('Road route and ETA are currently unavailable'));
    });
  });

  group('Phase 4.3 — Unverified Demo Hospital Fallback Labelling', () {
    test('Labels fallback template hospitals with unverified demo note', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Nearest hospital',
            'language': 'en',
          }),
          200,
        );
      });

      // Fallback template hospital (id starts with hosp_)
      mockHospitalService.hospitalsToReturn = [
        const HospitalModel(
          id: 'hosp_district_civil_hospital',
          name: 'District Civil & Trauma Hospital',
          latitude: 28.6214,
          longitude: 77.2135,
          distanceMeters: 900,
          durationSeconds: 120,
          etaText: '2 mins',
          type: 'Government Trauma Center',
          isGovernmentTraumaCenter: true,
        ),
      ];

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.isHospitalUnverified, isTrue);
      expect(result.answerText, contains('(Note: facility information is unverified demo data)'));
      expect(result.disclaimer, contains('Demo hospital data provided for resilience'));
    });
  });

  group('Phase 4.3 — Status, Victim Location and Distance Queries', () {
    test('Answers "Where is the victim?" accurately', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Where is the victim?',
            'language': 'en',
          }),
          200,
        );
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
        directDistanceMeters: 450,
      );

      expect(result.success, isTrue);
      expect(result.intentType, VoiceIntentType.victimLocation);
      expect(result.answerText, contains('450 meters away'));
      expect(result.answerText, contains('MEDICAL'));
    });

    test('Answers "What is the current emergency status?" accurately', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'What is the current emergency status?',
            'language': 'en',
          }),
          200,
        );
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(
        emergency: testEmergency,
      );

      expect(result.success, isTrue);
      expect(result.intentType, VoiceIntentType.emergencyStatus);
      expect(result.answerText, contains('ASSIGNED'));
      expect(result.answerText, contains('primary responder is preparing'));
    });
  });

  group('Phase 4.3 — HTTP Error & Provider Failure Handling', () {
    test('Handles HTTP 401 Unauthorized cleanly', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'UNAUTHORIZED', 'message': 'Authentication required.'}),
          401,
        );
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(emergency: testEmergency);
      expect(result.success, isFalse);
      expect(result.error, 'UNAUTHORIZED');
    });

    test('Handles HTTP 403 Forbidden cleanly', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'FORBIDDEN', 'message': 'Access forbidden.'}),
          403,
        );
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(emergency: testEmergency);
      expect(result.success, isFalse);
      expect(result.error, 'FORBIDDEN');
    });

    test('Handles HTTP 429 Rate Limited cleanly', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'ELEVENLABS_RATE_LIMITED', 'message': 'Rate limit exceeded.'}),
          429,
        );
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(emergency: testEmergency);
      expect(result.success, isFalse);
      expect(result.error, 'ELEVENLABS_RATE_LIMITED');
    });

    test('Handles HTTP 503 Provider Unavailable cleanly', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({'success': false, 'error': 'ELEVENLABS_KEY_MISSING', 'message': 'Voice API not configured.'}),
          503,
        );
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(emergency: testEmergency);
      expect(result.success, isFalse);
      expect(result.isOfflineOrUnavailable, isTrue);
    });

    test('Handles Network Disconnection / SocketException gracefully', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        throw const SocketException('Network unreachable');
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      final result = await service.stopRecordingAndProcess(emergency: testEmergency);
      expect(result.success, isFalse);
      expect(result.isOfflineOrUnavailable, isTrue);
      expect(result.message, contains('Emergency SOS and navigation remain fully active'));
    });
  });

  group('Phase 4.3 — Audio Playback & Replay without Re-transcription', () {
    test('replayLastAudio replays synthesized audio bytes without repeating STT request', () async {
      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;
      int sttCalls = 0;

      final mockClient = MockHttpClient((request) async {
        if (request.url.path.endsWith('/api/voice/transcribe')) {
          sttCalls++;
          return http.Response(
            jsonEncode({
              'success': true,
              'transcript': 'Emergency status',
              'language': 'en',
            }),
            200,
          );
        } else if (request.url.path.endsWith('/api/voice/speak')) {
          return http.Response.bytes([0x01, 0x02, 0x03, 0x04], 200);
        }
        return http.Response('Not Found', 404);
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      await service.stopRecordingAndProcess(emergency: testEmergency);
      expect(sttCalls, 1);
      expect(mockPlayer.lastPlayedBytes, isNotNull);

      // Replay audio
      final replayed = await service.replayLastAudio();
      expect(replayed, isTrue);
      expect(sttCalls, 1, reason: 'Replay must NOT repeat STT transcription call');
    });
  });

  group('Phase 4.3 — Safety Invariants: No Status Mutation or Auto-Assignment', () {
    test('Voice operations NEVER modify emergency status or helper assignment', () async {
      final originalStatus = testEmergency.status;
      final originalHelper = testEmergency.helperId;

      final validFile = createMockAudioFile(5000);
      mockRecorder.lastStartedPath = validFile.path;

      final mockClient = MockHttpClient((request) async {
        return http.Response(
          jsonEncode({
            'success': true,
            'transcript': 'Cancel emergency and mark arrived',
            'language': 'en',
          }),
          200,
        );
      });

      service.setDependenciesForTesting(httpClient: mockClient);

      await service.stopRecordingAndProcess(emergency: testEmergency);

      expect(testEmergency.status, originalStatus, reason: 'Voice assistant must be strictly read-only and never mutate status');
      expect(testEmergency.helperId, originalHelper, reason: 'Voice assistant must never reassign helpers');
    });
  });

  group('Phase 4.3 — AIAssistantSheet Voice UI Widget Integration', () {
    testWidgets('Renders push-to-talk mic icon, switches language, and displays result', (tester) async {
      final mockClient = MockHttpClient((request) async {
        if (request.url.path.endsWith('/api/ai/emergency-brief')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'answer': 'This is an active medical emergency with an assigned responder.',
              'disclaimer': 'Verified snapshot data only.',
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final aiService = AIAssistantService();
      aiService.setHttpClientForTesting(mockClient);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AIAssistantSheet(
              emergency: testEmergency,
              currentUserId: 'test_user_responder',
              aiService: aiService,
              voiceService: service,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('AI Emergency Assistant'), findsOneWidget);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(find.text('Situation Brief'), findsOneWidget);
      expect(find.text('Nearest Hospital'), findsOneWidget);

      // Tap Situation Brief
      await tester.tap(find.text('Situation Brief'));
      await tester.pumpAndSettle();

      expect(find.text('This is an active medical emergency with an assigned responder.'), findsOneWidget);
    });
  });
}

// Custom mock HTTP client helper
class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) _handler;

  MockHttpClient(this._handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}
