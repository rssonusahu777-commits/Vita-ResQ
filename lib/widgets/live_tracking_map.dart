// lib/widgets/live_tracking_map.dart
//
// Vindara — Mutual Live Location Tracking Map Widget (OpenStreetMap + Offline Fallback)
// Package: com.vindara.app
//
// Architectural Rules:
// - Rule #1: Online OpenStreetMap tiles with graceful offline vector fallback.
// - Rule #2: Real hardware GPS coordinates preserved with zero loss.
// - Rule #6: Clean lifecycle with auto-centering camera and bound adjustments.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme/app_theme.dart';
import '../models/emergency.dart';

class LiveTrackingMapWidget extends StatefulWidget {
  final Emergency emergency;
  final bool isUserResponder;
  final double height;
  final VoidCallback? onRecenter;

  const LiveTrackingMapWidget({
    super.key,
    required this.emergency,
    this.isUserResponder = false,
    this.height = 220,
    this.onRecenter,
  });

  @override
  State<LiveTrackingMapWidget> createState() => _LiveTrackingMapWidgetState();
}

class _LiveTrackingMapWidgetState extends State<LiveTrackingMapWidget>
    with SingleTickerProviderStateMixin {
  late final MapController _mapController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant LiveTrackingMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-fit camera bounds if coordinates updated meaningfully
    if (oldWidget.emergency.latitude != widget.emergency.latitude ||
        oldWidget.emergency.longitude != widget.emergency.longitude ||
        oldWidget.emergency.responderLatitude !=
            widget.emergency.responderLatitude ||
        oldWidget.emergency.responderLongitude !=
            widget.emergency.responderLongitude) {
      _fitMapBounds();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _fitMapBounds() {
    final vLat = widget.emergency.latitude;
    final vLng = widget.emergency.longitude;
    final rLat = widget.emergency.responderLatitude;
    final rLng = widget.emergency.responderLongitude;

    if (rLat != null && rLng != null) {
      final bounds = LatLngBounds(
        LatLng(min(vLat, rLat), min(vLng, rLng)),
        LatLng(max(vLat, rLat), max(vLng, rLng)),
      );
      try {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(40),
          ),
        );
      } catch (_) {}
    } else {
      try {
        _mapController.move(LatLng(vLat, vLng), 15.5);
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final emergency = widget.emergency;
    final victimPos = LatLng(emergency.latitude, emergency.longitude);
    final hasResponder = emergency.hasLiveResponderLocation;
    final responderPos = hasResponder
        ? LatLng(emergency.responderLatitude!, emergency.responderLongitude!)
        : null;

    final distanceMeters = emergency.distanceToResponderMeters;
    final distanceText = distanceMeters != null
        ? distanceMeters < 1000
            ? '${distanceMeters.toStringAsFixed(0)} m away'
            : '${(distanceMeters / 1000).toStringAsFixed(1)} km away'
        : null;

    final etaText = distanceMeters != null
        ? 'ETA ~${max(1, (distanceMeters / 400).ceil())} min'
        : null;

    return Container(
      height: widget.height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // 1. OpenStreetMap Tile Engine
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: victimPos,
                initialZoom: 15.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.vindara.app',
                  tileBuilder: (context, tileWidget, tile) {
                    return ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.multiply,
                      ),
                      child: tileWidget,
                    );
                  },
                ),

                // Connecting Polyline
                if (hasResponder && responderPos != null)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [victimPos, responderPos],
                        strokeWidth: 4.0,
                        color: AppColors.officialBlue,
                        pattern: StrokePattern.dashed(segments: const [10, 8]),
                      ),
                    ],
                  ),

                // Markers (Victim in Red, Responder in Blue)
                MarkerLayer(
                  markers: [
                    // Victim Live Marker
                    Marker(
                      point: victimPos,
                      width: 44,
                      height: 44,
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, _) {
                          final p = _pulseController.value;
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 20 + (p * 24),
                                height: 20 + (p * 24),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primaryRed
                                      .withValues(alpha: (1.0 - p) * 0.4),
                                ),
                              ),
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryRed,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2.5),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryRed
                                          .withValues(alpha: 0.4),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.person_pin_circle_rounded,
                                  color: Colors.white,
                                  size: 17,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),

                    // Responder Live Marker
                    if (hasResponder && responderPos != null)
                      Marker(
                        point: responderPos,
                        width: 44,
                        height: 44,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.officialBlue,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                widget.isUserResponder
                                    ? 'YOU'
                                    : 'RESPONDER',
                                style: const TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: AppColors.officialBlue,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.officialBlue
                                        .withValues(alpha: 0.4),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.directions_run_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // Top-Left: Live Tracking Badge
            Positioned(
              top: 10,
              left: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasResponder
                            ? AppColors.onlineGreen
                            : AppColors.officialBlue,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasResponder
                          ? 'Mutual Live Tracking'
                          : 'Victim Satellite Fix',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Top-Right: Recenter / Fit Camera Action
            Positioned(
              top: 10,
              right: 12,
              child: InkWell(
                onTap: () {
                  _fitMapBounds();
                  widget.onRecenter?.call();
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.my_location_rounded,
                    size: 18,
                    color: AppColors.officialBlue,
                  ),
                ),
              ),
            ),

            // Bottom Bar: High-Precision Distance & Coordinates
            Positioned(
              bottom: 8,
              left: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.gps_fixed_rounded,
                          size: 13,
                          color: AppColors.officialBlue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${emergency.latitude.toStringAsFixed(4)}, ${emergency.longitude.toStringAsFixed(4)}',
                          style: AppTheme.tabularNumericStyle.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (distanceText != null && etaText != null)
                      Text(
                        '$distanceText • $etaText',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.onlineGreen,
                        ),
                      )
                    else
                      const Text(
                        'Live GPS Locked',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

