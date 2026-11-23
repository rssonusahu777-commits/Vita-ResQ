import 'package:flutter/material.dart';

/// Categories for official Indian emergency and public assistance helplines.
enum HelplineCategory {
  emergency,
  womenAndChildren,
  cybercrime,
  seniorCitizens,
  other;

  String labelEn() {
    switch (this) {
      case HelplineCategory.emergency:
        return 'Emergency Services';
      case HelplineCategory.womenAndChildren:
        return 'Women & Children';
      case HelplineCategory.cybercrime:
        return 'Cybercrime';
      case HelplineCategory.seniorCitizens:
        return 'Senior Citizens';
      case HelplineCategory.other:
        return 'Other Assistance';
    }
  }

  String labelHi() {
    switch (this) {
      case HelplineCategory.emergency:
        return 'आपातकालीन सेवाएं';
      case HelplineCategory.womenAndChildren:
        return 'महिला एवं बाल सुरक्षा';
      case HelplineCategory.cybercrime:
        return 'साइबर अपराध';
      case HelplineCategory.seniorCitizens:
        return 'वरिष्ठ नागरिक';
      case HelplineCategory.other:
        return 'अन्य सहायता';
    }
  }

  IconData get icon {
    switch (this) {
      case HelplineCategory.emergency:
        return Icons.emergency_outlined;
      case HelplineCategory.womenAndChildren:
        return Icons.family_restroom_outlined;
      case HelplineCategory.cybercrime:
        return Icons.security_outlined;
      case HelplineCategory.seniorCitizens:
        return Icons.elderly_outlined;
      case HelplineCategory.other:
        return Icons.support_agent_outlined;
    }
  }
}

/// Structured data model representing an official public helpline entry.
class HelplineEntry {
  final String id;
  final String nameEn;
  final String nameHi;
  final String number;
  final HelplineCategory category;
  final String descriptionEn;
  final String descriptionHi;
  final String regionEn;
  final String regionHi;
  final String sourceName;
  final String sourceUrl;
  final bool isPrimaryUnified;

  const HelplineEntry({
    required this.id,
    required this.nameEn,
    required this.nameHi,
    required this.number,
    required this.category,
    required this.descriptionEn,
    required this.descriptionHi,
    this.regionEn = 'Pan-India',
    this.regionHi = 'अखिल भारतीय',
    required this.sourceName,
    required this.sourceUrl,
    this.isPrimaryUnified = false,
  });

  /// Name based on language code ('en' or 'hi')
  String localizedName(String lang) => lang == 'hi' ? nameHi : nameEn;

  /// Description based on language code ('en' or 'hi')
  String localizedDescription(String lang) => lang == 'hi' ? descriptionHi : descriptionEn;

  /// Region based on language code ('en' or 'hi')
  String localizedRegion(String lang) => lang == 'hi' ? regionHi : regionEn;

  /// Checks if this helpline matches a search query
  bool matchesQuery(String query) {
    if (query.trim().isEmpty) return true;
    final q = query.trim().toLowerCase();

    // Check number (exact or partial)
    final cleanNum = number.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanQ = q.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanQ.isNotEmpty && cleanNum.contains(cleanQ)) return true;

    // Check English and Hindi names
    if (nameEn.toLowerCase().contains(q) || nameHi.toLowerCase().contains(q)) return true;

    // Check category label
    if (category.labelEn().toLowerCase().contains(q) || category.labelHi().toLowerCase().contains(q)) return true;

    // Check descriptions
    if (descriptionEn.toLowerCase().contains(q) || descriptionHi.toLowerCase().contains(q)) return true;

    // Check source name
    if (sourceName.toLowerCase().contains(q)) return true;

    return false;
  }

  /// Official, verified Government of India helpline directory entries.
  /// Verified against MHA, MWCD, MoSJE, MoPNG, NHM, and Indian Railways official portals.
  static const List<HelplineEntry> defaultHelplines = [
    // 1. Primary Unified Emergency Number
    HelplineEntry(
      id: 'erss_112',
      nameEn: 'National Emergency Number (ERSS)',
      nameHi: 'राष्ट्रीय आपातकालीन सेवा (ERSS)',
      number: '112',
      category: HelplineCategory.emergency,
      descriptionEn: 'Single 24x7 unified emergency response for Police, Fire, Ambulance, and Disaster relief across India.',
      descriptionHi: 'पुलिस, दमकल, एम्बुलेंस और आपदा राहत के लिए 24x7 एकल अखिल भारतीय आपातकालीन नंबर।',
      regionEn: 'Pan-India (All States & UTs)',
      regionHi: 'अखिल भारतीय (सभी राज्य एवं केंद्रशासित प्रदेश)',
      sourceName: 'Ministry of Home Affairs (112.gov.in)',
      sourceUrl: 'https://112.gov.in',
      isPrimaryUnified: true,
    ),

    // 2. Fire Brigade
    HelplineEntry(
      id: 'fire_101',
      nameEn: 'Fire Brigade & Rescue',
      nameHi: 'अग्निशमन सेवा एवं बचाव',
      number: '101',
      category: HelplineCategory.emergency,
      descriptionEn: 'Direct emergency response line for fire outbreaks, structural collapses, and search & rescue operations.',
      descriptionHi: 'आग लगने, भवन ढहने और आपातकालीन बचाव कार्यों के लिए सीधी हेल्पलाइन।',
      regionEn: 'Pan-India',
      regionHi: 'अखिल भारतीय',
      sourceName: 'Directorate General of Civil Defence & Fire Services, MHA',
      sourceUrl: 'https://dgcd.gov.in',
    ),

    // 3. Ambulance / EMS
    HelplineEntry(
      id: 'ambulance_108',
      nameEn: 'Ambulance & Emergency Medical Service (EMS)',
      nameHi: 'एम्बुलेंस एवं चिकित्सा आपातकाल (EMS)',
      number: '108',
      category: HelplineCategory.emergency,
      descriptionEn: '24x7 emergency medical response providing ambulance dispatch, critical patient stabilization, and hospital transport.',
      descriptionHi: 'गंभीर चिकित्सा आपात स्थितियों, दुर्घटनाओं और अस्पताल परिवहन के लिए 24x7 मुफ्त एम्बुलेंस सेवा।',
      regionEn: 'Pan-India (NHM Partner States)',
      regionHi: 'अखिल भारतीय (राष्ट्रीय स्वास्थ्य मिशन)',
      sourceName: 'National Health Mission (NHM), MoHFW',
      sourceUrl: 'https://nhm.gov.in',
    ),

    // 4. Women Helpline
    HelplineEntry(
      id: 'women_181',
      nameEn: 'Women in Distress Helpline',
      nameHi: 'महिला हेल्पलाइन (संकट सहायता)',
      number: '181',
      category: HelplineCategory.womenAndChildren,
      descriptionEn: '24x7 toll-free emergency response and support for women facing domestic violence, harassment, or distress.',
      descriptionHi: 'संकट, घरेलू हिंसा या उत्पीड़न का सामना कर रही महिलाओं के लिए 24x7 आपातकालीन सहायता और कानूनी परामर्श।',
      regionEn: 'Pan-India',
      regionHi: 'अखिल भारतीय',
      sourceName: 'Ministry of Women and Child Development (MWCD)',
      sourceUrl: 'https://wcd.nic.in',
    ),

    // 5. Child Helpline
    HelplineEntry(
      id: 'child_1098',
      nameEn: 'Childline (Child Protection)',
      nameHi: 'चाइल्डलाइन (बाल सुरक्षा एवं सहायता)',
      number: '1098',
      category: HelplineCategory.womenAndChildren,
      descriptionEn: '24x7 emergency phone outreach service for children in need of care, protection, shelter, and rescue from abuse or trafficking.',
      descriptionHi: 'संकटग्रस्त, बेसहारा या पीड़ित बच्चों के बचाव, संरक्षण और पुनर्वास के लिए 24x7 आपातकालीन सेवा।',
      regionEn: 'Pan-India',
      regionHi: 'अखिल भारतीय',
      sourceName: 'Ministry of Women and Child Development (MWCD)',
      sourceUrl: 'https://wcd.nic.in',
    ),

    // 6. Cybercrime / Financial Cyber Fraud
    HelplineEntry(
      id: 'cyber_1930',
      nameEn: 'Financial Cyber Fraud / Cybercrime Reporting',
      nameHi: 'वित्तीय साइबर धोखाधड़ी / साइबर अपराध हेल्पलाइन',
      number: '1930',
      category: HelplineCategory.cybercrime,
      descriptionEn: 'Citizen Financial Cyber Fraud Reporting System for immediate freezing of defrauded bank/UPI funds and reporting online financial scams.',
      descriptionHi: 'ऑनलाइन वित्तीय धोखाधड़ी, बैंक/यूपीआई फ्रॉड और साइबर अपराधों की तत्काल रिपोर्टिंग और फंड फ्रीज कराने हेतु हेल्पलाइन।',
      regionEn: 'Pan-India (I4C Portal)',
      regionHi: 'अखिल भारतीय (I4C पोर्टल)',
      sourceName: 'Indian Cyber Crime Coordination Centre (I4C), MHA',
      sourceUrl: 'https://cybercrime.gov.in',
    ),

    // 7. Senior Citizen Helpline
    HelplineEntry(
      id: 'elder_14567',
      nameEn: 'Elder Line (Senior Citizens)',
      nameHi: 'एल्डर लाइन (वरिष्ठ नागरिक हेल्पलाइन)',
      number: '14567',
      category: HelplineCategory.seniorCitizens,
      descriptionEn: 'National helpline for senior citizens offering emotional support, legal guidance, field rescue for abandoned elders, and elder abuse intervention.',
      descriptionHi: 'वरिष्ठ नागरिकों के लिए भावनात्मक संबल, कानूनी सलाह, दुर्व्यवहार से सुरक्षा और बेसहारा बुजुर्गों के लिए बचाव सेवा।',
      regionEn: 'Pan-India (MoSJE / NISD)',
      regionHi: 'अखिल भारतीय (सामाजिक न्याय एवं अधिकारिता मंत्रालय)',
      sourceName: 'Ministry of Social Justice and Empowerment',
      sourceUrl: 'https://socialjustice.gov.in',
    ),

    // 8. LPG Leak Emergency Helpline
    HelplineEntry(
      id: 'lpg_1906',
      nameEn: 'LPG Gas Leak Emergency Helpline',
      nameHi: 'एलपीजी गैस रिसाव आपातकालीन हेल्पलाइन',
      number: '1906',
      category: HelplineCategory.other,
      descriptionEn: '24x7 pan-India emergency response helpline for domestic and commercial LPG cylinder gas leakages, operated by public sector oil marketing companies.',
      descriptionHi: 'घरेलू और व्यावसायिक एलपीजी गैस सिलेंडर रिसाव की 24x7 आपातकालीन रिपोर्टिंग और तत्काल सहायता हेतु नंबर।',
      regionEn: 'Pan-India (IOCL, BPCL, HPCL)',
      regionHi: 'अखिल भारतीय (सार्वजनिक क्षेत्र तेल कंपनियां)',
      sourceName: 'Ministry of Petroleum & Natural Gas (MoPNG)',
      sourceUrl: 'https://mopng.gov.in',
    ),

    // 9. National Disaster Management Helpline
    HelplineEntry(
      id: 'ndma_1078',
      nameEn: 'National Disaster Helpline (NDMA)',
      nameHi: 'राष्ट्रीय आपदा प्रबंधन हेल्पलाइन (NDMA)',
      number: '1078',
      category: HelplineCategory.other,
      descriptionEn: 'Emergency assistance and disaster situation updates during floods, cyclones, landslides, and earthquakes.',
      descriptionHi: 'बाढ़, चक्रवात, भूस्खलन और भूकंप जैसी प्राकृतिक आपदाओं के दौरान आपातकालीन सहायता एवं सूचना हेल्पलाइन।',
      regionEn: 'Pan-India',
      regionHi: 'अखिल भारतीय',
      sourceName: 'National Disaster Management Authority (NDMA), MHA',
      sourceUrl: 'https://ndma.gov.in',
    ),

    // 10. Railway Passenger Security & Medical Helpline
    HelplineEntry(
      id: 'rail_139',
      nameEn: 'Railway Security & Passenger Assistance (RailMadad)',
      nameHi: 'रेलवे सुरक्षा एवं यात्री सहायता (रेल मदद)',
      number: '139',
      category: HelplineCategory.other,
      descriptionEn: 'Unified 24x7 Indian Railways helpline for passenger security, on-board medical emergencies, and travel assistance.',
      descriptionHi: 'भारतीय रेल में सुरक्षा, यात्रा के दौरान चिकित्सा आपातकाल और यात्री सहायता हेतु 24x7 एकीकृत हेल्पलाइन।',
      regionEn: 'Pan-India (Indian Railways Network)',
      regionHi: 'अखिल भारतीय (भारतीय रेल नेटवर्क)',
      sourceName: 'Ministry of Railways (RailMadad)',
      sourceUrl: 'https://railmadad.indianrailways.gov.in',
    ),
  ];
}
