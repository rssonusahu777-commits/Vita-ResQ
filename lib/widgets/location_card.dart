// lib/widgets/location_card.dart
//
// Vindara — Hybrid Online OpenStreetMap / Offline Distance Card (Phase 7)
// Package: com.vindara.app
//
// Design rules followed:
//   Rule #2 — Offline-independent GPS: Coordinates always functional without online tiles.
//   Online Mode (isOnline == true): Interactive OpenStreetMap preview with Victim & Responder pins.
//   Offline Mode (isOnline == false): Map widget hidden; displays "Offline GPS Coordinate Mode".

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/emergency.dart';
import '../theme/vindara_theme.dart';

class LocationCard extends StatelessWidget {
  final Emergency emergency;
  final bool isOnline;
  final double? responderLatitude;
  final double? responderLongitude;
  final VoidCallback? onCoordinatesCopied;

  const LocationCard({
    super.key,
    required this.emergency,
    required this.isOnline,
    this.responderLatitude,
    this.responderLongitude,
    this.onCoordinatesCopied,
  });

  /// Computes Haversine distance in meters between responder and victim offline.
  double? get distanceMeters {
    if (responderLatitude == null || responderLongitude == null) return null;

    const earthRadius = 6371000.0; // meters
    final dLat = _degreesToRadians(emergency.latitude - responderLatitude!);
    final dLon = _degreesToRadians(emergency.longitude - responderLongitude!);

    final lat1 = _degreesToRadians(responderLatitude!);
    final lat2 = _degreesToRadians(emergency.latitude);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) => degrees * (pi / 180.0);

  String? get formattedDistance {
    final d = distanceMeters;
    if (d == null) return null;
    if (d < 1000) {
      return '${d.round()} m away';
    } else {
      return '${(d / 1000).toStringAsFixed(1)} km away';
    }
  }

  Future<void> _copyCoordinates(BuildContext context) async {
    onCoordinatesCopied?.call();
    final coords =
        '${emergency.latitude.toStringAsFixed(6)}, ${emergency.longitude.toStringAsFixed(6)}';
    try {
      await Clipboard.setData(ClipboardData(text: coords));
    } catch (_) {}
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Coordinates copied to clipboard: $coords'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openExternalMaps(BuildContext context) async {
    final lat = emergency.latitude;
    final lng = emergency.longitude;
    final geoUri = Uri.parse('geo:$lat,$lng?q=$lat,$lng(Emergency)');
    final webUri =
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');

    try {
      if (await canLaunchUrl(geoUri)) {
        await launchUrl(geoUri, mode: LaunchMode.externalApplication);
      } else if (await canLaunchUrl(webUri)) {
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open external maps.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error launching maps: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dist = formattedDistance;

    return Card(
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title & Offline Ready Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.gps_fixed_rounded,
                        color: Colors.blueGrey, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'GPS Coordinates',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
                if (dist != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Text(
                      dist,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade900,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // Hybrid Map / Offline Banner (Rule #2)
            if (isOnline)
              SizedBox(
                height: 190,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter:
                          LatLng(emergency.latitude, emergency.longitude),
                      initialZoom: 15.0,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.vindara.app',
                        errorTileCallback: (tile, error, stackTrace) {},
                      ),
                      MarkerLayer(
                        markers: [
                          // Victim Marker
                          Marker(
                            point:
                                LatLng(emergency.latitude, emergency.longitude),
                            width: 40,
                            height: 40,
                            child: const Icon(
                              Icons.location_on,
                              color: VindaraTheme.emergencyRed,
                              size: 38,
                            ),
                          ),
                          // Responder Marker (if available)
                          if (responderLatitude != null &&
                              responderLongitude != null)
                            Marker(
                              point: LatLng(
                                  responderLatitude!, responderLongitude!),
                              width: 36,
                              height: 36,
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.blueAccent,
                                size: 30,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade400),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        color: Colors.amber.shade900, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offline GPS Coordinate Mode',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.amber.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Map tiles hidden to save battery and prevent network errors. Exact satellite GPS coordinates remain 100% active.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.amber.shade900),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Raw Numerical Coordinates Box (Rule #2)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blueGrey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latitude:   ${emergency.latitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Longitude:  ${emergency.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accuracy:   ±${emergency.accuracyMeters.toStringAsFixed(1)} metres',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Action Buttons: Copy Coordinates & Open in External Maps
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy Coordinates'),
                    onPressed: () => _copyCoordinates(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Open in Maps'),
                    onPressed: () => _openExternalMaps(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
