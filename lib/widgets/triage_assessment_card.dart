import 'package:flutter/material.dart';
import '../models/triage_assessment_model.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/app_shapes.dart';

/// Clean, compact responder triage card displaying AI-assisted injury assessment.
///
/// Designed for high glanceability and zero RenderFlex overflow on 360x640 viewports.
class TriageAssessmentCard extends StatelessWidget {
  final TriageAssessment triage;
  final bool isCompact;

  const TriageAssessmentCard({
    super.key,
    required this.triage,
    this.isCompact = false,
  });

  Color _getLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'CRITICAL':
        return AppColors.emergencyRed;
      case 'HIGH':
        return const Color(0xFFE65100); // Deep Orange
      case 'MODERATE':
        return const Color(0xFFB78103); // Deep Amber
      case 'UNCLEAR':
      default:
        return AppColors.textSecondary;
    }
  }

  Color _getLevelBgColor(String level) {
    switch (level.toUpperCase()) {
      case 'CRITICAL':
        return AppColors.emergencyLightRed;
      case 'HIGH':
        return const Color(0xFFFFF3E0);
      case 'MODERATE':
        return const Color(0xFFFFF8E1);
      case 'UNCLEAR':
      default:
        return const Color(0xFFF5F5F7);
    }
  }

  String _formatSource(String source) {
    switch (source.toUpperCase()) {
      case 'AI_MULTIMODAL':
        return 'AI';
      case 'LOCAL_FALLBACK':
        return 'Offline Voice';
      case 'CRASH_ESCALATION':
        return 'Crash Auto-Escalation';
      default:
        return source;
    }
  }

  @override
  Widget build(BuildContext context) {
    final levelColor = _getLevelColor(triage.level);
    final levelBgColor = _getLevelBgColor(triage.level);
    final sourceLabel = _formatSource(triage.source);
    final hasTranscript =
        triage.transcript != null && triage.transcript!.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isCompact ? 10 : 14),
      decoration: BoxDecoration(
        color: AppColors.surfacePureWhite,
        borderRadius: AppShapes.card,
        border: Border.all(
          color: triage.level == 'CRITICAL'
              ? AppColors.emergencyRed.withValues(alpha: 0.3)
              : AppColors.borderSubtle,
          width: triage.level == 'CRITICAL' ? 1.5 : 1.0,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Title & Badges
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(
                Icons.medical_services_rounded,
                size: isCompact ? 16 : 18,
                color: levelColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI-Assisted Scene Triage',
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: isCompact ? 12 : 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.deepNavy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              // Severity Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: levelBgColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: levelColor.withValues(alpha: 0.5)),
                ),
                child: Text(
                  triage.level,
                  style: TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: levelColor,
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Confidence + Source Tag
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      triage.source == 'AI_MULTIMODAL'
                          ? Icons.auto_awesome
                          : triage.source == 'CRASH_ESCALATION'
                              ? Icons.warning_rounded
                              : Icons.mic_none_rounded,
                      size: 11,
                      color: AppColors.deepNavy,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        '$sourceLabel • ${triage.confidence} Confidence',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.deepNavy,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Briefing Summary Text
          Text(
            triage.summary,
            style: TextStyle(
              fontSize: isCompact ? 12 : 13,
              fontWeight: FontWeight.w500,
              color: AppColors.deepNavy,
              height: 1.35,
            ),
          ),

          // Voice Transcript Snippet (if present)
          if (hasTranscript) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.subtleBlueGray.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: AppColors.borderSubtle.withValues(alpha: 0.7),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.format_quote_rounded,
                    size: 14,
                    color: AppColors.brandBlue,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      triage.transcript!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

