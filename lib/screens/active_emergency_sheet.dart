import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import '../widgets/status_badge.dart';
import 'active_emergency_screen.dart';

/// Modal bottom sheet displaying active broadcast state, responders matched, and cancellation controls
class ActiveEmergencySheet extends StatefulWidget {
  final Emergency emergency;
  final EmergencyRepository repository;
  final VoidCallback? onDismiss;

  const ActiveEmergencySheet({
    super.key,
    required this.emergency,
    required this.repository,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    required Emergency emergency,
    required EmergencyRepository repository,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ActiveEmergencySheet(
        emergency: emergency,
        repository: repository,
      ),
    );
  }

  @override
  State<ActiveEmergencySheet> createState() => _ActiveEmergencySheetState();
}

class _ActiveEmergencySheetState extends State<ActiveEmergencySheet> {
  late Emergency _currentEmergency;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _currentEmergency = widget.emergency;
  }

  Future<void> _handleCancelAlert() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Cancel Active Emergency?'),
        content: const Text(
          'Are you safe? Cancelling will notify all responding community members and official services that this was a false alarm.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('STAY ACTIVE', style: TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.criticalDanger),
            child: const Text('YES, CANCEL ALERT'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isCancelling = true;
    });

    await widget.repository.cancelEmergency(_currentEmergency.id, reason: 'User marked false alarm.');

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency alert cancelled. Responders stand down.'),
        backgroundColor: AppColors.safe,
      ),
    );
  }

  void _openFullScreenView(Emergency emergency) {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ActiveEmergencyScreen(
          initialEmergency: emergency,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Emergency?>(
      stream: widget.repository.watchEmergency(_currentEmergency.id),
      initialData: _currentEmergency,
      builder: (context, snapshot) {
        final emergency = snapshot.data ?? _currentEmergency;

        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(color: AppColors.criticalDanger, width: 2),
            ),
          ),
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderHighlight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header Row: Broadcast Beacon + ID
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.criticalDanger.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.radar_rounded,
                          color: AppColors.criticalDanger,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'SOS BROADCAST ACTIVE',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: AppColors.criticalDanger,
                            ),
                          ),
                          Text(
                            emergency.id,
                            style: AppTheme.tabularNumericStyle.copyWith(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  StatusBadge.fromStatus(emergency.status),
                ],
              ),
              const SizedBox(height: 16),

              // Tags
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusBadge.fromEmergencyType(emergency.type),
                  StatusBadge.fromDetectionSource(emergency.detectionSource),
                  StatusBadge.fromCommunicationMode(emergency.communicationMode),
                ],
              ),
              const SizedBox(height: 16),

              // GPS Location Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: AppColors.criticalDanger),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            emergency.locationLabel,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text(
                          'COORDINATES: ',
                          style: TextStyle(
                            fontSize: 10.5,
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
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Responders Status Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: emergency.primaryResponder != null
                      ? AppColors.safe.withValues(alpha: 0.1)
                      : AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: emergency.primaryResponder != null
                        ? AppColors.safe.withValues(alpha: 0.3)
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: emergency.primaryResponder != null
                          ? AppColors.safe
                          : AppColors.warning.withValues(alpha: 0.2),
                      child: Icon(
                        emergency.primaryResponder != null
                            ? Icons.check_circle_rounded
                            : Icons.search_rounded,
                        size: 20,
                        color: emergency.primaryResponder != null ? Colors.white : AppColors.warning,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            emergency.primaryResponder != null
                                ? 'Primary: ${emergency.primaryResponder!.name}'
                                : 'Alerting Community Responders...',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            emergency.primaryResponder != null
                                ? '${emergency.primaryResponder!.formattedDistance} • ${emergency.primaryResponder!.formattedEta}'
                                : '4 community first responders in your 2.5km vicinity',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: emergency.primaryResponder != null
                                  ? AppColors.safe
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Expand to Full Screen Active Emergency View Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () => _openFullScreenView(emergency),
                  icon: const Icon(Icons.open_in_full_rounded, size: 18, color: AppColors.info),
                  label: const Text(
                    'OPEN FULL ACTIVE EMERGENCY VIEW',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: AppColors.info,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.info.withValues(alpha: 0.5)),
                    backgroundColor: AppColors.info.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Action Buttons: Cancel and Dial 112
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isCancelling ? null : _handleCancelAlert,
                      icon: const Icon(Icons.cancel_outlined, size: 18, color: AppColors.criticalDanger),
                      label: const Text(
                        'CANCEL ALERT',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.criticalDanger,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.criticalDanger),
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Simulated connecting to 112 PSAP Dispatcher.'),
                            backgroundColor: AppColors.info,
                          ),
                        );
                      },
                      icon: const Icon(Icons.call_rounded, size: 18),
                      label: const Text(
                        'DIAL 112',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.info,
                        minimumSize: const Size(0, 48),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
