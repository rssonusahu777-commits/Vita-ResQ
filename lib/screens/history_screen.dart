import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import 'incident_detail_screen.dart';

/// Clean, Modern Emergency History Screen
class HistoryScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const HistoryScreen({
    super.key,
    required this.repository,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  int _selectedSegment = 0; // 0: Help Asked, 1: Victims Helped

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Emergency History',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: Column(
        children: [
          // Segmented Pill Toggle at Top
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildSegmentButton('Help Asked', 0),
                  _buildSegmentButton('Victims Helped', 1),
                ],
              ),
            ),
          ),

          // Stream / Feed of Incidents
          Expanded(
            child: StreamBuilder<List<Emergency>>(
              stream: widget.repository.watchActiveEmergencies(),
              builder: (context, snapshot) {
                final allEmergencies = snapshot.data ?? [];

                // Filter based on segment
                final displayed = _selectedSegment == 0
                    ? allEmergencies
                    : allEmergencies.where((e) => e.primaryResponder != null).toList();

                if (displayed.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.history_rounded, size: 48, color: AppColors.textTertiary),
                        SizedBox(height: 12),
                        Text(
                          'No emergency records yet',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Your emergency requests and responses will appear here.',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  itemCount: displayed.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = displayed[index];
                    return _buildHistoryCard(context, item);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentButton(String label, int index) {
    final isSelected = _selectedSegment == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedSegment = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryCard(BuildContext context, Emergency item) {
    final statusData = _getStatusBadge(item.status);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Date & Time + Status Pill
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDate(item.createdAt),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: statusData.bgColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusData.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: statusData.textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Bold Title
          Text(
            '${item.typeDisplayName.toUpperCase()} Emergency SOS',
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),

          // Location line
          Text(
            item.locationLabel,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),

          // Gray GPS Coordinate Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  '${item.latitude.toStringAsFixed(4)}, ${item.longitude.toStringAsFixed(4)} (GPS Coordinates)',
                  style: AppTheme.tabularNumericStyle.copyWith(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Bar: Cloud/Mesh Network info + "View Details >" link
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    item.communicationMode == CommunicationMode.online
                        ? Icons.cloud_done_rounded
                        : Icons.sensors_rounded,
                    size: 14,
                    color: item.communicationMode == CommunicationMode.online
                        ? AppColors.onlineGreen
                        : AppColors.warningAmber,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    item.communicationMode == CommunicationMode.online
                        ? 'Cloud Network'
                        : 'Offline Relay Mesh',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: item.communicationMode == CommunicationMode.online
                          ? AppColors.onlineGreen
                          : AppColors.warningAmber,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => IncidentDetailScreen(
                        emergency: item,
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
                child: Row(
                  children: const [
                    Text(
                      'View Details',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryRed,
                      ),
                    ),
                    SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.primaryRed),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  ({String label, Color textColor, Color bgColor}) _getStatusBadge(EmergencyStatus status) {
    switch (status) {
      case EmergencyStatus.alerting:
      case EmergencyStatus.created:
        return (
          label: 'SEARCHING',
          textColor: AppColors.primaryRed,
          bgColor: AppColors.primaryRedLight,
        );
      case EmergencyStatus.accepted:
      case EmergencyStatus.inProgress:
        return (
          label: 'ASSIGNED',
          textColor: AppColors.officialBlue,
          bgColor: AppColors.blueLight,
        );
      case EmergencyStatus.resolved:
        return (
          label: 'RESOLVED',
          textColor: AppColors.onlineGreen,
          bgColor: AppColors.greenLight,
        );
      case EmergencyStatus.cancelled:
        return (
          label: 'CANCELLED',
          textColor: AppColors.textSecondary,
          bgColor: AppColors.surfaceMuted,
        );
    }
  }

  String _formatDate(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $ampm';
  }
}
