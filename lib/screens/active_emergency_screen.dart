import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import '../services/location_service.dart';

/// Clean, Light Theme Live Assistance & Active Emergency Screen
class ActiveEmergencyScreen extends StatefulWidget {
  final Emergency initialEmergency;
  final EmergencyRepository repository;

  const ActiveEmergencyScreen({
    super.key,
    required this.initialEmergency,
    required this.repository,
  });

  @override
  State<ActiveEmergencyScreen> createState() => _ActiveEmergencyScreenState();
}

class _ActiveEmergencyScreenState extends State<ActiveEmergencyScreen> {
  bool _isDemoExpanded = false;
  bool _isHospitalDirectoryAvailable = true;
  bool _isAcquiringGps = false;

  void _checkAndAcquireGpsIfNeeded(Emergency emergency) {
    if (emergency.latitude == 0.0 && emergency.longitude == 0.0 && !_isAcquiringGps) {
      _isAcquiringGps = true;
      LocationService.acquireBestAvailableFix().then((fix) {
        if (mounted && fix != null && (fix.latitude != 0.0 || fix.longitude != 0.0)) {
          final updated = emergency.copyWith(
            latitude: fix.latitude,
            longitude: fix.longitude,
            locationLabel:
                '${fix.latitude.toStringAsFixed(4)}, ${fix.longitude.toStringAsFixed(4)} (Acquired Fix)',
          );
          widget.repository.updateEmergency(updated);
        }
      }).catchError((e) {
        debugPrint('ActiveEmergencyScreen GPS acquire error: $e');
      }).whenComplete(() {
        _isAcquiringGps = false;
      });
    }
  }

  void _copyCoordinates(Emergency emergency) {
    Clipboard.setData(ClipboardData(text: emergency.formattedCoordinates));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('GPS Coordinates copied: ${emergency.formattedCoordinates}'),
        backgroundColor: AppColors.officialBlue,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleCancelEmergency(Emergency emergency) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Cancel Emergency Request?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Are you safe? Cancelling will stand down all community first responders and notify official dispatch.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('KEEP ACTIVE', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryRed),
            child: const Text('YES, CANCEL'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await widget.repository.cancelEmergency(emergency.id, reason: 'Victim confirmed safe / false alarm.');
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency request cancelled.'),
          backgroundColor: AppColors.onlineGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Emergency?>(
      stream: widget.repository.watchEmergency(widget.initialEmergency.id),
      initialData: widget.initialEmergency,
      builder: (context, snapshot) {
        final emergency = snapshot.data ?? widget.initialEmergency;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text(
              'Live Assistance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 20, color: AppColors.officialBlue),
                tooltip: 'Copy GPS',
                onPressed: () => _copyCoordinates(emergency),
              ),
            ],
          ),
          body: Column(
            children: [
              // 1. TOP MAP SPLIT VIEW WITH PINS
              _buildTopMapSplitView(emergency),

              // 2. SCROLLABLE BOTTOM CONTENT SHEET
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    // Status Pill + Subtitle
                    _buildStatusPill(emergency),
                    const SizedBox(height: 14),

                    // Emergency Type Card
                    _buildEmergencyTypeCard(emergency),
                    const SizedBox(height: 16),

                    // 4-Step Horizontal Progress Tracker
                    _buildProgressTracker(emergency),
                    const SizedBox(height: 16),

                    // Primary & Standby Responder Card
                    _buildResponderCard(emergency),
                    const SizedBox(height: 16),

                    // Trusted Contacts Fallback Card
                    _buildTrustedContactsCard(),
                    const SizedBox(height: 16),

                    // Nearby Hospitals (Standby) Card
                    _buildNearbyHospitalsCard(),
                    const SizedBox(height: 16),

                    // Demo State Switcher Strip
                    _buildDemoStateStrip(emergency),
                    const SizedBox(height: 20),

                    // Bottom Cancel Emergency Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () => _handleCancelEmergency(emergency),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.primaryRed, width: 1.4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          'Cancel Emergency',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primaryRed,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Top Map Split View
  Widget _buildTopMapSplitView(Emergency emergency) {
    _checkAndAcquireGpsIfNeeded(emergency);
    final hasPrimary = emergency.primaryResponder != null;
    final isGpsZero = emergency.latitude == 0.0 && emergency.longitude == 0.0;

    return Container(
      height: 190,
      width: double.infinity,
      color: const Color(0xFFF1F3F5),
      child: Stack(
        children: [
          // Background Streets
          CustomPaint(
            size: Size.infinite,
            painter: _ActiveMapPainter(),
          ),

          // Victim Pin (YOU)
          Positioned(
            left: 80,
            top: 75,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'YOU',
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(color: AppColors.primaryRed.withValues(alpha: 0.3), blurRadius: 6),
                    ],
                  ),
                  child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),

          // Primary Responder Pin
          if (hasPrimary)
            Positioned(
              right: 90,
              top: 55,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.onlineGreen,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'PRIMARY',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.onlineGreen,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(color: AppColors.onlineGreen.withValues(alpha: 0.3), blurRadius: 6),
                      ],
                    ),
                    child: const Icon(Icons.directions_run_rounded, color: Colors.white, size: 16),
                  ),
                ],
              ),
            ),

          // Bottom Bar: Offline-Safe Raw GPS Coordinates Strip
          Positioned(
            bottom: 8,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isGpsZero ? Icons.gps_not_fixed_rounded : Icons.gps_fixed_rounded,
                        size: 13,
                        color: isGpsZero ? AppColors.warningAmber : AppColors.officialBlue,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isGpsZero
                            ? 'Acquiring Satellite GPS Fix...'
                            : '${emergency.latitude.toStringAsFixed(4)}, ${emergency.longitude.toStringAsFixed(4)} (GPS Coordinates)',
                        style: AppTheme.tabularNumericStyle.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isGpsZero ? AppColors.warningAmber : AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    emergency.communicationMode == CommunicationMode.online
                        ? 'Online (Cloud Dispatch)'
                        : 'Offline (Peer Mesh Relay)',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: emergency.communicationMode == CommunicationMode.online
                          ? AppColors.onlineGreen
                          : AppColors.warningAmber,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Status Pill + Subtitle
  Widget _buildStatusPill(Emergency emergency) {
    final hasPrimary = emergency.primaryResponder != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
              decoration: BoxDecoration(
                color: hasPrimary ? AppColors.greenLight : AppColors.primaryRedLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                hasPrimary ? 'PRIMARY RESPONDER ASSIGNED' : 'SEARCHING FOR HELP',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                  color: hasPrimary ? AppColors.greenDark : AppColors.primaryRed,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Your request is active.',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  // Emergency Type Card
  Widget _buildEmergencyTypeCard(Emergency emergency) {
    final isOnline = emergency.communicationMode == CommunicationMode.online;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryRedLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.medical_services_rounded, color: AppColors.primaryRed, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${emergency.typeDisplayName} Emergency',
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Your location is being shared with nearby community responders.',
                      style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {},
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                child: const Text('Change', style: TextStyle(color: AppColors.primaryRed, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: isOnline ? AppColors.onlineGreen : AppColors.warningAmber,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isOnline
                      ? 'Connected to live mutual-aid dispatch network'
                      : 'Offline — Nearby Peer Relay active (P2P mesh)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: isOnline ? AppColors.greenDark : AppColors.warningAmber,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 4-Step Horizontal Progress Tracker
  Widget _buildProgressTracker(Emergency emergency) {
    const steps = ['Created', 'Dispatch Attempted', 'Responder Accepted', 'Arrived'];
    int activeIndex = 0;
    if (emergency.status == EmergencyStatus.alerting) activeIndex = 1;
    if (emergency.status == EmergencyStatus.accepted || emergency.status == EmergencyStatus.inProgress) activeIndex = 2;
    if (emergency.status == EmergencyStatus.resolved) activeIndex = 3;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isPastOrCurrent = index <= activeIndex;
          final isCurrent = index == activeIndex;

          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCurrent
                              ? AppColors.blueLight
                              : (isPastOrCurrent ? AppColors.officialBlue : AppColors.surfaceMuted),
                          border: Border.all(
                            color: isCurrent ? AppColors.officialBlue : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            isPastOrCurrent ? Icons.check : Icons.circle,
                            size: 14,
                            color: isPastOrCurrent
                                ? (isCurrent ? AppColors.officialBlue : Colors.white)
                                : AppColors.textTertiary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        steps[index],
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                          color: isCurrent ? AppColors.officialBlue : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < steps.length - 1)
                  Container(
                    width: 16,
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 16),
                    color: index < activeIndex ? AppColors.officialBlue : AppColors.border,
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // Primary & Standby Responder Card
  Widget _buildResponderCard(Emergency emergency) {
    final primary = emergency.primaryResponder;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'PRIMARY RESPONDER',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textTertiary),
              ),
              if (primary != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.greenLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('ASSIGNED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.greenDark)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (primary != null) ...[
            Row(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.greenLight,
                  child: Icon(Icons.shield_rounded, color: AppColors.greenDark, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        primary.name,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                      ),
                      Text(
                        '${primary.badgeLevel} • ${primary.formattedDistance} (${primary.formattedEta})',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Calling ${primary.name}...')),
                    );
                  },
                  icon: const Icon(Icons.call, size: 14),
                  label: const Text('Call', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.onlineGreen,
                    minimumSize: const Size(60, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryRed),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Searching for nearest verified responder...',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'STANDBY RESPONDER SLOT',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textTertiary),
              ),
              Text(
                emergency.standbyResponder != null ? 'BACKUP READY' : 'OPEN SLOT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: emergency.standbyResponder != null ? AppColors.warningAmber : AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            emergency.standbyResponder != null
                ? '${emergency.standbyResponder!.name} (${emergency.standbyResponder!.formattedDistance}) standing by for failover.'
                : 'A secondary responder will be armed automatically if primary encounters obstruction.',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // Trusted Contacts Fallback Card
  Widget _buildTrustedContactsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Having trouble finding help?',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          const Text(
            'Notify your emergency contacts immediately with your live GPS location.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Auto-SMS alert dispatched to ICE contacts.')),
                    );
                  },
                  icon: const Icon(Icons.sms_rounded, size: 16),
                  label: const Text('SMS Contacts', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.officialBlue,
                    minimumSize: const Size(0, 42),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('WhatsApp emergency broadcast opened.')),
                    );
                  },
                  icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                  label: const Text('WhatsApp', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 42),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Nearby Hospitals (Standby) Card
  Widget _buildNearbyHospitalsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'NEARBY HOSPITALS (STANDBY)',
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.textTertiary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.blueLight,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _isHospitalDirectoryAvailable ? '2 Verified' : 'Unavailable',
                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.officialBlue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Unverified directory data — confirm availability before transport.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          if (_isHospitalDirectoryAvailable) ...[
            _buildHospitalRow('City Central Care Hospital (ER)', '957 m away'),
            const Divider(height: 16),
            _buildHospitalRow('St. Martha Community Trauma Unit', '1.5 km away'),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Hospital directory currently unavailable for this jurisdiction. Call 112 directly for official ambulance & bed routing.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHospitalRow(String name, String distance) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.local_hospital_rounded, size: 16, color: AppColors.primaryRed),
            const SizedBox(width: 8),
            Text(name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        Text(distance, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // Demo State Switcher Strip
  Widget _buildDemoStateStrip(Emergency emergency) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.officialBlue.withValues(alpha: 0.3)),
      ),
      child: ExpansionTile(
        initiallyExpanded: _isDemoExpanded,
        onExpansionChanged: (val) => setState(() => _isDemoExpanded = val),
        title: const Text(
          'Demo State Switcher',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.officialBlue),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('Search State', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    widget.repository.advanceEmergencyStatus(emergency.id, EmergencyStatus.alerting);
                    widget.repository.clearEmergencyResponders(emergency.id);
                  },
                ),
                ActionChip(
                  label: const Text('Assigned State', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    widget.repository.advanceEmergencyStatus(emergency.id, EmergencyStatus.accepted);
                    widget.repository.assignMockPrimaryResponder(emergency.id);
                  },
                ),
                ActionChip(
                  label: const Text('Approaching State', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    widget.repository.advanceEmergencyStatus(emergency.id, EmergencyStatus.inProgress);
                  },
                ),
                ActionChip(
                  label: const Text('Arrived State', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    widget.repository.advanceEmergencyStatus(emergency.id, EmergencyStatus.resolved);
                  },
                ),
                ActionChip(
                  label: const Text('Toggle Offline Relay', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    widget.repository.toggleEmergencyCommunicationMode(emergency.id);
                  },
                ),
                ActionChip(
                  label: Text(
                    _isHospitalDirectoryAvailable ? 'Hide Hospitals (Directory Down)' : 'Show Hospitals (Directory Up)',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () {
                    setState(() => _isHospitalDirectoryAvailable = !_isHospitalDirectoryAvailable);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke;

    final paintLine = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(0, size.height * 0.4), Offset(size.width, size.height * 0.4), paintRoad);
    canvas.drawLine(Offset(size.width * 0.35, 0), Offset(size.width * 0.35, size.height), paintRoad);
    canvas.drawLine(Offset(0, size.height * 0.7), Offset(size.width, size.height * 0.1), paintLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
