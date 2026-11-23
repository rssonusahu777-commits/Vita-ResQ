import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../models/helpline_entry.dart';
import '../../services/helpline_call_service.dart';

/// Dedicated, searchable, bilingual Helpline Directory screen for Vita ResQ.
///
/// Principles:
/// 1. 100% offline access using verified, locally defined structured data.
/// 2. Prominent placement for 112 (India's single unified emergency response number).
/// 3. Categorized under: Emergency Services, Women & Children, Cybercrime, Senior Citizens, Other Assistance.
/// 4. Safe calling: Launches native dialer (`LaunchMode.externalApplication`) without auto-dialing or requiring `CALL_PHONE` permission.
/// 5. Copy-to-clipboard fallback and official government source verification for every entry.
class HelplineDirectoryScreen extends StatefulWidget {
  final HelplineCallService? callService;
  final List<HelplineEntry>? customHelplines;

  const HelplineDirectoryScreen({
    super.key,
    this.callService,
    this.customHelplines,
  });

  @override
  State<HelplineDirectoryScreen> createState() => _HelplineDirectoryScreenState();
}

class _HelplineDirectoryScreenState extends State<HelplineDirectoryScreen> {
  late final HelplineCallService _callService;
  late final List<HelplineEntry> _helplines;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  String _searchQuery = '';
  String _selectedLanguage = 'en'; // 'en' or 'hi'
  HelplineCategory? _selectedCategory; // null = all

  @override
  void initState() {
    super.initState();
    _callService = widget.callService ?? HelplineCallService.instance;
    _helplines = widget.customHelplines ?? HelplineEntry.defaultHelplines;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<HelplineEntry> get _filteredHelplines {
    return _helplines.where((entry) {
      if (_selectedCategory != null && entry.category != _selectedCategory) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty && !entry.matchesQuery(_searchQuery)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _handleCall(HelplineEntry entry) async {
    final success = await _callService.launchDialer(entry.number);
    if (!success && mounted) {
      // Fallback: Copy to clipboard and inform user
      HelplineCallService.copyToClipboard(entry.number);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.deepNavy,
          content: Row(
            children: [
              const Icon(Icons.copy_rounded, color: AppColors.surfacePureWhite, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _selectedLanguage == 'hi'
                      ? 'डायल नहीं हो सका। नंबर (${entry.number}) क्लिपबोर्ड पर कॉपी कर दिया गया।'
                      : 'Could not open dialer. Number (${entry.number}) copied to clipboard.',
                  style: const TextStyle(color: AppColors.surfacePureWhite, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _handleCopy(HelplineEntry entry) async {
    await HelplineCallService.copyToClipboard(entry.number);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.deepNavy,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          content: Text(
            _selectedLanguage == 'hi'
                ? '${entry.number} क्लिपबोर्ड पर कॉपी किया गया'
                : 'Copied ${entry.number} to clipboard',
            style: const TextStyle(color: AppColors.surfacePureWhite, fontSize: 13),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSourceDetails(HelplineEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: AppColors.surfacePureWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderMedium,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.deepNavy,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.number,
                    style: const TextStyle(
                      color: AppColors.surfacePureWhite,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.localizedName(_selectedLanguage),
                        style: AppTypography.subheading,
                      ),
                      Text(
                        entry.category.labelEn(),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _selectedLanguage == 'hi' ? 'आधिकारिक सत्यापन स्रोत:' : 'Official Verification Source:',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.sourceName,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.deepNavy),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.sourceUrl,
                    style: const TextStyle(fontSize: 12, color: AppColors.softBlue, decoration: TextDecoration.underline),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_selectedLanguage == 'hi' ? 'क्षेत्र:' : 'Region:'} ${entry.localizedRegion(_selectedLanguage)}',
                    style: AppTypography.metadata,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.deepNavy,
                      side: const BorderSide(color: AppColors.borderMedium),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.open_in_browser_rounded, size: 18),
                    label: Text(_selectedLanguage == 'hi' ? 'वेबसाइट खोलें' : 'Open Portal'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final uri = Uri.tryParse(entry.sourceUrl);
                      if (uri != null) {
                        try {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        } catch (_) {}
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.deepNavy,
                      foregroundColor: AppColors.surfacePureWhite,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: const Icon(Icons.phone_outlined, size: 18),
                    label: Text('${_selectedLanguage == 'hi' ? 'डायल करें' : 'Call'} ${entry.number}'),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _handleCall(entry);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredHelplines;
    final isSearching = _searchQuery.trim().isNotEmpty;
    final primary112 = _helplines.firstWhere((e) => e.isPrimaryUnified, orElse: () => _helplines.first);
    final show112Hero = (_selectedCategory == null || _selectedCategory == HelplineCategory.emergency) &&
        (!isSearching || primary112.matchesQuery(_searchQuery));

    return Scaffold(
      backgroundColor: AppColors.primaryBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surfacePureWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedLanguage == 'hi' ? 'हेल्पलाइन डायरेक्टरी' : 'Helpline Directory',
              style: AppTypography.subheading,
            ),
            Text(
              _selectedLanguage == 'hi'
                  ? 'आधिकारिक आपातकालीन एवं सहायता सेवाएं'
                  : 'Official Emergency & Public Assistance',
              style: AppTypography.metadata,
            ),
          ],
        ),
        actions: [
          _buildLanguageToggle(),
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          _buildSearchBar(),

          // Category Filters
          _buildCategoryFilterBar(),

          // Main List View
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      // Prominent 112 Unified Emergency Hero Card
                      if (show112Hero) ...[
                        _build112HeroCard(primary112),
                        const SizedBox(height: 16),
                      ],

                      // Section Title if not searching
                      if (!isSearching && _selectedCategory == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10, left: 4),
                          child: Text(
                            _selectedLanguage == 'hi'
                                ? 'सभी राष्ट्रीय एवं सार्वजनिक हेल्पलाइन'
                                : 'All National & Public Helplines',
                            style: AppTypography.sectionHeading,
                          ),
                        ),

                      // Filtered Cards (skip 112 if already shown in hero to prevent redundancy)
                      ...filtered
                          .where((e) => !(show112Hero && e.isPrimaryUnified))
                          .map((entry) => _buildHelplineCard(entry)),

                      const SizedBox(height: 16),
                      _buildFooterDisclaimer(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.borderSubtle),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLangButton('en', 'EN'),
              _buildLangButton('hi', 'हिन्दी'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLangButton(String code, String label) {
    final isSelected = _selectedLanguage == code;
    return GestureDetector(
      onTap: () {
        if (_selectedLanguage != code) {
          setState(() => _selectedLanguage = code);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.deepNavy : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? AppColors.surfacePureWhite : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: AppColors.surfacePureWhite,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (val) => setState(() => _searchQuery = val),
        style: const TextStyle(fontSize: 14, color: AppColors.deepNavy),
        decoration: InputDecoration(
          hintText: _selectedLanguage == 'hi'
              ? 'हेल्पलाइन, नंबर (उदा. 112, 1930) या श्रेणी खोजें...'
              : 'Search name, number (e.g. 112, 1930), or category...',
          hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.textMuted),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          filled: true,
          fillColor: AppColors.surfaceLight,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.borderSubtle),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.borderSubtle),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.deepNavy, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFilterBar() {
    return Container(
      height: 44,
      color: AppColors.surfacePureWhite,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildCategoryChip(
            key: const Key('category_chip_all'),
            label: _selectedLanguage == 'hi' ? 'सभी' : 'All',
            isSelected: _selectedCategory == null,
            onTap: () => setState(() => _selectedCategory = null),
          ),
          ...HelplineCategory.values.map(
            (cat) => _buildCategoryChip(
              key: Key('category_chip_${cat.name}'),
              label: _selectedLanguage == 'hi' ? cat.labelHi() : cat.labelEn(),
              icon: cat.icon,
              isSelected: _selectedCategory == cat,
              onTap: () => setState(() => _selectedCategory = cat),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    Key? key,
    required String label,
    IconData? icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.deepNavy : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.deepNavy : AppColors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: isSelected ? AppColors.surfacePureWhite : AppColors.textSecondary,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? AppColors.surfacePureWhite : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _build112HeroCard(HelplineEntry entry) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.deepNavy,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x200F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.emergencyRed,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '112',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _selectedLanguage == 'hi'
                            ? 'भारत की राष्ट्रीय आपातकालीन सेवा (ERSS)'
                            : 'INDIA UNIFIED EMERGENCY (ERSS)',
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entry.localizedName(_selectedLanguage),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            entry.localizedDescription(_selectedLanguage),
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12.5,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.verified_outlined, color: Color(0xFF94A3B8), size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  entry.sourceName,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emergencyRed,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                  label: Text(
                    _selectedLanguage == 'hi' ? '112 पर कॉल करें' : 'Call 112 (Emergency)',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  onPressed: () => _handleCall(entry),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.info_outline_rounded, size: 18),
                tooltip: 'Source Info',
                onPressed: () => _showSourceDetails(entry),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHelplineCard(HelplineEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfacePureWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderSubtle),
        boxShadow: const [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Phone Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderMedium),
                ),
                child: Text(
                  entry.number,
                  style: const TextStyle(
                    color: AppColors.deepNavy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Title and category tags
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.localizedName(_selectedLanguage),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.deepNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.subtleBlueGray,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _selectedLanguage == 'hi' ? entry.category.labelHi() : entry.category.labelEn(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.subtleBlueGray,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.localizedRegion(_selectedLanguage),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Description
          Text(
            entry.localizedDescription(_selectedLanguage),
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),

          // Source Tag
          Row(
            children: [
              const Icon(Icons.account_balance_outlined, size: 12, color: AppColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  entry.sourceName,
                  style: AppTypography.metadata,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Actions
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.deepNavy,
                    foregroundColor: AppColors.surfacePureWhite,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.phone_outlined, size: 16),
                  label: Text(
                    '${_selectedLanguage == 'hi' ? 'डायल करें' : 'Call'} ${entry.number}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  onPressed: () => _handleCall(entry),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceLight,
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 16),
                tooltip: 'Copy Number',
                onPressed: () => _handleCopy(entry),
              ),
              const SizedBox(width: 4),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surfaceLight,
                  foregroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: AppColors.borderSubtle),
                  ),
                ),
                icon: const Icon(Icons.info_outline_rounded, size: 16),
                tooltip: 'Verification Source',
                onPressed: () => _showSourceDetails(entry),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              _selectedLanguage == 'hi' ? 'कोई हेल्पलाइन नहीं मिली' : 'No Helplines Found',
              style: AppTypography.sectionHeading,
            ),
            const SizedBox(height: 8),
            Text(
              _selectedLanguage == 'hi'
                  ? 'खोज शब्द "$_searchQuery" के लिए कोई हेल्पलाइन नहीं मिली। सेवा का नाम, नंबर या श्रेणी बदल कर देखें।'
                  : 'No helpline matched "$_searchQuery". Try searching by name (e.g. Fire, Cyber, Ambulance), number, or category.',
              style: AppTypography.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.deepNavy,
                foregroundColor: AppColors.surfacePureWhite,
              ),
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedCategory = null;
                });
              },
              child: Text(_selectedLanguage == 'hi' ? 'खोज रीसेट करें' : 'Reset Search & Filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterDisclaimer() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        _selectedLanguage == 'hi'
            ? 'सूचना: वीटा रेस्क्यू (Vita ResQ) त्वरित सार्वजनिक पहुंच हेतु आधिकारिक सरकारी हेल्पलाइनों की निर्देशिका प्रदान करता है। वीटा रेस्क्यू इन स्वतंत्र सरकारी सेवाओं का संचालन नहीं करता है।'
            : 'Notice: Vita ResQ provides this verified directory of Government of India helplines for rapid public assistance. Vita ResQ does not operate or manage these independent public emergency services.',
        style: AppTypography.metadata,
        textAlign: TextAlign.center,
      ),
    );
  }
}
