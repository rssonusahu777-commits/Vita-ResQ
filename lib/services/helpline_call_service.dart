import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

typedef UrlLauncherDelegate = Future<bool> Function(Uri uri, {LaunchMode? mode});

/// Service responsible for safely normalizing helpline numbers, constructing
/// tel: URIs, and delegating call intents to the native device dialer without
/// initiating direct calls or requiring CALL_PHONE permissions.
class HelplineCallService {
  static HelplineCallService? _instance;
  static HelplineCallService get instance => _instance ??= HelplineCallService._();

  HelplineCallService._();

  @visibleForTesting
  factory HelplineCallService.forTesting({UrlLauncherDelegate? launcherDelegate}) {
    final service = HelplineCallService._();
    if (launcherDelegate != null) {
      service._customLauncher = launcherDelegate;
    }
    return service;
  }

  UrlLauncherDelegate? _customLauncher;

  @visibleForTesting
  void setLauncherForTesting(UrlLauncherDelegate? delegate) {
    _customLauncher = delegate;
  }

  @visibleForTesting
  void resetForTesting() {
    _customLauncher = null;
  }

  /// Normalizes and validates a helpline number string into a clean digit sequence.
  /// Supports short codes (e.g. 112, 101, 108, 181, 1098, 1930, 14567, 1906)
  /// and standard national phone numbers.
  static String normalizeNumber(String rawNumber) {
    final cleaned = rawNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (cleaned.isEmpty) return '';

    // Handle leading '+' if present
    final isPlus = cleaned.startsWith('+');
    final digitsOnly = cleaned.replaceAll(RegExp(r'[^0-9]'), '');

    // Helplines range from 3 digits (112, 101) up to 15 digits for E.164 numbers
    if (digitsOnly.length < 3 || digitsOnly.length > 15) {
      return '';
    }

    return isPlus ? '+$digitsOnly' : digitsOnly;
  }

  /// Verifies if a given string is a valid callable helpline number.
  static bool isValidHelplineNumber(String rawNumber) {
    return normalizeNumber(rawNumber).isNotEmpty;
  }

  /// Constructs the canonical `tel:` URI for a given helpline number.
  static Uri? constructTelUri(String rawNumber) {
    final normalized = normalizeNumber(rawNumber);
    if (normalized.isEmpty) return null;
    return Uri(scheme: 'tel', path: normalized);
  }

  /// Safely opens the device dialer with the helpline number populated.
  /// Returns `true` if the native dialer was successfully launched, or `false` otherwise.
  ///
  /// Important:
  /// - Uses `LaunchMode.externalApplication` to open the phone app.
  /// - Never places a call directly. The user must explicitly press dial on their phone.
  /// - Does NOT require or request the Android `CALL_PHONE` permission.
  Future<bool> launchDialer(String rawNumber) async {
    final uri = constructTelUri(rawNumber);
    if (uri == null) return false;

    try {
      if (_customLauncher != null) {
        return await _customLauncher!(uri, mode: LaunchMode.externalApplication);
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Copies the helpline number to the device clipboard as an accessible fallback.
  static Future<void> copyToClipboard(String rawNumber) async {
    final normalized = normalizeNumber(rawNumber);
    if (normalized.isNotEmpty) {
      try {
        await Clipboard.setData(ClipboardData(text: normalized));
      } catch (_) {}
    }
  }
}
