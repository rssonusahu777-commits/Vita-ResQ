# 🚨 Vita ResQ — Autonomous & Civilian Emergency Response Network

[![Flutter Tests](https://img.shields.io/badge/Flutter%20Tests-425%20Passing-brightgreen.svg)](test/)
[![Backend Tests](https://img.shields.io/badge/Backend%20Tests-84%20Passing-brightgreen.svg)](backend/test/)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-blue.svg)](pubspec.yaml)
[![License](https://img.shields.io/badge/License-MIT-orange.svg)](LICENSE)

**Vita ResQ** (formerly *Jan Sarthi*) is a resilient, hybrid emergency dispatch, civilian mutual-aid coordination, and AI-assisted triage platform engineered to save lives during critical first-response minutes. It combines online cloud infrastructure with offline direct peer-to-peer (P2P) connectivity to guarantee uninterrupted alert delivery even in zero-connectivity disaster zones.

> **Disclaimer:** Vita ResQ is a civilian mutual-aid assistance platform and does **not** replace national emergency services (112 / 911). In life-threatening emergencies, always contact official authorities directly.

---

## 🌟 Key Capabilities

- 🚨 **Hold-to-Activate SOS**: Deliberate 1.5-second press-and-hold trigger with glowing circular progress ring, haptics, and accidental tap cancellation.
- 📡 **Dual-Mode Hybrid Transport**:
  - **Online**: Firebase Firestore streams + Cloud Functions geofencing + FCM push notifications.
  - **Offline**: Google Nearby Connections direct P2P over BLE / Wi-Fi Direct with zero internet dependency.
  - **Application-Layer Integrity**: Pure-Dart FIPS 180-4 SHA-256 payload signing and tamper rejection (`P2PPayloadIntegrity`).
  - **Mutual Exclusion**: Seamless automatic fallback and background sync when network is restored.
  - **Community Cloud Gateway Relay**: 1-hop bystander P2P-to-Firestore bridge for fresh ($\le 10$ min) SHA-256 verified `JS-OFF-` alerts with idempotent non-overwrite protection and dedicated `firestore.rules` enforcement.
- 👥 **Authoritative Two-Way Claim Handshake & Role-Weighted Failover**: Multi-tier responder pool supporting `PRIMARY` and `STANDBY` roles. Deterministic role + proximity scoring (`DOCTOR` > `AMBULANCE_DRIVER` > `POLICE_PCR` > `CITIZEN`) with linear decay for 120s stall failover and manual breakdown handovers.
- 📴 **Guest Offline Emergency Access**: Logged-out `"Continue Offline (Emergency Access)"` flow on `LoginScreen` using isolated guest state and persistent `originDeviceId` without touching `local_user_profile_v2`.
- ⚡ **Dynamic Reliability Watchdog & Auto-Handover**: Continuously monitors responder ETA, progress, and GPS staleness. 120-second stall timer prevents false failovers at traffic lights while detecting genuine responder stalling.
- 🗺️ **Open-Source Navigation**: Powered by OpenStreetMap and OSRM for live road routing, polylines, and dynamic ETA with direct Haversine fallback and 8-meter movement throttling.
- 🤖 **AI Assistant & Situation Briefing (Google Gemini 3.8 Flash)**: Context-aware, privacy-sanitized emergency situational guidance with low-latency thinking configuration and multi-language support (English & Hindi).
- 🎙️ **Emergency Voice Assistant (ElevenLabs)**: Ultra-low latency voice transcription (Scribe v2) and clear text-to-speech feedback (Eleven Flash v2.5) for hands-free emergency communication.
- 📊 **Tiger Data & TimescaleDB Analytics**: Local-first telemetry and historical emergency insights dashboard for response time and route analysis.
- 📖 **Bilingual Helpline Directory**: Integrated emergency helpline directory with instant search, category filtering, and direct dialing.
- 🚗 **Sensor-Assisted Crash Detection**: Multi-sensor scoring matrix evaluating linear acceleration, angular rotation, velocity drop, and vehicle context with a 15-second cancellable confirmation dialog.

---

## 🏗️ Architecture Overview

```text
                                [ User Holds SOS (1.5s) ]
                                            │
                       ┌────────────────────┴────────────────────┐
                       ▼                                         ▼
               [ Online Mode ]                            [ Offline Mode ]
           Firestore + FCM + OSRM                      Nearby Direct P2P (BLE/Wi-Fi)
                       │                                   + SHA-256 Integrity
                       └────────────────────┬────────────────────┘
                                            ▼
                                [ Two-Way Claim Handshake ]
                                • PRIMARY (Live Route HUD)
                                • STANDBY (Hot Backup)
                                            │
                       ┌────────────────────┼────────────────────┐
                       ▼                    ▼                    ▼
          [ ResponderReliabilityMonitor ] [ Gemini Assistant ] [ Voice & Helpline ]
          • Telemetry Watchdog (>15s)    • Privacy Sanitized  • ElevenLabs STT/TTS
          • Stall Watchdog (>120s)       • 112 Statutory Safe • Offline Directory
          • Standby Promotion            • English / Hindi    • Instant Dialer
```

---

## 📁 Repository Structure

```text
├── android/                        # Android native configuration, Kotlin source & manifests
├── backend/                        # Node.js Express AI & Analytics backend
│   ├── src/                        # Middleware, routes, services (Gemini, ElevenLabs, TimescaleDB)
│   ├── test/                       # 84 automated backend unit & security tests
│   └── .env.example                # Environment configuration template
├── functions/                      # Firebase Cloud Functions (backend geofenced dispatch)
├── ios/                            # iOS native configuration & Info.plist
├── lib/
│   ├── core/                       # Theme, styling, constants, & navigation
│   ├── models/                     # Schemas for users, emergencies, responders, & helplines
│   ├── screens/                    # UI screens (Home, SOS Map, Details, History, Auth, Analytics)
│   ├── services/                   # Business logic, P2P networking, OSRM routing, AI assistant
│   └── widgets/                    # Custom UI widgets (Hold SOS button, OSM Map, AI Sheet)
├── test/                           # 425 automated Flutter unit, widget, and integration tests
├── pubspec.yaml                    # Dependencies and asset declarations
├── VITA_RESQ_FEATURES.md           # Quick-reference feature notepad (122 features)
└── VITA_RESQ_MASTER_CHANGELOG.md   # Canonical master project changelog & specification
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.24+ / Dart 3.5+)
- [Node.js](https://nodejs.org/) (v20+ recommended for backend)
- [Android Studio](https://developer.android.com/studio) / Android SDK (API 21+)
- [Firebase CLI](https://firebase.google.com/docs/cli) (for local emulator or Cloud Functions testing)

---

### 1. Flutter Mobile App Setup

1. **Clone the repository:**
   ```bash
   git clone https://github.com/karan442201-cmyk/Vita-resQ.git
   cd Vita-resQ
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Run Flutter tests:**
   ```bash
   flutter test
   ```

4. **Launch the application:**
   ```bash
   # Standard launch (default AI backend target: http://10.0.2.2:3000 for Android Emulator)
   flutter run

   # Or target a local physical device with ADB reverse proxying:
   flutter run --dart-define=AI_BACKEND_URL=http://localhost:3000
   ```

---

### 2. AI Assistant & Analytics Backend Setup

The backend service is located in `backend/` and provides Gemini AI situation briefs, ElevenLabs voice processing, and TimescaleDB analytics.

1. **Navigate to the backend directory and install dependencies:**
   ```bash
   cd backend
   npm install
   ```

2. **Configure Environment Variables:**
   Copy `.env.example` to `.env`:
   ```bash
   cp .env.example .env
   ```

3. **Provide Your Local API Keys in `backend/.env`:**
   > **Security Note:** Never commit your `.env` file into Git. It is excluded by `.gitignore`.

   - `PORT`: HTTP port for local backend (default: `3000`).
   - `GEMINI_API_KEY`: Obtain an API key from [Google AI Studio](https://aistudio.google.com/).
   - `GEMINI_MODEL`: Defaults to `gemini-3.8-flash`.
   - `FIREBASE_PROJECT_ID`: Firebase project identifier (`vita-resq` or `demo-vita-resq-local` for emulator testing).
   - `ELEVENLABS_API_KEY`: *(Optional)* API key from [ElevenLabs](https://elevenlabs.io/) for voice STT/TTS.
   - `TIMESCALE_DATABASE_URL`: *(Optional)* PostgreSQL/TimescaleDB connection string for analytics storage.

4. **Run Backend Tests:**
   ```bash
   node --test test/*.test.js
   ```

5. **Start the Backend Server:**
   ```bash
   npm start
   # Server runs at http://localhost:3000
   ```

---

## 🧪 Testing & Validation

### Flutter Test Suite (425 Tests)
```bash
flutter test
```
- **SOS Dispatch Security & Invariants**: UID impersonation prevention, bounded geofencing, GPS stream resilience.
- **P0-P3 Reliability & Core Experience**: Cache isolation, GPS thresholds, 120s stall timers, SHA-256 P2P payload signing.
- **AI Assistant & Voice UI Widgets**: `AIAssistantSheet`, voice mode toggles, Hindi/English localized disclaimers.
- **Helpline Directory & Navigation**: Search, filter, direct call intent integration.
- **Responsive Layouts**: Zero-overflow validation on ultra-compact (360x640) screens.

### Backend Test Suite (84 Tests)
```bash
cd backend && node --test test/*.test.js
```
- **Gemini Assistant**: Prompt sanitization, PII stripping, quota handling, 10s/30s timeouts, Hindi response validation.
- **ElevenLabs Voice**: Multi-format audio validation, text length limits, in-memory stream processing.
- **Tiger Data / TimescaleDB**: Batch event ingestion idempotency, aggregate summary authorization.
- **Security & Emulator Isolation**: Production fail-closed guards, loopback-only demo project enforcement.

---

## 🔒 Security & Privacy Model

1. **Zero Raw PII to LLMs**: The Gemini and ElevenLabs integration layers strictly sanitize all emergency context before sending prompts. Exact coordinates, victim/responder real names, phone numbers, and blood groups are never transmitted.
2. **Statutory 112 Disclaimers**: All AI responses automatically include explicit statutory guidance advising users to dial 112 directly for life-threatening situations.
3. **Fail-Closed Authentication**: Backend endpoints require Firebase Authentication Bearer ID tokens and verify that the calling user is an authorized participant (victim or assigned responder) of the active emergency.
4. **P2P Payload Integrity**: Direct peer-to-peer emergency transmissions are signed with SHA-256 cryptographic hashes and checked for sequence monotonicity to prevent tampering and replay attacks.
5. **No Dangerous Permissions**: Emergency SMS relies on standard system dialer and SMS intents (`url_launcher`) without requiring sensitive runtime SMS permissions.

---

## 📄 Canonical Documentation

- 👉 **[VITA_RESQ_MASTER_CHANGELOG.md](VITA_RESQ_MASTER_CHANGELOG.md)** — Canonical project history, architectural decisions, and feature inventory.
- 👉 **[VITA_RESQ_FEATURES.md](VITA_RESQ_FEATURES.md)** — Quick-reference feature notepad.
- 👉 **[backend/.env.example](backend/.env.example)** — Environment variable configuration template.
