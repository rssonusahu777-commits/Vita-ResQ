/// Vindara Core Constants
/// Community Emergency Response Platform
class AppConstants {
  AppConstants._();

  // Application Identity
  static const String appName = 'Vindara';
  static const String appTagline = 'Community Emergency Response Platform';
  static const String appVersion = '1.0.0 (Alpha)';

  // Emergency Hotlines & Services
  static const String emergencyHelpline = '112';
  static const String emergencyHelplineLabel = 'Emergency Helpline 112';
  static const String ambulanceHelpline = '108';
  static const String fireHelpline = '101';
  static const String policeHelpline = '100';

  // Geographic Default (India Reference Point)
  static const double defaultLatitude = 12.9716;
  static const double defaultLongitude = 77.5946;
  static const String defaultCity = 'Bengaluru, India';

  // State Labels for UI Display
  static const String statusCreated = 'Registered';
  static const String statusAlerting = 'Broadcasting HELP';
  static const String statusAccepted = 'Responder Assigned';
  static const String statusInProgress = 'En Route / On Scene';
  static const String statusResolved = 'Resolved & Safe';
  static const String statusCancelled = 'False Alarm / Cancelled';

  // Detection Source Labels
  static const String sourceManualSos = 'Manual HELP Alert';
  static const String sourceManualHelp = 'Manual HELP Alert';
  static const String sourcePossibleCrash = 'Possible Crash Detected';

  // Communication Mode Labels
  static const String modeOnline = 'Cloud Connected';
  static const String modeOfflineNearby = 'Offline Nearby Mesh (BLE/Wi-Fi Direct)';

  // Emergency Type Labels
  static const String typeRoadAccident = 'Road Crash / Accident';
  static const String typeMedical = 'Medical Emergency';
  static const String typeFire = 'Fire & Smoke';
  static const String typePersonalSafety = 'Personal Safety Threat';
  static const String typeOther = 'Critical Hazard / Other';
}

