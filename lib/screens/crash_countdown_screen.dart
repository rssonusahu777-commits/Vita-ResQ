// lib/screens/crash_countdown_screen.dart
//
// Vindara — Cancellable 10-Second Possible Crash Countdown Screen
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #10 — Honest "Possible Crash" framing. Strictly zero "SOS" labels.
//              Massive "I'M SAFE — CANCEL" button to abort without penalty.
//              Auto-triggers HELP alert with DetectionSource.possibleCrash at 0s.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/emergency.dart';
import '../providers/providers.dart';
import '../services/crash_detection_service.dart';
import '../theme/vindara_theme.dart';

class CrashCountdownScreen extends ConsumerStatefulWidget {
  final int initialSeconds;

  const CrashCountdownScreen({
    super.key,
    this.initialSeconds = 10,
  });

  @override
  ConsumerState<CrashCountdownScreen> createState() =>
      _CrashCountdownScreenState();
}

class _CrashCountdownScreenState extends ConsumerState<CrashCountdownScreen> {
  late int _secondsRemaining;
  Timer? _countdownTimer;
  bool _isAutoTriggering = false;
  late CrashDetectionService _crashDetectionService;

  @override
  void initState() {
    super.initState();
    _secondsRemaining = widget.initialSeconds;
    _crashDetectionService = ref.read(crashDetectionServiceProvider);
    _startTimer();
  }

  void _startTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
        _triggerHapticPulse();
      } else {
        _countdownTimer?.cancel();
        setState(() {
          _secondsRemaining = 0;
        });
        _autoTriggerHelp();
      }
    });
  }

  void _triggerHapticPulse() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  Future<void> _cancelCountdown() async {
    _countdownTimer?.cancel();
    // Unlock crash detection service debounce
    _crashDetectionService.setCountdownActive(false);

    if (mounted) {
      try {
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      } catch (_) {
        Navigator.of(context).maybePop();
      }
    }
  }

  Future<void> _autoTriggerHelp() async {
    if (_isAutoTriggering) return;
    _isAutoTriggering = true;

    try {
      final repo = ref.read(emergencyRepositoryProvider);
      final profile = ref.read(currentUserProfileProvider).asData?.value;
      final victimId = profile?.uid ?? 'local-victim-user';

      if (repo == null) {
        throw Exception('EmergencyRepository is not initialized');
      }

      // Create emergency with DetectionSource.possibleCrash (Rule #10)
      final emergency = await repo.createEmergency(
        victimId: victimId,
        type: EmergencyType.accident,
        detectionSource: DetectionSource.possibleCrash,
      );

      // Transition to alerting so nearby community responders receive push
      await repo.transitionStatus(emergency.id, EmergencyStatus.alerting);
      ref.invalidate(allEmergenciesProvider);

      // Release lock and route to emergency live detail
      _crashDetectionService.setCountdownActive(false);

      if (mounted) {
        try {
          context.go('/emergency/${emergency.id}');
        } catch (_) {}
      }
    } catch (e) {
      _crashDetectionService.setCountdownActive(false);
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to broadcast HELP: $e')),
          );
          context.go('/');
        } catch (_) {}
      }
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _crashDetectionService.setCountdownActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A), // High-contrast dark warning background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Warning Header
              Column(
                children: [
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: VindaraTheme.emergencyRed.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      color: VindaraTheme.emergencyRed,
                      size: 54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '⚠️ Possible Crash Detected',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Are you safe? Sending a HELP alert automatically in 10s...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              // Center Circular Countdown Dial
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: _secondsRemaining / widget.initialSeconds,
                      strokeWidth: 10,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        VindaraTheme.emergencyRed,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$_secondsRemaining',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 64,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Text(
                        'SECONDS',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Action Buttons
              Column(
                children: [
                  // Massive "I'M SAFE — CANCEL" button
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: _cancelCountdown,
                      child: const Text(
                        "I'M SAFE — CANCEL",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Secondary Immediate Send HELP Now
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                        side: BorderSide(color: Colors.red.shade400, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () {
                        _countdownTimer?.cancel();
                        _autoTriggerHelp();
                      },
                      child: const Text(
                        'SEND HELP NOW',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

