import 'package:flutter_test/flutter_test.dart';
import 'package:vindara/services/permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UniversalPermissionStatus unit tests', () {
    test('isFullyGranted returns true only when all applicable permissions and GPS are ready', () {
      const allReady = UniversalPermissionStatus(
        isLocationGranted: true,
        isLocationServiceEnabled: true,
        isBluetoothScanGranted: true,
        isBluetoothAdvertiseGranted: true,
        isBluetoothConnectGranted: true,
        isNearbyWifiGranted: true,
        isNotificationGranted: true,
        sdkInt: 34,
      );
      expect(allReady.isFullyGranted, isTrue);

      const locationOff = UniversalPermissionStatus(
        isLocationGranted: true,
        isLocationServiceEnabled: false,
        isBluetoothScanGranted: true,
        isBluetoothAdvertiseGranted: true,
        isBluetoothConnectGranted: true,
        isNearbyWifiGranted: true,
        isNotificationGranted: true,
        sdkInt: 34,
      );
      expect(locationOff.isFullyGranted, isFalse);

      const locationDenied = UniversalPermissionStatus(
        isLocationGranted: false,
        isLocationServiceEnabled: true,
        isBluetoothScanGranted: true,
        isBluetoothAdvertiseGranted: true,
        isBluetoothConnectGranted: true,
        isNearbyWifiGranted: true,
        isNotificationGranted: true,
        sdkInt: 34,
      );
      expect(locationDenied.isFullyGranted, isFalse);
    });

    test('isFullyGranted on older Android (SDK < 31) ignores modern Bluetooth and Wi-Fi', () {
      const oldAndroidReady = UniversalPermissionStatus(
        isLocationGranted: true,
        isLocationServiceEnabled: true,
        isBluetoothScanGranted: false,
        isBluetoothAdvertiseGranted: false,
        isBluetoothConnectGranted: false,
        isNearbyWifiGranted: false,
        isNotificationGranted: false,
        sdkInt: 28, // Android 9 Pie
      );
      expect(oldAndroidReady.isFullyGranted, isTrue);
    });

    test('isFullyGranted on Android 12 (SDK 31-32) requires BT scan/adv/connect but ignores API 33 Wi-Fi', () {
      const android12Incomplete = UniversalPermissionStatus(
        isLocationGranted: true,
        isLocationServiceEnabled: true,
        isBluetoothScanGranted: false,
        isBluetoothAdvertiseGranted: true,
        isBluetoothConnectGranted: true,
        isNearbyWifiGranted: false,
        isNotificationGranted: false,
        sdkInt: 31,
      );
      expect(android12Incomplete.isFullyGranted, isFalse);

      const android12Complete = UniversalPermissionStatus(
        isLocationGranted: true,
        isLocationServiceEnabled: true,
        isBluetoothScanGranted: true,
        isBluetoothAdvertiseGranted: true,
        isBluetoothConnectGranted: true,
        isNearbyWifiGranted: false,
        isNotificationGranted: false,
        sdkInt: 31,
      );
      expect(android12Complete.isFullyGranted, isTrue);
    });

    test('copyWith updates fields correctly', () {
      const original = UniversalPermissionStatus(
        isLocationGranted: false,
        isLocationServiceEnabled: false,
        isBluetoothScanGranted: false,
        isBluetoothAdvertiseGranted: false,
        isBluetoothConnectGranted: false,
        isNearbyWifiGranted: false,
        isNotificationGranted: false,
        sdkInt: 30,
      );

      final updated = original.copyWith(
        isLocationGranted: true,
        isLocationServiceEnabled: true,
      );

      expect(updated.isLocationGranted, isTrue);
      expect(updated.isLocationServiceEnabled, isTrue);
      expect(updated.sdkInt, equals(30));
    });
  });
}

