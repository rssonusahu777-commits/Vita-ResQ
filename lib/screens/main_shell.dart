import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/emergency.dart';
import '../models/responder.dart';
import 'auth_screen.dart';
import 'certificates_screen.dart';
import 'crash_countdown_screen.dart';
import 'crash_detection_screen.dart';
import 'emergency_contacts_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';
import 'sos_hub_screen.dart';

/// Clean Navigation Chrome Shell for Vindara
class MainShell extends StatefulWidget {
  final EmergencyRepository repository;

  const MainShell({
    super.key,
    required this.repository,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  void _launchCrashSimulation() {
    Navigator.of(context).push<Emergency?>(
      MaterialPageRoute(
        builder: (ctx) => CrashCountdownScreen(
          repository: widget.repository,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      SosHubScreen(repository: widget.repository),
      HistoryScreen(repository: widget.repository),
      ProfileScreen(
        repository: widget.repository,
        onBackToHome: () => setState(() => _currentIndex = 0),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _currentIndex == 2
          ? null
          : AppBar(
              backgroundColor: AppColors.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu_rounded, color: AppColors.textPrimary, size: 26),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
              title: const Text(
                'Vindara',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
      drawer: _buildNavigationDrawer(context),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: SafeArea(
          child: NavigationBar(
            selectedIndex: _currentIndex,
            backgroundColor: Colors.white,
            indicatorColor: AppColors.primaryRedLight,
            elevation: 0,
            height: 65,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined, color: AppColors.textSecondary),
                selectedIcon: Icon(Icons.home_rounded, color: AppColors.primaryRed),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_rounded, color: AppColors.textSecondary),
                selectedIcon: Icon(Icons.history_rounded, color: AppColors.primaryRed),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded, color: AppColors.textSecondary),
                selectedIcon: Icon(Icons.person_rounded, color: AppColors.primaryRed),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            // 1. DRAWER HEADER (Warm-Ivory #FAF9F6 top area)
            FutureBuilder<Responder>(
              future: widget.repository.getCurrentUserResponder(),
              builder: (context, snapshot) {
                final responder = snapshot.data;
                final name = responder?.name ?? 'ayush patnayak';
                final role = responder?.badgeLevel ?? 'Citizen Volunteer';

                // Initials from name
                final parts = name.trim().split(RegExp(r'\s+'));
                final initials = parts.length > 1
                    ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
                    : (parts.isNotEmpty && parts.first.isNotEmpty ? parts.first[0].toUpperCase() : 'AP');

                return Container(
                  color: const Color(0xFFFAF9F6),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                  child: Row(
                    children: [
                      // Solid dark charcoal/navy circular avatar (#1E293B, 50px)
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1E293B),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              role,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1, thickness: 1, color: Color(0xFFEAE8E3)),

            // 2. GROUPED SECTIONS WITH HAIRLINE DIVIDERS (#FFFFFF drawer surface)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 6),
                children: [
                  _buildSectionHeader('EMERGENCY'),
                  _buildDrawerRow(
                    icon: Icons.contact_emergency_outlined,
                    label: 'Emergency Contacts',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => const EmergencyContactsScreen(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 16, thickness: 1, color: Color(0xFFF1F0EC)),

                  _buildSectionHeader('SAFETY'),
                  _buildDrawerRow(
                    icon: Icons.car_crash_outlined,
                    label: 'Crash Detection',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => CrashDetectionScreen(
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 16, thickness: 1, color: Color(0xFFF1F0EC)),

                  _buildSectionHeader('IMPACT'),
                  _buildDrawerRow(
                    icon: Icons.military_tech_outlined,
                    label: 'Impact & Rewards',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => RewardsScreen(
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildDrawerRow(
                    icon: Icons.verified_outlined,
                    label: 'Certificates',
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (ctx) => CertificatesScreen(
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 16, thickness: 1, color: Color(0xFFF1F0EC)),

                  _buildSectionHeader('DEMO / JUDGE'),
                  _buildDrawerRow(
                    icon: Icons.science_outlined,
                    label: 'Accident Detection Demo',
                    onTap: () {
                      Navigator.of(context).pop();
                      _launchCrashSimulation();
                    },
                  ),
                ],
              ),
            ),

            // 3. BOTTOM ACCOUNT FOOTER
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'ACCOUNT',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (ctx) => AuthScreen(
                            repository: widget.repository,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFECACA), width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.logout_rounded, size: 18, color: Color(0xFFDC2626)),
                          SizedBox(width: 8),
                          Text(
                            'Sign Out',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'Vindara is a community emergency-response platform and does not replace official emergency services.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6B7280),
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  Widget _buildDrawerRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF374151), size: 20),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Color(0xFF111827),
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 18, color: Color(0xFF9CA3AF)),
      onTap: onTap,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
    );
  }
}
