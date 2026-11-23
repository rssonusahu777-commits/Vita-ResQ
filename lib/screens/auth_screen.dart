import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import 'main_shell.dart';

/// Onboarding & Authentication Flow for Vindara
class AuthScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const AuthScreen({
    super.key,
    required this.repository,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isPasswordVisible = false;
  bool _isResponderRoleEnabled = true;

  // Contextual Permission Toggles
  bool _permLocation = true;
  bool _permNotifications = true;
  bool _permMotion = true;
  bool _permNearby = true;

  final _identifierController = TextEditingController(text: 'vikram.rathore@vindara.org');
  final _passwordController = TextEditingController(text: '••••••••••••');

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    if (_identifierController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid phone number or email.'),
          backgroundColor: AppColors.primaryRed,
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (ctx) => MainShell(repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            if (Navigator.of(context).canPop())
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            // Center Logo & Positioning
            Center(
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppColors.primaryRed,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryRed.withValues(alpha: 0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.shield_rounded, size: 32, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Vindara',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Community emergency coordination alongside official emergency services',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Login / Register Segmented Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Toggle header
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        _buildSegmentTab('Sign In', _isLogin, () => setState(() => _isLogin = true)),
                        _buildSegmentTab('Register', !_isLogin, () => setState(() => _isLogin = false)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Phone or Email Input
                  const Text(
                    'Phone Number or Email',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _identifierController,
                    decoration: InputDecoration(
                      hintText: 'Enter phone or email address',
                      prefixIcon: const Icon(Icons.account_circle_outlined, size: 20, color: AppColors.textSecondary),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Password Input with Visibility Toggle
                  const Text(
                    'Password',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      hintText: 'Enter account password',
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: AppColors.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                      filled: true,
                      fillColor: AppColors.background,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Continue Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _handleContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        _isLogin ? 'Sign In & Enter Vindara' : 'Create Volunteer Account',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Role & Contextual Permissions Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
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
                          Icon(Icons.volunteer_activism_rounded, color: AppColors.onlineGreen, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Participate as a Responder',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Switch(
                        value: _isResponderRoleEnabled,
                        activeThumbColor: AppColors.onlineGreen,
                        onChanged: (val) => setState(() => _isResponderRoleEnabled = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Volunteer community assistance — does not certify professional medical credentials.',
                    style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.35),
                  ),
                  const Divider(height: 24),

                  const Text(
                    'CONTEXTUAL PERMISSION TRANSPARENCY',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: AppColors.textTertiary),
                  ),
                  const SizedBox(height: 10),

                  _buildPermissionRow(
                    icon: Icons.location_on_outlined,
                    title: 'Location',
                    reason: 'Transmits exact raw GPS coordinates for incident dispatch & nearby routing.',
                    value: _permLocation,
                    onChanged: (v) => setState(() => _permLocation = v),
                  ),
                  const SizedBox(height: 10),
                  _buildPermissionRow(
                    icon: Icons.notifications_active_outlined,
                    title: 'Notifications',
                    reason: 'Delivers high-priority nearby emergency broadcasts.',
                    value: _permNotifications,
                    onChanged: (v) => setState(() => _permNotifications = v),
                  ),
                  const SizedBox(height: 10),
                  _buildPermissionRow(
                    icon: Icons.sensors_outlined,
                    title: 'Motion Sensors',
                    reason: 'Detects sudden vehicular deceleration patterns for possible-crash verification.',
                    value: _permMotion,
                    onChanged: (v) => setState(() => _permMotion = v),
                  ),
                  const SizedBox(height: 10),
                  _buildPermissionRow(
                    icon: Icons.nearby_error_outlined,
                    title: 'Nearby Devices',
                    reason: 'Enables direct Bluetooth & Wi-Fi Direct peer mesh relay when cell towers fail.',
                    value: _permNearby,
                    onChanged: (v) => setState(() => _permNearby = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentTab(String title, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionRow({
    required IconData icon,
    required String title,
    required String reason,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: value ? AppColors.officialBlue : AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text(
                reason,
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.officialBlue,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

