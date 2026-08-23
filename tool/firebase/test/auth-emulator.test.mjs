import test from 'node:test';
import assert from 'node:assert/strict';

test('Auth emulator accepts anonymous sign-in without cloud credentials', async () => {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  assert.ok(host, 'FIREBASE_AUTH_EMULATOR_HOST must be set by Emulator Suite');

  const response = await fetch(
    `http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );

  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(typeof payload.localId, 'string');
  assert.ok(payload.localId.length > 0);
  assert.equal(typeof payload.idToken, 'string');
  assert.ok(payload.idToken.length > 0);
});
