import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:jan_sarthi/core/theme/app_theme.dart';
import 'package:jan_sarthi/models/emergency_model.dart';
import 'package:jan_sarthi/models/responder_model.dart';
import 'package:jan_sarthi/services/ai_assistant_service.dart';
import 'package:jan_sarthi/widgets/ai_assistant_sheet.dart';

/// Clean custom MockHttpClient implementing http.BaseClient
class MockHttpClient extends http.BaseClient {
  final Future<http.Response> Function(http.BaseRequest request) handler;
  int requestCount = 0;
  http.BaseRequest? lastRequest;
  String? lastRequestBody;

  MockHttpClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount++;
    lastRequest = request;
    if (request is http.Request) {
      lastRequestBody = request.body;
    }
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmergencyModel testEmergency;

  setUp(() {
    testEmergency = EmergencyModel(
      id: 'em_test_101',
      victimId: 'victim_user_456',
      type: 'MEDICAL',
      latitude: 28.6139,
      longitude: 77.2090,
      status: EmergencyStatus.ASSIGNED,
      helperId: 'responder_user_789',
      createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      updatedAt: DateTime.now(),
      responders: {
        'responder_user_789': ResponderModel(
          userId: 'responder_user_789',
          userName: 'Dr. Ramesh',
          role: ResponderRole.PRIMARY,
          status: ResponderStatus.RESPONDING,
          latitude: 28.6145,
          longitude: 77.2095,
          acceptedAt: DateTime.now(),
          lastLocationUpdate: DateTime.now(),
          distanceToVictim: 450.0,
          etaText: '3 min',
        ),
      },
    );
  });

  group('AIAssistantService Unit Tests', () {
    test('baseUrl trims trailing slashes cleanly', () {
      final service = AIAssistantService();
      service.baseUrl = 'http://10.0.2.2:3000///';
      expect(service.baseUrl, 'http://10.0.2.2:3000');
    });

    test('askAssistant sends request and parses successful 200 response', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        expect(req.url.path, '/api/ai/assistant');
        expect(req.headers['authorization'], startsWith('Bearer '));
        final body = jsonDecode((req as http.Request).body);
        expect(body['query'], 'Where is my responder?');
        expect(body['language'], 'en');

        // Verify non-authoritative client payload: emergencyId is sent; clientContext is NOT sent
        expect(body['emergencyId'], 'em_test_101');
        expect(body.containsKey('clientContext'), isFalse);
        final metrics = body['clientMetrics'];
        expect(metrics['distanceMeters'], 450.0);
        expect(metrics['etaText'], '3 min');
        expect(metrics['isRoadRoute'], isTrue);
        expect(metrics.containsKey('latitude'), isFalse);
        expect(metrics.containsKey('longitude'), isFalse);

        return http.Response(
          jsonEncode({
            'success': true,
            'answer': 'Your primary responder is approximately 450 meters away with an estimated road ETA of 3 min.',
            'disclaimer': 'Non-authoritative explanation based strictly on verified snapshot facts.',
            'model': 'gemini-3.8-flash',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      service.setHttpClientForTesting(mock);

      final res = await service.askAssistant(
        emergency: testEmergency,
        query: 'Where is my responder?',
        isRoadRoute: true,
        distanceMeters: 450.0,
        etaText: '3 min',
      );

      expect(res.success, isTrue);
      expect(res.answer, contains('450 meters away'));
      expect(res.model, 'gemini-3.8-flash');
      expect(res.disclaimer, contains('Non-authoritative'));
      expect(res.isOfflineOrUnavailable, isFalse);
    });

    test('getEmergencyBrief sends request to /api/ai/emergency-brief', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        expect(req.url.path, '/api/ai/emergency-brief');
        final body = jsonDecode((req as http.Request).body);
        expect(body['emergencyId'], 'em_test_101');
        expect(body.containsKey('clientContext'), isFalse);

        return http.Response(
          jsonEncode({
            'success': true,
            'answer': 'Situation Brief: Medical emergency active for 5 minutes. 1 primary responder en route.',
            'disclaimer': 'Non-authoritative emergency brief.',
            'model': 'gemini-3.8-flash',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      service.setHttpClientForTesting(mock);

      final res = await service.getEmergencyBrief(
        emergency: testEmergency,
        isRoadRoute: true,
        distanceMeters: 450.0,
        etaText: '3 min',
      );

      expect(res.success, isTrue);
      expect(res.answer, contains('Situation Brief'));
      expect(res.model, 'gemini-3.8-flash');
    });

    test('handles 401 Unauthorized securely', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'error': 'UNAUTHORIZED',
            'message': 'Valid Firebase ID token required in Authorization header',
          }),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      service.setHttpClientForTesting(mock);

      final res = await service.askAssistant(
        emergency: testEmergency,
        query: 'Test query',
      );

      expect(res.success, isFalse);
      expect(res.error, 'UNAUTHORIZED');
      expect(res.message, contains('Valid Firebase ID token required'));
    });

    test('handles 403 Forbidden securely', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'error': 'FORBIDDEN',
            'message': 'You are not an active participant in this emergency',
          }),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      service.setHttpClientForTesting(mock);

      final res = await service.askAssistant(
        emergency: testEmergency,
        query: 'Test query',
      );

      expect(res.success, isFalse);
      expect(res.error, 'FORBIDDEN');
      expect(res.message, contains('not an active participant'));
    });

    test('handles 429 Rate Limit cleanly', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'error': 'RATE_LIMITED',
            'message': 'Too many assistant requests. Please wait a minute before retrying.',
            'retryAfterSeconds': 60,
          }),
          429,
          headers: {'content-type': 'application/json', 'retry-after': '60'},
        );
      });

      service.setHttpClientForTesting(mock);

      final res = await service.askAssistant(
        emergency: testEmergency,
        query: 'Test query',
      );

      expect(res.success, isFalse);
      expect(res.error, 'RATE_LIMITED');
      expect(res.message, contains('Too many assistant requests'));
    });

    test('handles 503 Backend Unavailable with isOfflineOrUnavailable flag', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'error': 'GEMINI_UNAVAILABLE',
            'message': 'Gemini AI service is temporarily unavailable.',
          }),
          503,
          headers: {'content-type': 'application/json'},
        );
      });

      service.setHttpClientForTesting(mock);

      final res = await service.askAssistant(
        emergency: testEmergency,
        query: 'Test query',
      );

      expect(res.success, isFalse);
      expect(res.isOfflineOrUnavailable, isTrue);
      expect(res.error, 'GEMINI_UNAVAILABLE');
    });

    test('handles SocketException by returning offline fallback without throwing', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        throw const SocketException('Failed host lookup');
      });

      service.setHttpClientForTesting(mock);

      final res = await service.askAssistant(
        emergency: testEmergency,
        query: 'Test query',
      );

      expect(res.success, isFalse);
      expect(res.isOfflineOrUnavailable, isTrue);
      expect(res.error, 'BACKEND_UNAVAILABLE');
      expect(res.message, contains('backend is currently offline or unreachable'));
    });

    test('handles TimeoutException cleanly', () async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        throw TimeoutException('Request timed out');
      });

      service.setHttpClientForTesting(mock);

      final res = await service.askAssistant(
        emergency: testEmergency,
        query: 'Test query',
      );

      expect(res.success, isFalse);
      expect(res.isOfflineOrUnavailable, isTrue);
      expect(res.error, 'AI_TIMEOUT');
      expect(res.message, contains('request timed out'));
    });
  });

  group('AIAssistantSheet Widget Tests', () {
    testWidgets('renders header, non-authoritative disclaimer, quick chips, and initial hint', (tester) async {
      final service = AIAssistantService();
      service.setHttpClientForTesting(MockHttpClient((req) async => http.Response('{}', 200)));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AIAssistantSheet(
              emergency: testEmergency,
              currentUserId: 'victim_user_456',
              isRoadRoute: true,
              roadDistanceMeters: 450,
              directDistanceMeters: 400,
              roadEtaText: '3 min',
              aiService: service,
            ),
          ),
        ),
      );

      expect(find.text('AI Emergency Assistant'), findsOneWidget);
      expect(find.textContaining('Does not replace emergency dispatch (112)'), findsOneWidget);
      expect(find.text('Situation Brief'), findsOneWidget);
      expect(find.text('Where is my responder?'), findsOneWidget);
      expect(find.text('Why is ETA unavailable?'), findsOneWidget);
      expect(find.text('Ask for situational guidance'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('triggers Situation Brief, displays loading state, and renders AI response card', (tester) async {
      final completer = Completer<http.Response>();
      final service = AIAssistantService();
      final mock = MockHttpClient((req) => completer.future);
      service.setHttpClientForTesting(mock);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AIAssistantSheet(
              emergency: testEmergency,
              currentUserId: 'victim_user_456',
              isRoadRoute: true,
              roadDistanceMeters: 450,
              roadEtaText: '3 min',
              aiService: service,
            ),
          ),
        ),
      );

      // Tap Situation Brief
      await tester.tap(find.text('Situation Brief'));
      await tester.pump();

      // Verify loading state
      expect(find.text('Consulting Gemini AI Assistant...'), findsOneWidget);

      // Complete the HTTP response
      completer.complete(
        http.Response(
          jsonEncode({
            'success': true,
            'answer': 'A medical emergency was initiated 5 minutes ago. 1 primary responder is on the way.',
            'disclaimer': 'Non-authoritative explanation based strictly on verified snapshot facts.',
            'model': 'gemini-3.8-flash',
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );

      await tester.pumpAndSettle();

      // Verify AI Response Card is displayed
      expect(find.text('AI SITUATION SUMMARY'), findsOneWidget);
      expect(find.textContaining('A medical emergency was initiated 5 minutes ago'), findsOneWidget);
      expect(find.text('gemini-3.8-flash'), findsOneWidget);
      expect(find.textContaining('strictly on verified snapshot facts'), findsOneWidget);
    });

    testWidgets('displays error card and retry button on failure without crashing', (tester) async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        return http.Response(
          jsonEncode({
            'error': 'BACKEND_OFFLINE',
            'message': 'Cannot reach local Gemini backend at port 3000.',
          }),
          503,
          headers: {'content-type': 'application/json'},
        );
      });
      service.setHttpClientForTesting(mock);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AIAssistantSheet(
              emergency: testEmergency,
              currentUserId: 'victim_user_456',
              aiService: service,
            ),
          ),
        ),
      );

      // Tap Where is my responder?
      await tester.tap(find.text('Where is my responder?'));
      await tester.pumpAndSettle();

      // Verify Error Card is displayed
      expect(find.text('AI Assistant Backend Unavailable'), findsOneWidget);
      expect(find.textContaining('Cannot reach local Gemini backend'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('SOS and navigation are active'), findsOneWidget);
    });

    testWidgets('allows switching language between English and Hindi', (tester) async {
      final service = AIAssistantService();
      final mock = MockHttpClient((req) async {
        final body = jsonDecode((req as http.Request).body);
        expect(body['language'], 'hi');
        return http.Response(
          jsonEncode({
            'success': true,
            'answer': 'आपकी आपातकालीन स्थिति की समीक्षा: 1 सहायक रास्ते में है।',
            'model': 'gemini-3.8-flash',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      service.setHttpClientForTesting(mock);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AIAssistantSheet(
              emergency: testEmergency,
              currentUserId: 'victim_user_456',
              aiService: service,
            ),
          ),
        ),
      );

      // Tap Hindi toggle
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();

      // Trigger question in Hindi
      await tester.tap(find.text('Situation Brief'));
      await tester.pumpAndSettle();

      expect(find.textContaining('आपकी आपातकालीन स्थिति की समीक्षा'), findsOneWidget);
    });
  });
}
