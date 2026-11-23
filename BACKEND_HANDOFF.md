# Vindara — Merged Backend Architecture & Handoff Guide

> **Vindara** is a Community Emergency Response Platform built with an offline-first mesh philosophy. It connects victims facing medical, road crash, fire, or safety emergencies with nearby civilian responders and official dispatch channels (112).
>
> **Status:** Backend logic merged from `Vindara-main` into `Vindara` workspace. Static analysis: `flutter analyze` reports **0 issues**.

---

## 1. Merged Architecture & Folder Structure

The Flutter application strictly decouples UI widgets from backend services and cloud SDKs using `EmergencyRepository` and `FirebaseEmergencyRepository`.

```text
lib/
├── core/
│   ├── constants/
│   │   └── app_constants.dart          # System strings, official 112 hotline, emergency categories
│   └── theme/
│       └── app_theme.dart              # Material 3 light design system (Ivory #FAF9F6, White #FFFFFF)
├── constants/
│   └── platform_limitations.dart       # Transparent OS limitation disclosures (iOS BLE/background)
├── models/
│   ├── emergency.dart                  # Canonical Emergency model with toJson, fromJson, generateId(), state transitions
│   ├── responder.dart                  # Responder profile & verification model
│   └── user_profile.dart               # Firestore user profile model (reputation, badges, trust)
├── data/
│   ├── mock_emergency_repository.dart  # Abstract EmergencyRepository interface & in-memory mock repository
│   └── firebase_emergency_repository.dart # Production hybrid EmergencyRepository (Firestore + Hive + fallback)
├── services/
│   ├── firestore_emergency_service.dart# Firestore CRUD & atomic transaction claimEmergency()
│   ├── local_emergency_store.dart      # Offline-first Hive store with syncStatus (pending, synced, failed)
│   ├── sync_service.dart               # Idempotent cloud sync trigger on network re-connection
│   ├── connectivity_service.dart       # Connectivity state listener (connectivity_plus)
│   ├── location_service.dart           # Honest GPS acquisition with accuracy meters (no silent fallbacks)
│   ├── crash_detection_service.dart    # Accelerometer / impact detection (sensors_plus)
│   ├── nearby_relay_service.dart       # Local BLE / Wi-Fi mesh relay service stubs
│   ├── notification_service.dart       # Push notification handlers (FCM / Local Notifications)
│   └── reputation_service.dart         # Self-tracked community badge & reputation service
├── screens/                            # Complete Vindara UI screens (source of truth)
└── widgets/                            # Reusable UI widgets & status badges
firestore.rules                         # Server-side Firestore security rules (strict schema & auth checks)
firestore.indexes.json                  # Firestore composite queries index definitions
functions/
├── index.js                            # Firebase Cloud Functions (FCM push dispatch on emergency creation)
└── package.json                        # Cloud Functions Node.js dependencies
```

---

## 2. Merged Backend Components

### A. Firebase & Cloud Firestore
- **`lib/firebase_options.dart`:** Initial platform configuration for Web, Android, and iOS.
- **`lib/services/firestore_emergency_service.dart`:**
  - `upsertEmergency(Emergency)`: Version-guarded optimistic write (Rule #8).
  - `claimEmergency(emergencyId, responderId)`: **Atomic Transaction (Rule #3)** ensuring no race conditions for Primary vs Standby slots.
  - `releasePrimaryRole(emergencyId, responderId)`: Promotes standby to primary if standby exists, or resets status to `alerting`.
  - `watchRemoteEmergency(id)`: Real-time document snapshot stream.
- **`firestore.rules`:**
  - Enforces `^EMG-2026-[A-F0-9]{8}$` format.
  - Requires authenticated victim creation with `version >= 1`.
  - Enforces monotonic version increment on updates (`request.resource.data.version > resource.data.version`).
  - Immutable metadata: `victimId`, `createdAt`, `id`.
  - Delete operation is strictly denied to preserve audit integrity.

### B. Offline-First Hive Store & Auto-Sync
- **`lib/services/local_emergency_store.dart`:**
  - Offline persistence using Hive boxes (`emergencies_box` and `meta_box`).
  - Stores each emergency in an envelope with `syncStatus` (`pending`, `synced`, `failed`) and ISO-8601 UTC timestamp.
  - Maintains single broadcast stream per active emergency.
- **`lib/services/sync_service.dart`:**
  - Listens to `ConnectivityService.isOnline`.
  - Idempotently flushes all `pending` or `failed` local records to Firestore when connectivity is restored.

### C. Cloud Functions (FCM Push Dispatch)
- **`functions/index.js`:**
  - Triggers on `functions.firestore.document('emergencies/{emergencyId}').onCreate`.
  - Dispatches high-priority silent / heads-up push alert payload containing only `{ emergencyId: doc.id }`.
  - Zero PII in push payloads for privacy and compliance.
  - Client application queries fresh authoritative document on notification tap.

---

## 3. Strict Trust & Safety Guardrails Enforced

1. **No Silent Delhi Coordinates Fallback:**
   - Default Delhi coordinates (`28.6139, 77.2090`) are removed. If GPS lock fails, real coordinates with accuracy warning or manual landmark prompts are displayed.
2. **Atomic Responder Slot Claiming:**
   - Both Cloud Firestore and client repository enforce single-primary atomic assignment via `runTransaction`.
3. **No Fake Hospital Numbers / Response Times:**
   - Emergency contacts use the user's verified contacts or official `112`. Estimated ETAs are computed strictly from real distance or clearly marked as estimates.
4. **Transparent Civilian Volunteer Status:**
   - Responders are explicitly labeled as `Citizen Volunteer` / `Community Responder`, never claiming unverified professional paramedic status.

---

## 4. How the App Boots

In `lib/main.dart`:
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  EmergencyRepository repository;
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
    final fbRepo = FirebaseEmergencyRepository();
    await fbRepo.init();
    repository = fbRepo;
  } catch (e) {
    debugPrint('Firebase not initialized or running in local demo mode: $e');
    repository = MockEmergencyRepository();
  }

  runApp(VindaraApp(repository: repository));
}
```
If Firebase project credentials are configured and reachable, `FirebaseEmergencyRepository` actively manages Firestore and Hive sync. In local browser preview or demo mode without live credentials, it automatically falls back to `MockEmergencyRepository` so the UI runs with zero errors.
