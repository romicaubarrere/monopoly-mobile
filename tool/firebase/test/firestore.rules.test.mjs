import fs from 'node:fs';
import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync(new URL('../../../firestore.rules', import.meta.url), 'utf8'),
    },
  });

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'rooms/room-fixture'), {
      memberUids: ['member-uid'],
      roomVersion: 1,
      status: 'open',
    });
    await setDoc(doc(db, 'games/game-fixture'), {
      memberUids: ['member-uid'],
      schemaVersion: 1,
      stateVersion: 1,
      rulesVersion: 'synthetic-foundation',
    });
    await setDoc(doc(db, 'rooms/other-room'), {
      memberUids: ['other-uid'],
      roomVersion: 1,
      status: 'open',
    });
    await setDoc(doc(db, 'games/other-game'), {
      memberUids: ['other-uid'],
      schemaVersion: 1,
      stateVersion: 1,
      rulesVersion: 'synthetic-foundation',
    });
    await setDoc(doc(db, 'gameSecrets/game-fixture'), {
      seedBase64: 'test-only-secret-never-mobile',
      streamCounters: { dice: 0 },
    });
    await setDoc(doc(db, 'roomCodes/code-hash-fixture'), {
      roomId: 'room-fixture',
      expiresAt: '2099-01-01T00:00:00Z',
    });
    await setDoc(doc(db, 'roomCommands/command-fixture'), {
      commandId: 'command-fixture',
    });
    await setDoc(doc(db, 'games/game-fixture/commands/operation-fixture'), {
      operationId: 'operation-fixture',
      source: 'human',
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('member can read room and confirmed public game', async () => {
  const db = testEnv.authenticatedContext('member-uid').firestore();
  await assertSucceeds(getDoc(doc(db, 'rooms/room-fixture')));
  await assertSucceeds(getDoc(doc(db, 'games/game-fixture')));
});

test('membership is scoped per room and game', async () => {
  const db = testEnv.authenticatedContext('member-uid').firestore();
  await assertFails(getDoc(doc(db, 'rooms/other-room')));
  await assertFails(getDoc(doc(db, 'games/other-game')));
});

test('client cannot grant itself membership by mutating authority state', async () => {
  const db = testEnv.authenticatedContext('member-uid').firestore();
  await assertFails(
    setDoc(
      doc(db, 'rooms/other-room'),
      { memberUids: ['other-uid', 'member-uid'] },
      { merge: true },
    ),
  );
  await assertFails(
    setDoc(
      doc(db, 'games/other-game'),
      { memberUids: ['other-uid', 'member-uid'] },
      { merge: true },
    ),
  );
});

test('non-member cannot read private room or game', async () => {
  const db = testEnv.authenticatedContext('other-uid').firestore();
  await assertFails(getDoc(doc(db, 'rooms/room-fixture')));
  await assertFails(getDoc(doc(db, 'games/game-fixture')));
});

test('unauthenticated client cannot read member state', async () => {
  const db = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(db, 'rooms/room-fixture')));
  await assertFails(getDoc(doc(db, 'games/game-fixture')));
});

test('mobile cannot write authoritative room or game state', async () => {
  const db = testEnv.authenticatedContext('member-uid').firestore();
  await assertFails(setDoc(doc(db, 'rooms/room-fixture'), { memberUids: ['member-uid'] }));
  await assertFails(setDoc(doc(db, 'games/game-fixture'), { memberUids: ['member-uid'] }));
});

test('authority-private collections deny client read and write', async () => {
  const db = testEnv.authenticatedContext('member-uid').firestore();
  for (const path of [
    'gameSecrets/game-fixture',
    'roomCodes/code-hash-fixture',
    'roomCommands/command-fixture',
    'games/game-fixture/commands/operation-fixture',
  ]) {
    await assertFails(getDoc(doc(db, path)), `read must fail: ${path}`);
    await assertFails(setDoc(doc(db, path), { tampered: true }), `write must fail: ${path}`);
  }
});

test('unknown collections are denied by default', async () => {
  const db = testEnv.authenticatedContext('member-uid').firestore();
  await assertFails(getDoc(doc(db, 'unexpected/document')));
  await assertFails(setDoc(doc(db, 'unexpected/document'), { value: true }));
  assert.ok(true);
});
