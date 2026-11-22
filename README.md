# SafeReach

> Community Emergency Response Platform — `com.example.safereach`

## Phase 1 (current): Project Skeleton, Architecture Rules & Core Domain Models

| File | Description |
|---|---|
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Full architecture reference & 10 bug-prevention rules |
| [`lib/models/emergency.dart`](lib/models/emergency.dart) | Core `Emergency` entity with state machine |
| [`lib/models/user_profile.dart`](lib/models/user_profile.dart) | `UserProfile` domain model |
| [`lib/main.dart`](lib/main.dart) | App entry point, route stubs |
| [`pubspec.yaml`](pubspec.yaml) | Phase-annotated dependency list |
| [`test/models/emergency_test.dart`](test/models/emergency_test.dart) | Unit tests for `Emergency` |
| [`test/models/user_profile_test.dart`](test/models/user_profile_test.dart) | Unit tests for `UserProfile` |

## Running the tests

```bash
flutter test
```

## Running the app

```bash
flutter run
```

## Renaming from SafeReach

1. Update `name:` in `pubspec.yaml`.
2. Update `applicationId` in `android/app/build.gradle`.
3. Update `PRODUCT_BUNDLE_IDENTIFIER` in `ios/Runner.xcodeproj`.
4. Search & replace `com.example.safereach` and `safereach` project-wide.

