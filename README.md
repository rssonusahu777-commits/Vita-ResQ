# Vindara

> Community Emergency Response Platform — `com.vindara.app`

Vindara is an offline-first community emergency response platform built in Flutter, enabling civilians and verified local responders to coordinate rapidly online and offline.

---

## Phases & Status

| Phase | Description | Status |
|---|---|---|
| **Phase 1** | Project skeleton, architecture rules, core `Emergency` & `UserProfile` models | ✅ Completed (`phase-1`) |
| **Phase 2** | Local offline storage (Hive), offline-independent GPS location service, repositories & Riverpod providers | ✅ Completed (`phase-2`) |
| **Phase 3** | Rebrand to Vindara, real internet reachability probe, Cloud Firestore integration with atomic responder claims, and idempotent sync | ✅ Completed (`phase-3`) |
| **Phase 4** | FCM push notifications, all-state lifecycle deep-linking, privacy-minimal Cloud Function alert dispatch | ✅ Completed (`phase-4`) |
| **Phase 5** | Core UI: Home Screen (HELP button) and Responder Dashboard | ⏳ Up Next |
| **Phase 6** | Accelerometer crash detection ("Possible Crash" flow with 30s countdown) | ⏳ Planned |
| **Phase 7** | Nearby mesh relay (BLE / Wi-Fi Direct) | ⏳ Planned |

---

## Running Tests

```bash
flutter test
```

## Running the App

```bash
flutter run
```
