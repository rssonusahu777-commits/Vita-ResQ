import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/responder.dart';

/// Dedicated Full-Page Certificates & Verification Screen
class CertificatesScreen extends StatelessWidget {
  final EmergencyRepository repository;

  const CertificatesScreen({
    super.key,
    required this.repository,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: const Text(
          'Certificates & Verification',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: FutureBuilder<Responder>(
        future: repository.getCurrentUserResponder(),
        builder: (context, snapshot) {
          final responder = snapshot.data;
          final userName = (responder != null && responder.name.isNotEmpty && responder.name != 'ayush patnayak')
              ? responder.name
              : 'Citizen Volunteer';
          final completed = responder?.completedResponses ?? 0;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
            children: [
              // 1. Honest Participation Notice Banner
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
                    Icon(Icons.shield_outlined, size: 18, color: Color(0xFF6B7280)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Community Participation Record: Vindara certificates recognize active civic volunteer presence and mutual-aid assists. They do not constitute licensed medical or paramedic certification.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF4B5563), height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // 2. Rendered Certificate Preview Card
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Certificate Header Badge
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFD4AF37), width: 1.5),
                      ),
                      child: const Icon(
                        Icons.military_tech_rounded,
                        color: Color(0xFFD4AF37),
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'VINDARA COMMUNITY NETWORK',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Certificate of Community First Response',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'THIS RECOGNIZES THAT',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      userName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E293B),
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'has participated as a dedicated Citizen First Responder, completing $completed verified mutual-aid dispatches across the peer community network.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4B5563),
                          height: 1.45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: Color(0xFFEAE8E3)),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'VOLUNTEER ID',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF9CA3AF)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'VND-CG-4091',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: const [
                            Text(
                              'VERIFIED DATE',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF9CA3AF)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'November 2026',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 3. Export / Share Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Downloading high-res PDF certificate...'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download PDF', style: TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 46),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Volunteer credential link copied to clipboard.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: const Text('Share Record', style: TextStyle(fontWeight: FontWeight.w800)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.textPrimary,
                        minimumSize: const Size(0, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // 4. Milestone Badges Section
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'VOLUNTEER MILESTONES',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEAE8E3)),
                ),
                child: Column(
                  children: [
                    _buildMilestoneRow(
                      title: 'Community Onboarding Completed',
                      subtitle: 'Basic emergency coordination and peer mesh relay rules verified.',
                      isUnlocked: true,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F0EC)),
                    _buildMilestoneRow(
                      title: 'Active Community Responder (25+ Assists)',
                      subtitle: completed >= 25
                          ? 'Achieved $completed logged community assists in local area.'
                          : 'In Progress: $completed of 25 assists logged.',
                      isUnlocked: completed >= 25,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F0EC)),
                    _buildMilestoneRow(
                      title: 'Mesh Anchor Responder (50+ Assists)',
                      subtitle: completed >= 50
                          ? 'Achieved $completed logged community assists (Network Anchor).'
                          : 'In Progress: $completed of 50 assists completed towards network anchor status.',
                      isUnlocked: completed >= 50,
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

  Widget _buildMilestoneRow({
    required String title,
    required String subtitle,
    required bool isUnlocked,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isUnlocked ? const Color(0xFFD1FAE5) : const Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isUnlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
              color: isUnlocked ? const Color(0xFF059669) : const Color(0xFF9CA3AF),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isUnlocked ? AppColors.textPrimary : const Color(0xFF9CA3AF),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.35),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

