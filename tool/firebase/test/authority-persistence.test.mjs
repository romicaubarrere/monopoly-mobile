import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

async function applyAuthorityCommand({
  roomId,
  commandId,
  actorUid,
  inputHash,
  inputHashVersion = 1,
  expectedVersion,
  requestReceivedAt,
}) {
  let authorityResult;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const roomRef = doc(db, 'rooms', roomId);
    const commandRef = doc(db, 'rooms', roomId, 'commands', commandId);

    let reads = 0;
    let writes = 0;

    const result = await runTransaction(db, async (tx) => {
      const [roomSnap, commandSnap] = await Promise.all([
        tx.get(roomRef),
        tx.get(commandRef),
      ]);
      reads += 2;

      if (commandSnap.exists()) {
        const existing = commandSnap.data();
        const duplicate =
          existing.actorUid === actorUid &&
          existing.inputHashVersion === inputHashVersion &&
          existing.inputHash === inputHash;
        return {
          disposition: duplicate ? 'duplicate' : 'collision',
          stateVersion: roomSnap.data()?.stateVersion ?? 0,
        };
      }

      const currentVersion = roomSnap.data()?.stateVersion ?? 0;
      if (currentVersion !== expectedVersion) {
        return { disposition: 'stale', stateVersion: currentVersion };
      }

      const nextVersion = currentVersion + 1;
      tx.set(roomRef, { stateVersion: nextVersion }, { merge: true });
      tx.set(commandRef, {
        actorUid,
        inputHashVersion,
        inputHash,
        requestReceivedAt,
        processedAt: requestReceivedAt,
        resultSummary: { stateVersion: nextVersion },
        schemaVersion: 1,
        stateVersion: nextVersion,
      });
      writes += 2;

      return { disposition: 'applied', stateVersion: nextVersion };
    });

    authorityResult = { ...result, reads, writes };
  });

  return authorityResult;
}

test('authority transaction is atomic and duplicate-safe', async () => {
  const roomId = 'room-authority-test';
  const requestReceivedAt = '2026-08-24T02:00:00.000Z';

  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'rooms', roomId), { stateVersion: 0 });
  });

  const first = await applyAuthorityCommand({
    roomId,
    commandId: 'cmd-1',
    actorUid: 'actor-a',
    inputHash: 'hash-a',
    expectedVersion: 0,
    requestReceivedAt,
  });
  assert.deepEqual(first, {
    disposition: 'applied',
    stateVersion: 1,
    reads: 2,
    writes: 2,
  });

  const duplicate = await applyAuthorityCommand({
    roomId,
    commandId: 'cmd-1',
    actorUid: 'actor-a',
    inputHash: 'hash-a',
    expectedVersion: 0,
    requestReceivedAt,
  });
  assert.equal(duplicate.disposition, 'duplicate');
  assert.equal(duplicate.stateVersion, 1);
  assert.equal(duplicate.writes, 0);

  const collision = await applyAuthorityCommand({
    roomId,
    commandId: 'cmd-1',
    actorUid: 'actor-a',
    inputHash: 'hash-b',
    expectedVersion: 1,
    requestReceivedAt,
  });
  assert.equal(collision.disposition, 'collision');
  assert.equal(collision.stateVersion, 1);
  assert.equal(collision.writes, 0);

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const room = await getDoc(doc(db, 'rooms', roomId));
    const persisted = await getDoc(doc(db, 'rooms', roomId, 'commands', 'cmd-1'));
    assert.equal(room.data().stateVersion, 1);
    assert.equal(persisted.data().requestReceivedAt, requestReceivedAt);
    assert.equal(persisted.data().inputHashVersion, 1);
  });
});

test('stale expectedVersion never mutates authority state', async () => {
  const roomId = 'room-stale-test';
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'rooms', roomId), { stateVersion: 4 });
  });

  const stale = await applyAuthorityCommand({
    roomId,
    commandId: 'cmd-stale',
    actorUid: 'actor-b',
    inputHash: 'hash-stale',
    expectedVersion: 3,
    requestReceivedAt: '2026-08-24T02:00:01.000Z',
  });

  assert.equal(stale.disposition, 'stale');
  assert.equal(stale.stateVersion, 4);
  assert.equal(stale.writes, 0);

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const persisted = await getDoc(doc(db, 'rooms', roomId, 'commands', 'cmd-stale'));
    assert.equal(persisted.exists(), false);
  });
});
