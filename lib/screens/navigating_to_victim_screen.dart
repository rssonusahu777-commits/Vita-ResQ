import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';

/// Clean, Modern Navigating to Victim Screen (Matching Reference Screen)
class NavigatingToVictimScreen extends StatefulWidget {
  final Emergency emergency;
  final bool isPrimary;
  final EmergencyRepository repository;

  const NavigatingToVictimScreen({
    super.key,
    required this.emergency,
    required this.isPrimary,
    required this.repository,
  });

  @override
  State<NavigatingToVictimScreen> createState() => _NavigatingToVictimScreenState();
}

class _NavigatingToVictimScreenState extends State<NavigatingToVictimScreen> {
  late Emergency _currentEmergency;

  @override
  void initState() {
    super.initState();
    _currentEmergency = widget.emergency;
  }

  // Exact Call Victim Dialog from Reference
  void _showCallVictimDialog() {
    final victimName = _currentEmergency.victimName;
    final victimPhone = _currentEmergency.displayVictimPhone;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Blue circle with phone icon
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.blueLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.call, color: AppColors.officialBlue, size: 28),
            ),
            const SizedBox(height: 16),

            // Victim name
            Text(
              victimName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),

            // "Victim Phone Number:"
            const Text(
              'Victim Phone Number:',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),

            // Bold Blue Phone Number
            Text(
              victimPhone,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.officialBlue,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'CLOSE',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.officialBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Report Problem Dialog
  void _showReportProblemDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Report Navigation Obstruction', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Encountering heavy traffic or road closure? You can request instant failover to the Standby Responder so the victim gets help without delay.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CONTINUE ROUTE', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Standby failover alert dispatched to backup responders.'),
                  backgroundColor: AppColors.warningAmber,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warningAmber),
            child: const Text('FAILOVER TO STANDBY'),
          ),
        ],
      ),
    );
  }

  // I Have Arrived Action
  Future<void> _handleArrived() async {
    await widget.repository.advanceEmergencyStatus(_currentEmergency.id, EmergencyStatus.inProgress);

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.verified_rounded, color: AppColors.onlineGreen, size: 24),
            SizedBox(width: 10),
            Text('On Scene with Victim', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'You have marked arrival. Status updated to On-Scene in real-time dispatch network.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.35),
            ),
            SizedBox(height: 10),
            Text(
              '+50 Community Volunteer Points awarded.',
              style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.onlineGreen),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.onlineGreen),
            child: const Text('RETURN TO QUEUE'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 1. TOP TURN-BY-TURN HEADER BAR
            _buildNavigationHeader(),

            // 2. MAP SPLIT VIEW WITH ROUTE & GPS PILL
            _buildMapSplitView(),

            // 3. BOTTOM WHITE SHEET
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 10,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                  children: [
                    // Top Pills Row
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primaryRedLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'YOU ARE RESPONDING',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                              color: AppColors.primaryRed,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: widget.isPrimary ? AppColors.officialBlue : AppColors.warningAmber,
                            ),
                          ),
                          child: Text(
                            widget.isPrimary ? 'PRIMARY RESPONDER' : 'STANDBY RESPONDER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: widget.isPrimary ? AppColors.officialBlue : AppColors.warningAmber,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Heading + Subtitle
                    const Text(
                      'Navigating to Victim',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Keep app active for live routing and victim proximity updates.',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 16),

                    // Nearby Hospitals (Standby) Card
                    _buildNearbyHospitalsCard(),
                    const SizedBox(height: 16),

                    // Two Side-by-Side Action Buttons (Call & Report Problem)
                    Row(
                      children: [
                        // Call Victim Button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showCallVictimDialog,
                            icon: const Icon(Icons.call, size: 16, color: AppColors.officialBlue),
                            label: const Text(
                              'Call',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: AppColors.border, width: 1.2),
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Report Problem Button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _showReportProblemDialog,
                            icon: const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warningAmber),
                            label: const Text(
                              'Report Problem',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              side: const BorderSide(color: AppColors.border, width: 1.2),
                              minimumSize: const Size(0, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Bottom Full-Width "I HAVE ARRIVED" Button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _handleArrived,
                        icon: const Icon(Icons.check_rounded, size: 20, color: Colors.white),
                        label: const Text(
                          'I HAVE ARRIVED',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669), // Emerald Green
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Top Turn-by-Turn Navigation Header Bar
  Widget _buildNavigationHeader() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Text(
                'Navigating to Victim',
                style: TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppColors.blueLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.turn_slight_right_rounded, color: AppColors.officialBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Proceed to emergency location',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '${_currentEmergency.typeDisplayName.toUpperCase()} • Victim Location',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: const [
                  Text(
                    '1 min',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.onlineGreen,
                    ),
                  ),
                  Text(
                    '86 m',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Map Split View with Route preview and GPS pill
  Widget _buildMapSplitView() {
    return Container(
      height: 200,
      width: double.infinity,
      color: const Color(0xFFF1F3F5),
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _RouteMapPainter(),
          ),

          // Primary Responder Pin
          Positioned(
            left: 70,
            bottom: 60,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.onlineGreen,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('PRIMARY', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.onlineGreen,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.navigation_rounded, color: Colors.white, size: 14),
                ),
              ],
            ),
          ),

          // Victim Pin
          Positioned(
            right: 80,
            top: 40,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('VICTIM', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
                const SizedBox(height: 2),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.primaryRed,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.person_pin_circle_rounded, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),

          // Floating Recenter Button
          Positioned(
            right: 14,
            bottom: 14,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 6),
                ],
              ),
              child: const Icon(Icons.my_location_rounded, size: 18, color: AppColors.officialBlue),
            ),
          ),

          // Offline-Safe GPS Coordinate Pill
          Positioned(
            left: 14,
            bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed_rounded, size: 12, color: AppColors.officialBlue),
                  const SizedBox(width: 5),
                  Text(
                    '${_currentEmergency.latitude.toStringAsFixed(4)}, ${_currentEmergency.longitude.toStringAsFixed(4)} (GPS Active)',
                    style: AppTheme.tabularNumericStyle.copyWith(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
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

  // Nearby Hospitals (Standby) Card
  Widget _buildNearbyHospitalsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.add_box_rounded, color: AppColors.primaryRed, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Nearby Hospitals (Standby)',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.blueLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  '4 Found',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.officialBlue),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Unverified directory data — confirm availability before transport.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Hospital routing will become active after reaching victim.',
            style: TextStyle(fontSize: 10.5, color: AppColors.textTertiary),
          ),
          const Divider(height: 16),
          _buildHospitalRow('District Civil & Trauma Hospital', '957 m'),
          const Divider(height: 14),
          _buildHospitalRow('City Care Multi-Specialty Hospital', '1.5 km'),
        ],
      ),
    );
  }

  Widget _buildHospitalRow(String name, String distance) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            name,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ),
        Text(
          distance,
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _RouteMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintRoad = Paint()
      ..color = Colors.white
      ..strokeWidth = 10
      ..style = PaintingStyle.stroke;

    final paintRoute = Paint()
      ..color = AppColors.officialBlue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(size.width * 0.25, size.height * 0.7)
      ..lineTo(size.width * 0.45, size.height * 0.7)
      ..lineTo(size.width * 0.45, size.height * 0.25)
      ..lineTo(size.width * 0.75, size.height * 0.25);

    canvas.drawPath(path, paintRoad);
    canvas.drawPath(path, paintRoute);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

