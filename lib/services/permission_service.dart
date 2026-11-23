// lib/services/permission_service.dart
//
// Vindara — Universal Cross-Version Android Permission Service
// Package: com.vindara.app
//
// Compatibility Range: Android 6.0 (API 23) through latest Android versions (API 34+)
//
// Rules followed:
// - Android 6–11 (API 23–30): Requests Fine/Coarse Location and checks GPS hardware.
//   Skips Android 12+ Bluetooth runtime and Android 13+ Wi-Fi/Notification permissions to avoid crashes.
// - Android 12 (API 31–32): Adds BLUETOOTH_SCAN, BLUETOOTH_ADVERTISE, and BLUETOOTH_CONNECT.
// - Android 13+ (API 33+): Adds NEARBY_WIFI_DEVICES and POST_NOTIFICATIONS.
// - Never blocks or crashes older phones on unsupported permissions.
// - Gracefully falls back on iOS, Web, and unit tests without platform channels.

import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

/// Comprehensive snapshot of device permission state
class UniversalPermissionStatus {
  final bool isLocationGranted;
  final bool isLocationServiceEnabled;
  final bool isBluetoothGranted;
  final bool isNearbyWifiGranted;
  final bool isNotificationGranted;
  final bool isPermanentlyDenied;
  final int sdkInt;
  final List<String> missingPermissions;

  const UniversalPermissionStatus({
    required this.isLocationGranted,
    required this.isLocationServiceEnabled,
    required this.isBluetoothGranted,
    required this.isNearbyWifiGranted,
    required this.isNotificationGranted,
    required this.isPermanentlyDenied,
    required this.sdkInt,
    this.missingPermissions = const [],
  });

  /// Critical readiness for core emergency dispatch: needs hardware GPS + location permission
  bool get isReadyForEmergency => isLocationGranted && isLocationServiceEnabled;

  /// Whether all applicable permissions and hardware location for this device are granted
  bool get isFullyGranted {
    if (!isLocationGranted || !isLocationServiceEnabled) return false;
    if (sdkInt >= 31 && !isBluetoothGranted) return false;
    if (sdkInt >= 33 && (!isNearbyWifiGranted || !isNotificationGranted)) return false;
    return true;
  }

  /// Readiness for offline peer-to-peer mesh broadcasting
  bool get isReadyForP2pMesh =>
      isLocationGranted && isBluetoothGranted && (sdkInt < 33 || isNearbyWifiGranted);

  UniversalPermissionStatus copyWith({
    bool? isLocationGranted,
    bool? isLocationServiceEnabled,
    bool? isBluetoothGranted,
    bool? isNearbyWifiGranted,
    bool? isNotificationGranted,
    bool? isPermanentlyDenied,
    int? sdkInt,
    List<String>? missingPermissions,
  }) {
    return UniversalPermissionStatus(
      isLocationGranted: isLocationGranted ?? this.isLocationGranted,
      isLocationServiceEnabled: isLocationServiceEnabled ?? this.isLocationServiceEnabled,
      isBluetoothGranted: isBluetoothGranted ?? this.isBluetoothGranted,
      isNearbyWifiGranted: isNearbyWifiGranted ?? this.isNearbyWifiGranted,
      isNotificationGranted: isNotificationGranted ?? this.isNotificationGranted,
      isPermanentlyDenied: isPermanentlyDenied ?? this.isPermanentlyDenied,
      sdkInt: sdkInt ?? this.sdkInt,
      missingPermissions: missingPermissions ?? this.missingPermissions,
    );
  }
}

/// Service managing device-adaptive permission negotiation across all Android API levels
class PermissionService {
  static PermissionService? _instance;
  static PermissionService get instance => _instance ??= PermissionService();

  @visibleForTesting
  static void setMockInstance(PermissionService mock) {
    _instance = mock;
  }

  final DeviceInfoPlugin _deviceInfo;

  PermissionService({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  int? _cachedSdkInt;

  /// Retrieves Android SDK version integer safely (e.g. 23 for Android 6, 33 for Android 13)
  Future<int> getAndroidSdkVersion() async {
    if (_cachedSdkInt != null) return _cachedSdkInt!;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final androidInfo = await _deviceInfo.androidInfo;
        _cachedSdkInt = androidInfo.version.sdkInt;
        return _cachedSdkInt!;
      } catch (e) {
        debugPrint('PermissionService: Failed to query androidInfo: $e');
        _cachedSdkInt = 30; // Safe modern default
        return _cachedSdkInt!;
      }
    }

    _cachedSdkInt = 0; // Non-Android / Web / Unit test
    return _cachedSdkInt!;
  }

  /// Checks current permissions without prompting the user
  Future<UniversalPermissionStatus> checkPermissions() async {
    final sdk = await getAndroidSdkVersion();

    // 1. Hardware GPS Location Service Enabled Check
    bool isLocationServiceEnabled = false;
    try {
      isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      isLocationServiceEnabled = true;
    }

    // 2. Location Permission
    final locationStatus = await Permission.locationWhenInUse.status;
    final isLocationGranted = locationStatus.isGranted || locationStatus.isLimited;
    bool isPermanentlyDenied = locationStatus.isPermanentlyDenied;

    // 3. Bluetooth (Android 12+ API 31+)
    bool isBluetoothGranted = true;
    if (sdk >= 31) {
      final scan = await Permission.bluetoothScan.status;
      final advertise = await Permission.bluetoothAdvertise.status;
      final connect = await Permission.bluetoothConnect.status;
      isBluetoothGranted = scan.isGranted && advertise.isGranted && connect.isGranted;
      if (scan.isPermanentlyDenied || advertise.isPermanentlyDenied || connect.isPermanentlyDenied) {
        isPermanentlyDenied = true;
      }
    }

    // 4. Nearby Wi-Fi Devices (Android 13+ API 33+)
    bool isNearbyWifiGranted = true;
    if (sdk >= 33) {
      final nearbyWifi = await Permission.nearbyWifiDevices.status;
      isNearbyWifiGranted = nearbyWifi.isGranted;
      if (nearbyWifi.isPermanentlyDenied) {
        isPermanentlyDenied = true;
      }
    }

    // 5. Notifications (Android 13+ API 33+)
    bool isNotificationGranted = true;
    if (sdk >= 33) {
      final notif = await Permission.notification.status;
      isNotificationGranted = notif.isGranted;
    }

    final missing = <String>[];
    if (!isLocationGranted) missing.add('Location');
    if (!isLocationServiceEnabled) missing.add('GPS Hardware');
    if (!isBluetoothGranted) missing.add('Nearby Bluetooth');
    if (!isNearbyWifiGranted) missing.add('Nearby Wi-Fi Devices');
    if (!isNotificationGranted) missing.add('Notifications');

    return UniversalPermissionStatus(
      isLocationGranted: isLocationGranted,
      isLocationServiceEnabled: isLocationServiceEnabled,
      isBluetoothGranted: isBluetoothGranted,
      isNearbyWifiGranted: isNearbyWifiGranted,
      isNotificationGranted: isNotificationGranted,
      isPermanentlyDenied: isPermanentlyDenied,
      sdkInt: sdk,
      missingPermissions: missing,
    );
  }

  /// Requests appropriate permissions based strictly on the phone's Android OS version
  Future<UniversalPermissionStatus> requestEmergencyPermissions() async {
    final sdk = await getAndroidSdkVersion();

    // 1. Every Android version: Location is mandatory for lifesaving dispatch
    final locationStatus = await Permission.locationWhenInUse.request();
    final isLocationGranted = locationStatus.isGranted || locationStatus.isLimited;
    bool isPermanentlyDenied = locationStatus.isPermanentlyDenied;

    // Verify location services
    bool isLocationServiceEnabled = false;
    try {
      isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      isLocationServiceEnabled = true;
    }

    // 2. Android 12+ (API 31+): Request Bluetooth trio
    bool isBluetoothGranted = true;
    if (sdk >= 31) {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
      ].request();

      isBluetoothGranted = results.values.every((s) => s.isGranted);
      if (results.values.any((s) => s.isPermanentlyDenied)) {
        isPermanentlyDenied = true;
      }
    }

    // 3. Android 13+ (API 33+): Request Nearby Wi-Fi Devices & Notifications
    bool isNearbyWifiGranted = true;
    bool isNotificationGranted = true;
    if (sdk >= 33) {
      final nearbyWifi = await Permission.nearbyWifiDevices.request();
      isNearbyWifiGranted = nearbyWifi.isGranted;
      if (nearbyWifi.isPermanentlyDenied) {
        isPermanentlyDenied = true;
      }

      final notif = await Permission.notification.request();
      isNotificationGranted = notif.isGranted;
    }

    final missing = <String>[];
    if (!isLocationGranted) missing.add('Location');
    if (!isLocationServiceEnabled) missing.add('GPS Hardware');
    if (!isBluetoothGranted) missing.add('Nearby Bluetooth');
    if (!isNearbyWifiGranted) missing.add('Nearby Wi-Fi Devices');
    if (!isNotificationGranted) missing.add('Notifications');

    return UniversalPermissionStatus(
      isLocationGranted: isLocationGranted,
      isLocationServiceEnabled: isLocationServiceEnabled,
      isBluetoothGranted: isBluetoothGranted,
      isNearbyWifiGranted: isNearbyWifiGranted,
      isNotificationGranted: isNotificationGranted,
      isPermanentlyDenied: isPermanentlyDenied,
      sdkInt: sdk,
      missingPermissions: missing,
    );
  }

  /// Opens the device App Settings so the user can re-enable permanently denied permissions
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Opens platform Location/GPS settings screen
  Future<bool> promptEnableLocationService() async {
    return await Geolocator.openLocationSettings();
  }
}

