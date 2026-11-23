import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';
import '../data/mock_emergency_repository.dart';

/// Dedicated Full-Page Edit Profile & Medical ID Screen
class EditProfileScreen extends StatefulWidget {
  final EmergencyRepository repository;

  const EditProfileScreen({
    super.key,
    required this.repository,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _notesController;
  late TextEditingController _allergiesController;

  String _selectedBloodGroup = 'A+';
  String _badgeLevel = 'Citizen Volunteer';
  bool _isLoading = true;

  final List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _notesController = TextEditingController();
    _allergiesController = TextEditingController();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final responder = await widget.repository.getCurrentUserResponder();
    setState(() {
      _nameController.text = responder.name;
      _phoneController.text = responder.phoneNumber ?? '6265915661';
      _selectedBloodGroup = responder.bloodGroup;
      _badgeLevel = responder.badgeLevel;
      _notesController.text = responder.emergencyNotes ?? 'Carries basic first aid kit; two-wheeler available.';
      _allergiesController.text = responder.knownAllergies ?? 'None reported';
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    _allergiesController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    HapticFeedback.mediumImpact();
    await widget.repository.updateCurrentUserProfile(
      name: _nameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
      bloodGroup: _selectedBloodGroup,
      badgeLevel: _badgeLevel,
      emergencyNotes: _notesController.text.trim(),
      knownAllergies: _allergiesController.text.trim(),
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile & Medical ID updated successfully.'),
        backgroundColor: AppColors.onlineGreen,
        duration: Duration(seconds: 2),
      ),
    );
    Navigator.of(context).pop(true);
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
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleSpacing: 0,
        title: const Text(
          'Edit Profile & Medical ID',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryRed))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                children: [
                  // 1. Personal & Contact Card
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'PERSONAL INFORMATION',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEAE8E3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Full Name', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            hintText: 'Enter full name',
                            prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                            ),
                          ),
                          validator: (val) => (val == null || val.trim().isEmpty) ? 'Please enter name' : null,
                        ),
                        const SizedBox(height: 16),
                        const Text('Phone Number (SMS Alert Dispatch)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            hintText: '10-digit mobile number',
                            prefixIcon: const Icon(Icons.phone_outlined, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                            ),
                          ),
                          validator: (val) => (val == null || val.trim().length < 8) ? 'Enter valid phone number' : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 2. Emergency Medical ID Card
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'EMERGENCY MEDICAL ID',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEAE8E3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Blood Group', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedBloodGroup,
                          items: _bloodGroups.map((group) {
                            return DropdownMenuItem(
                              value: group,
                              child: Row(
                                children: [
                                  const Icon(Icons.water_drop_rounded, size: 18, color: AppColors.primaryRed),
                                  const SizedBox(width: 8),
                                  Text(group, style: const TextStyle(fontWeight: FontWeight.w700)),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedBloodGroup = val);
                          },
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Known Medical Allergies', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _allergiesController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Penicillin, Peanuts (or None reported)',
                            prefixIcon: const Icon(Icons.healing_outlined, size: 20),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('First Responder Notes', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            hintText: 'e.g. Carries trauma bandages, two-wheeler available',
                            contentPadding: const EdgeInsets.all(12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 3. Community Role Designation
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'COMMUNITY VOLUNTEER ROLE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFEAE8E3)),
                    ),
                    child: Column(
                      children: [
                        _buildRoleOption(
                          title: 'Citizen Volunteer',
                          subtitle: 'Local civic mutual-aid assistance; no professional medical claims.',
                          value: 'Citizen Volunteer',
                        ),
                        const Divider(height: 16, color: Color(0xFFF1F0EC)),
                        _buildRoleOption(
                          title: 'Verified Responder (Trained)',
                          subtitle: 'Trained citizen volunteer available for nearby primary on-scene assistance.',
                          value: 'Verified Responder',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 4. Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save Changes',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRoleOption({
    required String title,
    required String subtitle,
    required String value,
  }) {
    final isSelected = _badgeLevel == value;

    return InkWell(
      onTap: () => setState(() => _badgeLevel = value),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: isSelected ? AppColors.primaryRed : const Color(0xFF9CA3AF),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
