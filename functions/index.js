/* eslint-disable */

// 1st-gen Cloud Function: send FCM when a new private message is created
// Path: privateChats/{roomId}/messages/{messageId}

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

exports.onPrivateMessageCreate = functions
    .region("us-central1")
    .firestore
    .document("privateChats/{roomId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
        if (!snap || !snap.exists) {
            console.log("No snapshot data – exiting.");
            return null;
        }

        const message = snap.data() || {};
        const roomId = context.params.roomId;

        console.log("🔥 New message in room:", roomId, message);

        const db = admin.firestore();

        // 1) Load room to know participants
        const roomRef = db.doc(`privateChats/${roomId}`);
        const roomSnap = await roomRef.get();

        if (!roomSnap.exists) {
            console.warn("Room doc missing for", roomId);
            return null;
        }

        const roomData = roomSnap.data() || {};
        const participants = roomData.participants || [];

        const senderId = message.senderId;
        const receiverIds = participants.filter((uid) => uid !== senderId);

        if (!receiverIds.length) {
            console.log("No receivers for room", roomId);
            return null;
        }

        // 2) Load sender + receivers' user docs
        const senderSnap = await db.collection("users").doc(senderId).get();
        const senderData = senderSnap.exists ? senderSnap.data() : {};

        const userSnaps = await Promise.all(
            receiverIds.map((uid) => db.collection("users").doc(uid).get()),
        );

        // 3) Build sender name + body text
        const senderName =
            `${senderData.firstName || ""} ${senderData.lastName || ""}`.trim() ||
            "New message";

        const bodyText =
            typeof message.text === "string" && message.text.trim().length
                ? message.text.trim()
                : "New message in MW Chat";

        // 4) Collect FCM tokens
        const tokens = userSnaps
            .map((s) => (s.exists ? s.data().fcmToken : null))
            .filter((t) => typeof t === "string" && t.length > 0);

        if (!tokens.length) {
            console.log("No FCM tokens for receivers in room", roomId);
            return null;
        }

        // 5) Send the notification
        const payload = {
            notification: {
                title: senderName,
                body: bodyText,
            },
            data: {
                roomId,
                senderId: senderId || "",
                type: "private_message",
            },
        };

        const response = await admin.messaging().sendEachForMulticast({
            tokens,
            ...payload,
        });

        console.log("✅ FCM send result:", JSON.stringify(response, null, 2));
        return null;
    });


/**
 Callable: purgeChatRoom
 * Deletes Storage objects by exact paths (Admin SDK), and optionally deletes leftover messages.
 *
 * Expected payload:
 *  { roomId: string, paths?: string[] }
 */
exports.purgeChatRoom = functions
    .region("us-central1")
    .https.onCall(async (data, context) => {
        try {
            const uid =
                context &&
                context.auth &&
                typeof context.auth.uid === "string" &&
                context.auth.uid.length
                    ? context.auth.uid
                    : null;

            if (!uid) {
                throw new functions.https.HttpsError(
                    "unauthenticated",
                    "You must be signed in."
                );
            }

            const roomId =
                data && typeof data.roomId === "string" ? data.roomId.trim() : "";

            if (!roomId) {
                throw new functions.https.HttpsError(
                    "invalid-argument",
                    "roomId is required."
                );
            }

            // ✅ Verify user is participant
            const db = admin.firestore();
            const roomRef = db.doc("privateChats/" + roomId);
            const roomSnap = await roomRef.get();

            if (!roomSnap.exists) {
                return { ok: true, deleted: 0, skipped: 0, reason: "room_missing" };
            }

            const roomData = roomSnap.data() || {};
            const participants = Array.isArray(roomData.participants)
                ? roomData.participants
                : [];

            if (participants.indexOf(uid) === -1) {
                throw new functions.https.HttpsError(
                    "permission-denied",
                    "You are not a participant in this room."
                );
            }

            // ✅ Delete by exact object paths
            const inputPaths = data && Array.isArray(data.paths) ? data.paths : [];
            const paths = inputPaths
                .map((p) => (typeof p === "string" ? p.trim() : ""))
                .filter((p) => p.length > 0);

            const bucket = admin.storage().bucket();
            let deleted = 0;
            let skipped = 0;

            const chunkSize = 50;
            for (let i = 0; i < paths.length; i += chunkSize) {
                const slice = paths.slice(i, i + chunkSize);
                await Promise.all(
                    slice.map(async (p) => {
                        try {
                            await bucket.file(p).delete({ ignoreNotFound: true });
                            deleted += 1;
                        } catch (e) {
                            skipped += 1;
                            const msg = e && e.message ? e.message : String(e);
                            console.log("Storage delete failed:", p, msg);
                        }
                    })
                );
            }

            return { ok: true, deleted, skipped };
        } catch (e) {
            console.error("purgeChatRoom failed:", e);

            // If it's already an HttpsError, rethrow it
            if (e && e.code && e.message) {
                throw e;
            }

            const msg = e && e.message ? e.message : "Failed";
            throw new functions.https.HttpsError("internal", msg);
        }
    });

