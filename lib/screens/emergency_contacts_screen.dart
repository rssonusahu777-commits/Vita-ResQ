import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class EmergencyContact {
  final String id;
  final String name;
  final String relationship;
  final String phoneNumber;
  final bool autoSmsEnabled;

  const EmergencyContact({
    required this.id,
    required this.name,
    required this.relationship,
    required this.phoneNumber,
    this.autoSmsEnabled = true,
  });

  EmergencyContact copyWith({
    String? id,
    String? name,
    String? relationship,
    String? phoneNumber,
    bool? autoSmsEnabled,
  }) {
    return EmergencyContact(
      id: id ?? this.id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      autoSmsEnabled: autoSmsEnabled ?? this.autoSmsEnabled,
    );
  }
}

/// Emergency Contacts (Auto-SMS) Management Screen
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});

  @override
  State<EmergencyContactsScreen> createState() => _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  final List<EmergencyContact> _contacts = [
    const EmergencyContact(
      id: 'CNT-01',
      name: 'Ramesh Rathore',
      relationship: 'Father',
      phoneNumber: '+91 98765 11223',
      autoSmsEnabled: true,
    ),
    const EmergencyContact(
      id: 'CNT-02',
      name: 'Dr. Priya Verma',
      relationship: 'Primary Physician',
      phoneNumber: '+91 98111 22334',
      autoSmsEnabled: true,
    ),
    const EmergencyContact(
      id: 'CNT-03',
      name: 'Sunita Rathore',
      relationship: 'Sister',
      phoneNumber: '+91 98222 33445',
      autoSmsEnabled: false,
    ),
  ];

  void _showAddContactSheet() {
    final nameCtrl = TextEditingController();
    final relationCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Trusted Contact',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Contact Full Name',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: relationCtrl,
              decoration: InputDecoration(
                labelText: 'Relationship (e.g. Spouse, Parent, Friend)',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Mobile Phone Number (+91...)',
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().isNotEmpty) {
                    setState(() {
                      _contacts.add(
                        EmergencyContact(
                          id: 'CNT-${DateTime.now().millisecondsSinceEpoch}',
                          name: nameCtrl.text.trim(),
                          relationship: relationCtrl.text.trim().isEmpty ? 'Contact' : relationCtrl.text.trim(),
                          phoneNumber: phoneCtrl.text.trim(),
                          autoSmsEnabled: true,
                        ),
                      );
                    });
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Contact added for auto-fallback alerts.')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.officialBlue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save Trusted Contact', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Emergency Contacts (Auto-SMS)',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
        children: [
          // Fallback Info Banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.blueLight,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.officialBlue.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.sms_outlined, size: 20, color: AppColors.officialBlue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Fallback Protocol: If community responder matching takes longer than 90 seconds or connectivity is intermittent, Vindara auto-dispatches SMS & WhatsApp location coordinates to these trusted contacts.',
                    style: TextStyle(fontSize: 12, color: AppColors.officialBlue, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Add Contact Button
          OutlinedButton.icon(
            onPressed: _showAddContactSheet,
            icon: const Icon(Icons.person_add_outlined, size: 18, color: AppColors.officialBlue),
            label: const Text(
              'Add Emergency Contact',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.officialBlue),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: AppColors.officialBlue),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Contacts List
          ..._contacts.asMap().entries.map((entry) {
            final index = entry.key;
            final contact = entry.value;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.blueLight,
                    child: Text(
                      contact.name.substring(0, 1),
                      style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.officialBlue, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              contact.name,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceMuted,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                contact.relationship,
                                style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          contact.phoneNumber,
                          style: AppTheme.tabularNumericStyle.copyWith(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Switch(
                        value: contact.autoSmsEnabled,
                        activeThumbColor: AppColors.onlineGreen,
                        onChanged: (val) {
                          setState(() {
                            _contacts[index] = contact.copyWith(autoSmsEnabled: val);
                          });
                        },
                      ),
                      Text(
                        contact.autoSmsEnabled ? 'AUTO-SMS' : 'OFF',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: contact.autoSmsEnabled ? AppColors.onlineGreen : AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

