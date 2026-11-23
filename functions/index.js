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

const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
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

/**
 * Triggered whenever an emergency document is updated in Firestore.
 * Rewards verified responders upon 'resolved' status transition (Phase 7):
 * - Anti-Gaming: Zero points awarded for merely accepting.
 * - Anti-Farming: Zero points awarded if primaryResponderId === victimId.
 * - Primary Responder: +50 points, +1 successfulAssistanceCount, badge progression.
 * - Standby Responders: +20 points each.
 */
exports.onEmergencyUpdated = onDocumentUpdated(
  {
    document: "emergencies/{emergencyId}",
    region: "us-central1",
  },
  async (event) => {
    const beforeData = event.data.before ? event.data.before.data() : null;
    const afterData = event.data.after ? event.data.after.data() : null;

    if (!beforeData || !afterData) return;

    const beforeStatus = beforeData.status;
    const afterStatus = afterData.status;
    const emergencyId = event.params.emergencyId;

    // Only award points when newly transitioning to 'resolved'
    if (beforeStatus === "resolved" || afterStatus !== "resolved") {
      return;
    }

    const victimId = afterData.victimId;
    const primaryResponderId = afterData.primaryResponderId;
    const standbyResponderIds = afterData.standbyResponderIds || [];

    const db = admin.firestore();
    const batch = db.batch();

    // 1. Primary Responder Award (+50 pts & +1 assist)
    if (primaryResponderId && primaryResponderId !== victimId) {
      const primaryUserRef = db.collection("users").doc(primaryResponderId);
      const primaryDoc = await primaryUserRef.get();

      if (primaryDoc.exists) {
        const userData = primaryDoc.data();
        const currentPoints = userData.reputationPoints || 0;
        const currentAssists = (userData.successfulAssistanceCount || 0) + 1;
        const badges = new Set(userData.badges || []);

        // Milestone Badges
        if (currentAssists >= 1) badges.add("first_responder");
        if (currentAssists >= 5) badges.add("community_guardian");
        if (currentAssists >= 15) badges.add("vindara_vanguard");

        batch.update(primaryUserRef, {
          reputationPoints: currentPoints + 50,
          successfulAssistanceCount: currentAssists,
          badges: Array.from(badges),
          lastAssistedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        console.log(`Awarded 50 points to primary responder ${primaryResponderId} for emergency ${emergencyId}.`);
      }
    } else if (primaryResponderId === victimId) {
      console.log(`Self-farming attempt blocked: victim ${victimId} cannot claim reward for emergency ${emergencyId}.`);
    }

    // 2. Standby Responders Award (+20 pts)
    for (const standbyId of standbyResponderIds) {
      if (!standbyId || standbyId === victimId || standbyId === primaryResponderId) {
        continue;
      }

      const standbyRef = db.collection("users").doc(standbyId);
      const standbyDoc = await standbyRef.get();

      if (standbyDoc.exists) {
        const standbyData = standbyDoc.data();
        const currentPoints = standbyData.reputationPoints || 0;

        batch.update(standbyRef, {
          reputationPoints: currentPoints + 20,
        });

        console.log(`Awarded 20 points to standby responder ${standbyId} for emergency ${emergencyId}.`);
      }
    }

    await batch.commit();
  }
);

