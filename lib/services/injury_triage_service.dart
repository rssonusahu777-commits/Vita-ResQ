import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/triage_assessment_model.dart';

/// Pluggable HTTP client interface for testing and zero-cost REST transport.
abstract class TriageHttpClient {
  Future<String> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 8),
  });
}

/// Default production HTTP client using Dart's built-in dart:io HttpClient.
class DefaultTriageHttpClient implements TriageHttpClient {
  final HttpClient _client;

  DefaultTriageHttpClient([HttpClient? client]) : _client = client ?? HttpClient();

  @override
  Future<String> postJson(
    Uri uri,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final request = await _client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Gemini HTTP error ${response.statusCode}');
    }
    return await response.transform(utf8.decoder).join().timeout(timeout);
  }
}

/// Hybrid AI Injury Assessment Service combining online Gemini 2.5 Flash REST,
/// offline keyword-based fallback triage, and crash unresponsive escalation.
class InjuryTriageService {
  final TriageHttpClient _httpClient;
  final String _apiKey;

  InjuryTriageService({
    TriageHttpClient? httpClient,
    String? apiKey,
  })  : _httpClient = httpClient ?? DefaultTriageHttpClient(),
        _apiKey = apiKey ??
            const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  /// Performs injury assessment using online Gemini multimodal if available,
  /// falling back to local keyword triage on failure, and applying the crash escalation gate.
  Future<TriageAssessment> assessEmergency({
    List<Uint8List> jpegFrames = const [],
    String? transcript,
    bool isOnline = true,
    bool wasCrashDetected = false,
  }) async {
    final bool hasInput = jpegFrames.any((f) => f.isNotEmpty) ||
        (transcript != null && transcript.trim().isNotEmpty);

    if (isOnline && _apiKey.isNotEmpty && hasInput) {
      try {
        final assessment = await _assessOnline(
          jpegFrames: jpegFrames,
          transcript: transcript,
          wasCrashDetected: wasCrashDetected,
        );
        return _applyCrashEscalationGate(assessment, wasCrashDetected);
      } catch (_) {
        // Fall through cleanly to local fallback path on any network or parsing error
      }
    }

    return assessLocally(
      transcript: transcript,
      wasCrashDetected: wasCrashDetected,
    );
  }

  /// Online Gemini REST call to gemini-2.5-flash with inline base64 JPEG parts + transcript.
  Future<TriageAssessment> _assessOnline({
    required List<Uint8List> jpegFrames,
    String? transcript,
    required bool wasCrashDetected,
  }) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_apiKey',
    );

    final List<Map<String, dynamic>> parts = [];

    for (final frame in jpegFrames) {
      if (frame.isNotEmpty) {
        parts.add({
          'inlineData': {
            'mimeType': 'image/jpeg',
            'data': base64Encode(frame),
          }
        });
      }
    }

    final promptText = '''
You are an emergency medical triage assistant for first responders.
Analyze the provided camera frames (if any), voice transcript (if any), and crash sensor status.

Context:
- Crash Impact Detected: $wasCrashDetected
- Voice Transcript: ${transcript?.trim().isNotEmpty == true ? transcript : 'None'}

Instructions:
1. Provide a rapid injury triage assessment.
2. Return ONLY a single valid JSON object with the exact keys:
   {
     "level": "CRITICAL" | "HIGH" | "MODERATE" | "UNCLEAR",
     "summary": "<Concise 1-2 sentence responder briefing, maximum 180 characters>",
     "confidence": "HIGH" | "MEDIUM" | "LOW"
   }
3. Rules:
   - If images are dark, blurry, or obstructed AND transcript has no injury info, return level "UNCLEAR" and confidence "LOW". Never guess low severity.
   - Keep summary under 180 characters, factual, and framed as scene triage for first responders.
   - Do NOT include any markdown codeblocks, prefix, or suffix. Return only raw JSON.
''';

    parts.add({'text': promptText});

    final requestBody = {
      'contents': [
        {
          'parts': parts,
        }
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        'temperature': 0.2,
      }
    };

    final responseBody = await _httpClient.postJson(
      uri,
      requestBody,
      timeout: const Duration(seconds: 8),
    );

    final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
    final candidates = decoded['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw const FormatException('Empty candidates in Gemini response');
    }

    final content = candidates[0]['content'] as Map<String, dynamic>?;
    final partsList = content?['parts'] as List?;
    if (partsList == null || partsList.isEmpty) {
      throw const FormatException('No content parts in Gemini response');
    }

    String rawText = partsList[0]['text']?.toString() ?? '';
    rawText = rawText
        .replaceAll(RegExp(r'^```json\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^```\s*', multiLine: true), '')
        .trim();

    final data = jsonDecode(rawText) as Map<String, dynamic>;
    final level = _normalizeLevel(data['level']);
    final confidence = _normalizeConfidence(data['confidence']);

    String summary = data['summary']?.toString() ?? 'Scene assessment completed.';
    if (summary.length > 180) {
      summary = '${summary.substring(0, 177)}...';
    }

    return TriageAssessment(
      level: level,
      summary: summary,
      confidence: confidence,
      source: 'AI_MULTIMODAL',
      transcript: transcript,
      assessedAt: DateTime.now(),
    );
  }

  /// Offline / Fallback Path inspecting transcript keywords.
  TriageAssessment assessLocally({
    String? transcript,
    bool wasCrashDetected = false,
  }) {
    final text = transcript?.toLowerCase() ?? '';

    const criticalKeywords = [
      'unconscious',
      'not breathing',
      "can't breathe",
      'heavy bleeding',
      'severe bleeding',
      'heart',
      'chest pain',
      'head injury',
      'seizure',
      'trapped',
    ];

    const highKeywords = [
      'broken',
      'fracture',
      'leg',
      'arm',
      'bleeding',
      'accident',
      'crash',
      'fell',
      "can't move",
      'fire',
      'burn',
      'help',
    ];

    const moderateKeywords = [
      'sprain',
      'hurt',
      'pain',
      'dizzy',
      'cut',
    ];

    String level = 'UNCLEAR';
    String confidence = 'LOW';
    String summary = 'Unable to determine injury severity from local audio transcript.';

    if (criticalKeywords.any((kw) => text.contains(kw))) {
      level = 'CRITICAL';
      confidence = 'HIGH';
      summary = 'Critical injury indicators detected in audio transcript.';
    } else if (highKeywords.any((kw) => text.contains(kw))) {
      level = 'HIGH';
      confidence = 'MEDIUM';
      summary = 'Urgent injury or incident reported in audio transcript.';
    } else if (moderateKeywords.any((kw) => text.contains(kw))) {
      level = 'MODERATE';
      confidence = 'MEDIUM';
      summary = 'Moderate injury symptoms detected in audio transcript.';
    }

    final assessment = TriageAssessment(
      level: level,
      summary: summary,
      confidence: confidence,
      source: 'LOCAL_FALLBACK',
      transcript: transcript,
      assessedAt: DateTime.now(),
    );

    return _applyCrashEscalationGate(assessment, wasCrashDetected);
  }

  /// Crash Unresponsive Escalation Gate:
  /// If crash was detected and severity is UNCLEAR, escalate to CRITICAL.
  TriageAssessment _applyCrashEscalationGate(
    TriageAssessment assessment,
    bool wasCrashDetected,
  ) {
    if (wasCrashDetected && assessment.level == 'UNCLEAR') {
      return assessment.copyWith(
        level: 'CRITICAL',
        confidence: 'MEDIUM',
        source: 'CRASH_ESCALATION',
        summary:
            'High-G crash impact detected; victim unresponsive or camera obstructed. Treat as critical.',
      );
    }
    return assessment;
  }

  String _normalizeLevel(dynamic val) {
    final s = val?.toString().toUpperCase();
    if (s == 'CRITICAL' || s == 'HIGH' || s == 'MODERATE') {
      return s!;
    }
    return 'UNCLEAR';
  }

  String _normalizeConfidence(dynamic val) {
    final s = val?.toString().toUpperCase();
    if (s == 'HIGH' || s == 'MEDIUM') {
      return s!;
    }
    return 'LOW';
  }
}

