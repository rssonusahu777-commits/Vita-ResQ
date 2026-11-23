# Vindara — Features & Living Changelog

> **Package:** `com.vindara.app`  
> **Platform:** Flutter (Android & iOS)  
> **Status:** Production Release (`v1.0.1`)  
> **Rule:** Every developer and AI agent MUST update this document immediately upon completing any feature, enhancement, or bug fix.

---

## 1. Feature Catalog

### Feature 1: Real Internet Reachability Probe
- **Implementation:** `lib/services/connectivity_service.dart`
- **Architectural Rule:** Rule #1 — Real Reachability vs. No-Wi-Fi.
- **Description:** Never trusts raw `ConnectivityResult` interfaces alone. Performs an active, lightweight HTTP probe (HEAD request with fallback to GET, 3-second timeout) against captive-portal endpoints (`google.com/generate_204`, `1.1.1.1/cdn-cgi/trace`) to distinguish authentic end-to-end internet connectivity from dead Wi-Fi or captive login portals.
- **Failover:** When unreachable, switches seamlessly to `CommunicationMode.offlineNearby` or `offline` to enable offline mesh broadcasting.

### Feature 2: Cloud Firestore with Atomic Responder Claims
- **Implementation:** `lib/services/firestore_emergency_service.dart`, `lib/data/firebase_emergency_repository.dart`
- **Architectural Rule:** Rule #3 — Atomic Responder Claims (Concurrency Safety).
- **Description:** Multi-responder race conditions are impossible by design. Claims execute within atomic Firestore transactions checking `primaryResponderId == null`. If two volunteers tap "Accept" concurrently, the first transaction claims `primaryResponderId`, and the second is safely and atomically routed to `standbyResponderId`.

### Feature 3: Idempotent Offline Sync & Local Persistence
- **Implementation:** `lib/services/local_emergency_store.dart`, `lib/services/sync_service.dart`
- **Architectural Rule:** Rule #4 & Rule #8 — Authoritative State over Push Payloads & Idempotent Sync.
- **Description:** Built on an offline-first Hive storage foundation. Emergencies triggered offline are persisted with `syncStatus: pending`. When verified internet reachability returns, the sync service drains the local queue idempotently into Cloud Firestore without duplication or overwrite hazards.

### Feature 4: Multimodal Incident Severity Estimation
- **Implementation:** `lib/services/multimodal_severity_service.dart`
- **Contract Reference:** `docs/TEAMMATE_AI_CONTRACT.md`
- **Description:** Non-blocking 2.5-second scene analysis initiated immediately after HELP button trigger. Evaluates background noise patterns (decibel surge, crash transients) and optional scene imagery. Computes an apparent `EmergencySeverity` (`low`, `moderate`, `high`, `critical`) and recommended responder skill requirements (e.g. `['cpr', 'first_aid']`).
- **Privacy & Safety Non-Negotiable:** Raw audio/image buffers are strictly wiped immediately after feature extraction (`rawAudioBuffer.clear()`, `rawImageBuffer.clear()`). The engine provides apparent context estimation only, never automated medical diagnosis.

### Feature 5: Fair & Proximity-Weighted Responder Ranking Engine
- **Implementation:** `lib/services/responder_ranking_service.dart`
- **Description:** Mathematical scoring algorithm for routing alerts to the most effective nearby community responders:
  $$\text{Score} = (W_{\text{dist}} \times S_{\text{dist}}) + (W_{\text{rep}} \times S_{\text{rep}}) + (W_{\text{act}} \times S_{\text{act}}) + \text{Bonus}_{\text{skill}}$$
  In critical emergencies (severity `critical`), the proximity weight $W_{\text{dist}}$ automatically boosts from `0.50` to `0.80`, ensuring the physically closest responder is prioritized when seconds save lives.

### Feature 6: Possible Crash Detection Heuristic
- **Implementation:** `lib/services/crash_detection_service.dart`, `lib/screens/crash_countdown_screen.dart`
- **Architectural Rule:** Rule #10 — Honest "Possible Crash" Framing & Zero SOS Labels.
- **Description:** Real-time accelerometer and motion pattern monitoring. Detects abrupt negative deceleration patterns (>24 m/s²) coupled with subsequent stillness. Triggers a high-priority 10-second cancellable audio/haptic countdown screen allowing the driver or rider to tap "I am Safe". If uncancelled after 10 seconds, dispatches an automated HELP alert with hardware GPS coordinates.

### Feature 7: Offline Device-to-Device Mesh Relay (BLE / Wi-Fi Direct)
- **Implementation:** `lib/services/nearby_relay_service.dart`
- **Description:** Enables emergency alert propagation when cellular towers and Wi-Fi networks are completely unavailable. Dispatches emergency packets over peer-to-peer transport within a 100-meter physical radius. Relayed packets carry deduplication hashes and hop counts to avoid mesh broadcast storms.

### Feature 8: Official 112 Safety Layer & Emergency Escalation
- **Implementation:** `lib/screens/sos_hub_screen.dart`, `lib/screens/active_emergency_screen.dart`
- **Description:** Directly integrates India's unified emergency number (`112`) alongside community volunteers. Offers one-tap direct telephone dialing to official police, fire, and ambulance dispatch centers, ensuring community support complements rather than replaces official emergency services.

### Feature 9: Real GPS Hardware Fix & Sequential Fallback
- **Implementation:** `lib/services/location_service.dart`
- **Architectural Rule:** Rule #2 — Offline-Independent GPS.
- **Description:** Eliminates `0.000000, 0.000000` coordinate lock. Implements a robust sequential acquisition pipeline:
  1. Active high-accuracy satellite GPS fix (`getCurrentPosition`, 8s timeout).
  2. Platform hardware last known fix (`getLastKnownPosition`).
  3. Locally persisted last valid coordinate fix.
  Coordinates render instantly in tabular monospace figures without depending on map tile downloads.

### Feature 10: Camera & Microphone AI Opt-In & Instant Buffer Destruction
- **Implementation:** `lib/screens/auth_screen.dart`, `lib/screens/profile_screen.dart`, `lib/services/local_emergency_store.dart`
- **Description:** Transparent user consent during onboarding and profile settings. Users choose "Enable Now" or "Skip for Now" for emergency condition and skill-matching analysis. Zero runtime popups interrupt a live emergency, and user preferences persist locally in `LocalEmergencyStore`.

### Feature 11: True Offline Peer-to-Peer (P2P) Emergency HELP Mesh (`nearby_connections`)
- **Implementation:** `lib/services/offline_p2p_service.dart`, `nearby_connections` package (`Strategy.P2P_CLUSTER`).
- **Architectural Rules:** Rule #1 (Offline-First), Rule #2 (Raw GPS preservation), Rule #4 (Source of truth & Firestore sync), Rule #6 (Single-lifecycle subscriptions), Rule #7 (Deduplication by `emergencyId`), Rule #8 (Hive local-first persistence with `SyncStatus.pending`), Rule #10 (Zero "SOS" labels; honest HELP framing).
- **Description:** True device-to-device offline mesh network operating over Bluetooth Low Energy (BLE) and Wi-Fi Direct using Nearby Connections `Strategy.P2P_CLUSTER`. When a victim or citizen dispatches a HELP request without cellular coverage or active Wi-Fi, the alert is converted into a compact binary JSON payload and broadcast directly to nearby peers within radio range (~100m). Discovered peer devices automatically establish connections, accept incoming packets, deduplicate by `emergencyId` using an in-memory hash set, and persist the emergency into local Hive storage tagged as `SyncStatus.pending`.
- **Hybrid Cloud Relay:** If any peer receiving the offline P2P emergency alert has active internet reachability (verified via `ConnectivityService`), that peer acts as a community gateway, automatically syncing the emergency to Cloud Firestore (`FirestoreEmergencyService.upsertEmergency`) and marking it synced locally.
- **Privacy & Lightweight Radios:** The P2P byte payload is strictly constrained to emergency coordinates, victim details, type, apparent severity, and recommended responder skills (`cpr`, `first_aid`), completely omitting heavy media (audio/camera buffers) to guarantee rapid packet delivery and maintain victim privacy.

---

## 2. Changelog History

### [v1.0.2] — 2026-11-23: True Offline Peer-to-Peer (P2P) Emergency HELP Mesh & Cluster Relay
- **Nearby Connections Engine:** Added `nearby_connections: ^4.3.0` and Android 12+ / legacy Nearby permissions in `AndroidManifest.xml` (`NEARBY_WIFI_DEVICES`, `BLUETOOTH_ADVERTISE`, `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`, `CHANGE_NETWORK_STATE`).
- **P2P Service Architecture:** Created `OfflineP2pService` and `P2pHelpPayload` with binary serialization/deserialization, `NearbyClient` interface and `DefaultNearbyClient` / `MockNearbyClient` for testability without native channels.
- **Auto-Handshake & Cluster Mesh:** Implemented `Strategy.P2P_CLUSTER` multi-peer mesh with auto-accept handshakes, packet deduplication by `emergencyId`, local-first Hive storage (`SyncStatus.pending`), and real-time UI stream notification.
- **Community Cloud Gateway Relay:** Configured automatic Firestore sync hook when an offline P2P alert is received by an online device, seamlessly bridging disconnected victims to cloud responders.
- **UI P2P Indicators:** Added real-time P2P status indicators and listener subscriptions across `SosHubScreen`, `ActiveEmergencyScreen`, and `ResponderAlertsScreen` displaying "Offline P2P Mesh Ready", "Broadcasting HELP Nearby", and "Nearby HELP Received via P2P".
- **Comprehensive Unit Tests:** Created `test/services/offline_p2p_service_test.dart` validating payload encoding, zero raw media buffers, deduplication, cloud relay, and mesh lifecycle.

### [v1.0.1] — 2026-11-23: Live Firebase Sync, Real GPS Fallback, Profile Dynamic Stats & Zero SOS Purge
- **Live Firebase Integration:** Connected `vindara-d3d93` credentials (`AIzaSyCpw7Qwe5S_VX-x3VOwkFKGwj-MAfnt5Is`) directly across Android, Web, and iOS configurations in `lib/firebase_options.dart`.
- **Auth Exception UX:** Enhanced `AuthScreen` with friendly, actionable error dialogs for Firebase Auth codes (`invalid-api-key`, `user-not-found`, `wrong-password`, `network-request-failed`).
- **Sequential GPS Fallback:** Added `LocationService.acquireBestAvailableFix()`. Updated `ActiveEmergencyScreen` and `SosHubScreen` to display "Acquiring Satellite GPS Fix..." and automatically lock coordinates without remaining at `0.0, 0.0`.
- **Dynamic Responder Stats:** Removed hardcoded profile values (`'ayush patnayak'`, `'28 Assists'`, `'120 Points'`) from `ProfileScreen`, `MainShell`, `CertificatesScreen`, and `RewardsScreen`. Profiles for new users dynamically display verified `0` counts and real Firebase Auth emails.
- **Emergency AI Opt-In Toggle:** Added Camera & Microphone Scene Assist switch in `ProfileScreen` calling `LocalEmergencyStore().setCameraMicOptIn()`.
- **Strict Zero "SOS" Enforcement:** Purged every user-facing "SOS" string across all UI screens, widgets, badges, and alerts in compliance with Rule #10. All interfaces display honest, clear "HELP" terminology.

### [v1.0.0] — 2026-11-23: Phase 8 Production Firestore Security Rules & Composite Indexes
- **Production Firestore Rules:** Auth-protected `users/{uid}` rules prohibiting client-side score/badge tampering. Server-side timestamp guards and atomic claim rules for `emergencies/{emergencyId}`.
- **Composite Indexes:** Deployed `firestore.indexes.json` supporting compound queries for active emergency status and proximity ordering.
- **Teammate AI Contract:** Ratified `docs/TEAMMATE_AI_CONTRACT.md` establishing zero-interruption, non-blocking AI scene estimation standards.

### [Phase 7] — 2026-11-23: Offline D2D Peer Relay & Responder Trust Progression
- **Nearby Mesh Transport:** Implemented `NearbyRelayService` with deduplication and hop limit guards.
- **Trust Progression:** Added reputation scoring model rewarding completed verified assists while avoiding harmful gamification.
- **Offline Map Fallback:** Implemented hybrid OpenStreetMap view that falls back cleanly to coordinate cards when offline.

### [Phase 6] — 2026-11-23: Possible Crash Detection & 10s Cancellable Countdown
- **Crash Detection Heuristic:** Implemented `CrashDetectionService` using `sensors_plus` pattern detection.
- **Grace Countdown UI:** High-visibility 10-second countdown screen with sensory haptic pulses and prominent "I am Safe" cancellation button.

### [Phase 5] — 2026-11-23: Vindara High-Contrast UI & 112 Safety Layer
- **High-Contrast Theme:** High-stress emergency readability with clean typography and large touch targets.
- **112 Safety Layer:** Integrated official emergency contact actions alongside community assistance.
- **Live Emergency Detail Screen:** 4-step progress tracker, responder pins, and direct contact options.

### [Phase 4] — 2026-11-23: Bulletproof FCM Push Notifications & Cold-Start Deep-Linking
- **FCM Architecture:** Cold-start and background notification handling with single-lifecycle listeners.
- **Privacy-Minimal Alerts:** Multicast notifications omitting sensitive victim identity details.

### [Phase 3] — 2026-11-23: Vindara Rebrand, Real Reachability & Atomic Firestore Claims
- **Project Identity:** Rebranded project to Vindara (`com.vindara.app`).
- **HTTP Probe:** Active probe verifying genuine internet reachability.
- **Atomic Claims:** Concurrency-safe Firestore transactions preventing double-assignment.

### [Phase 2] — 2026-11-22: Local Persistence & Riverpod Architecture
- **Hive Database:** Local persistence for emergency records and user profiles.
- **State Management:** Riverpod providers managing reactive emergency streams and offline state.

### [Phase 1] — 2026-11-22: Foundation & Domain Core
- **Domain Modeling:** Initial `Emergency` and `UserProfile` domain models.
- **Collision-Resistant IDs:** `EMG-2026-XXXXXXXX` format generated using cryptographically secure random values.

---

## 3. Mandatory Rule for Developers & AI Agents
> [!IMPORTANT]
> Whenever any code changes are introduced—whether a new feature, performance optimization, refactoring, or bug fix—the authoring engineer or AI assistant **MUST** update this file (`docs/FEATURES_AND_CHANGELOG.md`) in the same turn or commit:
> 1. Add or refine the feature description in **Section 1 (Feature Catalog)**.
> 2. Add an entry to **Section 2 (Changelog History)** noting the version, date, and exact changes made.

