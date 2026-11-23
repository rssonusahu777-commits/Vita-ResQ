import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../core/constants/app_constants.dart';
import '../models/emergency_model.dart';

/// Structured response object returned by the AI Assistant service.
class AIAssistantResponse {
  final bool success;
  final String answer;
  final String? disclaimer;
  final String? error;
  final String? message;
  final bool isOfflineOrUnavailable;
  final String? model;

  const AIAssistantResponse({
    required this.success,
    required this.answer,
    this.disclaimer,
    this.error,
    this.message,
    this.isOfflineOrUnavailable = false,
    this.model,
  });

  factory AIAssistantResponse.offlineFallback({String? customMessage}) {
    return AIAssistantResponse(
      success: false,
      answer: '',
      isOfflineOrUnavailable: true,
      error: 'BACKEND_UNAVAILABLE',
      message: customMessage ??
          'AI Assistant backend is currently offline or unreachable. All core emergency navigation and dispatch functions remain fully active.',
    );
  }
}

/// Service managing communication with the optional local Gemini AI assistant backend.
class AIAssistantService {
  static final AIAssistantService _instance = AIAssistantService._internal();
  factory AIAssistantService() => _instance;
  AIAssistantService._internal();

  String _baseUrl = AppConstants.defaultAiBackendBaseUrl;
  http.Client? _customHttpClient;

  /// Configure base URL (e.g. for emulator, local network, or testing)
  String get baseUrl => _baseUrl;
  set baseUrl(String url) {
    _baseUrl = url.replaceAll(RegExp(r'/+$'), ''); // trim trailing slashes
  }

  /// Inject custom HTTP client for unit tests
  void setHttpClientForTesting(http.Client? client) {
    _customHttpClient = client;
  }

  http.Client get _client => _customHttpClient ?? http.Client();

  /// Query the AI assistant for situational guidance or questions
  Future<AIAssistantResponse> askAssistant({
    required EmergencyModel emergency,
    required String query,
    String language = 'en',
    bool? isRoadRoute,
    double? distanceMeters,
    String? etaText,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _sendAIRequest(
      endpoint: '/api/ai/assistant',
      emergency: emergency,
      bodyPayload: {
        'query': query,
        'language': language,
      },
      isRoadRoute: isRoadRoute,
      distanceMeters: distanceMeters,
      etaText: etaText,
      timeout: timeout,
    );
  }

  /// Request a concise situation brief
  Future<AIAssistantResponse> getEmergencyBrief({
    required EmergencyModel emergency,
    String language = 'en',
    bool? isRoadRoute,
    double? distanceMeters,
    String? etaText,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _sendAIRequest(
      endpoint: '/api/ai/emergency-brief',
      emergency: emergency,
      bodyPayload: {
        'language': language,
      },
      isRoadRoute: isRoadRoute,
      distanceMeters: distanceMeters,
      etaText: etaText,
      timeout: timeout,
    );
  }

  /// Helper preparing coarse privacy-compliant snapshot and executing HTTP POST
  Future<AIAssistantResponse> _sendAIRequest({
    required String endpoint,
    required EmergencyModel emergency,
    required Map<String, dynamic> bodyPayload,
    bool? isRoadRoute,
    double? distanceMeters,
    String? etaText,
    required Duration timeout,
  }) async {
    try {
      // 1. Obtain Firebase Auth ID token
      String? idToken;
      try {
        idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}

      // In testing or unauthenticated states, handle gracefully
      idToken ??= 'anonymous_dev_token';

      // 2. Build non-authoritative payload: only send emergencyId and optional client-computed telemetry
      // Authoritative state (victimId, status, responders) is strictly retrieved server-side from Firestore.
      final payload = Map<String, dynamic>.from(bodyPayload);
      payload['emergencyId'] = emergency.id;
      if (distanceMeters != null || etaText != null || isRoadRoute != null) {
        payload['clientMetrics'] = {
          'isRoadRoute': isRoadRoute,
          'distanceMeters': distanceMeters,
          'etaText': etaText,
          'timestamp': DateTime.now().toIso8601String(),
        };
      }

      final uri = Uri.parse('$_baseUrl$endpoint');
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);

      final Map<String, dynamic> body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return AIAssistantResponse(
          success: true,
          answer: body['answer'] ?? '',
          disclaimer: body['disclaimer'],
          model: body['model'],
        );
      } else {
        return AIAssistantResponse(
          success: false,
          answer: '',
          error: body['error'] ?? 'ERROR_${response.statusCode}',
          message: body['message'] ?? 'Server returned HTTP ${response.statusCode}',
          isOfflineOrUnavailable: response.statusCode == 503,
        );
      }
    } on SocketException catch (_) {
      return AIAssistantResponse.offlineFallback();
    } on http.ClientException catch (_) {
      return AIAssistantResponse.offlineFallback();
    } on TimeoutException catch (_) {
      return const AIAssistantResponse(
        success: false,
        answer: '',
        isOfflineOrUnavailable: true,
        error: 'AI_TIMEOUT',
        message: 'The AI assistant request timed out. Please check your network connection and retry.',
      );
    } catch (e) {
      return AIAssistantResponse(
        success: false,
        answer: '',
        isOfflineOrUnavailable: true,
        error: 'CLIENT_ERROR',
        message: e.toString(),
      );
    }
  }
}
