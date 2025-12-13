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
