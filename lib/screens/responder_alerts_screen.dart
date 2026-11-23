import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import '../models/responder.dart';
import 'responder_emergency_detail_screen.dart';

/// Nearby Emergency Alerts & Responder Queue Screen
class ResponderAlertsScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const ResponderAlertsScreen({
    super.key,
    required this.repository,
  });

  @override
  State<ResponderAlertsScreen> createState() => _ResponderAlertsScreenState();
}

class _ResponderAlertsScreenState extends State<ResponderAlertsScreen> {
  bool _isAvailable = true;
  Responder? _currentResponder;

  @override
  void initState() {
    super.initState();
    _loadResponder();
  }

  Future<void> _loadResponder() async {
    final responder = await widget.repository.getCurrentUserResponder();
    if (mounted) {
      setState(() {
        _currentResponder = responder;
        _isAvailable = responder.isAvailable;
      });
    }
  }

  void _showSimulatedPushNotification(Emergency emergency) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.crisis_alert_rounded, color: AppColors.primaryRed, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'CRITICAL HELP NEAR YOU',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryRed,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primaryRedLight,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${emergency.typeDisplayName.toUpperCase()} • 86m away',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryRed,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${emergency.victimName} triggered HELP at ${emergency.locationLabel}.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Source-of-Truth Rule: Tapping view fetches the live record directly from the database rather than trusting stale notification payloads.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('DISMISS', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => ResponderEmergencyDetailScreen(
                    emergencyId: emergency.id,
                    repository: widget.repository,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.flash_on_rounded, size: 16),
            label: const Text('FETCH LIVE & RESPOND'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryRed,
              minimumSize: const Size(140, 42),
            ),
          ),
        ],
      ),
    );
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
          'Nearby Emergency Alerts',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: StreamBuilder<List<Emergency>>(
        stream: widget.repository.watchActiveEmergencies(),
        builder: (context, snapshot) {
          final emergencies = snapshot.data ?? [];
          final activeAlerts = emergencies
              .where((e) => e.status != EmergencyStatus.resolved && e.status != EmergencyStatus.cancelled)
              .toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              // 1. SIMULATE INCOMING PUSH ALERT BUTTON
              if (activeAlerts.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ElevatedButton.icon(
                    onPressed: () => _showSimulatedPushNotification(activeAlerts.first),
                    icon: const Icon(Icons.notifications_active_rounded, size: 18, color: Colors.white),
                    label: const Text(
                      'SIMULATE INCOMING PUSH ALERT',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

              // 2. RESPONDER AVAILABILITY & TRUST CARD
              _buildAvailabilityCard(),
              const SizedBox(height: 16),

              // 3. NEARBY INCIDENTS SECTION HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'ACTIVE QUEUE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primaryRedLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${activeAlerts.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Text(
                    'Raipur • 5.0 km radius',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 4. INCIDENT CARDS
              if (activeAlerts.isEmpty)
                _buildEmptyState()
              else
                ...activeAlerts.map((item) => _buildAlertCard(item)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAvailabilityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _isAvailable ? AppColors.onlineGreen : AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isAvailable ? 'Responder Status: Available' : 'Responder Status: Offline',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _isAvailable ? AppColors.greenDark : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              Switch(
                value: _isAvailable,
                activeThumbColor: AppColors.onlineGreen,
                onChanged: (val) async {
                  setState(() => _isAvailable = val);
                  await widget.repository.updateCurrentUserAvailability(val);
                },
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatPill(Icons.verified_rounded, 'Verified', AppColors.officialBlue),
              _buildStatPill(Icons.star_rounded, '${_currentResponder?.points ?? 1420} XP', AppColors.warningAmber),
              _buildStatPill(Icons.check_circle_rounded, '${_currentResponder?.completedResponses ?? 28} Assists', AppColors.onlineGreen),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
      ],
    );
  }

  Widget _buildAlertCard(Emergency item) {
    final isPrimaryClaimed = item.primaryResponder != null;
    final isOnline = item.communicationMode == CommunicationMode.online;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPrimaryClaimed ? AppColors.border : AppColors.primaryRed.withValues(alpha: 0.35),
          width: isPrimaryClaimed ? 1 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Type pill + Distance + Mode
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryRedLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.typeDisplayName.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: AppColors.primaryRed,
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(
                    isOnline ? Icons.cloud_done_rounded : Icons.sensors_rounded,
                    size: 13,
                    color: isOnline ? AppColors.onlineGreen : AppColors.warningAmber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isOnline ? 'Cloud Network' : 'Offline Mesh Relay',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isOnline ? AppColors.onlineGreen : AppColors.warningAmber,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '86m • 1 min',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Victim & Location
          Text(
            'Victim: ${item.victimName}',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.locationLabel,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),

          // Raw Coordinates Strip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Text(
                      '${item.latitude.toStringAsFixed(4)}, ${item.longitude.toStringAsFixed(4)} (GPS Coordinates)',
                      style: AppTheme.tabularNumericStyle.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: item.formattedCoordinates));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Coordinates copied.')),
                    );
                  },
                  child: const Text(
                    'COPY',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.officialBlue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Slot Indicators + View & Respond Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: isPrimaryClaimed ? AppColors.surfaceMuted : AppColors.greenLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      isPrimaryClaimed ? 'Primary: Taken' : 'Primary: Open',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: isPrimaryClaimed ? AppColors.textSecondary : AppColors.greenDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.amberLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Standby: Open',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.warningAmber,
                      ),
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => ResponderEmergencyDetailScreen(
                        emergencyId: item.id,
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPrimaryClaimed ? AppColors.officialBlue : AppColors.primaryRed,
                  minimumSize: const Size(110, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  'View & Respond',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: const [
          Icon(Icons.shield_outlined, size: 44, color: AppColors.onlineGreen),
          SizedBox(height: 12),
          Text(
            'Neighborhood is Currently Safe',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          SizedBox(height: 4),
          Text(
            'No active emergencies in your broadcast radius. Keep app active to receive mutual-aid alerts.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

