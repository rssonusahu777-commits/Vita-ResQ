import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'communication_service_interface.dart';
import 'emergency_service.dart';
import '../models/emergency_model.dart';

class OnlineCommunicationService implements ICommunicationService {
  EmergencyService get _emergencyService => EmergencyService();
  StreamSubscription? _alertSub;

  static const int maxOnlineFreshnessMinutes = 10;

  /// Validates whether an online Firestore emergency timestamp is within the acceptable freshness window (<= 10 minutes).
  /// Rejects alerts older than 10 minutes or created far in the future (absorbing reasonable 1-minute clock drift).
  static bool isOnlineAlertFresh(DateTime createdAt, {DateTime? now}) {
    final currentTime = now ?? DateTime.now();
    final difference = currentTime.difference(createdAt);
    // Cannot be in the future by more than 1 minute (clock drift protection)
    if (difference.inSeconds < -60) return false;
    return difference.inMinutes <= maxOnlineFreshnessMinutes;
  }

  @override
  Future<String> broadcastSOS({
    required Position position,
    required String currentUserId,
  }) async {
    return await _emergencyService.createSOS(position, victimId: currentUserId);
  }

  @override
  Stream<List<EmergencyModel>> listenForAlerts({
    required double userLat,
    required double userLon,
    required String currentUserId,
  }) {
    _alertSub?.cancel();
    final controller = StreamController<List<EmergencyModel>>.broadcast(
      onCancel: () {
        _alertSub?.cancel();
      },
    );

    _alertSub = _emergencyService
        .streamNearbySearchingEmergencies(userLat, userLon)
        .listen(
      (data) {
        if (!controller.isClosed) {
          // Strictly enforce online freshness for SEARCHING alerts while preserving terminal updates
          final freshData = data.where((e) {
            if (e.isTerminal) return true;
            if (e.isOffline) return true; // Handled by offline P2P freshness guards
            return isOnlineAlertFresh(e.createdAt);
          }).toList();
          controller.add(freshData);
        }
      },
      onError: (err) {
        if (!controller.isClosed) controller.addError(err);
      },
    );

    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await _alertSub?.cancel();
    _alertSub = null;
  }
}
