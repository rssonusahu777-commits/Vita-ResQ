# Vindara — Teammate AI Integration Contract

> **Target Audience:** Teammates building background AI modules (Multimodal Camera/Mic Severity Estimation & Mathematical Responder Ranking Engine).  
> **App Identity:** `Vindara` (`com.vindara.app`)  
> **Status:** Authoritative Architectural Contract for Phase 8+

---

## 1. Architectural Philosophy

Vindara is designed as an **offline-first, zero-hesitation emergency response platform**. In high-stress crisis scenarios, seconds matter. Therefore:

- **AI is an asynchronous enrichment layer, NEVER a gatekeeper.**
- A HELP broadcast or crash detection alert **must dispatch immediately** with baseline GPS coordinates and type, even if the device is offline or AI processing is pending.
- AI analysis runs in the background to update the authoritative emergency record asynchronously.

---

## 2. Non-Negotiable Guardrails

All future AI modules must strictly adhere to these 5 non-negotiable rules:

| # | Rule | Contract Requirement |
|---|---|---|
| **1** | **Asynchronous / Non-Blocking** | **Never block emergency creation on AI.** Camera/mic capture and model inference must run asynchronously in background isolates or Cloud Functions. If inference fails or times out, the baseline emergency alert remains fully operational. |
| **2** | **Zero "SOS" Rule** | **Never use the word "SOS" in UI strings or logs.** All user-facing interfaces, banners, buttons, and notifications must strictly use **"HELP"**. |
| **3** | **Minimal Push Payloads (Rule #9)** | FCM push alerts must **never carry victim PII, raw audio, video frames, or precise street addresses**. Only `{ "emergencyId": "...", "type": "...", "severity": "..." }` is permissible in push payloads. Responders fetch authoritative details from Firestore/local DB upon opening the app. |
| **4** | **Explicit Capture Indicators & Media TTL** | If client-side mic or camera sampling is active post-trigger, an explicit visual indicator (e.g., status pill) must be displayed. Captured audio/image buffers must be purged from memory and ephemeral storage immediately after feature extraction or encrypted upload with a short TTL (e.g. 24 hours). |
| **5** | **Proximity Over Ranking in Critical State** | In `critical` severity emergencies (e.g., severe crash, cardiac event), the mathematical responder ranking algorithm **must never delay or skip an immediately available nearby responder** in favor of a higher-reputation responder who is further away. Physical proximity and immediate availability take precedence over historical assist scores. |

---

## 3. Extension Point A: Domain Model Enrichment (`Emergency`)

### 1. Schema Additions
In `lib/models/emergency.dart`, optional non-blocking AI fields can be added:

```dart
/// Optional background AI enrichment metadata
enum EmergencySeverity {
  low,
  moderate,
  high,
  critical,
}

class Emergency {
  // Existing fields (id, victimId, latitude, longitude, accuracyMeters, type, etc.)
  ...

  // AI Enrichment fields (Optional, nullable):
  final EmergencySeverity? severity;
  final double? responsivenessScore; // 0.0 (unresponsive) to 1.0 (fully responsive)
  final String? aiContextSummary;    // e.g. "Glass shatter sound and high deceleration pattern"

  const Emergency({
    ...
    this.severity,
    this.responsivenessScore,
    this.aiContextSummary,
  });
}
```

### 2. Firestore Document Structure
```json
{
  "id": "EMG-2026-9F4A2C1B",
  "victimId": "uid_victim_123",
  "status": "alerting",
  "type": "accident",
  "severity": "critical",
  "responsivenessScore": 0.25,
  "aiContextSummary": "High-impact collision detected; voice non-responsive during 10s countdown.",
  "version": 2
}
```

---

## 4. Extension Point B: Client-Side Multimodal Service

When implementing camera/mic capture after `HELP` button press or crash detection:

1. **Trigger Time**: Start background capture **after** the emergency is persisted in `LocalEmergencyStore` and broadcast via `EmergencyRepository`.
2. **Execution**:
   ```dart
   // Recommended pattern:
   class EmergencyAiAnalysisService {
     Future<void> runPostTriggerAnalysis(String emergencyId) async {
       try {
         // 1. Capture 3-5 seconds of ambient audio / camera snapshot in background
         final audioSample = await _captureBriefAudioSample();

         // 2. Extract features locally (tflite/onnx) or stream to secure Cloud Function
         final result = await _analyzeSample(audioSample);

         // 3. Update emergency record with optimistic version increment
         await emergencyRepository.updateAiEnrichment(
           emergencyId,
           severity: result.severity,
           responsivenessScore: result.responsiveness,
           aiContextSummary: result.summary,
         );
       } catch (e) {
         // Graceful fallback: Alert is already out; AI failure does not compromise safety
         debugPrint('AI analysis skipped/failed: $e');
       }
     }
   }
   ```

---

## 5. Extension Point C: Mathematical Responder Ranking Engine (`functions/index.js`)

In `functions/index.js` under `onEmergencyCreated`, replace simple FIFO/multicast dispatch with the mathematical scoring function:

### Mathematical Scoring Formula
For each candidate responder $i$ within radius $R$:

$$S_i = w_d \cdot \left(1 - \frac{d_i}{d_{\max}}\right) + w_r \cdot \left(\frac{\min(P_i, 1000)}{1000}\right) + w_a \cdot A_i + B_i$$

Where:
- $d_i$: Haversine distance from responder $i$ to victim.
- $w_d$: Distance weight ($0.55$ standard, $0.80$ in `critical` emergencies).
- $P_i$: Reputation points ($w_r = 0.25$).
- $A_i$: Historical acceptance rate / response history ($w_a = 0.20$).
- $B_i$: Badge bonus (e.g., $+0.15$ for medical badge on medical emergency).

### Implementation Hook in `functions/index.js`
```javascript
// Inside exports.onEmergencyCreated in functions/index.js:

// Query eligible responders
const responders = await queryAvailableResponders();

// Rank responders using mathematical engine
const rankedResponders = rankResponders(responders, emergencyData);

// Dispatch high-priority alert to Top N responders first (e.g. N = 5),
// then cascade to remaining standby responders after 30 seconds if unaccepted.
const targetTokens = rankedResponders.slice(0, 5).map(r => r.fcmToken);

await admin.messaging().sendEachForMulticast({
  notification: {
    title: "🚨 HELP NEEDED NEAR YOU",
    body: emergencyData.severity === "critical" 
      ? "CRITICAL assistance needed nearby. Tap to view."
      : "Someone nearby requested assistance. Tap to view details.",
  },
  data: {
    emergencyId: emergencyId,
    type: type,
    severity: emergencyData.severity || "moderate", // Privacy-minimal (Rule #9)
  },
  tokens: targetTokens,
  ...
});
```

---

## 6. Testing Requirements for Teammates

Any PR introducing AI features must provide tests demonstrating:
1. **Network failure**: Emergency alert succeeds even if the AI backend endpoint is unreachable (offline resilience).
2. **High latency**: Emergency detail UI displays GPS coordinates instantly while showing a subtle `"Analyzing situation..."` shimmer until AI results land.
3. **Privacy**: Verification that no base64 images, raw audio buffers, or victim personal identifiers leak into FCM payloads or Firestore public feeds.

