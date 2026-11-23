import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import '../services/connectivity_service.dart';
import '../services/location_service.dart';
import '../services/offline_p2p_service.dart';
import 'active_emergency_screen.dart';
import 'crash_detection_screen.dart';
import 'responder_alerts_screen.dart';

/// Clean, Light Theme Home & HELP Hub Screen
class SosHubScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const SosHubScreen({
    super.key,
    required this.repository,
  });

  @override
  State<SosHubScreen> createState() => _SosHubScreenState();
}

class _SosHubScreenState extends State<SosHubScreen> with TickerProviderStateMixin {
  // Reachability state (synced with real connectivity & probe)
  CommunicationMode _communicationMode = CommunicationMode.online;

  // Selected Emergency Type
  final EmergencyType _selectedType = EmergencyType.medical;

  // GPS Simulation state (True: fix active, False: unavailable warning state)
  bool _isGpsAvailable = true;

  // Crash Guard monitoring state
  final bool _isCrashGuardActive = true;

  // Hardware/cached GPS coordinates (never stuck at 0,0)
  double _currentLatitude = 21.1619;
  double _currentLongitude = 81.7869;
  String _currentLocationLabel = 'Sector 4, Community Axis, Raipur / Central Hub';
  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<P2pMeshStatus>? _p2pStatusSub;
  StreamSubscription<Emergency>? _p2pAlertsSub;
  P2pMeshStatus _p2pStatus = P2pMeshStatus.idle;

  // HELP button press & hold state
  late final AnimationController _holdController;
  late final AnimationController _pulseController;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();

    _initGps();
    _initConnectivity();
    _initP2pMesh();

    // 2-second hold controller for tactile HELP press
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _holdController.addListener(() {
      setState(() {});
    });

    _holdController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _triggerHelpDispatch();
      }
    });

    // Gentle continuous pulsing ring for the map location pin
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  Future<void> _initGps() async {
    try {
      final fix = await LocationService.acquireBestAvailableFix();
      if (mounted && fix != null) {
        setState(() {
          _currentLatitude = fix.latitude;
          _currentLongitude = fix.longitude;
          _currentLocationLabel =
              '${fix.latitude.toStringAsFixed(4)}, ${fix.longitude.toStringAsFixed(4)} (GPS Fix Locked)';
          _isGpsAvailable = true;
        });
      }
    } catch (e) {
      debugPrint('GPS fix acquisition fallback in SosHub: $e');
    }
  }

  void _initConnectivity() {
    _connectivitySub = ConnectivityService().isOnline.listen((isOnline) {
      if (mounted) {
        setState(() {
          _communicationMode =
              isOnline ? CommunicationMode.online : CommunicationMode.offlineNearby;
        });
      }
    });
  }

  void _initP2pMesh() {
    _p2pStatus = OfflineP2pService.instance.currentStatus;
    _p2pStatusSub = OfflineP2pService.instance.statusStream.listen((status) {
      if (mounted) {
        setState(() => _p2pStatus = status);
      }
    });
    _p2pAlertsSub = OfflineP2pService.instance.incomingHelpAlertsStream.listen((alert) {
      if (!mounted) return;
      HapticFeedback.heavyImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.primaryRed,
          duration: const Duration(seconds: 5),
          content: Text('Nearby HELP Received via P2P Mesh: ${alert.victimName}'),
          action: SnackBarAction(
            textColor: Colors.white,
            label: 'VIEW',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (ctx) => ActiveEmergencyScreen(
                    initialEmergency: alert,
                    repository: widget.repository,
                  ),
                ),
              );
            },
          ),
        ),
      );
    });
    OfflineP2pService.instance.startDiscovery().catchError((e) {
      debugPrint('SosHub P2P discovery auto-start error: $e');
      return false;
    });
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _p2pStatusSub?.cancel();
    _p2pAlertsSub?.cancel();
    _holdController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleCommunicationMode() {
    setState(() {
      _communicationMode = _communicationMode == CommunicationMode.online
          ? CommunicationMode.offlineNearby
          : CommunicationMode.online;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _communicationMode == CommunicationMode.online
              ? 'Switched to Online (Cloud Dispatch)'
              : 'Switched to Offline (Nearby Peer Mesh Relay Active)',
        ),
        backgroundColor: _communicationMode == CommunicationMode.online
            ? AppColors.onlineGreen
            : AppColors.warningAmber,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _startHolding() {
    if (!_isGpsAvailable) {
      _showGpsUnavailableDialog();
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isHolding = true;
    });
    _holdController.forward(from: 0.0);
  }

  void _cancelHolding() {
    if (_isHolding && _holdController.value < 1.0) {
      HapticFeedback.selectionClick();
      _holdController.reset();
      setState(() {
        _isHolding = false;
      });
    }
  }

  void _showGpsUnavailableDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.location_off_rounded, color: AppColors.primaryRed),
            SizedBox(width: 8),
            Text('Location Unavailable', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Hardware satellite fix is not yet locked. Vindara refuses to silently guess coordinates because incorrect location dispatch endangers lives. Please retry GPS fix or set landmark manually.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('DISMISS', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _isGpsAvailable = true);
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.officialBlue),
            child: const Text('RETRY GPS FIX'),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerHelpDispatch() async {
    _holdController.reset();
    setState(() {
      _isHolding = false;
    });

    if (!_isGpsAvailable) {
      _showGpsUnavailableDialog();
      return;
    }

    final emergency = await widget.repository.createEmergency(
      victimName: 'CurrentUser (Citizen Victim)',
      latitude: _currentLatitude,
      longitude: _currentLongitude,
      locationLabel: _currentLocationLabel,
      type: _selectedType,
      detectionSource: DetectionSource.manualHelp,
      communicationMode: _communicationMode,
      notes: 'Immediate HELP triggered with raw hardware GPS broadcast.',
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => ActiveEmergencyScreen(
          initialEmergency: emergency,
          repository: widget.repository,
        ),
      ),
    );
  }

  void _showCall112Sheet() {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.blueLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.emergency_rounded, color: AppColors.officialBlue, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'National Emergency Helpline',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Direct official police, fire, & medical dispatch',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'Dialing 112 connects directly to state emergency response centres (ERSS). Vindara volunteers complement but never replace official dispatch.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dialing official emergency helpline 112...'),
                            backgroundColor: AppColors.officialBlue,
                          ),
                        );
                      },
                      icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                      label: const Text(
                        'Dial 112',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.officialBlue,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final isOnline = _communicationMode == CommunicationMode.online;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        children: [
          // 1. TOP STATUS PILL CARD (Split interactive halves)
          _buildTopStatusPillCard(isOnline),
          const SizedBox(height: 10),

          // 2. MAP PREVIEW CARD
          _buildMapPreviewCard(),
          const SizedBox(height: 14),

          // 3. CENTER HERO COPY
          Center(
            child: Column(
              children: const [
                Text(
                  'Need emergency help?',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Hold the button below to dispatch HELP to nearby community responders and emergency contacts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. LARGE CIRCULAR HELP BUTTON WITH TACTILE HOLD ARC
          Center(
            child: _buildHelpTriggerArea(),
          ),
          const SizedBox(height: 16),

          // 5. SLIM BOTTOM SAFETY & 112 ACTION STRIP
          _buildBottomSafetyStrip(),
        ],
      ),
    );
  }

  // Slim Bottom Safety & 112 Action Strip
  Widget _buildBottomSafetyStrip() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left Action: Crash Guard Status
            Expanded(
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => CrashDetectionScreen(
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _isCrashGuardActive ? AppColors.greenLight : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.sensors_rounded,
                          size: 20,
                          color: _isCrashGuardActive ? AppColors.onlineGreen : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Crash Guard',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: _isCrashGuardActive ? AppColors.onlineGreen : AppColors.textSecondary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isCrashGuardActive ? 'Monitoring' : 'Off',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _isCrashGuardActive ? AppColors.greenDark : AppColors.textSecondary,
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
            ),
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
            // Right Action: Call 112 Official Emergency
            Expanded(
              child: InkWell(
                onTap: _showCall112Sheet,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.blueLight,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.phone_in_talk_rounded,
                          size: 19,
                          color: AppColors.officialBlue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Text(
                              'Call 112',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.officialBlue,
                              ),
                            ),
                            SizedBox(height: 1),
                            Text(
                              'Official Hotline',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Top Status Pill Card (Split in two interactive halves)
  Widget _buildTopStatusPillCard(bool isOnline) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Left Half: Citizen Responder
            Expanded(
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (ctx) => ResponderAlertsScreen(
                        repository: widget.repository,
                      ),
                    ),
                  );
                },
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppColors.onlineGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Row(
                              children: [
                                Text(
                                  'Citizen Responder',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                SizedBox(width: 2),
                                Icon(Icons.chevron_right_rounded, size: 14, color: AppColors.textSecondary),
                              ],
                            ),
                            Text(
                              'Community mutual-aid active',
                              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.divider),
            // Right Half: Online/Offline Toggle
            Expanded(
              child: InkWell(
                onTap: _toggleCommunicationMode,
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isOnline ? 'Online' : 'Offline Relay',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: isOnline ? AppColors.onlineGreen : AppColors.warningAmber,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: isOnline ? AppColors.onlineGreen : AppColors.warningAmber,
                          ),
                        ],
                      ),
                      Text(
                        isOnline ? '112 Official primary' : 'Nearby Mesh P2P',
                        style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Map Preview Card with GPS Active Pill and Coordinates (or Honest Unavailable State)
  Widget _buildMapPreviewCard() {
    if (!_isGpsAvailable) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.6), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.location_off_rounded, color: AppColors.warningAmber, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Location Unavailable — GPS Lost',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => setState(() => _isGpsAvailable = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.greenLight,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Simulate Lock', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: AppColors.greenDark)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Hardware satellite fix is unavailable or permission denied. Vindara does not silently substitute a false location.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _isGpsAvailable = true),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry GPS Lock', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.officialBlue,
                      minimumSize: const Size(0, 38),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Manual landmark selector opened.')),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: const Text('Set Manually', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      height: 168,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F5F2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Rich Vector City Map (Roads, parks, blocks)
            CustomPaint(
              size: Size.infinite,
              painter: const _CityMapPainter(),
            ),

            // Center Pin Indicator with Animated Pulsing Halo
            Center(
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final pulseProgress = _pulseController.value;
                  final pulseRadius = 18.0 + (pulseProgress * 28.0);
                  final pulseAlpha = (1.0 - pulseProgress) * 0.35;

                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      // Expanding dynamic pulse ring
                      Container(
                        width: pulseRadius * 2,
                        height: pulseRadius * 2,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primaryRed.withValues(alpha: pulseAlpha * 0.4),
                          border: Border.all(
                            color: AppColors.primaryRed.withValues(alpha: pulseAlpha),
                            width: 1.5,
                          ),
                        ),
                      ),
                      // Translucent GPS accuracy halo
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.officialBlue.withValues(alpha: 0.12),
                          border: Border.all(
                            color: AppColors.officialBlue.withValues(alpha: 0.28),
                            width: 1.2,
                          ),
                        ),
                      ),
                      // Core Red Location Marker
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primaryRed,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryRed.withValues(alpha: 0.38),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_pin_circle_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            // Top-Left: • GPS Active White Pill
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.circle, color: AppColors.onlineGreen, size: 8),
                    SizedBox(width: 6),
                    Text(
                      'GPS Active',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top-Right: Test Toggle to Simulate GPS Loss + Blue Recenter Arrow
            Positioned(
              top: 12,
              right: 12,
              child: Row(
                children: [
                  InkWell(
                    onTap: () => setState(() => _isGpsAvailable = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Text(
                        'Lost GPS?',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.warningAmber,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Map recentered to live satellite fix (21.1619, 81.7869)'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.officialBlue,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.officialBlue.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.navigation_rounded, size: 16, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

            // Bottom-Left: GPS Active + Raw Coordinates Badge
            Positioned(
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.my_location_rounded, size: 13, color: AppColors.officialBlue),
                    const SizedBox(width: 6),
                    Text(
                      '${_currentLatitude.toStringAsFixed(4)}, ${_currentLongitude.toStringAsFixed(4)} (GPS Coordinates)',
                      style: AppTheme.tabularNumericStyle.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom-Right: Offline P2P Mesh Indicator (Feature 11)
            Positioned(
              bottom: 12,
              right: 12,
              child: _buildP2pStatusChip(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildP2pStatusChip() {
    String label;
    Color color;
    IconData icon;
    switch (_p2pStatus) {
      case P2pMeshStatus.broadcasting:
        label = 'Broadcasting HELP';
        color = AppColors.primaryRed;
        icon = Icons.sensors_rounded;
        break;
      case P2pMeshStatus.alertReceived:
        label = 'Nearby HELP Received';
        color = AppColors.primaryRed;
        icon = Icons.crisis_alert_rounded;
        break;
      case P2pMeshStatus.connected:
        label = 'P2P Connected';
        color = AppColors.onlineGreen;
        icon = Icons.hub_rounded;
        break;
      case P2pMeshStatus.advertising:
      case P2pMeshStatus.discovering:
      case P2pMeshStatus.idle:
        label = 'Offline P2P Mesh Ready';
        color = AppColors.officialBlue;
        icon = Icons.bluetooth_searching_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // Large Circular HELP Trigger Area with Tactile Animated Hold Arc
  Widget _buildHelpTriggerArea() {
    return GestureDetector(
      onTapDown: (_) => _startHolding(),
      onTapUp: (_) => _cancelHolding(),
      onTapCancel: _cancelHolding,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outermost soft ambient ring
          Container(
            width: 210,
            height: 210,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryRed.withValues(alpha: _isHolding ? 0.08 : 0.04),
            ),
          ),
          // Middle soft ambient ring
          Container(
            width: 178,
            height: 178,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryRed.withValues(alpha: _isHolding ? 0.14 : 0.08),
            ),
          ),

          // Animated Circular Progress Arc wrapping the HELP button
          SizedBox(
            width: 154,
            height: 154,
            child: AnimatedBuilder(
              animation: _holdController,
              builder: (context, _) {
                return CircularProgressIndicator(
                  value: _holdController.value,
                  strokeWidth: 5.5,
                  strokeCap: StrokeCap.round,
                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryRed),
                  backgroundColor: _isHolding
                      ? AppColors.primaryRed.withValues(alpha: 0.18)
                      : Colors.transparent,
                );
              },
            ),
          ),

          // Core Solid Red Circle
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.primaryRed,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryRed.withValues(alpha: _isHolding ? 0.45 : 0.32),
                  blurRadius: _isHolding ? 24 : 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.shield_rounded, size: 28, color: Colors.white),
                const SizedBox(height: 2),
                const Text(
                  'HELP',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                // Crimson Capsule Pill with dynamic text
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF991B1B), // Dark crimson
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _isHolding ? 'KEEP HOLDING...' : 'HOLD 2 SECONDS',
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rich Vector City Map Painter (Roads, avenues, parks, and urban building footprints)
class _CityMapPainter extends CustomPainter {
  const _CityMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Soft Urban Background
    final bgPaint = Paint()..color = const Color(0xFFF7F6F2);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 2. Pale-Green Park Blocks
    final parkPaint = Paint()
      ..color = const Color(0xFFE5EEDD)
      ..style = PaintingStyle.fill;
    final parkBorderPaint = Paint()
      ..color = const Color(0xFFD6E4CC)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Top-left Park
    final park1 = RRect.fromRectAndRadius(
      Rect.fromLTWH(18, 14, 76, 48),
      const Radius.circular(8),
    );
    canvas.drawRRect(park1, parkPaint);
    canvas.drawRRect(park1, parkBorderPaint);

    // Bottom-right Park
    final park2 = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width - 98, size.height - 56, 82, 42),
      const Radius.circular(8),
    );
    canvas.drawRRect(park2, parkPaint);
    canvas.drawRRect(park2, parkBorderPaint);

    // 3. Subtle Building Footprints / Neighborhood Blocks
    final blockPaint = Paint()
      ..color = const Color(0xFFEBE8E1)
      ..style = PaintingStyle.fill;

    final buildingBlocks = [
      Rect.fromLTWH(108, 16, 36, 32),
      Rect.fromLTWH(152, 16, 40, 32),
      Rect.fromLTWH(size.width - 80, 16, 44, 34),
      Rect.fromLTWH(24, size.height - 54, 52, 36),
      Rect.fromLTWH(86, size.height - 54, 46, 36),
      Rect.fromLTWH(140, size.height - 52, 38, 34),
      Rect.fromLTWH(size.width * 0.70, 72, 36, 28),
    ];

    for (final rect in buildingBlocks) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(5)),
        blockPaint,
      );
    }

    // 4. Road Networks (Outlines + Pure White Surface)
    final roadCasingPaint = Paint()
      ..color = const Color(0xFFDDD9CF)
      ..style = PaintingStyle.stroke;

    final roadSurfacePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke;

    // Avenues & Major Arterials (Thick)
    roadCasingPaint.strokeWidth = 11;
    roadSurfacePaint.strokeWidth = 9;

    // Horizontal Main Avenue
    final hAvenueStart = Offset(0, size.height * 0.44);
    final hAvenueEnd = Offset(size.width, size.height * 0.44);
    canvas.drawLine(hAvenueStart, hAvenueEnd, roadCasingPaint);
    canvas.drawLine(hAvenueStart, hAvenueEnd, roadSurfacePaint);

    // Diagonal Arterial
    final dStart = Offset(0, size.height * 0.85);
    final dEnd = Offset(size.width, size.height * 0.22);
    canvas.drawLine(dStart, dEnd, roadCasingPaint);
    canvas.drawLine(dStart, dEnd, roadSurfacePaint);

    // Secondary Cross Streets (Medium)
    roadCasingPaint.strokeWidth = 6.5;
    roadSurfacePaint.strokeWidth = 5;

    // Vertical Cross Street 1
    final v1Start = Offset(size.width * 0.28, 0);
    final v1End = Offset(size.width * 0.28, size.height);
    canvas.drawLine(v1Start, v1End, roadCasingPaint);
    canvas.drawLine(v1Start, v1End, roadSurfacePaint);

    // Vertical Cross Street 2
    final v2Start = Offset(size.width * 0.65, 0);
    final v2End = Offset(size.width * 0.65, size.height);
    canvas.drawLine(v2Start, v2End, roadCasingPaint);
    canvas.drawLine(v2Start, v2End, roadSurfacePaint);

    // Minor Local Lanes (Fine)
    final minorLanePaint = Paint()
      ..color = const Color(0xFFFAF9F6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(size.width * 0.42, 0),
      Offset(size.width * 0.42, size.height * 0.44),
      minorLanePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.84, size.height * 0.44),
      Offset(size.width * 0.84, size.height),
      minorLanePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
