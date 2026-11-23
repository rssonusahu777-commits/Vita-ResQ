import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../models/responder.dart';
import '../services/local_emergency_store.dart';
import 'edit_profile_screen.dart';
import 'emergency_contacts_screen.dart';
import 'notifications_screen.dart';
import 'rewards_screen.dart';

/// Clean, Modern Profile Screen Matching Reference Design
class ProfileScreen extends StatefulWidget {
  final EmergencyRepository repository;
  final VoidCallback? onBackToHome;

  const ProfileScreen({
    super.key,
    required this.repository,
    this.onBackToHome,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _spokenAlertsEnabled = true;
  bool _cameraMicOptedIn = false;

  User? _safeGetCurrentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _cameraMicOptedIn = LocalEmergencyStore().isCameraMicOptedIn();
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      widget.onBackToHome?.call();
    }
  }

  Future<void> _openEditProfile() async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => EditProfileScreen(
          repository: widget.repository,
        ),
      ),
    );
    if (updated == true && mounted) {
      setState(() {});
    }
  }

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
          onPressed: _handleBack,
        ),
        titleSpacing: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: FutureBuilder<Responder>(
        future: widget.repository.getCurrentUserResponder(),
        builder: (context, snapshot) {
          final currentFirebaseUser = _safeGetCurrentUser();
          final responder = snapshot.data;
          final displayName = (responder != null && responder.name.isNotEmpty && responder.name != 'ayush patnayak')
              ? responder.name
              : (currentFirebaseUser?.displayName?.isNotEmpty == true
                  ? currentFirebaseUser!.displayName!
                  : 'Citizen Volunteer');
          final phone = (responder != null && responder.phoneNumber?.isNotEmpty == true && responder.phoneNumber != '6265915661')
              ? responder.phoneNumber!
              : (currentFirebaseUser?.phoneNumber?.isNotEmpty == true
                  ? currentFirebaseUser!.phoneNumber!
                  : 'Not configured');
          final bloodGroup = responder?.bloodGroup ?? 'Not specified';
          final badge = responder?.badgeLevel ?? 'Citizen Volunteer';
          final userEmail = currentFirebaseUser?.email ?? 'Emergency Access (Offline Mode)';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              // 1. Centered Circular Avatar + User Header
              Center(
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEFF2F6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.person_rounded,
                            size: 52,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: _openEditProfile,
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: Color(0xFF374151),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      userEmail,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF1E293B)),
                          const SizedBox(width: 6),
                          Text(
                            badge,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1E293B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // 2. ACCOUNT Section
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'ACCOUNT',
                  style: TextStyle(
                    fontSize: 11.5,
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildProfileItem(
                      icon: Icons.person_outline_rounded,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      title: 'Personal Information',
                      subtitle: '$phone • Blood: $bloodGroup',
                      onTap: _openEditProfile,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    _buildProfileItem(
                      icon: Icons.phone_outlined,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      title: 'Phone Number',
                      subtitle: phone,
                      onTap: _openEditProfile,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    _buildProfileItem(
                      icon: Icons.water_drop_outlined,
                      iconColor: const Color(0xFFDC2626),
                      iconBgColor: const Color(0xFFFEE2E2),
                      title: 'Blood Group',
                      subtitle: '$bloodGroup (Medical ID)',
                      onTap: _openEditProfile,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    _buildProfileItem(
                      icon: Icons.badge_outlined,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      title: 'Edit Profile & Role',
                      subtitle: 'Update phone number, blood group, or volunteer role',
                      onTap: _openEditProfile,
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    _buildProfileItem(
                      icon: Icons.contact_phone_outlined,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      title: 'Emergency Contacts (Auto-SMS)',
                      subtitle: '3 Configured trusted contacts',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => const EmergencyContactsScreen(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    _buildProfileItem(
                      icon: Icons.volunteer_activism_outlined,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      title: 'My Impact & Activity',
                      subtitle: '${responder?.completedResponses ?? 0} Assists Logged • Community Trust',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => RewardsScreen(repository: widget.repository),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                    _buildProfileItem(
                      icon: Icons.notifications_none_rounded,
                      iconColor: const Color(0xFF1E293B),
                      iconBgColor: const Color(0xFFF1F5F9),
                      title: 'Emergency Notifications History',
                      subtitle: 'Recent broadcast logs & dispatch alerts',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (ctx) => NotificationsScreen(repository: widget.repository),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 3. EMERGENCY NOTIFICATIONS Section
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'EMERGENCY NOTIFICATIONS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEAE8E3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.record_voice_over_outlined,
                        color: Color(0xFF2563EB),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Spoken Emergency Alerts',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Spoken audio alert enabled for incoming emergencies',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF6B7280),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _spokenAlertsEnabled,
                      activeTrackColor: const Color(0xFF3B82F6),
                      activeThumbColor: Colors.white,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: const Color(0xFFE5E7EB),
                      onChanged: (val) {
                        setState(() => _spokenAlertsEnabled = val);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // 4. EMERGENCY AI & SENSOR PERMISSIONS Section
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  'EMERGENCY AI & SENSOR ASSIST',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEAE8E3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Color(0xFF16A34A),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Camera & Mic Scene Assist',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Non-blocking 2.5s assessment after HELP to match skilled responders. Buffers are wiped instantly.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF6B7280),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: _cameraMicOptedIn,
                      activeTrackColor: const Color(0xFF16A34A),
                      activeThumbColor: Colors.white,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: const Color(0xFFE5E7EB),
                      onChanged: (val) async {
                        await LocalEmergencyStore().setCameraMicOptIn(val);
                        if (!context.mounted) return;
                        setState(() => _cameraMicOptedIn = val);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              val
                                  ? 'Emergency Camera & Mic Scene Assist enabled.'
                                  : 'Emergency Camera & Mic Scene Assist disabled.',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              if (currentFirebaseUser != null) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      await FirebaseAuth.instance.signOut();
                    } catch (_) {}
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Signed out successfully.')),
                      );
                      setState(() {});
                    }
                  },
                  icon: const Icon(Icons.logout_rounded, color: AppColors.primaryRed),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(
                      color: AppColors.primaryRed,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildProfileItem({
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF9CA3AF),
            ),
          ],
        ),
      ),
    );
  }
}
