import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import '../models/responder.dart';
import 'navigating_to_victim_screen.dart';

/// Responder Detail & Atomic Claim Screen
class ResponderEmergencyDetailScreen extends StatefulWidget {
  final String emergencyId;
  final EmergencyRepository repository;

  const ResponderEmergencyDetailScreen({
    super.key,
    required this.emergencyId,
    required this.repository,
  });

  @override
  State<ResponderEmergencyDetailScreen> createState() => _ResponderEmergencyDetailScreenState();
}

class _ResponderEmergencyDetailScreenState extends State<ResponderEmergencyDetailScreen> {
  late Responder _currentUser;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final responder = await widget.repository.getCurrentUserResponder();
    if (mounted) {
      setState(() {
        _currentUser = responder;
        _isLoadingUser = false;
      });
    }
  }

  Future<void> _claimPrimary(Emergency emergency) async {
    // Atomic claim as Primary
    await widget.repository.acceptAsPrimary(emergency.id, _currentUser);
    final updated = await widget.repository.getEmergencyById(emergency.id);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (ctx) => NavigatingToVictimScreen(
          emergency: updated ?? emergency,
          isPrimary: true,
          repository: widget.repository,
        ),
      ),
    );
  }

  Future<void> _claimStandby(Emergency emergency) async {
    // Atomic claim as Standby
    await widget.repository.acceptAsStandby(emergency.id, _currentUser);
    final updated = await widget.repository.getEmergencyById(emergency.id);

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (ctx) => NavigatingToVictimScreen(
          emergency: updated ?? emergency,
          isPrimary: false,
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Emergency?>(
      stream: widget.repository.watchEmergency(widget.emergencyId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || _isLoadingUser) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(title: const Text('Emergency Details')),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(color: AppColors.primaryRed),
                  SizedBox(height: 16),
                  Text(
                    'Fetching latest emergency status from database...',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        final emergency = snapshot.data!;
        final isPrimaryClaimed = emergency.primaryResponder != null;
        final isStandbyClaimed = emergency.standbyResponder != null;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              emergency.id,
              style: AppTheme.tabularNumericStyle.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
            children: [
              // 1. LIVE STATUS & VICTIM CARD
              Container(
                padding: const EdgeInsets.all(16),
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
                            emergency.typeDisplayName.toUpperCase(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primaryRed),
                          ),
                        ),
                        Text(
                          '86m away • 1 min ETA',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Victim: ${emergency.victimName}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      emergency.locationLabel,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),

                    // Raw GPS bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.my_location_rounded, size: 14, color: AppColors.officialBlue),
                              const SizedBox(width: 6),
                              Text(
                                '${emergency.latitude.toStringAsFixed(4)}, ${emergency.longitude.toStringAsFixed(4)} (GPS Coordinates)',
                                style: AppTheme.tabularNumericStyle.copyWith(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: emergency.formattedCoordinates));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Coordinates copied.')),
                              );
                            },
                            child: const Text(
                              'COPY',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.officialBlue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 2. RESPONDER SLOTS REAL-TIME STATUS CARD
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RESPONDER SLOTS ALLOCATION',
                      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textTertiary),
                    ),
                    const SizedBox(height: 12),

                    // Primary Slot
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isPrimaryClaimed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: isPrimaryClaimed ? AppColors.onlineGreen : AppColors.primaryRed,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Primary Responder Slot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                Text(
                                  isPrimaryClaimed
                                      ? 'Claimed by ${emergency.primaryResponder!.name}'
                                      : 'Available for immediate response',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isPrimaryClaimed ? AppColors.textSecondary : AppColors.primaryRed,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPrimaryClaimed ? AppColors.surfaceMuted : AppColors.greenLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isPrimaryClaimed ? 'OCCUPIED' : 'OPEN',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isPrimaryClaimed ? AppColors.textSecondary : AppColors.greenDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),

                    // Standby Slot
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isStandbyClaimed ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: isStandbyClaimed ? AppColors.warningAmber : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Standby Responder Slot', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                Text(
                                  isStandbyClaimed
                                      ? 'Claimed by ${emergency.standbyResponder!.name}'
                                      : 'Open for backup failover support',
                                  style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.amberLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isStandbyClaimed ? 'OCCUPIED' : 'OPEN',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.warningAmber),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 3. ATOMIC CLAIM ACTIONS
              if (!isPrimaryClaimed) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => _claimPrimary(emergency),
                    icon: const Icon(Icons.flash_on_rounded, size: 20),
                    label: const Text(
                      'ACCEPT AS PRIMARY RESPONDER',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryRed,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ] else ...[
                // Primary already claimed warning box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.amberLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.warningAmber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Primary slot already claimed by ${emergency.primaryResponder!.name}. You can join as Standby to ensure zero failover delay.',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isStandbyClaimed ? null : () => _claimStandby(emergency),
                    icon: const Icon(Icons.hourglass_top_rounded, size: 18),
                    label: const Text(
                      'JOIN AS STANDBY RESPONDER',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.warningAmber,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

