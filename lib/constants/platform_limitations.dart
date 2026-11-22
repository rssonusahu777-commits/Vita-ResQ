// lib/constants/platform_limitations.dart
//
// Vindara — Platform Limitations & OS Constraints (Rule #5)
// Package: com.vindara.app

abstract class PlatformLimitations {
  PlatformLimitations._();

  /// Honest explanation of OS force-stop and battery saver restrictions.
  /// Used in Settings, Battery Optimization guidance, and Permission screens.
  static const String osForceStopLimitationNotice =
      'OS Platform Notice: On Android and iOS, if you explicitly force-stop Vindara '
      'in system settings or place it into aggressive battery-saver restrictions, the OS '
      'suspends all background FCM push delivery until you manually reopen the app. '
      'To guarantee you never miss nearby civilian emergency alerts, allow unrestricted '
      'background battery execution in your device settings.';
}

