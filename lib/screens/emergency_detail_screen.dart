// lib/screens/emergency_detail_screen.dart
//
// Vindara — Live Emergency Detail Screen
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #2 — GPS coordinates rendered directly in offline text without map tiles.
//   Rule #3 — Role-aware atomic claims and transitions.
//   Rule #4 — Local DB / Firestore stream is authoritative; no reliance on push params.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency.dart';
import '../providers/providers.dart';
import '../repositories/emergency_repository.dart';
import '../theme/vindara_theme.dart';

class EmergencyDetailScreen extends ConsumerStatefulWidget {
  final String emergencyId;

  const EmergencyDetailScreen({
    super.key,
    required this.emergencyId,
  });

  @override
  ConsumerState<EmergencyDetailScreen> createState() =>
      _EmergencyDetailScreenState();
}

class _EmergencyDetailScreenState extends ConsumerState<EmergencyDetailScreen> {
  bool _isClaiming = false;

  @override
  Widget build(BuildContext context) {
    // Watch local stream (backed by Hive) with instant offline response
    final emergencyAsync = ref.watch(emergencyStreamProvider(widget.emergencyId));
    final userProfile = ref.watch(currentUserProfileProvider).asData?.value;
    final currentUid = userProfile?.uid ?? 'local-user';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Emergency Status'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Coordinates',
            onPressed: () {
              emergencyAsync.whenData((emergency) {
                if (emergency != null) {
                  _copyCoordinates(context, emergency);
                }
              });
            },
          ),
        ],
      ),
      body: emergencyAsync.when(
        data: (emergency) {
          if (emergency == null) {
            return _buildNotFound(context);
          }
          return _buildEmergencyContent(context, emergency, currentUid);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading emergency: $e')),
      ),
    );
  }

  Widget _buildNotFound(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'Emergency record not found',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'ID: ${widget.emergencyId}',
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencyContent(
    BuildContext context,
    Emergency emergency,
    String currentUid,
  ) {
    final isVictim = emergency.victimId == currentUid;
    final isPrimary = emergency.primaryResponderId == currentUid;
    final isStandby = emergency.standbyResponderId == currentUid;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top Banner / Status Stepper Card
        _buildStatusCard(context, emergency),

        // Offline-Independent GPS Location Card (Rule #2)
        _buildGpsCard(context, emergency),

        // Responder & Coordination Card
        _buildResponderCard(context, emergency, isVictim, isPrimary, isStandby),

        const SizedBox(height: 16),

        // Role-Aware Action Buttons
        _buildActionButtons(
          context,
          emergency,
          currentUid,
          isVictim: isVictim,
          isPrimary: isPrimary,
          isStandby: isStandby,
        ),

        const SizedBox(height: 24),

        // Official 112 Help Quick Dial Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: VindaraTheme.official112Color,
              side: const BorderSide(color: VindaraTheme.official112Color, width: 2),
            ),
            icon: const Icon(Icons.phone_in_talk_rounded),
            label: const Text('Call 112 Official Emergency Line'),
            onPressed: () => _launchOfficial112(context),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Status Stepper Card
  // ---------------------------------------------------------------------------
  Widget _buildStatusCard(BuildContext context, Emergency emergency) {
    Color badgeColor;
    String badgeText;

    switch (emergency.status) {
      case EmergencyStatus.created:
        badgeColor = Colors.grey.shade700;
        badgeText = 'CREATED';
        break;
      case EmergencyStatus.alerting:
        badgeColor = VindaraTheme.statusAlerting;
        badgeText = 'ALERTING RESPONDERS';
        break;
      case EmergencyStatus.accepted:
        badgeColor = VindaraTheme.statusAccepted;
        badgeText = 'RESPONDER EN ROUTE';
        break;
      case EmergencyStatus.inProgress:
        badgeColor = VindaraTheme.statusInProgress;
        badgeText = 'HELP IN PROGRESS';
        break;
      case EmergencyStatus.resolved:
        badgeColor = VindaraTheme.statusResolved;
        badgeText = 'RESOLVED';
        break;
      case EmergencyStatus.cancelled:
        badgeColor = VindaraTheme.statusCancelled;
        badgeText = 'CANCELLED';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: badgeColor, width: 1.5),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Text(
                  'Type: ${emergency.type.name.toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Emergency ID: ${emergency.id}',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Source: ${emergency.detectionSource == DetectionSource.possibleCrash ? "Possible Crash Detection" : "Manual Help Request"} • Mode: ${emergency.communicationMode.name.toUpperCase()}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Offline-Independent GPS Location Card (Rule #2)
  // ---------------------------------------------------------------------------
  Widget _buildGpsCard(BuildContext context, Emergency emergency) {
    return Card(
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.gps_fixed_rounded, color: Colors.blueGrey, size: 20),
                SizedBox(width: 8),
                Text(
                  'GPS Coordinates (Offline Ready)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latitude:   ${emergency.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Longitude:  ${emergency.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accuracy:   ±${emergency.accuracyMeters.toStringAsFixed(1)} metres',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Coordinates'),
                    onPressed: () => _copyCoordinates(context, emergency),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Open in Maps'),
                    onPressed: () => _openExternalMaps(
                      emergency.latitude,
                      emergency.longitude,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Responder & Coordination Card
  // ---------------------------------------------------------------------------
  Widget _buildResponderCard(
    BuildContext context,
    Emergency emergency,
    bool isVictim,
    bool isPrimary,
    bool isStandby,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Community Responder Network',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  emergency.primaryResponderId != null
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  color: emergency.primaryResponderId != null
                      ? Colors.green.shade700
                      : Colors.orange.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    emergency.primaryResponderId != null
                        ? 'Primary Responder: ${isPrimary ? "You (Responding)" : "Assigned"}'
                        : 'Searching for primary community responder...',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            if (emergency.standbyResponderId != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.shield_outlined,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Standby Responder: ${isStandby ? "You (Backup Ready)" : "Active Backup"}',
                      style: TextStyle(
                        color: Colors.blue.shade900,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Role-Aware Action Buttons (Rule #3)
  // ---------------------------------------------------------------------------
  Widget _buildActionButtons(
    BuildContext context,
    Emergency emergency,
    String currentUid, {
    required bool isVictim,
    required bool isPrimary,
    required bool isStandby,
  }) {
    final repo = ref.read(emergencyRepositoryProvider);
    final firestoreService = ref.read(firestoreEmergencyServiceProvider);

    if (emergency.status == EmergencyStatus.resolved ||
        emergency.status == EmergencyStatus.cancelled) {
      return Center(
        child: Text(
          'This emergency has ended (${emergency.status.name.toUpperCase()}).',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
      );
    }

    // --- Scenario A: Viewer is Victim ---
    if (isVictim) {
      return Column(
        children: [
          if (emergency.status == EmergencyStatus.accepted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: VindaraTheme.statusInProgress,
                ),
                child: const Text('Responder On Scene (Mark In Progress)'),
                onPressed: () => repo?.transitionStatus(
                  emergency.id,
                  EmergencyStatus.inProgress,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VindaraTheme.statusResolved,
                  ),
                  child: const Text('Mark Resolved'),
                  onPressed: () => repo?.transitionStatus(
                    emergency.id,
                    EmergencyStatus.resolved,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  child: const Text('Cancel Request'),
                  onPressed: () => repo?.cancelEmergency(emergency.id),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // --- Scenario B: Viewer is Primary Responder ---
    if (isPrimary) {
      return Column(
        children: [
          if (emergency.status == EmergencyStatus.accepted)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: VindaraTheme.statusInProgress,
                ),
                child: const Text('I Have Arrived (Mark In Progress)'),
                onPressed: () => repo?.transitionStatus(
                  emergency.id,
                  EmergencyStatus.inProgress,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VindaraTheme.statusResolved,
                  ),
                  child: const Text('Resolve Emergency'),
                  onPressed: () => repo?.transitionStatus(
                    emergency.id,
                    EmergencyStatus.resolved,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  child: const Text('Step Back'),
                  onPressed: () async {
                    await firestoreService.releasePrimaryRole(
                      emergency.id,
                      currentUid,
                    );
                    // Also transition locally if offline
                    await repo?.transitionStatus(
                      emergency.id,
                      EmergencyStatus.alerting,
                      clearPrimaryResponderId: true,
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      );
    }

    // --- Scenario C: Viewer is Standby Responder ---
    if (isStandby) {
      return Card(
        color: Colors.blue.shade50,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'You are on standby backup.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton(
                child: const Text('Leave Standby'),
                onPressed: () => repo?.transitionStatus(
                  emergency.id,
                  emergency.status,
                  clearStandbyResponderId: true,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // --- Scenario D: Viewer is eligible nearby Responder ---
    final canClaimPrimary = emergency.primaryResponderId == null;
    final canClaimStandby =
        emergency.primaryResponderId != null && emergency.standbyResponderId == null;

    if (canClaimPrimary || canClaimStandby) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: canClaimPrimary
                ? VindaraTheme.emergencyRed
                : Colors.blue.shade800,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.volunteer_activism_rounded),
          label: Text(
            canClaimPrimary
                ? 'Accept & Respond (Primary)'
                : 'Join as Standby Backup',
          ),
          onPressed: _isClaiming
              ? null
              : () async {
                  setState(() => _isClaiming = true);
                  try {
                    await firestoreService.claimEmergency(
                      emergency.id,
                      currentUid,
                    );
                    // Also persist claim update to local repository
                    await repo?.transitionStatus(
                      emergency.id,
                      EmergencyStatus.accepted,
                      primaryResponderId: canClaimPrimary ? currentUid : emergency.primaryResponderId,
                      standbyResponderId: !canClaimPrimary ? currentUid : null,
                    );
                  } finally {
                    if (mounted) setState(() => _isClaiming = false);
                  }
                },
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  void _copyCoordinates(BuildContext context, Emergency emergency) {
    final text =
        'Vindara Emergency ${emergency.id}: https://maps.google.com/?q=${emergency.latitude},${emergency.longitude} (${emergency.latitude}, ${emergency.longitude})';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coordinates copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openExternalMaps(double lat, double lng) async {
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
    final webUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
    } else if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _launchOfficial112(BuildContext context) async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not trigger phone dialer for 112.')),
        );
      }
    }
  }
}
