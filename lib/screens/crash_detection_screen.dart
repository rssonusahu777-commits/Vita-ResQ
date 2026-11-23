import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import 'crash_countdown_screen.dart';

/// Dedicated Full-Page Crash & Accident Detection Screen
class CrashDetectionScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const CrashDetectionScreen({
    super.key,
    required this.repository,
  });

  @override
  State<CrashDetectionScreen> createState() => _CrashDetectionScreenState();
}

class _CrashDetectionScreenState extends State<CrashDetectionScreen> {
  bool _isSensorEnabled = true;
  final double _sensitivityG = 4.2;
  final int _graceCountdownSeconds = 20;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: const Text(
          'Crash & Impact Detection',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
        children: [
          // 1. Master Enable/Disable Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEAE8E3)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: _isSensorEnabled ? AppColors.greenLight : AppColors.surfaceMuted,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.sensors_rounded,
                            color: _isSensorEnabled ? AppColors.onlineGreen : AppColors.textSecondary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Crash Guard',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: _isSensorEnabled ? AppColors.onlineGreen : AppColors.textSecondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _isSensorEnabled ? 'Active (20Hz loop)' : 'Monitoring Paused',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _isSensorEnabled ? AppColors.greenDark : AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: _isSensorEnabled,
                      activeTrackColor: AppColors.onlineGreen,
                      activeThumbColor: Colors.white,
                      onChanged: (val) {
                        HapticFeedback.lightImpact();
                        setState(() => _isSensorEnabled = val);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Color(0xFFF1F0EC)),
                const SizedBox(height: 12),
                const Text(
                  'Continuously monitors smartphone accelerometer and gyroscope data to detect high-impact decelerations typical of motorcycle or vehicle collisions.',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Hardware Readiness & Permissions Strip
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'HARDWARE SENSORS & STATUS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEAE8E3)),
            ),
            child: Column(
              children: [
                _buildSensorRow(
                  icon: Icons.speed_rounded,
                  name: '3-Axis Accelerometer',
                  status: 'Calibrated • 20 Hz loop',
                  statusColor: AppColors.onlineGreen,
                ),
                const Divider(height: 16, color: Color(0xFFF1F0EC)),
                _buildSensorRow(
                  icon: Icons.screen_rotation_rounded,
                  name: 'Angular Gyroscope',
                  status: 'Listening for roll/pitch',
                  statusColor: AppColors.onlineGreen,
                ),
                const Divider(height: 16, color: Color(0xFFF1F0EC)),
                _buildSensorRow(
                  icon: Icons.my_location_rounded,
                  name: 'GPS Satellite Fix',
                  status: '21.1619, 81.7869 (Ready)',
                  statusColor: AppColors.officialBlue,
                ),
                const Divider(height: 16, color: Color(0xFFF1F0EC)),
                _buildSensorRow(
                  icon: Icons.notifications_active_outlined,
                  name: 'Full-Volume Audio Alarm',
                  status: '20s Pre-dispatch Siren ready',
                  statusColor: AppColors.onlineGreen,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Rule-Based Evaluation Logic & Honest Disclaimer
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ACCIDENT EVALUATION RULES',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEAE8E3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.shield_outlined, size: 18, color: Color(0xFF6B7280)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Honest Protocol Rule: Vindara uses mathematical rule-based sensor evaluation on commercial phone hardware. It does not replace automotive OEM telematics, vehicle air-bag ECUs, or certified medical sensors.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF4B5563), height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildRuleItem(
                  title: 'Sudden Deceleration Trigger',
                  value: '> $_sensitivityG G-force peak',
                  subtitle: 'Evaluates abrupt negative acceleration exceeding normal road bumps.',
                ),
                const Divider(height: 20, color: Color(0xFFF1F0EC)),
                _buildRuleItem(
                  title: 'False Alarm Grace Window',
                  value: '$_graceCountdownSeconds Seconds',
                  subtitle: 'Plays audible beep warning allowing the driver or rider to tap "I am Safe".',
                ),
                const Divider(height: 20, color: Color(0xFFF1F0EC)),
                _buildRuleItem(
                  title: 'Automated Failover Broadcast',
                  value: 'Cloud + Offline Mesh',
                  subtitle: 'If countdown expires without cancellation, broadcasts SOS with raw GPS coordinates.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Prominent Accident Detection Demo Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                HapticFeedback.mediumImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => CrashCountdownScreen(
                      repository: widget.repository,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.car_crash_rounded, size: 20),
              label: const Text(
                'Run Accident Detection Demo (20s Countdown)',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryRed,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSensorRow({
    required IconData icon,
    required String name,
    required String status,
    required Color statusColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF4B5563)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        Text(
          status,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: statusColor,
          ),
        ),
      ],
    );
  }

  Widget _buildRuleItem({
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
        ),
      ],
    );
  }
}
