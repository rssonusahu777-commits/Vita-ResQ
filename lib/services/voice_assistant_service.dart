import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/app_constants.dart';
import '../models/emergency_model.dart';
import '../models/hospital_model.dart';
import 'ai_assistant_service.dart';
import 'hospital_service.dart';
import 'osrm_routing_service.dart';
import 'routing_service_interface.dart';

/// Push-to-Talk Voice Assistant state
enum VoiceAssistantState {
  idle,
  requestingPermission,
  recording,
  transcribing,
  processingIntent,
  synthesizingSpeech,
  playing,
  error,
}

/// Supported deterministic and AI voice intent classifications
enum VoiceIntentType {
  nearestHospital,
  victimLocation,
  emergencyStatus,
  distanceAndEta,
  generalGemini,
  unrecognized,
}

/// Structured query result returned by the voice assistant
class VoiceQueryResult {
  final bool success;
  final String transcript;
  final String answerText;
  final VoiceIntentType intentType;
  final String language; // 'en' or 'hi'
  final HospitalModel? hospital;
  final bool isHospitalUnverified;
  final double? roadDistanceMeters;
  final double? directDistanceMeters;
  final String? roadEtaText;
  final Uint8List? audioBytes;
  final bool isAudioGenerated;
  final String? error;
  final String? message;
  final bool isOfflineOrUnavailable;
  final String? disclaimer;

  const VoiceQueryResult({
    required this.success,
    required this.transcript,
    required this.answerText,
    required this.intentType,
    this.language = 'en',
    this.hospital,
    this.isHospitalUnverified = false,
    this.roadDistanceMeters,
    this.directDistanceMeters,
    this.roadEtaText,
    this.audioBytes,
    this.isAudioGenerated = false,
    this.error,
    this.message,
    this.isOfflineOrUnavailable = false,
    this.disclaimer,
  });

  factory VoiceQueryResult.error({
    required String error,
    required String message,
    String transcript = '',
    bool isOfflineOrUnavailable = false,
  }) {
    return VoiceQueryResult(
      success: false,
      transcript: transcript,
      answerText: message,
      intentType: VoiceIntentType.unrecognized,
      error: error,
      message: message,
      isOfflineOrUnavailable: isOfflineOrUnavailable,
    );
  }
}

/// Interface for audio recording hardware abstraction
abstract class IAudioRecorder {
  Future<bool> hasPermission();
  Future<bool> requestPermission();
  Future<void> startRecording({required String outputPath});
  Future<String?> stopRecording();
  Future<void> cancelRecording();
  bool get isRecording;
}

/// Interface for audio playback hardware abstraction
abstract class IAudioPlayer {
  Future<void> playBytes(Uint8List bytes);
  Future<void> playFile(String path);
  Future<void> stop();
  bool get isPlaying;
  Stream<bool> get playbackStateStream;
}

/// Native implementation of audio recorder using platform channels
class NativeAudioRecorder implements IAudioRecorder {
  static const MethodChannel _channel = MethodChannel('com.example.jan_sarthi/voice');
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() async {
    try {
      final status = await Permission.microphone.status;
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final status = await Permission.microphone.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> startRecording({required String outputPath}) async {
    try {
      await _channel.invokeMethod('startRecording', {'outputPath': outputPath});
      _recording = true;
    } catch (e) {
      _recording = false;
      rethrow;
    }
  }

  @override
  Future<String?> stopRecording() async {
    try {
      final path = await _channel.invokeMethod<String>('stopRecording');
      _recording = false;
      return path;
    } catch (e) {
      _recording = false;
      rethrow;
    }
  }

  @override
  Future<void> cancelRecording() async {
    try {
      await _channel.invokeMethod('cancelRecording');
    } catch (_) {}
    _recording = false;
  }
}

/// Native implementation of audio player using platform channels
class NativeAudioPlayer implements IAudioPlayer {
  static const MethodChannel _channel = MethodChannel('com.example.jan_sarthi/voice');
  final StreamController<bool> _stateController = StreamController<bool>.broadcast();
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Stream<bool> get playbackStateStream => _stateController.stream;

  @override
  Future<void> playBytes(Uint8List bytes) async {
    try {
      await _channel.invokeMethod('playAudioBytes', {'bytes': bytes});
      _playing = true;
      _stateController.add(true);
    } catch (e) {
      _playing = false;
      _stateController.add(false);
      rethrow;
    }
  }

  @override
  Future<void> playFile(String path) async {
    try {
      await _channel.invokeMethod('playAudioFile', {'filePath': path});
      _playing = true;
      _stateController.add(true);
    } catch (e) {
      _playing = false;
      _stateController.add(false);
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopAudioPlayback');
    } catch (_) {}
    _playing = false;
    _stateController.add(false);
  }
}

/// Primary Flutter Voice Assistant Service coordinating Push-to-Talk recording,
/// ElevenLabs STT transcription, deterministic intent evaluation, hospital discovery,
/// road routing, Gemini fallback, ElevenLabs TTS, and safe audio playback.
class VoiceAssistantService {
  static final VoiceAssistantService _instance = VoiceAssistantService._internal();
  factory VoiceAssistantService() => _instance;
  VoiceAssistantService._internal();

  String _baseUrl = AppConstants.defaultAiBackendBaseUrl;

  String get baseUrl => _baseUrl;
  set baseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), '');
  }

  // Injectable dependencies for deterministic testing
  IAudioRecorder _recorder = NativeAudioRecorder();
  IAudioPlayer _player = NativeAudioPlayer();
  http.Client? _customHttpClient;
  IHospitalService _hospitalService = HospitalService.instance;
  IRoutingService _routingService = OSRMRoutingService();
  AIAssistantService _aiService = AIAssistantService();

  // Active state management
  VoiceAssistantState _state = VoiceAssistantState.idle;
  Timer? _maxRecordingTimer;
  String? _currentRecordingPath;
  VoiceQueryResult? _lastResult;

  final StreamController<VoiceAssistantState> _stateController =
      StreamController<VoiceAssistantState>.broadcast();

  Stream<VoiceAssistantState> get stateStream => _stateController.stream;
  VoiceAssistantState get currentState => _state;
  VoiceQueryResult? get lastResult => _lastResult;

  void _setState(VoiceAssistantState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// Dependency injection for automated unit and widget testing
  void setDependenciesForTesting({
    IAudioRecorder? recorder,
    IAudioPlayer? player,
    http.Client? httpClient,
    IHospitalService? hospitalService,
    IRoutingService? routingService,
    AIAssistantService? aiService,
  }) {
    if (recorder != null) _recorder = recorder;
    if (player != null) _player = player;
    if (httpClient != null) _customHttpClient = httpClient;
    if (hospitalService != null) _hospitalService = hospitalService;
    if (routingService != null) _routingService = routingService;
    if (aiService != null) _aiService = aiService;
  }

  http.Client get _client => _customHttpClient ?? http.Client();

  /// Start push-to-talk recording with explicit permission check and 10s auto-stop
  Future<bool> startRecording({
    required String emergencyId,
    String? tempPath,
    void Function()? onAutoStop,
  }) async {
    if (_recorder.isRecording) return true;

    // 1. Request microphone permission explicitly
    _setState(VoiceAssistantState.requestingPermission);
    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      final granted = await _recorder.requestPermission();
      if (!granted) {
        _setState(VoiceAssistantState.error);
        _lastResult = VoiceQueryResult.error(
          error: 'PERMISSION_DENIED',
          message: 'Microphone permission was denied. Please grant microphone access in device settings to use voice commands.',
        );
        return false;
      }
    }

    // 2. Prepare temporary file
    final path = tempPath ??
        '${Directory.systemTemp.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _currentRecordingPath = path;

    try {
      await _recorder.startRecording(outputPath: path);
      _setState(VoiceAssistantState.recording);

      // 3. Enforce maximum 10-second recording duration
      _maxRecordingTimer?.cancel();
      _maxRecordingTimer = Timer(const Duration(seconds: 10), () {
        if (_recorder.isRecording) {
          if (onAutoStop != null) {
            onAutoStop();
          }
        }
      });
      return true;
    } catch (e) {
      _setState(VoiceAssistantState.error);
      _lastResult = VoiceQueryResult.error(
        error: 'RECORDER_ERROR',
        message: 'Could not initialize audio recorder: ${e.toString()}',
      );
      return false;
    }
  }

  /// Reset service state (for testing)
  void resetForTesting() {
    _state = VoiceAssistantState.idle;
    _lastResult = null;
    _currentRecordingPath = null;
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = null;
  }

  /// Stop push-to-talk recording, transcribe via ElevenLabs STT, interpret intent,
  /// fetch verified data, synthesize speech via ElevenLabs TTS, and play result.
  Future<VoiceQueryResult> stopRecordingAndProcess({
    required EmergencyModel emergency,
    String? audioFilePath,
    LatLng? responderLocation,
    bool? isRoadRoute,
    double? roadDistanceMeters,
    double? directDistanceMeters,
    String? roadEtaText,
    String preferredLanguage = 'en',
  }) async {
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = null;

    String? audioPath = audioFilePath;
    if (audioPath == null) {
      try {
        audioPath = await _recorder.stopRecording();
      } catch (_) {
        audioPath = _currentRecordingPath;
      }
      audioPath ??= _currentRecordingPath;
    }

    if (audioPath == null) {
      _setState(VoiceAssistantState.idle);
      return VoiceQueryResult.error(
        error: 'NOT_RECORDING',
        message: 'No active recording found.',
      );
    }

    final audioFile = File(audioPath);
    if (!audioFile.existsSync()) {
      _setState(VoiceAssistantState.error);
      return VoiceQueryResult.error(
        error: 'AUDIO_FILE_NOT_FOUND',
        message: 'Recorded audio file could not be found.',
      );
    }

    // Check file size (<= 2 MB backend limit)
    final int fileBytesLength = audioFile.lengthSync();
    if (fileBytesLength > 2 * 1024 * 1024) {
      _safeDeleteFile(audioFile);
      _setState(VoiceAssistantState.error);
      final res = VoiceQueryResult.error(
        error: 'AUDIO_TOO_LARGE',
        message: 'Audio recording exceeds maximum allowed size of 2 MB.',
      );
      _lastResult = res;
      return res;
    }

    Uint8List fileBytes;
    try {
      fileBytes = audioFile.readAsBytesSync();
    } catch (e) {
      _safeDeleteFile(audioFile);
      _setState(VoiceAssistantState.error);
      final res = VoiceQueryResult.error(
        error: 'AUDIO_READ_ERROR',
        message: 'Failed to read recorded audio: ${e.toString()}',
      );
      _lastResult = res;
      return res;
    }

    // Clean up temporary audio recording file immediately after reading
    _safeDeleteFile(audioFile);
    _currentRecordingPath = null;

    // 1. Transcribe audio via ElevenLabs STT
    _setState(VoiceAssistantState.transcribing);
    final transcribeResult = await _transcribeAudio(
      emergencyId: emergency.id,
      audioBytes: fileBytes,
      preferredLanguage: preferredLanguage,
    );

    if (!transcribeResult.success) {
      _setState(VoiceAssistantState.error);
      _lastResult = transcribeResult;
      return transcribeResult;
    }

    final transcript = transcribeResult.transcript;
    final detectedLang = transcribeResult.language;

    // 2. Classify and process intent
    _setState(VoiceAssistantState.processingIntent);
    final intentResult = await _processIntent(
      emergency: emergency,
      transcript: transcript,
      detectedLanguage: detectedLang,
      responderLocation: responderLocation,
      isRoadRoute: isRoadRoute,
      roadDistanceMeters: roadDistanceMeters,
      directDistanceMeters: directDistanceMeters,
      roadEtaText: roadEtaText,
    );

    // 3. Synthesize speech via ElevenLabs TTS (optional audio output)
    _setState(VoiceAssistantState.synthesizingSpeech);
    final speechBytes = await _synthesizeSpeech(
      emergencyId: emergency.id,
      text: intentResult.answerText,
      language: intentResult.language,
    );

    VoiceQueryResult finalResult;
    if (speechBytes != null && speechBytes.isNotEmpty) {
      finalResult = VoiceQueryResult(
        success: true,
        transcript: intentResult.transcript,
        answerText: intentResult.answerText,
        intentType: intentResult.intentType,
        language: intentResult.language,
        hospital: intentResult.hospital,
        isHospitalUnverified: intentResult.isHospitalUnverified,
        roadDistanceMeters: intentResult.roadDistanceMeters,
        directDistanceMeters: intentResult.directDistanceMeters,
        roadEtaText: intentResult.roadEtaText,
        audioBytes: speechBytes,
        isAudioGenerated: true,
        disclaimer: intentResult.disclaimer,
      );
    } else {
      finalResult = intentResult;
    }

    _lastResult = finalResult;

    // 4. Play audio if generated
    if (finalResult.audioBytes != null) {
      _setState(VoiceAssistantState.playing);
      try {
        await _player.playBytes(finalResult.audioBytes!);
      } catch (_) {
        // Audio playback failure does not invalidate the text result
      }
    }

    _setState(VoiceAssistantState.idle);
    return finalResult;
  }

  /// Cancel active recording and discard temporary files
  Future<void> cancelRecording() async {
    _maxRecordingTimer?.cancel();
    _maxRecordingTimer = null;
    try {
      await _recorder.cancelRecording();
    } catch (_) {}
    if (_currentRecordingPath != null) {
      _safeDeleteFile(File(_currentRecordingPath!));
      _currentRecordingPath = null;
    }
    _setState(VoiceAssistantState.idle);
  }

  /// Replay the last synthesized speech without repeating STT or TTS API requests
  Future<bool> replayLastAudio() async {
    if (_lastResult?.audioBytes == null) return false;
    _setState(VoiceAssistantState.playing);
    try {
      await _player.playBytes(_lastResult!.audioBytes!);
      _setState(VoiceAssistantState.idle);
      return true;
    } catch (_) {
      _setState(VoiceAssistantState.idle);
      return false;
    }
  }

  /// Stop any active audio playback
  Future<void> stopAudio() async {
    try {
      await _player.stop();
    } catch (_) {}
    if (_state == VoiceAssistantState.playing) {
      _setState(VoiceAssistantState.idle);
    }
  }

  /// Execute HTTP POST to ElevenLabs STT endpoint on backend
  Future<VoiceQueryResult> _transcribeAudio({
    required String emergencyId,
    required Uint8List audioBytes,
    required String preferredLanguage,
  }) async {
    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    idToken ??= 'anonymous_dev_token';

    try {
      final uri = Uri.parse('$_baseUrl/api/voice/transcribe');
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $idToken'
        ..fields['emergencyId'] = emergencyId
        ..fields['language'] = preferredLanguage
        ..files.add(
          http.MultipartFile.fromBytes(
            'audio',
            audioBytes,
            filename: 'recording.m4a',
          ),
        );

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 12));
      final response = await http.Response.fromStream(streamedResponse);

      Map<String, dynamic> body = {};
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {}

      if (response.statusCode == 200 && body['success'] == true) {
        final transcript = (body['transcript'] ?? '').toString().trim();
        final lang = (body['language'] ?? preferredLanguage).toString();
        if (transcript.isEmpty) {
          return VoiceQueryResult.error(
            error: 'NO_SPEECH_DETECTED',
            message: 'No clear speech could be detected in the recording. Please try speaking again.',
          );
        }
        return VoiceQueryResult(
          success: true,
          transcript: transcript,
          answerText: '',
          intentType: VoiceIntentType.unrecognized,
          language: lang,
        );
      } else {
        final errorCode = body['error']?.toString() ?? 'VOICE_HTTP_${response.statusCode}';
        final message = body['message']?.toString() ?? 'Voice transcription failed (${response.statusCode})';
        final isUnavailable = response.statusCode == 503 || response.statusCode == 504 || response.statusCode == 502;
        return VoiceQueryResult.error(
          error: errorCode,
          message: message,
          isOfflineOrUnavailable: isUnavailable,
        );
      }
    } on SocketException catch (_) {
      return VoiceQueryResult.error(
        error: 'BACKEND_OFFLINE',
        message: 'Voice assistant backend is currently offline. Emergency SOS and navigation remain fully active.',
        isOfflineOrUnavailable: true,
      );
    } on http.ClientException catch (_) {
      return VoiceQueryResult.error(
        error: 'BACKEND_UNAVAILABLE',
        message: 'Could not connect to voice backend. Please check network connectivity.',
        isOfflineOrUnavailable: true,
      );
    } on TimeoutException catch (_) {
      return VoiceQueryResult.error(
        error: 'VOICE_TIMEOUT',
        message: 'Voice request timed out. Please retry with a shorter voice query.',
        isOfflineOrUnavailable: true,
      );
    } catch (e) {
      return VoiceQueryResult.error(
        error: 'TRANSCRIPTION_FAILED',
        message: e.toString(),
      );
    }
  }

  /// Execute HTTP POST to ElevenLabs TTS endpoint on backend
  Future<Uint8List?> _synthesizeSpeech({
    required String emergencyId,
    required String text,
    required String language,
  }) async {
    if (text.trim().isEmpty) return null;

    String? idToken;
    try {
      idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    idToken ??= 'anonymous_dev_token';

    try {
      final uri = Uri.parse('$_baseUrl/api/voice/speak');
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({
              'emergencyId': emergencyId,
              'text': text,
              'language': language,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return response.bodyBytes;
      }
      return null;
    } catch (_) {
      // Speech synthesis failure is optional and gracefully skipped
      return null;
    }
  }

  /// Classify intent deterministically or delegate to Gemini assistant
  Future<VoiceQueryResult> _processIntent({
    required EmergencyModel emergency,
    required String transcript,
    required String detectedLanguage,
    LatLng? responderLocation,
    bool? isRoadRoute,
    double? roadDistanceMeters,
    double? directDistanceMeters,
    String? roadEtaText,
  }) async {
    final lower = transcript.toLowerCase();
    final isHindi = detectedLanguage == 'hi' || _isHindiText(lower);
    final lang = isHindi ? 'hi' : 'en';

    // 1. Check Hospital Intent
    if (_isHospitalIntent(lower)) {
      return _handleHospitalIntent(
        emergency: emergency,
        transcript: transcript,
        lowerQuery: lower,
        isHindi: isHindi,
        responderLocation: responderLocation,
      );
    }

    // 2. Check Victim Location Intent
    if (_isVictimLocationIntent(lower)) {
      return _handleVictimLocationIntent(
        emergency: emergency,
        transcript: transcript,
        isHindi: isHindi,
        responderLocation: responderLocation,
        directDistanceMeters: directDistanceMeters,
      );
    }

    // 3. Check Emergency Status Intent
    if (_isStatusIntent(lower)) {
      return _handleStatusIntent(
        emergency: emergency,
        transcript: transcript,
        isHindi: isHindi,
      );
    }

    // 4. Check Distance and ETA Intent
    if (_isDistanceAndEtaIntent(lower)) {
      return _handleDistanceAndEtaIntent(
        emergency: emergency,
        transcript: transcript,
        isHindi: isHindi,
        isRoadRoute: isRoadRoute,
        roadDistanceMeters: roadDistanceMeters,
        directDistanceMeters: directDistanceMeters,
        roadEtaText: roadEtaText,
      );
    }

    // 5. General Questions via Gemini AI Assistant
    return _handleGeneralGeminiIntent(
      emergency: emergency,
      transcript: transcript,
      language: lang,
      isRoadRoute: isRoadRoute,
      roadDistanceMeters: roadDistanceMeters,
      roadEtaText: roadEtaText,
    );
  }

  bool _isHindiText(String query) {
    const hindiKeywords = [
      'hospital', 'aspatal', 'aspataal', 'nazdeek', 'paas', 'sabse', 'kahan',
      'mariz', 'batao', 'door', 'kitna', 'samay', 'hai', 'kya', 'madad', 'sthiti',
      'pahunchne', 'doori', 'chahiye'
    ];
    // Check Devanagari Unicode range (0900–097F)
    final hasDevanagari = RegExp(r'[\u0900-\u097F]').hasMatch(query);
    if (hasDevanagari) return true;

    int matched = 0;
    for (var word in hindiKeywords) {
      if (query.contains(word)) matched++;
    }
    return matched >= 2;
  }

  bool _isHospitalIntent(String query) {
    const patterns = [
      'hospital', 'trauma', 'medical center', 'clinic', 'aspatal', 'aspataal',
      'nazdeek hospital', 'paas ka hospital', 'paas me hospital', 'sabse nazdeek',
      'nearest hospital', 'closest hospital', 'emergency room', 'hospital batao'
    ];
    return patterns.any((p) => query.contains(p));
  }

  bool _isVictimLocationIntent(String query) {
    const patterns = [
      'where is the victim', 'where is patient', 'victim location', 'patient location',
      'where is victim', 'find victim', 'victim kahan', 'patient kahan', 'mariz kahan',
      'incident location', 'where is the emergency', 'emergency kahan'
    ];
    return patterns.any((p) => query.contains(p));
  }

  bool _isStatusIntent(String query) {
    const patterns = [
      'emergency status', 'current status', 'what is the status', 'status of emergency',
      'status kya hai', 'emergency ka status', 'kya sthiti', 'status update'
    ];
    return patterns.any((p) => query.contains(p));
  }

  bool _isDistanceAndEtaIntent(String query) {
    const patterns = [
      'road distance', 'estimated arrival time', 'what is the eta', 'how far',
      'arrival time', 'distance and eta', 'kitni door', 'kitna time', 'kitna samay',
      'pahunchne me kitna', 'eta kya hai', 'doori kitni'
    ];
    return patterns.any((p) => query.contains(p));
  }

  /// Handle hospital query with location discrimination, road routing, and demo disclaimer
  Future<VoiceQueryResult> _handleHospitalIntent({
    required EmergencyModel emergency,
    required String transcript,
    required String lowerQuery,
    required bool isHindi,
    LatLng? responderLocation,
  }) async {
    // 1. Determine target origin: responder location if explicitly requested ("near me", "my location", "mere paas")
    final bool useResponderLoc = (lowerQuery.contains('near me') ||
            lowerQuery.contains('my location') ||
            lowerQuery.contains('mere paas') ||
            lowerQuery.contains('mujhe paas')) &&
        responderLocation != null;

    final LatLng targetLocation = useResponderLoc
        ? responderLocation
        : LatLng(emergency.latitude, emergency.longitude);

    // 2. Discover nearby hospitals
    List<HospitalModel> hospitals = [];
    try {
      hospitals = await _hospitalService.discoverNearbyHospitals(
        location: targetLocation,
        emergencyId: emergency.id,
      );
    } catch (_) {}

    if (hospitals.isEmpty) {
      final msg = isHindi
          ? 'Kripya dhyaan dein: Aas-paas koi hospital uplabdh nahi ho saka.'
          : 'No nearby hospitals could be located at this time.';
      return VoiceQueryResult(
        success: true,
        transcript: transcript,
        answerText: msg,
        intentType: VoiceIntentType.nearestHospital,
        language: isHindi ? 'hi' : 'en',
      );
    }

    // 3. Select best hospital
    final HospitalModel hospital = hospitals.first;
    final bool isUnverified = hospital.id.startsWith('hosp_') ||
        hospital.name.contains('District Civil & Trauma Hospital') ||
        hospital.name.contains('City Care Multi-Specialty Hospital') ||
        hospital.name.contains('Apex Super-Specialty Medical Institute') ||
        hospital.name.contains('Metro Community Emergency Center');

    // 4. Calculate straight-line distance
    final double straightLineDist = Geolocator.distanceBetween(
      targetLocation.latitude,
      targetLocation.longitude,
      hospital.latitude,
      hospital.longitude,
    );

    // 5. Calculate road route and ETA
    RouteResult? route;
    try {
      route = await _routingService.fetchRoadRoute(targetLocation, hospital.location);
    } catch (_) {}

    final bool hasRoadRoute = route != null && route.isRoadRoute && route.distanceMeters > 0;
    final double? roadDist = hasRoadRoute ? route.distanceMeters : null;
    final String? eta = hasRoadRoute ? route.etaText : null;

    // 6. Format concise answer text
    String answer;
    final String distanceLabel = formatDistance(straightLineDist);
    final String demoNoteEn = isUnverified ? ' (Note: facility information is unverified demo data).' : '';
    final String demoNoteHi = isUnverified ? ' (Yeh facility asatyapit demo data hai).' : '';

    if (isHindi) {
      if (hasRoadRoute) {
        final roadDistLabel = formatDistance(roadDist!);
        answer = 'Sabse nazdeek hospital ${hospital.name} hai, sadak doori $roadDistLabel, pahunchne ka anumanit samay $eta$demoNoteHi.';
      } else {
        answer = 'Sabse nazdeek hospital ${hospital.name} hai, sidhi doori $distanceLabel. Sadak marg aur ETA uplabdh nahi hai$demoNoteHi.';
      }
    } else {
      if (hasRoadRoute) {
        final roadDistLabel = formatDistance(roadDist!);
        answer = 'Nearest hospital is ${hospital.name}, road distance $roadDistLabel, estimated arrival time $eta$demoNoteEn.';
      } else {
        answer = 'Nearest hospital is ${hospital.name}, $distanceLabel straight-line distance. Road route and ETA are currently unavailable$demoNoteEn.';
      }
    }

    return VoiceQueryResult(
      success: true,
      transcript: transcript,
      answerText: answer,
      intentType: VoiceIntentType.nearestHospital,
      language: isHindi ? 'hi' : 'en',
      hospital: hospital,
      isHospitalUnverified: isUnverified,
      roadDistanceMeters: roadDist,
      directDistanceMeters: straightLineDist,
      roadEtaText: eta,
      disclaimer: isUnverified
          ? 'Demo hospital data provided for resilience when network/Overpass API is unreachable.'
          : null,
    );
  }

  /// Handle victim location request
  VoiceQueryResult _handleVictimLocationIntent({
    required EmergencyModel emergency,
    required String transcript,
    required bool isHindi,
    LatLng? responderLocation,
    double? directDistanceMeters,
  }) {
    double dist = directDistanceMeters ?? 0.0;
    if (responderLocation != null && dist <= 0) {
      dist = Geolocator.distanceBetween(
        responderLocation.latitude,
        responderLocation.longitude,
        emergency.latitude,
        emergency.longitude,
      );
    }
    final distStr = dist > 0 ? ' (${formatDistance(dist)} away)' : '';

    String answer;
    if (isHindi) {
      answer = dist > 0
          ? 'Victim emergency coordinates par sthit hain, aapse lagbhag ${formatDistance(dist)} door.'
          : 'Victim emergency map coordinates par sthit hain.';
    } else {
      answer = 'The victim is at the emergency coordinates$distStr. Emergency type: ${emergency.type}.';
    }

    return VoiceQueryResult(
      success: true,
      transcript: transcript,
      answerText: answer,
      intentType: VoiceIntentType.victimLocation,
      language: isHindi ? 'hi' : 'en',
      directDistanceMeters: dist > 0 ? dist : null,
    );
  }

  /// Handle emergency status query
  VoiceQueryResult _handleStatusIntent({
    required EmergencyModel emergency,
    required String transcript,
    required bool isHindi,
  }) {
    String answer;

    if (isHindi) {
      switch (emergency.status) {
        case EmergencyStatus.SEARCHING:
          answer = 'Emergency ki vartaman sthiti SEARCHING hai: aas-paas ke responders ko alert bheja ja raha hai.';
          break;
        case EmergencyStatus.ASSIGNED:
          answer = 'Emergency ki sthiti ASSIGNED hai: responder assign ho chuke hain aur tayari me hain.';
          break;
        case EmergencyStatus.APPROACHING:
          answer = 'Emergency ki sthiti APPROACHING hai: responder victim ki or badh rahe hain.';
          break;
        case EmergencyStatus.ARRIVED:
          answer = 'Emergency ki sthiti ARRIVED hai: responder ghatnasthal par pahunch chuke hain.';
          break;
        case EmergencyStatus.COMPLETED:
          answer = 'Yeh emergency surakshit roop se COMPLETED ho chuki hai.';
          break;
        case EmergencyStatus.CANCELLED:
          answer = 'Yeh emergency CANCEL ho chuki hai.';
          break;
      }
    } else {
      switch (emergency.status) {
        case EmergencyStatus.SEARCHING:
          answer = 'The emergency status is SEARCHING: actively alerting nearby responders.';
          break;
        case EmergencyStatus.ASSIGNED:
          answer = 'The emergency status is ASSIGNED: a primary responder is preparing.';
          break;
        case EmergencyStatus.APPROACHING:
          answer = 'The emergency status is APPROACHING: responder is en route to victim coordinates.';
          break;
        case EmergencyStatus.ARRIVED:
          answer = 'The emergency status is ARRIVED: responder has reached the scene.';
          break;
        case EmergencyStatus.COMPLETED:
          answer = 'The emergency is COMPLETED and safely resolved.';
          break;
        case EmergencyStatus.CANCELLED:
          answer = 'The emergency has been CANCELLED.';
          break;
      }
    }

    return VoiceQueryResult(
      success: true,
      transcript: transcript,
      answerText: answer,
      intentType: VoiceIntentType.emergencyStatus,
      language: isHindi ? 'hi' : 'en',
    );
  }

  /// Handle distance and ETA query
  VoiceQueryResult _handleDistanceAndEtaIntent({
    required EmergencyModel emergency,
    required String transcript,
    required bool isHindi,
    bool? isRoadRoute,
    double? roadDistanceMeters,
    double? directDistanceMeters,
    String? roadEtaText,
  }) {
    final bool hasRoad = (isRoadRoute == true) && (roadDistanceMeters != null && roadDistanceMeters > 0);
    String answer;

    if (isHindi) {
      if (hasRoad) {
        final roadStr = formatDistance(roadDistanceMeters);
        final etaStr = roadEtaText ?? '-- min';
        answer = 'Sadak doori $roadStr hai aur anumanit samay $etaStr hai.';
      } else if (directDistanceMeters != null && directDistanceMeters > 0) {
        final directStr = formatDistance(directDistanceMeters);
        answer = 'Sidhi doori $directStr hai. Sadak marg aur ETA vartaman me uplabdh nahi hai.';
      } else {
        answer = 'Doori aur ETA vartaman me uplabdh nahi hai.';
      }
    } else {
      if (hasRoad) {
        final roadStr = formatDistance(roadDistanceMeters);
        final etaStr = roadEtaText ?? '-- min';
        answer = 'The road distance is $roadStr with an estimated arrival time of $etaStr.';
      } else if (directDistanceMeters != null && directDistanceMeters > 0) {
        final directStr = formatDistance(directDistanceMeters);
        answer = 'Straight-line distance is $directStr. Road route and ETA are currently unavailable.';
      } else {
        answer = 'Distance and ETA metrics are currently unavailable.';
      }
    }

    return VoiceQueryResult(
      success: true,
      transcript: transcript,
      answerText: answer,
      intentType: VoiceIntentType.distanceAndEta,
      language: isHindi ? 'hi' : 'en',
      roadDistanceMeters: roadDistanceMeters,
      directDistanceMeters: directDistanceMeters,
      roadEtaText: roadEtaText,
    );
  }

  /// Handle open-ended general questions using Gemini AI Assistant endpoint
  Future<VoiceQueryResult> _handleGeneralGeminiIntent({
    required EmergencyModel emergency,
    required String transcript,
    required String language,
    bool? isRoadRoute,
    double? roadDistanceMeters,
    String? roadEtaText,
  }) async {
    try {
      final aiResponse = await _aiService.askAssistant(
        emergency: emergency,
        query: transcript,
        language: language,
        isRoadRoute: isRoadRoute,
        distanceMeters: roadDistanceMeters,
        etaText: roadEtaText,
      );

      if (aiResponse.success && aiResponse.answer.isNotEmpty) {
        return VoiceQueryResult(
          success: true,
          transcript: transcript,
          answerText: aiResponse.answer,
          intentType: VoiceIntentType.generalGemini,
          language: language,
          disclaimer: aiResponse.disclaimer,
        );
      } else {
        final fallbackMsg = language == 'hi'
            ? 'AI Assistant se sampark nahi ho saka. Emergency navigation aur dispatch puri tarah sakriya hain.'
            : 'AI assistant is currently unavailable. All core emergency navigation and dispatch functions remain active.';

        return VoiceQueryResult(
          success: true,
          transcript: transcript,
          answerText: fallbackMsg,
          intentType: VoiceIntentType.generalGemini,
          language: language,
          isOfflineOrUnavailable: true,
          error: aiResponse.error,
        );
      }
    } catch (_) {
      final fallbackMsg = language == 'hi'
          ? 'AI Assistant se sampark nahi ho saka. Emergency dispatch sakriya hai.'
          : 'AI assistant is currently unavailable. All core emergency operations remain fully active.';

      return VoiceQueryResult(
        success: true,
        transcript: transcript,
        answerText: fallbackMsg,
        intentType: VoiceIntentType.generalGemini,
        language: language,
        isOfflineOrUnavailable: true,
      );
    }
  }

  static String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.round()} meters';
    }
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static void _safeDeleteFile(File file) {
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  void dispose() {
    _maxRecordingTimer?.cancel();
    _stateController.close();
  }
}
