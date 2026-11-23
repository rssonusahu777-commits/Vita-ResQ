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
| **Phase 5** | Core UI: Home Screen (HELP button), 112 Official layer, and live Emergency Detail screen | ✅ Completed (`phase-5`) |
| **Phase 6** | Possible crash detection service (sensors_plus), 10s cancellable countdown, and monitoring controls | ✅ Completed (`phase-6`) |
| **Phase 7** | Nearby offline device-to-device relay, responder rewards & trust progression, hybrid OSM/offline distance card | ⏳ In Progress |

---

## Running Tests

```bash
flutter test
```

## Running the App

```bash
flutter run
```
