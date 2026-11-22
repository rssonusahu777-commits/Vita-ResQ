// lib/screens/home_screen.dart
//
// Vindara — Home Screen & HELP Emergency Trigger
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #1 — Live reachability pill (isOnlineStreamProvider).
//   Rule #2 — GPS captured directly without online map tiles.
//   Rule #7 — Generates EMG-2026-XXXXXXXX.
//   Rule #8 — Local write first, immediate cloud sync.
//   UX Rule — NEVER use "SOS" in user-facing strings; use "HELP".
//             Prominent "Call 112" official emergency layer.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency.dart';
import '../providers/providers.dart';
import '../theme/vindara_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _isTriggering = false;
  Timer? _holdTimer;
  double _holdProgress = 0.0;
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _pulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnlineAsync = ref.watch(isOnlineStreamProvider);
    final isOnline = isOnlineAsync.valueOrNull ?? false;
    final userProfile = ref.watch(currentUserProfileProvider).asData?.value;
    final allEmergenciesAsync = ref.watch(allEmergenciesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Vindara',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 10),
            // Live Connectivity Pill (Rule #1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isOnline
                    ? Colors.green.shade50
                    : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isOnline
                      ? Colors.green.shade600
                      : Colors.amber.shade700,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 3.5,
                    backgroundColor: isOnline
                        ? Colors.green.shade600
                        : Colors.amber.shade700,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isOnline ? 'Online' : 'Offline Mode',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isOnline
                          ? Colors.green.shade900
                          : Colors.amber.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Responder Profile & Settings',
            onPressed: () => context.push('/profile'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                const SizedBox(height: 12),

                // Center Primary HELP Trigger Button
                _buildHelpButtonSection(context),

                const SizedBox(height: 24),

                // Fast 1-Tap Category Triggers
                _buildQuickCategoryRow(context),

                const SizedBox(height: 20),

                // Responder Mode Card
                _buildResponderCard(context, userProfile, allEmergenciesAsync),
              ],
            ),
          ),

          // Official Emergency Services Layer (Docked Bottom Bar)
          _buildOfficialServicesBar(context),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Primary HELP Button Section
  // ---------------------------------------------------------------------------
  Widget _buildHelpButtonSection(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Press & hold or tap category for instant emergency broadcast',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTapDown: (_) => _startHoldTimer(),
          onTapUp: (_) => _cancelHoldTimer(),
          onTapCancel: () => _cancelHoldTimer(),
          onTap: () => _showCategoryConfirmationSheet(context),
          child: AnimatedBuilder(
            animation: _pulseController!,
            builder: (context, child) {
              final scale = 1.0 + (_pulseController!.value * 0.04);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        VindaraTheme.emergencyRed,
                        VindaraTheme.emergencyDarkRed,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: VindaraTheme.emergencyRed.withOpacity(0.35),
                        blurRadius: 24,
                        spreadRadius: 4,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_holdProgress > 0.0)
                        SizedBox(
                          width: 180,
                          height: 180,
                          child: CircularProgressIndicator(
                            value: _holdProgress,
                            strokeWidth: 6,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.emergency_share_rounded,
                            size: 42,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'HELP',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 1.5,
                            ),
                          ),
                          Text(
                            _isTriggering
                                ? 'ACQUIRING GPS...'
                                : 'HOLD 1.2S',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white70,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Fast 1-Tap Category Triggers
  // ---------------------------------------------------------------------------
  Widget _buildQuickCategoryRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCategoryPill(
          context,
          icon: Icons.local_hospital_rounded,
          label: 'Medical',
          type: EmergencyType.medical,
        ),
        _buildCategoryPill(
          context,
          icon: Icons.car_crash_rounded,
          label: 'Accident',
          type: EmergencyType.accident,
        ),
        _buildCategoryPill(
          context,
          icon: Icons.security_rounded,
          label: 'Safety',
          type: EmergencyType.safety,
        ),
        _buildCategoryPill(
          context,
          icon: Icons.warning_amber_rounded,
          label: 'General',
          type: EmergencyType.general,
        ),
      ],
    );
  }

  Widget _buildCategoryPill(
    BuildContext context, {
    required IconData icon,
    required String label,
    required EmergencyType type,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _triggerEmergency(context, type: type),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: VindaraTheme.emergencyRed),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Responder Mode Card
  // ---------------------------------------------------------------------------
  Widget _buildResponderCard(
    BuildContext context,
    dynamic userProfile,
    AsyncValue<List<Emergency>> allEmergenciesAsync,
  ) {
    final isAvailable = userProfile?.isAvailable ?? false;
    final isVerified = userProfile?.isVerifiedResponder ?? true;
    final repPoints = userProfile?.reputationPoints ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isVerified ? Icons.verified_user : Icons.shield_outlined,
                      color: isVerified
                          ? Colors.blue.shade700
                          : Colors.grey.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Responder Mode',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '★ $repPoints pts',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Available to Help Nearby',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Toggle to receive alerts when someone in your area requests HELP.',
                style: TextStyle(fontSize: 12),
              ),
              value: isAvailable,
              onChanged: (val) {
                ref
                    .read(currentUserProfileProvider.notifier)
                    .setAvailability(val);
              },
            ),

            // Active Alerting Emergencies Feed
            allEmergenciesAsync.when(
              data: (list) {
                final active = list
                    .where((e) =>
                        e.status == EmergencyStatus.alerting ||
                        e.status == EmergencyStatus.accepted)
                    .toList();
                if (active.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 20),
                    const Text(
                      'Active Nearby Incidents',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: VindaraTheme.emergencyDarkRed,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...active.take(2).map(
                          (emg) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.location_on_rounded,
                              color: VindaraTheme.emergencyRed,
                            ),
                            title: Text(
                              '${emg.type.name.toUpperCase()} • ${emg.id}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text('Status: ${emg.status.name}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push('/emergency/${emg.id}'),
                          ),
                        ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Official Emergency Services Layer (Docked Bottom Bar)
  // ---------------------------------------------------------------------------
  Widget _buildOfficialServicesBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Official Emergency Services',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: VindaraTheme.official112Color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.phone_in_talk_rounded, size: 20),
                label: const Text(
                  'Call 112 (Official Emergency)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _call112(),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Vindara community response complements, but never replaces, official 112 dispatch.',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Trigger Logic
  // ---------------------------------------------------------------------------
  void _startHoldTimer() {
    _holdProgress = 0.0;
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      setState(() {
        _holdProgress += 0.05 / 1.2; // 1.2s hold duration
        if (_holdProgress >= 1.0) {
          _holdTimer?.cancel();
          _holdProgress = 0.0;
          _triggerEmergency(context, type: EmergencyType.general);
        }
      });
    });
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    if (_holdProgress > 0.0 && _holdProgress < 1.0) {
      setState(() => _holdProgress = 0.0);
    }
  }

  void _showCategoryConfirmationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Confirm Emergency Category',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select category to broadcast your HELP request immediately.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.red,
                    child: Icon(Icons.local_hospital, color: Colors.white),
                  ),
                  title: const Text('Medical Emergency'),
                  subtitle: const Text('Cardiac, trauma, fainting, severe illness'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _triggerEmergency(context, type: EmergencyType.medical);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.orange,
                    child: Icon(Icons.car_crash, color: Colors.white),
                  ),
                  title: const Text('Vehicle / Road Accident'),
                  subtitle: const Text('Collision, vehicle rollover, pedestrian injury'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _triggerEmergency(context, type: EmergencyType.accident);
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.security, color: Colors.white),
                  ),
                  title: const Text('Personal Safety / Threat'),
                  subtitle: const Text('Assault, stalking, harassment, physical threat'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _triggerEmergency(context, type: EmergencyType.safety);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _triggerEmergency(
    BuildContext context, {
    required EmergencyType type,
  }) async {
    if (_isTriggering) return;
    setState(() => _isTriggering = true);

    try {
      final repo = ref.read(emergencyRepositoryProvider);
      final profile = ref.read(currentUserProfileProvider).asData?.value;
      final victimId = profile?.uid ?? 'local-victim-user';

      if (repo == null) {
        throw Exception('EmergencyRepository is not initialized yet');
      }

      // Create emergency locally first (status: alerting)
      final emergency = await repo.createEmergency(
        victimId: victimId,
        type: type,
        detectionSource: DetectionSource.manualHelp,
      );

      // Transition to alerting status so responders are notified
      await repo.transitionStatus(emergency.id, EmergencyStatus.alerting);

      // Refresh emergencies list provider
      ref.invalidate(allEmergenciesProvider);

      if (mounted) {
        context.push('/emergency/${emergency.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to trigger emergency: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTriggering = false);
    }
  }

  Future<void> _call112() async {
    final uri = Uri.parse('tel:112');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
}
