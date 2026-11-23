import 'package:latlong2/latlong.dart';

class RouteResult {
  final List<LatLng> polylinePoints;
  final double distanceMeters;
  final double durationSeconds;
  final String etaText;
  final bool isRoadRoute;

  RouteResult({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.etaText,
    this.isRoadRoute = true,
  });

  factory RouteResult.directFallback({
    required LatLng origin,
    required LatLng destination,
    required double directDistanceMeters,
  }) {
    return RouteResult(
      polylinePoints: [origin, destination],
      distanceMeters: directDistanceMeters,
      durationSeconds: 0,
      etaText: 'ETA unavailable',
      isRoadRoute: false,
    );
  }
}

abstract class IRoutingService {
  Future<RouteResult?> fetchRoadRoute(LatLng origin, LatLng destination);
}
