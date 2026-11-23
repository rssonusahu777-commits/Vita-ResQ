import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/emergency.dart';
import '../models/responder.dart';
import 'status_badge.dart';

/// Reusable high-contrast Emergency Card for Vindara feed
class EmergencyCard extends StatelessWidget {
  final Emergency emergency;
  final Responder currentUser;
  final VoidCallback? onAcceptPrimary;
  final VoidCallback? onAcceptStandby;
  final ValueChanged<EmergencyStatus>? onAdvanceStatus;
  final VoidCallback? onCall112;

  const EmergencyCard({
    super.key,
    required this.emergency,
    required this.currentUser,
    this.onAcceptPrimary,
    this.onAcceptStandby,
    this.onAdvanceStatus,
    this.onCall112,
  });

  Color _getAccentColor() {
    switch (emergency.status) {
      case EmergencyStatus.alerting:
      case EmergencyStatus.created:
        return AppColors.criticalDanger;
      case EmergencyStatus.accepted:
        return AppColors.safe;
      case EmergencyStatus.inProgress:
        return AppColors.info;
      case EmergencyStatus.resolved:
        return AppColors.safe;
      case EmergencyStatus.cancelled:
        return AppColors.border;
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _getAccentColor();
    final isCritical = emergency.status == EmergencyStatus.alerting;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCritical ? AppColors.criticalDanger.withValues(alpha: 0.65) : AppColors.border,
          width: isCritical ? 1.6 : 1.2,
        ),
        boxShadow: isCritical
            ? [
                BoxShadow(
                  color: AppColors.criticalDanger.withValues(alpha: 0.08),
                  blurRadius: 18,
                  spreadRadius: 2,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Accent indicator stripe
              Container(
                width: 5.5,
                color: accentColor,
              ),

              // Main Card Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Row: Emergency ID + Status Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSubtle,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  emergency.id,
                                  style: AppTheme.tabularNumericStyle.copyWith(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.access_time_rounded,
                                size: 13,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _timeAgo(emergency.createdAt),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                          StatusBadge.fromStatus(emergency.status),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Badges Row: Type + Detection Source + Communication Mode
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          StatusBadge.fromEmergencyType(emergency.type),
                          StatusBadge.fromDetectionSource(emergency.detectionSource),
                          StatusBadge.fromCommunicationMode(emergency.communicationMode),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Victim Name & Location
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceElevated,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              size: 18,
                              color: AppColors.criticalDanger,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  emergency.victimName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  emergency.locationLabel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      // GPS Coordinates Readout
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.my_location_rounded,
                              size: 14,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'GPS: ',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            Text(
                              emergency.formattedCoordinates,
                              style: AppTheme.tabularNumericStyle.copyWith(
                                color: AppColors.info,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Optional Incident Notes
                      if (emergency.notes != null && emergency.notes!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0x11EF4444),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0x33EF4444)),
                          ),
                          child: Text(
                            emergency.notes!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],

                      // Responder Assignment Section
                      if (emergency.primaryResponder != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.safe.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.safe.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 14,
                                backgroundColor: AppColors.safe,
                                child: Icon(Icons.shield_rounded, size: 16, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Primary: ${emergency.primaryResponder!.name}',
                                      style: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${emergency.primaryResponder!.formattedDistance} • ${emergency.primaryResponder!.formattedEta}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: AppColors.safe,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Interactive Actions Section
                      const SizedBox(height: 14),
                      _buildActionButtons(context),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final isAlerting = emergency.status == EmergencyStatus.alerting;
    final isAccepted = emergency.status == EmergencyStatus.accepted;
    final isInProgress = emergency.status == EmergencyStatus.inProgress;

    return Column(
      children: [
        Row(
          children: [
            // Primary response action
            if (isAlerting) ...[
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: onAcceptPrimary,
                  icon: const Icon(Icons.flash_on_rounded, size: 18),
                  label: const Text('RESPOND (PRIMARY)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.criticalDanger,
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: onAcceptStandby,
                  icon: const Icon(Icons.hourglass_empty_rounded, size: 16, color: AppColors.warning),
                  label: const Text(
                    'STANDBY',
                    style: TextStyle(color: AppColors.warning, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    side: const BorderSide(color: AppColors.warning, width: 1.2),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            ] else if (isAccepted) ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => onAdvanceStatus?.call(EmergencyStatus.inProgress),
                  icon: const Icon(Icons.directions_run_rounded, size: 18),
                  label: const Text('MARK ON-SCENE / ACTIVE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ] else if (isInProgress) ...[
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => onAdvanceStatus?.call(EmergencyStatus.resolved),
                  icon: const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('RESOLVE & SAFE'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.safe,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ] else ...[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onAdvanceStatus?.call(EmergencyStatus.alerting),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text('REOPEN ALERT'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        // Secondary Emergency Hotline button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: onCall112,
            icon: const Icon(Icons.call_rounded, size: 16, color: AppColors.info),
            label: const Text(
              'Call Official Helpline (112)',
              style: TextStyle(fontSize: 13, color: AppColors.info, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.info.withValues(alpha: 0.4)),
              backgroundColor: AppColors.info.withValues(alpha: 0.06),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
