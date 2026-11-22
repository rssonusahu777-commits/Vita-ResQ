/**
 * Vindara — Cloud Functions for Emergency Alert Dispatch
 * Package: com.vindara.app
 *
 * Design rules followed:
 *   Rule #4 — Firestore is source of truth; push notification only carries emergencyId.
 *   Rule #9 — Minimal push payloads without sensitive PII.
 *              Strictly omit victim name, phone number, medical details, or exact coordinates.
 *   Rule #5 — High-priority delivery headers for waking background devices.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

/**
 * Triggered whenever a new emergency document is created in Firestore.
 * If status is 'alerting', sends a high-priority push alert to all available
 * registered responders (excluding the victim itself).
 */
exports.onEmergencyCreated = onDocumentCreated(
  {
    document: "emergencies/{emergencyId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const data = snapshot.data();
    const emergencyId = event.params.emergencyId;
    const status = data.status;
    const victimId = data.victimId;
    const type = data.type || "general";

    // Only dispatch push alerts when status is 'alerting'
    if (status !== "alerting") {
      console.log(`Emergency ${emergencyId} status is '${status}'. Skipping alert dispatch.`);
      return;
    }

    // Query active and verified responders with valid FCM tokens
    const respondersQuery = await admin
      .firestore()
      .collection("users")
      .where("isAvailable", "==", true)
      .where("isVerifiedResponder", "==", true)
      .get();

    const tokens = [];
    respondersQuery.forEach((doc) => {
      // Never send alert to the victim itself
      if (doc.id === victimId) return;

      const userData = doc.data();
      if (userData.fcmToken && typeof userData.fcmToken === "string") {
        tokens.push(userData.fcmToken);
      }
    });

    if (tokens.length === 0) {
      console.log(`No available responders found for emergency ${emergencyId}.`);
      return;
    }

    // Rule #9: Push payload carries NO PII, no address, no coordinates, no name.
    // Client will fetch authoritative full emergency document directly from Firestore upon opening.
    const message = {
      notification: {
        title: "🚨 HELP NEEDED NEAR YOU",
        body: "Someone nearby requested assistance. Tap to view details.",
      },
      data: {
        emergencyId: emergencyId,
        type: type,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "emergency_alerts_channel",
          priority: "max",
          sound: "default",
          defaultVibrateTimings: true,
          visibility: "public",
        },
      },
      apns: {
        headers: {
          "apns-priority": "10", // High priority
          "apns-push-type": "alert",
        },
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            contentAvailable: true,
          },
        },
      },
      tokens: tokens,
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(
        `Dispatched alert for emergency ${emergencyId}: ${response.successCount} succeeded, ${response.failureCount} failed.`
      );

      // Clean up stale or invalid tokens
      if (response.failureCount > 0) {
        const batch = admin.firestore().batch();
        let cleaned = 0;

        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const error = resp.error;
            if (
              error &&
              (error.code === "messaging/invalid-registration-token" ||
                error.code === "messaging/registration-token-not-registered")
            ) {
              const staleToken = tokens[idx];
              // Search document with this stale token and clear it
              respondersQuery.forEach((doc) => {
                if (doc.data().fcmToken === staleToken) {
                  batch.update(doc.ref, { fcmToken: null });
                  cleaned++;
                }
              });
            }
          }
        });

        if (cleaned > 0) {
          await batch.commit();
          console.log(`Cleaned up ${cleaned} invalid FCM tokens.`);
        }
      }
    } catch (error) {
      console.error(`Error sending emergency push notification for ${emergencyId}:`, error);
    }
  }
);

