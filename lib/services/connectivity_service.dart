// lib/services/connectivity_service.dart
//
// Vindara — Real Internet Reachability Service
// Package: com.vindara.app
//
// Design rule:
//   Rule #1 — Real reachability vs. no-Wi-Fi.
//   Never trust ConnectivityResult alone. Always verify end-to-end internet
//   reachability via active lightweight HTTP probe (HEAD/GET with 3s timeout).

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;

/// Interface for probing network endpoints to verify end-to-end reachability.
abstract class NetworkReachabilityProbe {
  Future<bool> probe({Duration timeout = const Duration(seconds: 3)});
}

/// Default HTTP probe that pings reliable captive-portal / connectivity endpoints.
class HttpReachabilityProbe implements NetworkReachabilityProbe {
  final http.Client _client;
  final List<Uri> probeUrls;

  HttpReachabilityProbe({
    http.Client? client,
    List<Uri>? urls,
  })  : _client = client ?? http.Client(),
        probeUrls = urls ??
            [
              Uri.parse('https://www.google.com/generate_204'),
              Uri.parse('https://1.1.1.1/cdn-cgi/trace'),
            ];

  @override
  Future<bool> probe({Duration timeout = const Duration(seconds: 3)}) async {
    for (final url in probeUrls) {
      try {
        final response = await _client.head(url).timeout(timeout);
        if (response.statusCode >= 200 && response.statusCode < 400) {
          return true;
        }
      } catch (_) {
        // Try fallback GET if HEAD is rejected by intermediate proxy
        try {
          final getResponse = await _client.get(url).timeout(timeout);
          if (getResponse.statusCode >= 200 && getResponse.statusCode < 400) {
            return true;
          }
        } catch (_) {
          // Continue to next probe url
        }
      }
    }
    return false;
  }
}

/// Service that combines interface connectivity events with active HTTP probes
/// to expose a continuous, reliable [isOnline] stream and on-demand [checkReachability].
class ConnectivityService {
  final Connectivity _connectivity;
  final NetworkReachabilityProbe _probe;
  final Duration periodicInterval;

  final StreamController<bool> _isOnlineController =
      StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicTimer;

  bool _lastKnownOnlineState = false;

  ConnectivityService({
    Connectivity? connectivity,
    NetworkReachabilityProbe? probe,
    this.periodicInterval = const Duration(seconds: 30),
  })  : _connectivity = connectivity ?? Connectivity(),
        _probe = probe ?? HttpReachabilityProbe();

  /// Whether current verified state is online.
  bool get isCurrentlyOnline => _lastKnownOnlineState;

  /// Continuous stream emitting true when verified online, false otherwise.
  Stream<bool> get isOnline => _isOnlineController.stream;

  /// Initializes listening to connectivity changes and starts background health checks.
  Future<void> init() async {
    // Perform initial check
    final initial = await checkReachability();
    _updateState(initial);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (results) async {
        final hasInterface = results.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.ethernet,
        );

        if (!hasInterface) {
          _updateState(false);
        } else {
          // Interface exists: perform immediate active probe to check for captive portals or dead Wi-Fi
          final online = await _probe.probe();
          _updateState(online);
        }
      },
    );

    // Periodic safety check in case DNS/routing fails without interface drop
    if (periodicInterval > Duration.zero) {
      _periodicTimer = Timer.periodic(periodicInterval, (_) async {
        final online = await checkReachability();
        _updateState(online);
      });
    }
  }

  /// On-demand reachability check.
  Future<bool> checkReachability() async {
    final results = await _connectivity.checkConnectivity();
    final hasInterface = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet,
    );

    if (!hasInterface) {
      return false;
    }

    return await _probe.probe();
  }

  void _updateState(bool isOnline) {
    if (_lastKnownOnlineState != isOnline || !_isOnlineController.hasListener) {
      _lastKnownOnlineState = isOnline;
      if (!_isOnlineController.isClosed) {
        _isOnlineController.add(isOnline);
      }
    }
  }

  /// Disposes stream subscriptions and timers.
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _periodicTimer?.cancel();
    await _isOnlineController.close();
  }
}

