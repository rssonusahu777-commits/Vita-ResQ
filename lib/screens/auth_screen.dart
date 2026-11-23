import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';
import '../services/local_emergency_store.dart';
import '../services/multimodal_severity_service.dart';
import 'main_shell.dart';

/// Onboarding & Authentication Flow for Vindara
class AuthScreen extends StatefulWidget {
  final EmergencyRepository repository;
  final VoidCallback? onOfflineAccess;

  const AuthScreen({
    super.key,
    required this.repository,
    this.onOfflineAccess,
  });

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLogin = true;
  bool _isPasswordVisible = false;
  bool _isResponderRoleEnabled = true;
  bool _isLoading = false;

  // Contextual Permission Toggles
  bool _permLocation = true;
  bool _permNotifications = true;
  bool _permMotion = true;
  bool _permNearby = true;
  bool _permCameraMic = false;

  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkExistingCameraMicOptIn();
  }

  Future<void> _checkExistingCameraMicOptIn() async {
    final store = LocalEmergencyStore();
    try {
      await store.init();
      final opted = store.isCameraMicOptedIn();
      if (mounted) {
        setState(() => _permCameraMic = opted);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    final email = _identifierController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty) {
      _showError('Please enter your email address.');
      return;
    }
    if (!email.contains('@')) {
      _showError('Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (Firebase.apps.isNotEmpty) {
        if (_isLogin) {
          // Firebase Sign In
          await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          // Firebase Create Account
          final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
            email: email,
            password: password,
          );
          final user = credential.user;
          if (user != null) {
            // Safe initial profile in Firestore with 0 points
            try {
              await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
                'uid': user.uid,
                'displayName': email.split('@').first,
                'isVerifiedResponder': false,
                'isAvailable': _isResponderRoleEnabled,
                'reputationPoints': 0,
                'successfulAssistanceCount': 0,
                'responseHistoryCount': 0,
                'badges': <String>[],
                'fcmToken': null,
                'createdAt': FieldValue.serverTimestamp(),
              });
            } catch (e) {
              debugPrint('Firestore initial profile creation warning: $e');
            }
          }
        }

        // Update local responder state
        await widget.repository.updateCurrentUserProfile(
          name: email.split('@').first,
          badgeLevel: 'Citizen Volunteer',
        );
        await widget.repository.updateCurrentUserAvailability(_isResponderRoleEnabled);
      } else {
        // Local mode fallback
        await widget.repository.updateCurrentUserProfile(
          name: email.split('@').first,
          badgeLevel: 'Citizen Volunteer',
        );
      }

      if (!mounted) return;

      // Ask for Camera + Microphone Opt-In if not yet chosen
      await _promptCameraMicOptInIfNeeded();

      if (!mounted) return;
      _navigateToHome();
    } on FirebaseAuthException catch (e) {
      _showError(_getFriendlyErrorMessage(e));
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _continueOfflineAccess() {
    if (widget.onOfflineAccess != null) {
      widget.onOfflineAccess!();
    } else {
      _navigateToHome();
    }
  }

  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (ctx) => MainShell(repository: widget.repository),
      ),
    );
  }

  /// One-time Camera + Microphone opt-in dialog / bottom sheet
  Future<void> _promptCameraMicOptInIfNeeded() async {
    final store = LocalEmergencyStore();
    try {
      await store.init();
      if (store.isCameraMicOptedIn()) return; // Already opted in
    } catch (_) {}

    if (!mounted) return;

    final bool? optedIn = await showModalBottomSheet<bool>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.blueLight,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.emergency_recording_rounded, color: AppColors.officialBlue, size: 26),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emergency Condition Matching',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Optional Camera + Mic Analysis',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Text(
                  'When you trigger HELP, Vindara can run a brief ~3s background visual & acoustic check to estimate apparent severity and recommend responders with matched skills (CPR, Trauma, Rescue).\n\n'
                  '• Ephemeral memory only — immediately deleted after analysis.\n'
                  '• Zero raw media stored in cloud feeds or push alerts.\n'
                  '• Apparent situation estimation only (never a medical diagnosis).',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.45),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Skip for Now',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.officialBlue,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text(
                        'Enable Now',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.white),
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

    if (optedIn == true) {
      final granted = await MultimodalSeverityService.requestCameraAndMicPermissions();
      final store = LocalEmergencyStore();
      try {
        await store.init();
        await store.setCameraMicOptIn(granted);
      } catch (_) {}
      setState(() => _permCameraMic = granted);
    } else {
      final store = LocalEmergencyStore();
      try {
        await store.init();
        await store.setCameraMicOptIn(false);
      } catch (_) {}
      setState(() => _permCameraMic = false);
    }
  }

  String _getFriendlyErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-api-key':
      case 'api-key-not-valid':
        return 'Firebase API Key is invalid or restricted. Please verify configuration.';
      case 'user-not-found':
        return 'No account found with this email. Please register.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account with this email already exists. Please Sign In.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'network-request-failed':
        return 'Network connection issue. Tap "Continue Offline" below for emergency access.';
      default:
        return e.message ?? 'Authentication error occurred.';
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.primaryRed,
        duration: const Duration(seconds: 4),
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
            const SizedBox(height: 20),

            // Emergency Access Bypass Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.flash_on_rounded, color: Colors.amber.shade900, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'In an emergency? Skip login for 112 dialing & offline peer mesh.',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _continueOfflineAccess,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.amber.shade900,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('Offline Access', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

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
                    'Email Address',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _identifierController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Enter your email address',
                      prefixIcon: const Icon(Icons.email_outlined, size: 20, color: AppColors.textSecondary),
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
                      hintText: 'Enter account password (min 6 chars)',
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
                      onPressed: _isLoading ? null : _handleContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
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
                      const Row(
                        children: [
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
                  const SizedBox(height: 10),
                  _buildPermissionRow(
                    icon: Icons.emergency_recording_outlined,
                    title: 'Camera & Microphone (AI Opt-In)',
                    reason: 'Enables non-blocking post-HELP condition and responder skill matching.',
                    value: _permCameraMic,
                    onChanged: (v) async {
                      if (v) {
                        final granted = await MultimodalSeverityService.requestCameraAndMicPermissions();
                        final store = LocalEmergencyStore();
                        try {
                          await store.init();
                          await store.setCameraMicOptIn(granted);
                        } catch (_) {}
                        setState(() => _permCameraMic = granted);
                      } else {
                        final store = LocalEmergencyStore();
                        try {
                          await store.init();
                          await store.setCameraMicOptIn(false);
                        } catch (_) {}
                        setState(() => _permCameraMic = false);
                      }
                    },
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
