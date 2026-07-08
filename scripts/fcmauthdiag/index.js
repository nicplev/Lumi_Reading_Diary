// Disposable FCM auth diagnostic v4 — real-registration-token cells.
// Reads the test parent's own fcmToken server-side (it never leaves the
// function; only a prefix is echoed for identification). dryRun validates
// without delivering; the non-dry cell attempts the actual push the user has
// been requesting via the app's "Send test".

const admin = require("firebase-admin");
admin.initializeApp();

const MD = "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default";
const FCM_URL = "https://fcm.googleapis.com/v1/projects/lumi-ninc-au/messages:send";
const SCHOOL = "beaumaris_primary_school";
const PARENT_UID = "bSjSHpdAnHMryKSQdaWCKyem64P2";

function appStyleMessage(token) {
  // Mirrors sendTestReadingReminder's message shape exactly.
  return {
    token,
    notification: {title: "Time to read with Lumi! 📚", body: "Diagnostic push — the full pipeline works."},
    data: {type: "reading_reminder", schoolId: SCHOOL, studentIds: ""},
    apns: {payload: {aps: {sound: "default"}}},
    android: {priority: "high", notification: {sound: "default", clickAction: "FLUTTER_NOTIFICATION_CLICK"}},
  };
}

function sdkErr(e) {
  return {
    code: e && e.code,
    message: e && e.message ? String(e.message).slice(0, 220) : String(e).slice(0, 220),
  };
}

async function mdGet(path) {
  const r = await fetch(MD + path, { headers: { "Metadata-Flavor": "Google" } });
  return { status: r.status, text: await r.text() };
}

async function rawFcm(tok, message, validateOnly) {
  const r = await fetch(FCM_URL, {
    method: "POST",
    headers: { "Authorization": "Bearer " + tok, "Content-Type": "application/json" },
    body: JSON.stringify({ validate_only: validateOnly, message }),
  });
  return { status: r.status, body: (await r.text()).slice(0, 800) };
}

exports.diag = async (req, res) => {
  const out = {};
  try {
    const snap = await admin.firestore()
      .doc(`schools/${SCHOOL}/parents/${PARENT_UID}`).get();
    const fcmToken = snap.exists ? snap.data().fcmToken : undefined;
    if (!fcmToken) {
      out.realtoken = "ABSENT — parent has no fcmToken (not logged in?)";
      res.json(out);
      return;
    }
    out.realtoken_prefix = fcmToken.slice(0, 12) + `… (len ${fcmToken.length})`;

    // Control: dummy token via SDK (expected: registration-token-not-registered)
    try {
      out.sdk_dummy_dryrun = { ok: await admin.messaging().send({token: "diagnostic-dummy-token", notification: {title: "d", body: "d"}}, true) };
    } catch (e) {
      out.sdk_dummy_dryrun = sdkErr(e);
    }

    // 1. Real token, dryRun (validates registration; no delivery)
    try {
      out.sdk_real_dryrun = { ok: await admin.messaging().send(appStyleMessage(fcmToken), true) };
    } catch (e) {
      out.sdk_real_dryrun = sdkErr(e);
    }

    // 2. Real token, REAL DELIVERY (the push the user is waiting for)
    try {
      out.sdk_real_send = { ok: await admin.messaging().send(appStyleMessage(fcmToken), false) };
    } catch (e) {
      out.sdk_real_send = sdkErr(e);
    }

    // 3. Raw REST with real token, validate_only (full response body visible)
    const t1 = JSON.parse((await mdGet("/token")).text);
    out.raw_real_validate = await rawFcm(t1.access_token, appStyleMessage(fcmToken), true);

    // 4. Raw REST real delivery only if SDK real send failed (keeps at most
    //    one delivered push per invocation) — full body shows the true error.
    if (!out.sdk_real_send.ok) {
      out.raw_real_send = await rawFcm(t1.access_token, appStyleMessage(fcmToken), false);
    }

    res.json(out);
  } catch (e) {
    out.fatal = String(e && e.stack ? e.stack : e).slice(0, 400);
    res.status(500).json(out);
  }
};
