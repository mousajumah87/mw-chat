// functions/index.js
/* eslint-disable */

const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

// ✅ Node 20 safe APNs: HTTP/2 + jose (replaces `apn`)
const http2 = require("http2");
const { SignJWT, importPKCS8 } = require("jose");

// ✅ used to generate short/stable keys for APNs collapse-id (<= 64 bytes)
const crypto = require("crypto");

admin.initializeApp();

// ----------------------------------------------
// Helpers
// ----------------------------------------------

function asString(v) {
    return typeof v === "string" ? v : "";
}
function trimString(v) {
    return asString(v).trim();
}
function isNonEmptyString(v) {
    return typeof v === "string" && v.trim().length > 0;
}
function uniqStrings(arr) {
    const out = [];
    const seen = new Set();
    for (const v of arr || []) {
        const s = trimString(v);
        if (!s) continue;
        if (seen.has(s)) continue;
        seen.add(s);
        out.push(s);
    }
    return out;
}
function chunk(arr, n) {
    const out = [];
    for (let i = 0; i < (arr || []).length; i += n) out.push(arr.slice(i, i + n));
    return out;
}

// ✅ APNs requires apns-collapse-id <= 64 bytes.
// We generate a stable, short key based on roomId/callId (hash), safe for iOS + Android.
function shortStableKey(prefix, raw, maxLen = 64) {
    const s = trimString(raw);
    const h = crypto.createHash("sha256").update(s).digest("hex").slice(0, 32); // 32 chars
    const out = `${prefix}_${h}`;
    return out.length > maxLen ? out.slice(0, maxLen) : out;
}

// ✅ NEW: feature flag for hiding message content in push notifications
function isHideMessageBodyEnabled() {
    const v = trimString(process.env.HIDE_MESSAGE_BODY).toLowerCase();
    return v === "1" || v === "true" || v === "yes";
}

// ✅ NEW: build notification body (never include real message text when enabled)
function buildNotificationBody(message) {
    if (isHideMessageBodyEnabled()) return "New message";
    const t = message && typeof message.text === "string" ? message.text.trim() : "";
    return t.length ? t : "New message in MW Chat";
}

/**
 * Extract FCM tokens from user doc.
 * Supports:
 *  - user.fcmToken: string
 *  - user.fcmTokens: array<string>
 *  - user.fcmTokensMap: map<string,bool|string|number>
 */
function extractFcmTokensFromUserDoc(userData) {
    const tokens = [];

    const single = userData && userData.fcmToken;
    if (isNonEmptyString(single)) tokens.push(single.trim());

    const arr = userData && userData.fcmTokens;
    if (Array.isArray(arr)) {
        for (const t of arr) {
            if (isNonEmptyString(t)) tokens.push(t.trim());
        }
    }

    const maybeMap = userData && userData.fcmTokensMap;
    if (maybeMap && typeof maybeMap === "object" && !Array.isArray(maybeMap)) {
        for (const [k, v] of Object.entries(maybeMap)) {
            if (!isNonEmptyString(k)) continue;
            if (v === true || isNonEmptyString(v) || typeof v === "number") {
                tokens.push(k.trim());
            }
        }
    }

    return uniqStrings(tokens);
}

/**
 * Extract VoIP tokens from user doc.
 * Supports:
 *  - user.voipToken: string
 *  - user.voipTokens: array<string>
 *  - user.voipTokensMap: map<string,bool|string|number>
 */
function extractVoipTokensFromUserDoc(userData) {
    const tokens = [];

    const single = userData && userData.voipToken;
    if (isNonEmptyString(single)) tokens.push(single.trim());

    const arr = userData && userData.voipTokens;
    if (Array.isArray(arr)) {
        for (const t of arr) {
            if (isNonEmptyString(t)) tokens.push(t.trim());
        }
    }

    const maybeMap = userData && userData.voipTokensMap;
    if (maybeMap && typeof maybeMap === "object" && !Array.isArray(maybeMap)) {
        for (const [k, v] of Object.entries(maybeMap)) {
            if (!isNonEmptyString(k)) continue;
            if (v === true || isNonEmptyString(v) || typeof v === "number") {
                tokens.push(k.trim());
            }
        }
    }

    return uniqStrings(tokens);
}

function tokensToRemoveFromSendResult(tokens, sendResponse) {
    const bad = [];
    if (!sendResponse || !Array.isArray(sendResponse.responses)) return bad;

    for (let i = 0; i < sendResponse.responses.length; i++) {
        const r = sendResponse.responses[i];
        if (r && r.success) continue;

        const err = r && r.error ? r.error : null;
        const code = err && err.code ? String(err.code) : "";

        if (
            code.includes("messaging/invalid-registration-token") ||
            code.includes("messaging/registration-token-not-registered")
        ) {
            bad.push(tokens[i]);
        }
    }
    return bad;
}

async function cleanupInvalidFcmTokensBestEffort(db, receiverIds, invalidTokens) {
    if (!receiverIds.length || !invalidTokens.length) return;

    const invalidSet = new Set(invalidTokens);

    await Promise.all(
        receiverIds.map(async (uid) => {
            try {
                const ref = db.collection("users").doc(uid);
                const snap = await ref.get();
                if (!snap.exists) return;

                const data = snap.data() || {};
                const updates = {};

                if (isNonEmptyString(data.fcmToken) && invalidSet.has(data.fcmToken.trim())) {
                    updates.fcmToken = admin.firestore.FieldValue.delete();
                }

                if (Array.isArray(data.fcmTokens) && data.fcmTokens.length) {
                    const next = data.fcmTokens
                        .map((t) => (typeof t === "string" ? t.trim() : ""))
                        .filter((t) => t && !invalidSet.has(t));
                    if (next.length !== data.fcmTokens.length) updates.fcmTokens = next;
                }

                if (data.fcmTokensMap && typeof data.fcmTokensMap === "object" && !Array.isArray(data.fcmTokensMap)) {
                    let changed = false;
                    const nextMap = { ...data.fcmTokensMap };
                    for (const t of invalidSet) {
                        if (t in nextMap) {
                            delete nextMap[t];
                            changed = true;
                        }
                    }
                    if (changed) updates.fcmTokensMap = nextMap;
                }

                if (Object.keys(updates).length) {
                    await ref.set(updates, { merge: true });
                }
            } catch (e) {
                console.log("[FCM] token cleanup skipped for", uid, e && e.message ? e.message : String(e));
            }
        })
    );
}

/**
 * log per-token failures so you can see WHY totalFailure=1
 */
function logMulticastFailures(tag, tokens, response, extra) {
    try {
        if (!response || !Array.isArray(response.responses)) return;
        const failures = [];

        for (let i = 0; i < response.responses.length; i++) {
            const r = response.responses[i];
            if (r && r.success) continue;

            const err = r && r.error ? r.error : null;
            failures.push({
                tokenSuffix: tokens[i] ? String(tokens[i]).slice(-12) : "",
                code: err && err.code ? String(err.code) : "",
                message: err && err.message ? String(err.message) : "",
            });
        }

        if (failures.length) {
            console.log(`[${tag}] ❌ FCM failures:`, {
                ...(extra || {}),
                count: failures.length,
                failures,
            });
        }
    } catch (_) {}
}

// ----------------------------------------------
// ✅ APNs (VoIP) helpers - Node 20 SAFE
// ----------------------------------------------

function getApnsConfig() {
    const teamId = trimString(process.env.APNS_TEAM_ID);
    const keyId = trimString(process.env.APNS_KEY_ID);

    let p8 = asString(process.env.APNS_P8);
    if (p8.includes("\\n")) p8 = p8.replace(/\\n/g, "\n");

    const productionExplicit = trimString(process.env.APNS_PRODUCTION).toLowerCase();
    const production = productionExplicit === "true" ? true : productionExplicit === "false" ? false : false;

    const topic = trimString(process.env.APNS_VOIP_TOPIC);

    if (!teamId || !keyId || !p8) return null;
    if (!topic) return { teamId, keyId, p8, production, topic: "", topicMissing: true };

    return { teamId, keyId, p8, production, topic, topicMissing: false };
}

let _cachedPk = null;
let _cachedPkKey = "";

async function getCachedPrivateKey(cfg) {
    const cacheKey = `${cfg.teamId}|${cfg.keyId}|${cfg.p8.length}`;
    if (_cachedPk && _cachedPkKey === cacheKey) return _cachedPk;

    const pk = await importPKCS8(cfg.p8, "ES256");
    _cachedPk = pk;
    _cachedPkKey = cacheKey;
    return pk;
}

async function buildApnsJwt(cfg) {
    const privateKey = await getCachedPrivateKey(cfg);
    const now = Math.floor(Date.now() / 1000);
    return await new SignJWT({})
        .setProtectedHeader({ alg: "ES256", kid: cfg.keyId })
        .setIssuedAt(now)
        .setIssuer(cfg.teamId)
        .sign(privateKey);
}

async function sendVoipApnsPushBestEffort({ voipToken, payload, callId }) {
    try {
        const cfg = getApnsConfig();

        if (!cfg) {
            console.log("[CALL][VOIP] APNs config missing; skipping VoIP push");
            return { ok: false, skipped: true, reason: "missing_apns_config" };
        }
        if (cfg.topicMissing) {
            console.log("[CALL][VOIP] APNS_VOIP_TOPIC missing; skipping VoIP push", { callId, production: cfg.production });
            return { ok: false, skipped: true, reason: "missing_apns_topic" };
        }
        if (!voipToken) {
            console.log("[CALL][VOIP] missing voipToken; skipping VoIP push");
            return { ok: false, skipped: true, reason: "missing_voip_token" };
        }

        const host = cfg.production ? "api.push.apple.com" : "api.sandbox.push.apple.com";
        const jwt = await buildApnsJwt(cfg);

        const body = JSON.stringify({
            aps: { "content-available": 1 },
            ...payload,
        });

        const client = http2.connect(`https://${host}`);

        const req = client.request({
            ":method": "POST",
            ":path": `/3/device/${voipToken}`,
            authorization: `bearer ${jwt}`,
            "apns-topic": cfg.topic,
            "apns-push-type": "voip",
            "apns-priority": "10",
        });

        let status = 0;
        let resp = "";

        req.on("response", (headers) => {
            status = Number(headers[":status"] || 0);
        });

        req.setEncoding("utf8");
        req.on("data", (chunk) => (resp += chunk));

        await new Promise((resolve, reject) => {
            req.on("end", resolve);
            req.on("error", reject);
            req.end(body);
        });

        client.close();

        let parsed = null;
        try {
            parsed = resp ? JSON.parse(resp) : null;
        } catch (_) {}

        console.log("[CALL][VOIP] apns result:", {
            callId,
            production: cfg.production,
            topic: cfg.topic,
            host,
            status,
            response: parsed || resp || "",
        });

        return { ok: status === 200, status, response: parsed || resp || "" };
    } catch (e) {
        console.log("[CALL][VOIP] send failed:", callId, e && e.message ? e.message : String(e));
        return { ok: false, error: true, reason: "exception", message: e && e.message ? e.message : String(e) };
    }
}

// ----------------------------------------------
// ✅ Trigger: New message in private chat
// ----------------------------------------------
exports.onPrivateMessageCreate = functions
    .runWith({
        // ✅ attach the secret (no deprecated runtime config)
        secrets: ["HIDE_MESSAGE_BODY"],
    })
    .region("us-central1")
    .firestore.document("privateChats/{roomId}/messages/{messageId}")
    .onCreate(async (snap, context) => {
        try {
            if (!snap || !snap.exists) return null;

            const message = snap.data() || {};
            const roomId = trimString(context && context.params ? context.params.roomId : "");
            const messageId = trimString(context && context.params ? context.params.messageId : "");
            if (!roomId) return null;

            const db = admin.firestore();

            // skip call messages if you store them in messages
            const msgType = trimString(message.type);
            if (msgType === "call") return null;

            // 1) Load room doc and receivers
            const roomRef = db.doc(`privateChats/${roomId}`);
            const roomSnap = await roomRef.get();
            if (!roomSnap.exists) return null;

            const roomData = roomSnap.data() || {};
            const participants = Array.isArray(roomData.participants) ? roomData.participants : [];
            const participantIds = uniqStrings(participants);
            if (!participantIds.length) return null;

            const senderId = trimString(message.senderId);
            const receiverIds = participantIds.filter((uid) => uid && uid !== senderId);
            if (!receiverIds.length) {
                console.log("[MSG] No receivers for room", roomId);
                return null;
            }

            // 2) Load sender + receivers
            let senderName = "New message";
            if (senderId) {
                try {
                    const senderSnap = await db.collection("users").doc(senderId).get();
                    const senderData = senderSnap.exists ? senderSnap.data() || {} : {};
                    const full = `${trimString(senderData.firstName)} ${trimString(senderData.lastName)}`.trim();
                    if (full) senderName = full;
                } catch (_) {}
            }

            // ✅ IMPORTANT: notification body is privacy-safe if flag enabled
            const notifBody = buildNotificationBody(message);

            const userSnaps = await Promise.all(receiverIds.map((uid) => db.collection("users").doc(uid).get()));

            // 3) Collect tokens
            const tokens = uniqStrings(userSnaps.flatMap((s) => (s.exists ? extractFcmTokensFromUserDoc(s.data() || {}) : [])));

            if (!tokens.length) {
                console.log("[MSG] No FCM tokens for receivers in room", roomId, { receiverIds });
                return null;
            }

            // 4) Send
            // apns-collapse-id must be <= 64 bytes. roomId is long, so we hash it.
            const roomKey = shortStableKey("mw_room", roomId);
            const tokenBatches = chunk(tokens, 500);

            let totalSuccess = 0;
            let totalFailure = 0;
            const invalidTokens = [];

            for (const batch of tokenBatches) {
                const multicastMessage = {
                    tokens: batch,

                    // data-only for app routing
                    data: {
                        roomId: String(roomId),
                        senderId: String(senderId || ""),
                        type: "private_message",
                        roomKey: String(roomKey),
                        messageId: String(messageId || ""),
                    },

                    android: {
                        priority: "high",
                        collapseKey: roomKey,
                        notification: {
                            tag: roomKey,
                            channelId: "mw_chat",
                            title: senderName,
                            // ✅ hide message content here too
                            body: notifBody,
                        },
                    },

                    apns: {
                        headers: {
                            "apns-push-type": "alert",
                            "apns-priority": "10",
                            "apns-collapse-id": roomKey,
                        },
                        payload: {
                            aps: {
                                alert: { title: senderName, body: notifBody }, // ✅ hide content
                                sound: "default",
                                "thread-id": roomKey,
                            },
                        },
                    },
                };

                const response = await admin.messaging().sendEachForMulticast(multicastMessage);

                totalSuccess += response.successCount || 0;
                totalFailure += response.failureCount || 0;

                logMulticastFailures("MSG", batch, response, { roomId, messageId });
                invalidTokens.push(...tokensToRemoveFromSendResult(batch, response));
            }

            if (invalidTokens.length) {
                await cleanupInvalidFcmTokensBestEffort(db, receiverIds, uniqStrings(invalidTokens));
            }

            console.log("✅ MSG FCM send summary:", {
                roomId,
                messageId,
                receivers: receiverIds.length,
                tokens: tokens.length,
                totalSuccess,
                totalFailure,
                hideBody: isHideMessageBodyEnabled(),
            });

            return null;
        } catch (e) {
            console.error("onPrivateMessageCreate failed:", e);
            return null;
        }
    });

// ----------------------------------------------
// ✅ Trigger: New call created (USES SECRETS)
// ----------------------------------------------
exports.onCallCreate = functions
    .runWith({
        secrets: ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_P8", "APNS_VOIP_TOPIC", "APNS_PRODUCTION"],
    })
    .region("us-central1")
    .firestore.document("calls/{callId}")
    .onCreate(async (snap, context) => {
        try {
            if (!snap || !snap.exists) return null;

            const call = snap.data() || {};
            const callId = trimString(context && context.params ? context.params.callId : "");
            if (!callId) return null;

            const callerId = trimString(call.callerId);
            const calleeId = trimString(call.calleeId);

            const callType = trimString(call.type) || trimString(call.callType) || "audio";
            const status = trimString(call.status) || "ringing";

            if (status !== "ringing") return null;
            if (!calleeId) return null;

            const db = admin.firestore();

            const calleeSnap = await db.collection("users").doc(calleeId).get();
            if (!calleeSnap.exists) return null;

            const calleeData = calleeSnap.data() || {};

            const fcmTokens = extractFcmTokensFromUserDoc(calleeData);

            let voipToken = "";
            const voipTokens = extractVoipTokensFromUserDoc(calleeData);
            if (voipTokens.length) voipToken = voipTokens[0];

            if (!voipToken) {
                try {
                    const priv = await db.doc(`users/${calleeId}/private/profile`).get();
                    if (priv.exists) {
                        const more = extractVoipTokensFromUserDoc(priv.data() || {});
                        if (more.length) voipToken = more[0];
                    }
                } catch (_) {}
            }

            const callKey = shortStableKey("mw_call", callId);

            const voipPayload = {
                type: "call",
                callId: String(callId),
                callerId: String(callerId || ""),
                calleeId: String(calleeId),
                callType: String(callType),
                callKey: String(callKey),
            };

            const voipRes = await sendVoipApnsPushBestEffort({
                voipToken,
                payload: voipPayload,
                callId,
            });

            // FCM fallback
            if (fcmTokens.length) {
                const title = "MW";
                const body = "Incoming call";

                const tokenBatches = chunk(fcmTokens, 500);
                let totalSuccess = 0;
                let totalFailure = 0;
                const invalidTokens = [];

                for (const batch of tokenBatches) {
                    const multicastMessage = {
                        tokens: batch,
                        data: {
                            type: "call",
                            callId: String(callId),
                            callerId: String(callerId || ""),
                            calleeId: String(calleeId),
                            callType: String(callType),
                            callKey: String(callKey),
                        },
                        android: {
                            priority: "high",
                            ttl: 35 * 1000,
                            collapseKey: callKey,
                            notification: {
                                tag: callKey,
                                channelId: "mw_calls",
                                title,
                                body,
                            },
                        },
                        apns: {
                            headers: {
                                "apns-push-type": "alert",
                                "apns-priority": "10",
                                "apns-collapse-id": callKey,
                            },
                            payload: {
                                aps: {
                                    alert: { title, body },
                                    sound: "default",
                                    "thread-id": callKey,
                                    "interruption-level": "time-sensitive",
                                },
                            },
                        },
                    };

                    const response = await admin.messaging().sendEachForMulticast(multicastMessage);
                    totalSuccess += response.successCount || 0;
                    totalFailure += response.failureCount || 0;

                    logMulticastFailures("CALL", batch, response, { callId, calleeId });
                    invalidTokens.push(...tokensToRemoveFromSendResult(batch, response));
                }

                if (invalidTokens.length) {
                    await cleanupInvalidFcmTokensBestEffort(db, [calleeId], uniqStrings(invalidTokens));
                }

                console.log("[CALL] push summary:", {
                    callId,
                    calleeId,
                    fcmTokens: fcmTokens.length,
                    totalSuccess,
                    totalFailure,
                    voip: voipRes,
                    voipTokenPresent: !!voipToken,
                });

                try {
                    await db.collection("calls").doc(callId).set(
                        {
                            pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
                            pushVoip: voipRes && voipRes.ok === true,
                            pushFcm: totalSuccess > 0,
                            pushVoipReason: voipRes && voipRes.reason ? String(voipRes.reason) : admin.firestore.FieldValue.delete(),
                        },
                        { merge: true }
                    );
                } catch (_) {}
            } else {
                console.log("[CALL] no FCM tokens; voip result:", {
                    callId,
                    calleeId,
                    voip: voipRes,
                    voipTokenPresent: !!voipToken,
                });
            }

            return null;
        } catch (e) {
            console.error("onCallCreate failed:", e);
            return null;
        }
    });

// ----------------------------------------------
// Callable: purgeChatRoom
// ----------------------------------------------
exports.purgeChatRoom = functions.region("us-central1").https.onCall(async (data, context) => {
    try {
        const uid =
            context && context.auth && typeof context.auth.uid === "string" && context.auth.uid.length ? context.auth.uid : null;

        if (!uid) throw new functions.https.HttpsError("unauthenticated", "You must be signed in.");

        const roomId = data && typeof data.roomId === "string" ? data.roomId.trim() : "";
        if (!roomId) throw new functions.https.HttpsError("invalid-argument", "roomId is required.");

        const db = admin.firestore();

        const roomRef = db.doc(`privateChats/${roomId}`);
        const roomSnap = await roomRef.get();
        if (!roomSnap.exists) return { ok: true, deleted: 0, skipped: 0, reason: "room_missing" };

        const roomData = roomSnap.data() || {};
        const participants = Array.isArray(roomData.participants) ? roomData.participants : [];
        const participantIds = uniqStrings(participants);

        if (participantIds.indexOf(uid) === -1) {
            throw new functions.https.HttpsError("permission-denied", "You are not a participant in this room.");
        }

        const inputPaths = data && Array.isArray(data.paths) ? data.paths : [];
        const paths = uniqStrings(inputPaths.map((p) => (typeof p === "string" ? p.trim() : "")).filter(Boolean));

        if (!paths.length) return { ok: true, deleted: 0, skipped: 0, reason: "no_paths" };

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
                        console.log("Storage delete failed:", p, e && e.message ? e.message : String(e));
                    }
                })
            );
        }

        return { ok: true, deleted, skipped };
    } catch (e) {
        console.error("purgeChatRoom failed:", e);
        if (e && e.code && e.message) throw e;
        throw new functions.https.HttpsError("internal", e && e.message ? e.message : "Failed");
    }
});
