import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Result containing captured camera frames and/or speech transcript.
class MultimodalCaptureResult {
  final List<Uint8List> jpegFrames;
  final String? transcript;

  const MultimodalCaptureResult({
    this.jpegFrames = const [],
    this.transcript,
  });

  bool get isEmpty =>
      jpegFrames.isEmpty && (transcript == null || transcript!.trim().isEmpty);
}

typedef FrameCaptureDelegate = Future<List<Uint8List>> Function();
typedef AudioCaptureDelegate = Future<String?> Function(Duration duration);

/// Non-blocking sequential multimodal capture service.
///
/// Runs an asynchronous 6-second scene burst after SOS dispatch:
/// 1. Concurrently starts speech-to-text audio capture.
/// 2. Sequentially accesses Rear camera (~1.5s) -> Disposes -> Front camera (~1.5s) -> Disposes.
/// 3. Safely handles missing hardware, revoked permissions, or plugin errors without crashing.
class SosMultimodalCaptureService {
  final FrameCaptureDelegate? _frameCaptureDelegate;
  final AudioCaptureDelegate? _audioCaptureDelegate;

  SosMultimodalCaptureService({
    FrameCaptureDelegate? frameCaptureDelegate,
    AudioCaptureDelegate? audioCaptureDelegate,
  })  : _frameCaptureDelegate = frameCaptureDelegate,
        _audioCaptureDelegate = audioCaptureDelegate;

  Future<MultimodalCaptureResult> captureSixSecondBurst() async {
    try {
      if (_frameCaptureDelegate != null || _audioCaptureDelegate != null) {
        List<Uint8List> frames = [];
        String? text;
        if (_frameCaptureDelegate != null) {
          try {
            frames = await _frameCaptureDelegate!();
          } catch (_) {}
        }
        if (_audioCaptureDelegate != null) {
          try {
            text = await _audioCaptureDelegate!(const Duration(seconds: 6));
          } catch (_) {}
        }
        return MultimodalCaptureResult(jpegFrames: frames, transcript: text);
      }
      return await _executeNativeBurst();
    } catch (_) {
      return const MultimodalCaptureResult();
    }
  }

  Future<MultimodalCaptureResult> _executeNativeBurst() async {
    String? capturedTranscript;
    final List<Uint8List> capturedFrames = [];

    // Check permissions silently; if both missing, exit immediately
    try {
      final camStatus = await Permission.camera.status;
      final micStatus = await Permission.microphone.status;
      if (!camStatus.isGranted && !micStatus.isGranted) {
        return const MultimodalCaptureResult();
      }
    } catch (_) {
      return const MultimodalCaptureResult();
    }

    // 1. Start audio capture asynchronously
    SpeechToText? speech;
    try {
      final micStatus = await Permission.microphone.status;
      if (micStatus.isGranted) {
        speech = SpeechToText();
        bool available = await speech.initialize(
          onError: (_) {},
          onStatus: (_) {},
        );
        if (available) {
          speech.listen(
            onResult: (result) {
              if (result.recognizedWords.isNotEmpty) {
                capturedTranscript = result.recognizedWords;
              }
            },
            listenOptions: SpeechListenOptions(
              listenFor: const Duration(seconds: 6),
              pauseFor: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (_) {}

    // 2. Sequential camera capture: Rear -> Dispose -> Front -> Dispose
    try {
      final camStatus = await Permission.camera.status;
      if (camStatus.isGranted) {
        List<CameraDescription> cameras = [];
        try {
          cameras = await availableCameras();
        } catch (_) {}

        if (cameras.isNotEmpty) {
          // --- REAR CAMERA ---
          try {
            final rearCameras =
                cameras.where((c) => c.lensDirection == CameraLensDirection.back);
            if (rearCameras.isNotEmpty) {
              final rearCamera = rearCameras.first;
              CameraController? rearController = CameraController(
                rearCamera,
                ResolutionPreset.low,
                enableAudio: false,
              );
              try {
                await rearController.initialize();
                await Future.delayed(const Duration(milliseconds: 1500));
                final file = await rearController.takePicture();
                final bytes = await file.readAsBytes();
                if (bytes.isNotEmpty) {
                  capturedFrames.add(bytes);
                }
              } catch (_) {
              } finally {
                try {
                  await rearController.dispose();
                } catch (_) {}
                rearController = null;
              }
            }
          } catch (_) {}

          // --- FRONT CAMERA ---
          try {
            final frontCameras =
                cameras.where((c) => c.lensDirection == CameraLensDirection.front);
            if (frontCameras.isNotEmpty) {
              CameraController? frontController = CameraController(
                frontCameras.first,
                ResolutionPreset.low,
                enableAudio: false,
              );
              try {
                await frontController.initialize();
                await Future.delayed(const Duration(milliseconds: 1500));
                final file = await frontController.takePicture();
                final bytes = await file.readAsBytes();
                if (bytes.isNotEmpty) {
                  capturedFrames.add(bytes);
                }
              } catch (_) {
              } finally {
                try {
                  await frontController.dispose();
                } catch (_) {}
                frontController = null;
              }
            }
          } catch (_) {}
        }
      }
    } catch (_) {}

    // 3. Stop speech recognition
    try {
      if (speech != null && speech.isListening) {
        await speech.stop();
      }
    } catch (_) {}

    debugPrint(
      '[VITA-TRIAGE-CAPTURE] Captured ${capturedFrames.length} frames (sizes: ${capturedFrames.map((f) => f.length).toList()}), transcriptLen: ${capturedTranscript?.length ?? 0}',
    );

    return MultimodalCaptureResult(
      jpegFrames: capturedFrames,
      transcript: capturedTranscript,
    );
  }
}

