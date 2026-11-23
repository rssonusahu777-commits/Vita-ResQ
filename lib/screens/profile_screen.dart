// lib/screens/profile_screen.dart
//
// Vindara — Profile & Responder Settings Screen (Phase 6)
// Package: com.vindara.app

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../constants/platform_limitations.dart';
import '../models/user_profile.dart';
import '../providers/providers.dart';
import 'auth_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfileAsync = ref.watch(currentUserProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Responder Profile & Settings'),
      ),
      body: userProfileAsync.when(
        data: (profile) => _buildProfileBody(context, ref, profile),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading profile: $e')),
      ),
    );
  }

  Widget _buildProfileBody(
    BuildContext context,
    WidgetRef ref,
    UserProfile? profile,
  ) {
    final effectiveProfile = profile ??
        const UserProfile(
          uid: 'local-user',
          displayName: 'Community Member',
          isVerifiedResponder: true,
          isAvailable: true,
          reputationPoints: 120,
          successfulAssistanceCount: 6,
          responseHistoryCount: 7,
          badges: ['first_responder', 'community_guardian'],
        );

    final isCrashMonitoring = ref.watch(crashMonitoringEnabledProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // User Identity Card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    effectiveProfile.displayName.isNotEmpty
                        ? effectiveProfile.displayName[0].toUpperCase()
                        : 'V',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        effectiveProfile.displayName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            effectiveProfile.isVerifiedResponder
                                ? Icons.verified
                                : Icons.person_outline,
                            size: 16,
                            color: effectiveProfile.isVerifiedResponder
                                ? Colors.blue.shade700
                                : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            effectiveProfile.isVerifiedResponder
                                ? 'Verified Community Responder'
                                : 'Civilian User',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Responder Availability Toggle Card
        Card(
          child: SwitchListTile(
            title: const Text(
              'Available to Help Nearby',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Receive high-priority emergency push alerts when someone near you requests HELP.',
            ),
            value: effectiveProfile.isAvailable,
            onChanged: (val) {
              ref
                  .read(currentUserProfileProvider.notifier)
                  .setAvailability(val);
            },
          ),
        ),

        // Possible Crash Detection Monitoring Toggle Card (Rule #10)
        Card(
          child: Column(
            children: [
              SwitchListTile(
                title: const Text(
                  'Possible Crash Detection',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Detects high-impact motion patterns and starts a 10s cancellable countdown.',
                ),
                value: isCrashMonitoring,
                onChanged: (val) {
                  ref
                      .read(crashMonitoringEnabledProvider.notifier)
                      .toggle(val);
                },
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Test Simulation:',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Test Possible Crash Countdown'),
                      onPressed: () {
                        context.push('/crash-countdown');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Reputation & Stats Grid
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Community Reputation & Track Record',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(
                      label: 'Points',
                      value: '${effectiveProfile.reputationPoints}',
                      icon: Icons.stars_rounded,
                      color: Colors.amber.shade700,
                    ),
                    _buildStatItem(
                      label: 'Assists',
                      value: '${effectiveProfile.successfulAssistanceCount}',
                      icon: Icons.volunteer_activism_rounded,
                      color: Colors.green.shade700,
                    ),
                    _buildStatItem(
                      label: 'Success Rate',
                      value: '${(effectiveProfile.successRate * 100).toInt()}%',
                      icon: Icons.trending_up_rounded,
                      color: Colors.blue.shade700,
                    ),
                  ],
                ),
                if (effectiveProfile.badges.isNotEmpty) ...[
                  const Divider(height: 32),
                  const Text(
                    'Earned Badges',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: effectiveProfile.badges.map((b) {
                      return Chip(
                        avatar: const Icon(Icons.shield_outlined, size: 16),
                        label: Text(
                          b.replaceAll('_', ' ').toUpperCase(),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: Colors.blueGrey.shade50,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),

        // System & Notification Reliability Card (Rule #5)
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'System & Notification Reliability',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  PlatformLimitations.osForceStopLimitationNotice,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.amber.shade900,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Sign Out Card
        Card(
          elevation: 0,
          color: Colors.red.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.shade200),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ListTile(
              leading: Icon(Icons.logout_rounded, color: Colors.red.shade800),
              title: Text(
                'Sign Out',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade900,
                ),
              ),
              subtitle: const Text(
                'Sign out of your Vindara account on this device.',
              ),
              trailing: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (Firebase.apps.isNotEmpty) {
                    try {
                      await FirebaseAuth.instance.signOut();
                    } catch (_) {}
                  }
                  ref.read(offlineEmergencyBypassProvider.notifier).state = false;
                  final repo = await ref.read(userProfileRepositoryProvider.future);
                  await repo.clearProfile();
                  if (context.mounted) {
                    context.go('/auth');
                  }
                },
                child: const Text('Sign Out'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
