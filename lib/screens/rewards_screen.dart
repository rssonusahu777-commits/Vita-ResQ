import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/responder.dart';

/// My Impact Screen (Subordinate, Honest, Non-Competitive Self-Tracked Activity)
class RewardsScreen extends StatelessWidget {
  final EmergencyRepository repository;

  const RewardsScreen({
    super.key,
    required this.repository,
  });

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
          'My Impact & Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: FutureBuilder<Responder>(
        future: repository.getCurrentUserResponder(),
        builder: (context, snapshot) {
          final responder = snapshot.data;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              // Honest Subordinate Disclaimer
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.shield_outlined, size: 18, color: AppColors.textSecondary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Locally recorded community activity — unverified self-tracked summary. Vindara intentionally omits competitive rankings and gamified point leaderboards to prevent dangerous incentive distortions.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Activity Metrics Grouped Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SELF-TRACKED ASSISTANCE LOG',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _buildMetricBox('Completed Assists', '${responder?.completedResponses ?? 28}', AppColors.onlineGreen),
                        const SizedBox(width: 12),
                        _buildMetricBox('Reliability Index', '99.4%', AppColors.officialBlue),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildMetricBox('Standby Failovers', '6 Ready', AppColors.warningAmber),
                        const SizedBox(width: 12),
                        _buildMetricBox('Mesh Packets Relayed', '142 hops', AppColors.textPrimary),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Volunteer Role & Guidelines Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'COMMUNITY VOLUNTEER PRINCIPLES',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textTertiary),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '1. Life Safety First: Always notify 112 before or during peer mutual aid.\n'
                      '2. Never Exceed Training: First-aid is bystander assistance until official ambulances arrive.\n'
                      '3. Zero False Expectations: Standby failover automatically re-routes when volunteers are obstructed.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }
}

