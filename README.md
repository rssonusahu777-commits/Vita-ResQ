# Vindara

> **Community Emergency Response Platform**  
> Package Identity: `com.vindara.app`  
> Release Version: `v1.0.0`

Vindara is an offline-first community emergency response platform built in Flutter, enabling civilians and verified local responders to coordinate rapidly both online and offline.

---

## Completed Phases Overview

| Phase | Milestone Description | Tag / Status |
|---|---|---|
| **Phase 1** | Project skeleton, architectural rules, core `Emergency` & `UserProfile` models, collision-resistant `EMG-2026-XXXXXXXX` ID generator | ✅ [`phase-1`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/phase-1) |
| **Phase 2** | Local offline storage (Hive), offline-independent GPS location service, repositories & Riverpod providers | ✅ [`phase-2`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/phase-2) |
| **Phase 3** | Rebrand to Vindara, real internet reachability probe, Cloud Firestore integration with atomic responder claims, and idempotent offline sync | ✅ [`phase-3`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/phase-3) |
| **Phase 4** | FCM push notification architecture, cold-start & background lifecycle deep-linking, privacy-minimal Cloud Function alert dispatch | ✅ [`phase-4`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/phase-4) |
| **Phase 5** | High-contrast emergency theme, Home Screen (`HELP` button), 112 Official Emergency layer, and live Emergency Detail screen | ✅ [`phase-5`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/phase-5) |
| **Phase 6** | Possible crash detection service (`sensors_plus`), 10-second cancellable countdown screen, and monitoring controls | ✅ [`phase-6`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/phase-6) |
| **Phase 7** | Nearby offline device-to-device peer relay (D2D mesh), verified responder rewards & trust progression, hybrid OpenStreetMap / offline distance card | ✅ [`phase-7`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/phase-7) |
| **Phase 8** | Production Firestore security rules, composite indexes, Teammate AI integration contract, and production release | ✅ [`v1.0.0`](https://github.com/rssonusahu777-commits/Vindara/releases/tag/v1.0.0) |

---

## Architectural Rules (Enforced & Tested)

1. **Real Reachability Probe**: Probes genuine HTTP reachability (`clients3.google.com/generate_204`), not raw Wi-Fi association (avoids captive portals).
2. **Offline-Independent GPS**: Satellite coordinates are captured and displayed immediately without dependency on map tiles or routing networks.
3. **Atomic Responder Claims**: Race conditions prevented via Firestore field-null checks (`primaryResponderId == null`) and local version guards.
4. **Authoritative State over Push Payloads**: The local Hive store and Cloud Firestore document are the source of truth; push alerts only trigger fetches.
5. **Cold-Start Deep-Linking**: Single-lifecycle routing safely navigates cold-start and background notification taps without race conditions.
6. **Single-Lifecycle Subscriptions**: All streams, sensors, and timers cancel cleanly via Riverpod `ref.onDispose` and widget lifecycle methods.
7. **Collision-Resistant IDs**: Generated client-side using `Random.secure()` in the format `EMG-2026-XXXXXXXX` (8 uppercase hex chars).
8. **Idempotent Offline Sync**: Relayed and offline emergencies are marked with `syncStatus: pending` and auto-drain cleanly upon connectivity recovery.
9. **Privacy-Minimal Alerts**: Push notifications strictly omit victim names, medical details, and exact addresses (`{ emergencyId, type }` only).
10. **Honest "Possible Crash" Framing**: Crash heuristics are labeled honestly without guaranteeing certainty, guarded by a 10s cancel countdown and strictly zero `"SOS"` strings.

---

## Setup & Execution Guide

### Prerequisites
- **Flutter SDK**: `>=3.3.0 <4.0.0`
- **Dart SDK**: `^3.3.0`
- **Firebase CLI**: `npm install -g firebase-tools` (for security rules, indexes, and Cloud Functions)

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run the App Locally
```bash
# Debug mode on connected device / emulator
flutter run
```

### 3. Run the Complete Test Suite
```bash
# Execute all 131+ unit, widget, and integration tests
flutter test --no-pub
```

### 4. Static Code Analysis
```bash
flutter analyze
# or
dart analyze lib test
```

---

## Firebase Deployment

Deploy the production security rules, composite database indexes, and Cloud Functions:

```bash
# 1. Log in to Firebase CLI
firebase login

# 2. Select your Firebase project
firebase use <your-project-id>

# 3. Deploy Firestore Security Rules
firebase deploy --only firestore:rules

# 4. Deploy Firestore Composite Indexes
firebase deploy --only firestore:indexes

# 5. Deploy Cloud Functions (Alert Dispatch + Responder Rewards)
cd functions
npm install
cd ..
firebase deploy --only functions
```

---

## Teammate AI Integration

Refer to [`docs/TEAMMATE_AI_CONTRACT.md`](docs/TEAMMATE_AI_CONTRACT.md) for specifications on adding:
- Multimodal Camera/Mic Severity Estimation.
- Mathematical Responder Ranking Engine (`functions/index.js`).
