import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import 'active_emergency_screen.dart';

/// Dedicated Full-Page Incident History Detail Screen
class IncidentDetailScreen extends StatelessWidget {
  final Emergency emergency;
  final EmergencyRepository repository;

  const IncidentDetailScreen({
    super.key,
    required this.emergency,
    required this.repository,
  });

  String _getStatusLabel(EmergencyStatus status) {
    switch (status) {
      case EmergencyStatus.created:
        return 'REGISTERED';
      case EmergencyStatus.alerting:
        return 'BROADCASTING';
      case EmergencyStatus.accepted:
        return 'RESPONDER ASSIGNED';
      case EmergencyStatus.inProgress:
        return 'ON SCENE';
      case EmergencyStatus.resolved:
        return 'RESOLVED & SAFE';
      case EmergencyStatus.cancelled:
        return 'FALSE ALARM / CANCELLED';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = emergency.communicationMode == CommunicationMode.online;
    final isLive = emergency.status != EmergencyStatus.resolved && emergency.status != EmergencyStatus.cancelled;

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
        title: Text(
          'Incident #${emergency.id.substring(emergency.id.length - 6)}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
        children: [
          // 1. Top Incident Summary Card
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryRedLight,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        emergency.typeDisplayName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: AppColors.primaryRed,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: emergency.status == EmergencyStatus.resolved
                            ? AppColors.greenLight
                            : (emergency.status == EmergencyStatus.cancelled ? AppColors.surfaceMuted : AppColors.blueLight),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _getStatusLabel(emergency.status),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: emergency.status == EmergencyStatus.resolved
                              ? AppColors.greenDark
                              : (emergency.status == EmergencyStatus.cancelled ? AppColors.textSecondary : AppColors.officialBlue),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  emergency.victimName,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  emergency.locationLabel,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.3),
                ),
                const SizedBox(height: 12),
                // Raw GPS Strip with Copy Action
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.my_location_rounded, size: 15, color: AppColors.officialBlue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${emergency.latitude.toStringAsFixed(4)}, ${emergency.longitude.toStringAsFixed(4)} (Raw Hardware Satellite Fix)',
                          style: AppTheme.tabularNumericStyle.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: '${emergency.latitude}, ${emergency.longitude}'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Coordinates copied to clipboard')),
                          );
                        },
                        child: const Icon(Icons.copy_rounded, size: 15, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      isOnline ? Icons.cloud_done_rounded : Icons.sensors_rounded,
                      size: 16,
                      color: isOnline ? AppColors.onlineGreen : AppColors.warningAmber,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'Dispatched via Cloud Network (112 ERSS Logged)' : 'Dispatched via Offline Peer-to-Peer Relay',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isOnline ? AppColors.greenDark : AppColors.warningAmber,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 2. Full Incident Audit Timeline
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'AUDIT TIMELINE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFEAE8E3)),
            ),
            child: Column(
              children: [
                _buildTimelineItem(
                  time: '00:00',
                  title: 'HELP Alert Triggered',
                  subtitle: emergency.detectionSource == DetectionSource.possibleCrash
                      ? 'Automated pattern-based crash trigger (grace expired).'
                      : 'Manual Hold-to-HELP triggered by victim.',
                  isDone: true,
                  isLast: false,
                ),
                _buildTimelineItem(
                  time: '00:06',
                  title: 'Geo-Radius Broadcast',
                  subtitle: 'Coordinates pushed to nearby citizen volunteers within 1000m.',
                  isDone: true,
                  isLast: false,
                ),
                _buildTimelineItem(
                  time: '00:22',
                  title: emergency.primaryResponder != null
                      ? 'Primary Responder Committed'
                      : 'Awaiting Primary Responder Slot',
                  subtitle: emergency.primaryResponder != null
                      ? '${emergency.primaryResponder!.name} (${emergency.primaryResponder!.badgeLevel}) locked primary on-scene slot.'
                      : 'Community mesh broadcast active; standby slot open.',
                  isDone: emergency.primaryResponder != null,
                  isLast: false,
                ),
                _buildTimelineItem(
                  time: '01:45',
                  title: 'Scene Arrival & Triage',
                  subtitle: 'Standby backup notified. Emergency contacts updated via automated SMS.',
                  isDone: emergency.status == EmergencyStatus.inProgress || emergency.status == EmergencyStatus.resolved,
                  isLast: false,
                ),
                _buildTimelineItem(
                  time: '04:10',
                  title: emergency.status == EmergencyStatus.resolved
                      ? 'Incident Resolved & Handed to Official Services'
                      : (emergency.status == EmergencyStatus.cancelled ? 'Incident Cancelled / Dismissed' : 'On Scene Active'),
                  subtitle: emergency.status == EmergencyStatus.resolved
                      ? 'Victim handed over to 108 Emergency Ambulance. All volunteers released.'
                      : 'Incident lifecycle in progress.',
                  isDone: emergency.status == EmergencyStatus.resolved || emergency.status == EmergencyStatus.cancelled,
                  isLast: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 3. Responders Allocated
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'ASSIGNED RESPONDERS',
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
                _buildResponderSlotRow(
                  role: 'PRIMARY RESPONDER',
                  responder: emergency.primaryResponder,
                  roleColor: AppColors.primaryRed,
                ),
                const Divider(height: 18, color: Color(0xFFF1F0EC)),
                _buildResponderSlotRow(
                  role: 'STANDBY BACKUP',
                  responder: emergency.standbyResponder,
                  roleColor: AppColors.officialBlue,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 4. Live Action or Export Button
          if (isLive)
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => ActiveEmergencyScreen(
                        initialEmergency: emergency,
                        repository: repository,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.bolt_rounded, size: 20),
                label: const Text('Open Active Live View', style: TextStyle(fontWeight: FontWeight.w800)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryRed,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Audit report exported to device storage.')),
                  );
                },
                icon: const Icon(Icons.receipt_long_rounded, size: 18),
                label: const Text('Export Incident Audit Log', style: TextStyle(fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required String time,
    required String title,
    required String subtitle,
    required bool isDone,
    required bool isLast,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isDone ? AppColors.onlineGreen : const Color(0xFFE5E7EB),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 46,
                color: isDone ? AppColors.greenLight : const Color(0xFFE5E7EB),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isDone ? AppColors.textPrimary : const Color(0xFF9CA3AF),
                      ),
                    ),
                    Text(
                      time,
                      style: AppTheme.tabularNumericStyle.copyWith(
                        fontSize: 11,
                        color: const Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.3),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponderSlotRow({
    required String role,
    required dynamic responder,
    required Color roleColor,
  }) {
    final hasResponder = responder != null;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: hasResponder ? roleColor : const Color(0xFF9CA3AF),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: roleColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                hasResponder ? responder.name : 'Slot Open (Available for response)',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: hasResponder ? AppColors.textPrimary : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
        if (hasResponder)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              responder.badgeLevel,
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
            ),
          ),
      ],
    );
  }
}
