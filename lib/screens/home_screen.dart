import 'package:flutter/material.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import '../models/responder.dart';
import '../widgets/emergency_card.dart';

/// Primary Home Screen for Vindara Community Emergency Response Platform
class HomeScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const HomeScreen({
    super.key,
    required this.repository,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  EmergencyType? _selectedFilterType;
  bool _filterCriticalOnly = false;
  late Responder _currentUser;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final responder = await widget.repository.getCurrentUserResponder();
    if (mounted) {
      setState(() {
        _currentUser = responder;
        _isLoadingUser = false;
      });
    }
  }

  void _showHotlineDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.phone_in_talk_rounded, color: AppColors.info),
            SizedBox(width: 10),
            Text('Official Emergency 112'),
          ],
        ),
        content: const Text(
          'Connecting to National Emergency Helpline (112). In a live deployment, this dials the verified public safety answering point (PSAP).',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('DISMISS', style: TextStyle(color: AppColors.textTertiary)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Simulated dialing 112 emergency hotline.'),
                  backgroundColor: AppColors.info,
                ),
              );
            },
            icon: const Icon(Icons.call_rounded, size: 16),
            label: const Text('CALL 112 NOW'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              minimumSize: const Size(120, 44),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _simulateNewEmergency() async {
    final types = [
      EmergencyType.roadAccident,
      EmergencyType.medical,
      EmergencyType.personalSafety,
      EmergencyType.fire,
    ];
    final randomType = types[(DateTime.now().second) % types.length];
    final isCrash = randomType == EmergencyType.roadAccident;

    final messenger = ScaffoldMessenger.of(context);

    await widget.repository.createEmergency(
      victimName: 'Citizen ${DateTime.now().second}',
      latitude: 12.9716 + (DateTime.now().millisecond % 50) * 0.001,
      longitude: 77.5946 + (DateTime.now().millisecond % 50) * 0.001,
      locationLabel: 'MG Road Metro Station, Bengaluru',
      type: randomType,
      detectionSource: isCrash ? DetectionSource.possibleCrash : DetectionSource.manualSos,
      communicationMode: CommunicationMode.online,
      notes: isCrash
          ? 'Automated accelerometer spike: Severe crash impact profile.'
          : 'User triggered manual panic button with live location broadcast.',
    );

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('New ${randomType.name} alert dispatched to community network!'),
        backgroundColor: AppColors.criticalDanger,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.criticalDanger),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.criticalDanger,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.emergency_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  AppConstants.appTagline,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Quick 112 Hotline Pill Button
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: InkWell(
              onTap: () => _showHotlineDialog(context),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.criticalDanger.withValues(alpha: 0.15),
                  border: Border.all(color: AppColors.criticalDanger.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.call_rounded, size: 14, color: AppColors.criticalDanger),
                    SizedBox(width: 6),
                    Text(
                      '112',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.criticalDanger,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<Emergency>>(
        stream: widget.repository.watchActiveEmergencies(),
        builder: (context, snapshot) {
          final emergencies = snapshot.data ?? [];
          return _buildContent(context, emergencies);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _simulateNewEmergency,
        backgroundColor: AppColors.criticalDanger,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.warning_amber_rounded),
        label: const Text(
          'SIMULATE SOS ALERT',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<Emergency> allEmergencies) {
    // Apply local filters
    final displayedEmergencies = allEmergencies.where((e) {
      if (_filterCriticalOnly && e.status != EmergencyStatus.alerting) {
        return false;
      }
      if (_selectedFilterType != null && e.type != _selectedFilterType) {
        return false;
      }
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
      children: [
        // STEP 3: Semantic Colors Badge Row
        _buildSemanticPaletteLegend(),
        const SizedBox(height: 16),

        // Responder Profile & Readiness Banner
        _buildResponderProfileBanner(),
        const SizedBox(height: 20),

        // Filter Controls & Section Header
        _buildFeedHeader(allEmergencies.length, displayedEmergencies.length),
        const SizedBox(height: 12),

        // Emergencies List
        if (displayedEmergencies.isEmpty)
          _buildEmptyState()
        else
          ...displayedEmergencies.map((emergency) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: EmergencyCard(
                emergency: emergency,
                currentUser: _currentUser,
                onAcceptPrimary: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await widget.repository.acceptAsPrimary(emergency.id, _currentUser);
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Accepted ${emergency.id} as Primary Responder!'),
                      backgroundColor: AppColors.safe,
                    ),
                  );
                },
                onAcceptStandby: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await widget.repository.acceptAsStandby(emergency.id, _currentUser);
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Registered as Standby Responder for ${emergency.id}.'),
                      backgroundColor: AppColors.warning,
                    ),
                  );
                },
                onAdvanceStatus: (nextStatus) async {
                  await widget.repository.advanceEmergencyStatus(emergency.id, nextStatus);
                },
                onCall112: () => _showHotlineDialog(context),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildSemanticPaletteLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_outlined, size: 14, color: AppColors.textTertiary),
              SizedBox(width: 6),
              Text(
                'SYSTEM SEMANTIC STATUS CHANNELS',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildPaletteItem('SOS / CRITICAL', AppColors.criticalDanger),
              const SizedBox(width: 6),
              _buildPaletteItem('CRASH / STANDBY', AppColors.warning),
              const SizedBox(width: 6),
              _buildPaletteItem('SAFE / ONLINE', AppColors.safe),
              const SizedBox(width: 6),
              _buildPaletteItem('112 / INFO', AppColors.info),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaletteItem(String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResponderProfileBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.surface,
            AppColors.surfaceElevated,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.criticalDanger.withValues(alpha: 0.15),
                child: const Icon(Icons.shield_outlined, color: AppColors.criticalDanger, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _currentUser.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (_currentUser.isVerified)
                          const Icon(Icons.verified, size: 16, color: AppColors.info),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_currentUser.badgeLevel} • ${_currentUser.points} XP • ${_currentUser.completedResponses} Responses',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              // Availability Switch
              Column(
                children: [
                  Switch(
                    value: _currentUser.isAvailable,
                    activeThumbColor: AppColors.safe,
                    onChanged: (val) async {
                      await widget.repository.updateCurrentUserAvailability(val);
                      setState(() {
                        _currentUser = _currentUser.copyWith(isAvailable: val);
                      });
                    },
                  ),
                  Text(
                    _currentUser.isAvailable ? 'READY' : 'OFFLINE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _currentUser.isAvailable ? AppColors.safe : AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeedHeader(int totalCount, int filteredCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.radar_rounded, size: 18, color: AppColors.criticalDanger),
                const SizedBox(width: 8),
                const Text(
                  'ACTIVE NEARBY INCIDENTS',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.criticalDanger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.criticalDanger.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '$filteredCount',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.criticalDanger,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Within 5.0 km',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              FilterChip(
                label: const Text('All Incidents'),
                selected: !_filterCriticalOnly && _selectedFilterType == null,
                onSelected: (_) {
                  setState(() {
                    _filterCriticalOnly = false;
                    _selectedFilterType = null;
                  });
                },
                selectedColor: AppColors.criticalDanger.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Critical Alerts'),
                selected: _filterCriticalOnly,
                onSelected: (val) {
                  setState(() {
                    _filterCriticalOnly = val;
                  });
                },
                selectedColor: AppColors.criticalDanger.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Road Crashes'),
                selected: _selectedFilterType == EmergencyType.roadAccident,
                onSelected: (val) {
                  setState(() {
                    _selectedFilterType = val ? EmergencyType.roadAccident : null;
                  });
                },
                selectedColor: AppColors.warning.withValues(alpha: 0.25),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Medical'),
                selected: _selectedFilterType == EmergencyType.medical,
                onSelected: (val) {
                  setState(() {
                    _selectedFilterType = val ? EmergencyType.medical : null;
                  });
                },
                selectedColor: AppColors.criticalDanger.withValues(alpha: 0.25),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.shield_rounded, size: 48, color: AppColors.safe.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'Vicinity Is Currently Safe',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'No active emergency broadcasts matching filters within your neighborhood radius.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
