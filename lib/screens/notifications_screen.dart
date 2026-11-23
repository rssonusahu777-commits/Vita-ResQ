import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import 'active_emergency_screen.dart';
import 'responder_emergency_detail_screen.dart';

/// Categories of Notifications in Vindara
enum NotificationCategory {
  incomingRequest,
  assignmentUpdate,
  progressUpdate,
  systemNotice,
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final NotificationCategory category;
  final String? relatedEmergencyId;
  final bool isUnread;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.category,
    this.relatedEmergencyId,
    this.isUnread = true,
  });
}

/// Clean Notifications Screen
class NotificationsScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const NotificationsScreen({
    super.key,
    required this.repository,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late List<AppNotification> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = [
      AppNotification(
        id: 'NOTIF-01',
        title: 'Incoming Emergency Alert Nearby',
        body: 'Medical SOS registered 86m from your location at Sector 4, Community Axis, Raipur.',
        timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
        category: NotificationCategory.incomingRequest,
        relatedEmergencyId: 'EMG-2026-781920',
        isUnread: true,
      ),
      AppNotification(
        id: 'NOTIF-02',
        title: 'Primary Responder Assigned',
        body: 'Dr. Rajesh Sharma accepted as Primary Responder for incident EMG-2026-849201.',
        timestamp: DateTime.now().subtract(const Duration(minutes: 8)),
        category: NotificationCategory.assignmentUpdate,
        relatedEmergencyId: 'EMG-2026-849201',
        isUnread: true,
      ),
      AppNotification(
        id: 'NOTIF-03',
        title: 'Assistance Arrived On-Scene',
        body: 'Volunteer responder marked arrival for Indiranagar medical assistance.',
        timestamp: DateTime.now().subtract(const Duration(hours: 1, minutes: 12)),
        category: NotificationCategory.progressUpdate,
        relatedEmergencyId: 'EMG-2026-849201',
        isUnread: false,
      ),
      AppNotification(
        id: 'NOTIF-04',
        title: 'Offline Mesh Relay Node Active',
        body: 'Bluetooth Low Energy background packet listening active for zero-connectivity neighborhood safety.',
        timestamp: DateTime.now().subtract(const Duration(hours: 3)),
        category: NotificationCategory.systemNotice,
        isUnread: false,
      ),
    ];
  }

  void _handleNotificationTap(AppNotification notif) async {
    if (notif.relatedEmergencyId != null) {
      final emergency = await widget.repository.getEmergencyById(notif.relatedEmergencyId!);
      if (!mounted) return;

      if (emergency != null) {
        if (notif.category == NotificationCategory.incomingRequest) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => ResponderEmergencyDetailScreen(
                emergencyId: emergency.id,
                repository: widget.repository,
              ),
            ),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (ctx) => ActiveEmergencyScreen(
                initialEmergency: emergency,
                repository: widget.repository,
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency record resolved or dismissed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          // Source-of-Truth Info Banner
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.blueLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.officialBlue.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.info_outline_rounded, size: 18, color: AppColors.officialBlue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Opening an alert loads the live emergency status directly from the database rather than trusting stale notification payloads.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.officialBlue,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Notifications List
          ..._notifications.map((item) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: item.isUnread ? AppColors.primaryRed.withValues(alpha: 0.3) : AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: ListTile(
                onTap: () => _handleNotificationTap(item),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                leading: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _getCategoryColor(item.category).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getCategoryIcon(item.category),
                    size: 20,
                    color: _getCategoryColor(item.category),
                  ),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (item.isUnread) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.primaryRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatRelativeTime(item.timestamp),
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(NotificationCategory cat) {
    switch (cat) {
      case NotificationCategory.incomingRequest:
        return Icons.crisis_alert_rounded;
      case NotificationCategory.assignmentUpdate:
        return Icons.handshake_rounded;
      case NotificationCategory.progressUpdate:
        return Icons.directions_run_rounded;
      case NotificationCategory.systemNotice:
        return Icons.sensors_rounded;
    }
  }

  Color _getCategoryColor(NotificationCategory cat) {
    switch (cat) {
      case NotificationCategory.incomingRequest:
        return AppColors.primaryRed;
      case NotificationCategory.assignmentUpdate:
        return AppColors.officialBlue;
      case NotificationCategory.progressUpdate:
        return AppColors.onlineGreen;
      case NotificationCategory.systemNotice:
        return AppColors.warningAmber;
    }
  }

  String _formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

