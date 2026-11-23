import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../models/emergency.dart';

/// Semantic pill/badge for displaying status, detection source, and communication modes
class StatusBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
  final bool isPulsing;

  const StatusBadge({
    super.key,
    required this.label,
    this.icon,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
    this.isPulsing = false,
  });

  /// Factory for EmergencyStatus
  factory StatusBadge.fromStatus(EmergencyStatus status) {
    switch (status) {
      case EmergencyStatus.alerting:
      case EmergencyStatus.created:
        return StatusBadge(
          label: 'CRITICAL ALERT',
          icon: Icons.campaign_rounded,
          foregroundColor: AppColors.criticalDanger,
          backgroundColor: AppColors.criticalDanger.withValues(alpha: 0.12),
          borderColor: AppColors.criticalDanger.withValues(alpha: 0.4),
          isPulsing: true,
        );
      case EmergencyStatus.accepted:
        return StatusBadge(
          label: 'RESPONDER ASSIGNED',
          icon: Icons.check_circle_outline_rounded,
          foregroundColor: AppColors.safe,
          backgroundColor: AppColors.safe.withValues(alpha: 0.12),
          borderColor: AppColors.safe.withValues(alpha: 0.4),
        );
      case EmergencyStatus.inProgress:
        return StatusBadge(
          label: 'ON SCENE / ACTIVE',
          icon: Icons.directions_run_rounded,
          foregroundColor: AppColors.info,
          backgroundColor: AppColors.info.withValues(alpha: 0.12),
          borderColor: AppColors.info.withValues(alpha: 0.4),
        );
      case EmergencyStatus.resolved:
        return StatusBadge(
          label: 'RESOLVED & SAFE',
          icon: Icons.verified_rounded,
          foregroundColor: AppColors.safe,
          backgroundColor: AppColors.safe.withValues(alpha: 0.12),
          borderColor: AppColors.safe.withValues(alpha: 0.4),
        );
      case EmergencyStatus.cancelled:
        return StatusBadge(
          label: 'CANCELLED',
          icon: Icons.cancel_outlined,
          foregroundColor: AppColors.textTertiary,
          backgroundColor: AppColors.surfaceSubtle,
          borderColor: AppColors.border,
        );
    }
  }

  /// Factory for DetectionSource
  factory StatusBadge.fromDetectionSource(DetectionSource source) {
    switch (source) {
      case DetectionSource.possibleCrash:
        return StatusBadge(
          label: 'CRASH DETECTED',
          icon: Icons.car_crash_rounded,
          foregroundColor: AppColors.warning,
          backgroundColor: AppColors.warning.withValues(alpha: 0.12),
          borderColor: AppColors.warning.withValues(alpha: 0.4),
        );
      case DetectionSource.manualSos:
      case DetectionSource.manualHelp:
        return StatusBadge(
          label: 'MANUAL SOS',
          icon: Icons.touch_app_rounded,
          foregroundColor: AppColors.criticalDanger,
          backgroundColor: AppColors.criticalDanger.withValues(alpha: 0.12),
          borderColor: AppColors.criticalDanger.withValues(alpha: 0.4),
        );
    }
  }

  /// Factory for CommunicationMode
  factory StatusBadge.fromCommunicationMode(CommunicationMode mode) {
    switch (mode) {
      case CommunicationMode.online:
        return StatusBadge(
          label: 'ONLINE CLOUD',
          icon: Icons.cloud_done_rounded,
          foregroundColor: AppColors.safe,
          backgroundColor: AppColors.safe.withValues(alpha: 0.1),
          borderColor: AppColors.safe.withValues(alpha: 0.3),
        );
      case CommunicationMode.offlineNearby:
      case CommunicationMode.offline:
        return StatusBadge(
          label: 'OFFLINE MESH (P2P)',
          icon: Icons.nearby_error_rounded,
          foregroundColor: AppColors.warning,
          backgroundColor: AppColors.warning.withValues(alpha: 0.12),
          borderColor: AppColors.warning.withValues(alpha: 0.4),
        );
    }
  }

  /// Factory for EmergencyType
  factory StatusBadge.fromEmergencyType(EmergencyType type) {
    switch (type) {
      case EmergencyType.roadAccident:
      case EmergencyType.accident:
        return const StatusBadge(
          label: 'ROAD CRASH',
          icon: Icons.car_crash_rounded,
          foregroundColor: AppColors.warning,
          backgroundColor: Color(0x22F59E0B),
          borderColor: Color(0x55F59E0B),
        );
      case EmergencyType.medical:
        return const StatusBadge(
          label: 'MEDICAL',
          icon: Icons.medical_services_rounded,
          foregroundColor: AppColors.criticalDanger,
          backgroundColor: Color(0x22EF4444),
          borderColor: Color(0x55EF4444),
        );
      case EmergencyType.fire:
        return const StatusBadge(
          label: 'FIRE',
          icon: Icons.local_fire_department_rounded,
          foregroundColor: AppColors.criticalDanger,
          backgroundColor: Color(0x22EF4444),
          borderColor: Color(0x55EF4444),
        );
      case EmergencyType.personalSafety:
      case EmergencyType.safety:
        return const StatusBadge(
          label: 'SAFETY THREAT',
          icon: Icons.shield_rounded,
          foregroundColor: AppColors.info,
          backgroundColor: Color(0x223B82F6),
          borderColor: Color(0x553B82F6),
        );
      case EmergencyType.general:
      case EmergencyType.other:
        return const StatusBadge(
          label: 'HAZARD',
          icon: Icons.warning_amber_rounded,
          foregroundColor: AppColors.textSecondary,
          backgroundColor: Color(0x2294A3B8),
          borderColor: AppColors.border,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4.5),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foregroundColor),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: foregroundColor,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}
