import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';

/// Full-screen high-contrast Possible Crash Countdown Warning Screen
class CrashCountdownScreen extends StatefulWidget {
  final EmergencyRepository repository;
  final CommunicationMode communicationMode;

  const CrashCountdownScreen({
    super.key,
    required this.repository,
    this.communicationMode = CommunicationMode.online,
  });

  @override
  State<CrashCountdownScreen> createState() => _CrashCountdownScreenState();
}

class _CrashCountdownScreenState extends State<CrashCountdownScreen>
    with SingleTickerProviderStateMixin {
  static const int _initialCountdown = 10;
  int _secondsRemaining = _initialCountdown;
  Timer? _countdownTimer;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  bool _isDispatched = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsRemaining > 1) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        _dispatchCrashEmergency();
      }
    });
  }

  Future<void> _dispatchCrashEmergency() async {
    if (_isDispatched) return;
    setState(() {
      _secondsRemaining = 0;
      _isDispatched = true;
    });

    final emergency = await widget.repository.createEmergency(
      victimName: 'CurrentUser (Vehicular Impact)',
      latitude: 12.9298,
      longitude: 77.6834,
      locationLabel: 'Outer Ring Road, Bellandur Flyover, Bengaluru',
      type: EmergencyType.roadAccident,
      detectionSource: DetectionSource.possibleCrash,
      communicationMode: widget.communicationMode,
      notes:
          'Automated crash trigger: High-G deceleration spike (4.8G) followed by 10s inactivity. Unresponsive countdown dispatch.',
    );

    if (!mounted) return;
    Navigator.of(context).pop(emergency);
  }

  void _cancelAlert() {
    _countdownTimer?.cancel();
    Navigator.of(context).pop(null);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _secondsRemaining / _initialCountdown;
    final isCriticalPhase = _secondsRemaining <= 4;
    final themeColor = isCriticalPhase ? AppColors.criticalDanger : AppColors.warning;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _cancelAlert();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // Header Warning Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.15),
                  border: Border(
                    bottom: BorderSide(color: themeColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: themeColor),
                      onPressed: _cancelAlert,
                    ),
                    Icon(Icons.warning_amber_rounded, color: themeColor, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AUTOMATED MOTION SAFETY MONITOR',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: themeColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Car Crash Impact Badge
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: themeColor.withValues(alpha: 0.4), width: 2),
                        ),
                        child: Icon(
                          Icons.car_crash_rounded,
                          size: 48,
                          color: themeColor,
                        ),
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'Possible Crash Detected',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 10),

                      Text(
                        'Sudden high-impact pattern detected. Are you safe? A critical HELP broadcast will dispatch if uncancelled.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 36),

                      // Countdown Circle with tab figures
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 170,
                              height: 170,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 10,
                                backgroundColor: AppColors.surfaceElevated,
                                valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '$_secondsRemaining',
                                  style: AppTheme.tabularNumericStyle.copyWith(
                                    fontSize: 72,
                                    fontWeight: FontWeight.w900,
                                    color: themeColor,
                                    height: 1.0,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'SECONDS',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Coordinates preview
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.my_location_rounded, size: 14, color: AppColors.textTertiary),
                            const SizedBox(width: 8),
                            Text(
                              'Auto-transmitting: 12.92980° N, 77.68340° E',
                              style: AppTheme.tabularNumericStyle.copyWith(
                                fontSize: 11.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bottom Cancel Action Button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton.icon(
                        onPressed: _cancelAlert,
                        icon: const Icon(Icons.check_circle_rounded, size: 24),
                        label: const Text(
                          "I'M SAFE — CANCEL ALERT",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.safe,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Tapping cancel disarms the alert and keeps your record safe.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

