const {test} = require('node:test');
const assert = require('node:assert/strict');

const PROJECT_ID = process.env.GCLOUD_PROJECT || 'demo-lumi-audio-appcheck';
const FUNCTIONS_ORIGIN = `http://127.0.0.1:5001/${PROJECT_ID}/australia-southeast1`;
const AUTH_ORIGIN = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099'}`;

async function createIdentity() {
  const response = await fetch(
    `${AUTH_ORIGIN}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
    {
      method: 'POST',
      headers: {'content-type': 'application/json'},
      body: JSON.stringify({
        email: 'appcheck-audio-parent@lumi.local',
        password: 'Local-test-only-Password1!',
        returnSecureToken: true,
      }),
    }
  );
  const body = await response.json();
  assert.equal(response.status, 200, JSON.stringify(body));
  return body.idToken;
}

test('enforced audio callable rejects authenticated request missing App Check', async () => {
  const token = await createIdentity();
  const response = await fetch(
    `${FUNCTIONS_ORIGIN}/confirmComprehensionAudioUpload`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        data: {schoolId: 'school_x', logId: 'log_x', durationSec: 12},
      }),
    }
  );
  const body = await response.json();
  assert.equal(response.status, 401, JSON.stringify(body));
  assert.equal(body.error.status, 'UNAUTHENTICATED');
});
