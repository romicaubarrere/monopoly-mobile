import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp, doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

async function resolveRoomCodeForJoin({ codeHash, actorUid, serverNowMs }) {
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const locatorRef = doc(db, 'roomCodes', codeHash);

    result = await runTransaction(db, async (tx) => {
      const locatorSnap = await tx.get(locatorRef);
      if (!locatorSnap.exists()) {
        return { disposition: 'roomUnavailable' };
      }

      const locator = locatorSnap.data();
      if (locator.expiresAt.toMillis() <= serverNowMs) {
        return { disposition: 'roomUnavailable' };
      }

      const roomRef = doc(db, 'rooms', locator.roomId);
      const roomSnap = await tx.get(roomRef);
      const room = roomSnap.data();
      if (!roomSnap.exists() || room.status !== 'open') {
        return { disposition: 'roomUnavailable' };
      }

      const memberUids = room.memberUids ?? [];
      if (!memberUids.includes(actorUid)) {
        tx.set(
          roomRef,
          {
            memberUids: [...memberUids, actorUid],
            roomVersion: (room.roomVersion ?? 0) + 1,
          },
          { merge: true },
        );
      }

      return { disposition: 'joined', roomId: locator.roomId };
    });
  });

  return result;
}

async function claimRoomCode({
  codeHash,
  roomId,
  serverNowMs,
  expiresAtMs,
}) {
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const locatorRef = doc(db, 'roomCodes', codeHash);
    const roomRef = doc(db, 'rooms', roomId);

    result = await runTransaction(db, async (tx) => {
      const locatorSnap = await tx.get(locatorRef);
      if (locatorSnap.exists()) {
        const locator = locatorSnap.data();
        if (locator.expiresAt.toMillis() > serverNowMs) {
          return { disposition: 'occupied', roomId: locator.roomId };
        }
      }

      tx.set(locatorRef, {
        codeHash,
        roomId,
        expiresAt: Timestamp.fromMillis(expiresAtMs),
        updatedAt: Timestamp.fromMillis(serverNowMs),
      });
      tx.set(roomRef, {
        roomId,
        roomVersion: 0,
        status: 'open',
        memberUids: [],
      });

      return { disposition: 'claimed', roomId };
    });
  });

  return result;
}

async function resolveExpiredDecision({ gameId, decisionId, authorityNowMs }) {
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const operationId = `deadline:v1:${decisionId}`;
    const operationRef = doc(db, 'games', gameId, 'commands', operationId);

    result = await runTransaction(db, async (tx) => {
      const operationSnap = await tx.get(operationRef);
      if (operationSnap.exists()) {
        const operation = operationSnap.data();
        return {
          disposition: 'duplicate',
          stateVersion: operation.stateVersionAfter,
        };
      }

      const gameSnap = await tx.get(gameRef);
      const game = gameSnap.data();
      const pending = game?.pendingDecision;
      if (!gameSnap.exists() || pending?.decisionId !== decisionId) {
        return { disposition: 'no_op', reason: 'alreadyResolved' };
      }
      if (authorityNowMs < pending.deadlineAt.toMillis()) {
        return { disposition: 'no_op', reason: 'notExpired' };
      }

      const stateVersionBefore = game.stateVersion;
      const stateVersionAfter = stateVersionBefore + 1;
      const deadlineEffectCount = (game.deadlineEffectCount ?? 0) + 1;

      // Test-harness effect only: it proves the transaction can persist at most
      // one state mutation for the deterministic operation id. Gameplay timeout
      // outcome selection remains owned by the Engine in production.
      tx.set(
        gameRef,
        {
          stateVersion: stateVersionAfter,
          pendingDecision: null,
          deadlineEffectCount,
        },
        { merge: true },
      );
      tx.set(operationRef, {
        operationId,
        source: 'system',
        operationType: 'ResolveExpiredDecision',
        decisionId,
        stateVersionBefore,
        stateVersionAfter,
        status: 'accepted',
        reason: 'expired',
        processedAt: Timestamp.fromMillis(authorityNowMs),
      });

      return { disposition: 'accepted', stateVersion: stateVersionAfter };
    });
  });

  return result;
}

test('TV-40 physically present expired locator is unavailable with zero membership', async () => {
  const codeHash = 'hash-tv40';
  const roomId = 'room-tv40-expired';
  const actorUid = 'actor-tv40';

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'roomCodes', codeHash), {
      codeHash,
      roomId,
      expiresAt: Timestamp.fromMillis(1000),
    });
    await setDoc(doc(db, 'rooms', roomId), {
      roomId,
      roomVersion: 0,
      status: 'open',
      memberUids: [],
    });
  });

  const result = await resolveRoomCodeForJoin({
    codeHash,
    actorUid,
    serverNowMs: 1000,
  });
  assert.deepEqual(result, { disposition: 'roomUnavailable' });

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const locator = await getDoc(doc(db, 'roomCodes', codeHash));
    const room = await getDoc(doc(db, 'rooms', roomId));
    assert.equal(locator.exists(), true, 'expired mapping remains physically present');
    assert.deepEqual(room.data().memberUids, []);
    assert.equal(room.data().roomVersion, 0);
  });
});

test('TV-41 concurrent reclaim of expired codeHash admits max one active mapping', async () => {
  const codeHash = 'hash-tv41';
  const serverNowMs = 2000;
  const expiresAtMs = 5000;

  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'roomCodes', codeHash), {
      codeHash,
      roomId: 'room-tv41-old',
      expiresAt: Timestamp.fromMillis(1000),
    });
  });

  const candidates = ['room-tv41-a', 'room-tv41-b'];
  const results = await Promise.all(
    candidates.map((roomId) =>
      claimRoomCode({ codeHash, roomId, serverNowMs, expiresAtMs }),
    ),
  );

  const claimed = results.filter((result) => result.disposition === 'claimed');
  const occupied = results.filter((result) => result.disposition === 'occupied');
  assert.equal(claimed.length, 1);
  assert.equal(occupied.length, 1);

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const locator = await getDoc(doc(db, 'roomCodes', codeHash));
    assert.equal(locator.data().roomId, claimed[0].roomId);
    assert.equal(locator.data().expiresAt.toMillis(), expiresAtMs);

    const roomDocs = await Promise.all(
      candidates.map((roomId) => getDoc(doc(db, 'rooms', roomId))),
    );
    assert.equal(roomDocs.filter((snap) => snap.exists()).length, 1);
    assert.equal(
      roomDocs.find((snap) => snap.exists()).data().roomId,
      claimed[0].roomId,
    );
  });
});

test('deadline wake-up before deadline is a read-only no-op', async () => {
  const gameId = 'game-deadline-early';
  const decisionId = 'decision-early';

  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'games', gameId), {
      stateVersion: 3,
      pendingDecision: {
        decisionId,
        deadlineAt: Timestamp.fromMillis(5000),
      },
      deadlineEffectCount: 0,
    });
  });

  const result = await resolveExpiredDecision({
    gameId,
    decisionId,
    authorityNowMs: 4999,
  });
  assert.deepEqual(result, { disposition: 'no_op', reason: 'notExpired' });

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const game = await getDoc(doc(db, 'games', gameId));
    const operation = await getDoc(
      doc(db, 'games', gameId, 'commands', `deadline:v1:${decisionId}`),
    );
    assert.equal(game.data().stateVersion, 3);
    assert.equal(game.data().deadlineEffectCount, 0);
    assert.equal(game.data().pendingDecision.deadlineAt.toMillis(), 5000);
    assert.equal(operation.exists(), false);
  });
});

test('concurrent deadline wake-ups persist one operation and one effect', async () => {
  const gameId = 'game-deadline-race';
  const decisionId = 'decision-race';
  const authorityNowMs = 5000;

  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'games', gameId), {
      stateVersion: 7,
      pendingDecision: {
        decisionId,
        deadlineAt: Timestamp.fromMillis(5000),
      },
      deadlineEffectCount: 0,
    });
  });

  const results = await Promise.all([
    resolveExpiredDecision({ gameId, decisionId, authorityNowMs }),
    resolveExpiredDecision({ gameId, decisionId, authorityNowMs }),
  ]);
  assert.equal(
    results.filter((result) => result.disposition === 'accepted').length,
    1,
  );
  assert.equal(
    results.filter((result) => result.disposition === 'duplicate').length,
    1,
  );

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const operationId = `deadline:v1:${decisionId}`;
    const game = await getDoc(doc(db, 'games', gameId));
    const operation = await getDoc(
      doc(db, 'games', gameId, 'commands', operationId),
    );

    assert.equal(game.data().stateVersion, 8);
    assert.equal(game.data().deadlineEffectCount, 1);
    assert.equal(game.data().pendingDecision, null);
    assert.equal(operation.exists(), true);
    assert.equal(operation.data().operationId, operationId);
    assert.equal(operation.data().source, 'system');
    assert.equal(operation.data().status, 'accepted');
    assert.equal(operation.data().stateVersionBefore, 7);
    assert.equal(operation.data().stateVersionAfter, 8);
  });
});
