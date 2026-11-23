# 🚨 Vita ResQ — Autonomous & Civilian Emergency Response Network

[![Flutter Tests](https://img.shields.io/badge/Flutter%20Tests-444%20Passing-brightgreen.svg)](test/)
[![Backend Tests](https://img.shields.io/badge/Backend%20Tests-84%20Passing-brightgreen.svg)](backend/test/)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-blue.svg)](pubspec.yaml)
[![License](https://img.shields.io/badge/License-MIT-orange.svg)](LICENSE)

**Vita ResQ** is a resilient, hybrid emergency dispatch, civilian mutual-aid coordination, and AI-assisted triage platform engineered to save lives during critical first-response minutes. It combines cloud infrastructure with offline direct peer-to-peer (P2P) connectivity to guarantee uninterrupted alert delivery even in zero-connectivity disaster zones.

> **Disclaimer:** Vita ResQ is a civilian mutual-aid assistance platform and does **not** replace national emergency services (112 / 911). In life-threatening emergencies, always contact official authorities directly.

---

## 🎯 The Problem

In the critical minutes following an accident or medical emergency, delayed emergency dispatch, network blackouts, and uncoordinated bystanders often cost lives. Traditional SOS tools either fail completely without internet, broadcast raw personal data insecurely, or create bystander chaos without clear responder ownership.

---

## 💡 Our Solution

Vita ResQ bridges the gap between an emergency trigger and official first-responder arrival through **offline-first mesh resilience**, **deterministic responder coordination**, and **privacy-sanitized AI triage**:

- 🚨 **Hold-to-Activate SOS**: Deliberate 1.5-second press-and-hold trigger with a glowing circular progress ring, haptic feedback, and accidental tap cancellation.
- 📡 **Dual-Mode Hybrid Transport**:
  - **Online**: Firebase Firestore real-time streams, Cloud Functions geofencing, and FCM push notifications.
  - **Offline**: Google Nearby Connections direct P2P over BLE / Wi-Fi Direct with zero internet dependency.
  - **Cryptographic Integrity**: Pure-Dart FIPS 180-4 SHA-256 payload signing and tamper rejection (`P2PPayloadIntegrity`).
  - **Community Cloud Gateway Relay**: 1-hop bystander P2P-to-Firestore bridge for fresh (<= 10 min) SHA-256 verified offline alerts with idempotent non-overwrite protection.
- 📴 **Guest Offline Emergency Access**: Instant `"Continue Offline (Emergency Access)"` mode on the login screen using isolated, device-bound guest state—eliminating registration friction during life-or-death emergencies.
- 👥 **Two-Way Claim Handshake & Role-Weighted Failover**: Assigns `PRIMARY` and `STANDBY` responder slots using deterministic role + proximity scoring (`DOCTOR` > `AMBULANCE_DRIVER` > `POLICE_PCR` > `CITIZEN`) with linear distance decay.
- ⚡ **Reliability Watchdog & Auto-Handover**: Monitors responder ETA, movement progress, and GPS freshness—triggering automatic standby promotion if a primary responder stalls for >120 seconds.
- 🩺 **AI-Assisted Multimodal Scene & Injury Triage**:
  - **Zero-Delay SOS**: Dispatches the alert at T=0s while triage runs asynchronously in the background.
  - **6-Second Sequential Capture**: Captures rear and front camera frames sequentially alongside a 6-second voice transcript.
  - **Hybrid Triage Engine**: Uses `gemini-2.5-flash` online for structured severity (`CRITICAL`, `HIGH`, `MODERATE`, `UNCLEAR`) and responder briefings, with an automatic deterministic keyword fallback offline.
  - **Crash Unresponsive Auto-Escalation**: Automatically escalates accelerometer-detected crashes to `CRITICAL` if the victim is unresponsive.
- 🚗 **Sensor-Assisted Crash Detection**: Multi-sensor scoring matrix evaluating linear acceleration, angular rotation, velocity drop, and vehicle context with a 15-second cancellable countdown.
- 🤖 **AI Situation Assistant & Hands-Free Voice**:
  - **Gemini 3.8 Flash Briefing**: Context-aware, privacy-sanitized guidance in English and Hindi.
  - **ElevenLabs Voice Interface**: Low-latency speech-to-text (Scribe v2) and text-to-speech (Eleven Flash v2.5) for hands-free emergency interaction.
- 🗺️ **Open-Source Routing & Bilingual Helplines**: Live turn-by-turn routing via OpenStreetMap and OSRM with Haversine fallback, paired with an offline searchable helpline directory and direct 112 dialing.

---

## 🏗️ System Architecture

1. **Trigger Layer:** User holds SOS (1.5s) or Sensor Crash Detection triggers automatically.
2. **Dual-Mode Transport:**
   - **Online Path:** Cloud Firestore + FCM Push + OSRM Live Routing.
   - **Offline Path:** Google Nearby Direct P2P (BLE / Wi-Fi Direct) + SHA-256 Integrity + 1-Hop Community Cloud Relay.
3. **Coordination Engine:** Two-Way Claim Handshake assigning `PRIMARY` (Live Route & Triage HUD) and `STANDBY` (Role-Weighted Backup).
4. **Live Response Modules:**
   - **Reliability Watchdog:** Monitors GPS freshness & 120s stall threshold for automatic standby promotion.
   - **Gemini AI Triage:** Multimodal scene/audio analysis with deterministic offline keyword fallback.
   - **Voice & Helplines:** ElevenLabs STT/TTS guidance + offline helpline directory & 112 statutory dialer.

---

## 🛠️ Tech Stack

- **Mobile Frontend**: Flutter & Dart (Material 3)
- **Backend & Cloud**: Node.js (Express), Firebase Cloud Firestore, Cloud Functions, Cloud Messaging (FCM), Firebase Auth
- **Offline & P2P Networking**: Google Nearby Connections (BLE / Wi-Fi Direct), Local SQLite / Hive persistence, Pure-Dart SHA-256 signing
- **AI & Voice**: Google Gemini (`gemini-2.5-flash` & `gemini-3.8-flash`), ElevenLabs (`Scribe v2` & `Eleven Flash v2.5`), `speech_to_text`
- **Mapping & Telemetry**: OpenStreetMap, OSRM Routing Engine, TimescaleDB / Tiger Data Analytics
- **Quality Assurance**: 444 Flutter unit/widget/integration tests + 84 Node.js backend security & unit tests

---

## 🔒 Security & Privacy Principles

- **Zero Raw PII to LLMs**: Exact GPS coordinates, real names, phone numbers, and blood groups are stripped before any AI or voice API call.
- **Statutory 112 Guardrails**: Every AI guidance screen reinforces dialing official emergency services (`112`) for life-threatening situations.
- **Fail-Closed Authorization**: Backend endpoints enforce Firebase Auth Bearer tokens and verify active incident participation before granting data access.
- **Tamper-Proof P2P Packets**: Offline broadcasts carry SHA-256 signatures and monotonic sequence numbers to block spoofing and replay attacks.
- **Least-Privilege Permissions**: Uses native system dialer and SMS intents (`url_launcher`) without requesting invasive runtime SMS permissions.
