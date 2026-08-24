import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const rngVersion = 'hmac_sha256_counter_v1';
const testSeed = Buffer.from(
  '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
  'hex',
);
const twoTo64 = 1n << 64n;

let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

function nextInt({ seed, stream, counter, upperBound }) {
  const counterBytes = Buffer.alloc(8);
  counterBytes.writeBigUInt64BE(counter);
  const message = Buffer.concat([
    Buffer.from('monopoly-rng-v1', 'utf8'),
    Buffer.from([0]),
    Buffer.from(stream, 'utf8'),
    Buffer.from([0]),
    counterBytes,
  ]);
  const raw = createHmac('sha256', seed).update(message).digest().readBigUInt64BE(0);
  const limit = (twoTo64 / upperBound) * upperBound;
  if (raw >= limit) {
    return nextInt({
      seed,
      stream,
      counter: counter + 1n,
      upperBound,
    });
  }
  return {
    value: raw % upperBound,
    successor: counter + 1n,
  };
}

function retryBarrier(participants) {
  let waiting = 0;
  let release;
  const ready = new Promise((resolve) => {
    release = resolve;
  });
  return async () => {
    waiting += 1;
    if (waiting === participants) release();
    await ready;
  };
}

async function executeRandomCommand({ gameId, commandId, beforeFirstWrite, trace }) {
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const secretRef = doc(db, 'gameSecrets', gameId);
    const commandRef = doc(db, 'games', gameId, 'commands', commandId);
    let callbackCount = 0;

    result = await runTransaction(db, async (tx) => {
      callbackCount += 1;
      const commandSnap = await tx.get(commandRef);
      if (commandSnap.exists()) {
        const previous = commandSnap.data();
        return {
          disposition: 'duplicate',
          face: previous.face,
          stateVersion: previous.stateVersionAfter,
        };
      }

      const [gameSnap, secretSnap] = await Promise.all([
        tx.get(gameRef),
        tx.get(secretRef),
      ]);
      assert.ok(gameSnap.exists());
      assert.ok(secretSnap.exists());
      const game = gameSnap.data();
      const secret = secretSnap.data();
      assert.equal(secret.rngVersion, rngVersion);

      const draw = nextInt({
        seed: Buffer.from(secret.seedHex, 'hex'),
        stream: 'dice',
        counter: BigInt(secret.diceCounter),
        upperBound: 6n,
      });
      const face = Number(draw.value) + 1;
      trace.push({
        callbackCount,
        counterBefore: secret.diceCounter,
        face,
        successor: Number(draw.successor),
      });

      if (callbackCount === 1 && beforeFirstWrite) await beforeFirstWrite();

      const stateVersionAfter = game.stateVersion + 1;
      tx.set(
        gameRef,
        {
          stateVersion: stateVersionAfter,
          lastDiceFace: face,
          randomEffectCount: game.randomEffectCount + 1,
        },
        { merge: true },
      );
      tx.set(
        secretRef,
        { diceCounter: Number(draw.successor) },
        { merge: true },
      );
      tx.set(commandRef, {
        commandId,
        operationType: 'RollSingleDie',
        rngVersion,
        face,
        stateVersionBefore: game.stateVersion,
        stateVersionAfter,
        status: 'accepted',
      });
      return { disposition: 'accepted', face, stateVersion: stateVersionAfter };
    });
  });
  return result;
}

test('TV-27 callback retry and lost ACK commit one random effect and counter advance', async () => {
  const gameId = 'rng-tv-27';
  const commandId = 'command-roll-1';
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'games', gameId), {
      stateVersion: 7,
      randomEffectCount: 0,
    });
    await setDoc(doc(db, 'gameSecrets', gameId), {
      rngVersion,
      seedHex: testSeed.toString('hex'),
      diceCounter: 0,
    });
  });

  const waitForBothCallbacks = retryBarrier(2);
  const firstTrace = [];
  const secondTrace = [];
  const concurrentResults = await Promise.all([
    executeRandomCommand({
      gameId,
      commandId,
      beforeFirstWrite: waitForBothCallbacks,
      trace: firstTrace,
    }),
    executeRandomCommand({
      gameId,
      commandId,
      beforeFirstWrite: waitForBothCallbacks,
      trace: secondTrace,
    }),
  ]);

  assert.deepEqual(firstTrace[0], secondTrace[0]);
  assert.equal(firstTrace[0].face, 6);
  assert.equal(firstTrace[0].successor, 1);
  assert.deepEqual(
    concurrentResults.map((result) => result.disposition).sort(),
    ['accepted', 'duplicate'],
  );

  // Simulate retry after commit-before-ACK. The persisted command result wins.
  const lostAckRetry = await executeRandomCommand({
    gameId,
    commandId,
    trace: [],
  });
  assert.deepEqual(lostAckRetry, {
    disposition: 'duplicate',
    face: 6,
    stateVersion: 8,
  });

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [gameSnap, secretSnap, commandSnap] = await Promise.all([
      getDoc(doc(db, 'games', gameId)),
      getDoc(doc(db, 'gameSecrets', gameId)),
      getDoc(doc(db, 'games', gameId, 'commands', commandId)),
    ]);
    assert.equal(gameSnap.data().stateVersion, 8);
    assert.equal(gameSnap.data().lastDiceFace, 6);
    assert.equal(gameSnap.data().randomEffectCount, 1);
    assert.equal(secretSnap.data().diceCounter, 1);
    assert.equal(commandSnap.data().stateVersionBefore, 7);
    assert.equal(commandSnap.data().stateVersionAfter, 8);
  });
});
