import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const fixtures = JSON.parse(
  readFileSync(
    new URL(
      '../../../backend/command_service/test/fixtures/rng_operation_plans.json',
      import.meta.url,
    ),
    'utf8',
  ),
);
const rngDomain = Buffer.from('monopoly-rng-v1', 'utf8');
const uint64Cardinality = 1n << 64n;
let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

function fixture(id) {
  const found = fixtures.find((candidate) => candidate.id === id);
  assert.ok(found, `missing shared Dart RNG plan fixture ${id}`);
  return structuredClone(found);
}

// Independent test oracle only. Product authority invokes the pure-Dart
// AuthorityRngOperationPlanner; no JavaScript RNG ships in the command service.
function evaluateTestOracle({ rngVersion, seedBytes, streamCounters }, operation) {
  assert.equal(rngVersion, 'hmac_sha256_counter_v1');
  assert.equal(seedBytes.length, 32);
  const counters = { ...streamCounters };
  const values = [];
  let candidatesConsumed = 0;

  for (const upperBoundNumber of operation.upperBounds) {
    assert.ok(Number.isSafeInteger(upperBoundNumber) && upperBoundNumber > 0);
    const upperBound = BigInt(upperBoundNumber);
    const limit = (uint64Cardinality / upperBound) * upperBound;

    while (true) {
      const counter = counters[operation.stream];
      assert.ok(Number.isSafeInteger(counter) && counter >= 0);
      const counterBytes = Buffer.alloc(8);
      counterBytes.writeBigUInt64BE(BigInt(counter));
      const message = Buffer.concat([
        rngDomain,
        Buffer.from([0]),
        Buffer.from(operation.stream, 'utf8'),
        Buffer.from([0]),
        counterBytes,
      ]);
      const block = createHmac('sha256', Buffer.from(seedBytes)).update(message).digest();
      const raw64 = block.readBigUInt64BE(0);
      counters[operation.stream] = counter + 1;
      candidatesConsumed += 1;
      if (raw64 < limit) {
        values.push(Number(raw64 % upperBound));
        break;
      }
    }
  }

  return { values, candidatesConsumed, successorCounters: counters };
}

async function seedRandomOperation(testFixture, suffix) {
  const { operation, privateInput, rngVersion } = testFixture;
  const gameId = `${operation.gameId}-${suffix}`;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'games', gameId), {
        schemaVersion: 1,
        stateVersion: operation.expectedStateVersion,
        rngVersion,
        memberUids: [operation.actorUid],
        lastRandomResult: null,
      }),
      setDoc(doc(db, 'gameSecrets', gameId), {
        schemaVersion: 1,
        rngVersion,
        seedBytes: privateInput.seedBytes,
        streamCounters: privateInput.streamCounters,
      }),
      setDoc(doc(db, 'rngRetryBarriers', gameId), { revision: 0 }),
    ]);
  });
  return gameId;
}

async function applyRandomOperation({
  testFixture,
  gameId,
  inputHash = testFixture.operation.inputHash,
  forceCallbackRetry = false,
}) {
  const { operation, rngVersion, expectedPlan } = testFixture;
  let callbackAttempts = 0;
  const callbackPlans = [];
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const secretRef = doc(db, 'gameSecrets', gameId);
    const operationRef = doc(db, 'games', gameId, 'commands', operation.commandId);
    const barrierRef = doc(db, 'rngRetryBarriers', gameId);

    result = await runTransaction(db, async (tx) => {
      callbackAttempts += 1;
      const priorOperation = await tx.get(operationRef);
      if (priorOperation.exists()) {
        const prior = priorOperation.data();
        const duplicate =
          prior.actorUid === operation.actorUid &&
          prior.inputHashVersion === operation.inputHashVersion &&
          prior.inputHash === inputHash;
        return duplicate
          ? {
              disposition: 'duplicate',
              stateVersion: prior.stateVersionAfter,
              values: prior.resultSummary.values,
            }
          : { disposition: 'commandIdCollision' };
      }

      const gameSnap = await tx.get(gameRef);
      if (!gameSnap.exists()) {
        return { disposition: 'gameUnavailable' };
      }
      const game = gameSnap.data();
      if (game.stateVersion !== operation.expectedStateVersion) {
        return {
          disposition: 'staleStateVersion',
          stateVersion: game.stateVersion,
        };
      }
      if (game.rngVersion !== rngVersion) {
        return { disposition: 'rngVersionMismatch' };
      }

      const [secretSnap, barrierSnap] = await Promise.all([
        tx.get(secretRef),
        tx.get(barrierRef),
      ]);
      if (!secretSnap.exists()) {
        return { disposition: 'privateStateUnavailable' };
      }

      const plan = evaluateTestOracle(secretSnap.data(), operation);
      callbackPlans.push(plan);
      assert.deepEqual(plan, expectedPlan);

      if (forceCallbackRetry && callbackAttempts === 1) {
        await setDoc(barrierRef, { revision: barrierSnap.data().revision + 1 });
      }

      const stateVersionAfter = game.stateVersion + 1;
      const safeResult = {
        operationType: 'RandomDraw',
        rngVersion,
        values: plan.values,
      };
      tx.set(
        gameRef,
        {
          stateVersion: stateVersionAfter,
          lastRandomResult: {
            operationId: operation.commandId,
            ...safeResult,
          },
        },
        { merge: true },
      );
      tx.set(
        secretRef,
        { streamCounters: plan.successorCounters },
        { merge: true },
      );
      tx.set(operationRef, {
        source: 'human',
        operationId: operation.commandId,
        commandId: operation.commandId,
        commandType: 'RandomDraw',
        actorUid: operation.actorUid,
        inputHashVersion: operation.inputHashVersion,
        inputHash,
        stateVersionBefore: game.stateVersion,
        stateVersionAfter,
        status: 'accepted',
        resultSummary: safeResult,
      });

      return {
        disposition: 'accepted',
        stateVersion: stateVersionAfter,
        values: plan.values,
      };
    });
  });

  return { result, callbackAttempts, callbackPlans };
}

async function readDurableState({ gameId, commandId }) {
  let state;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [game, secret, operation] = await Promise.all([
      getDoc(doc(db, 'games', gameId)),
      getDoc(doc(db, 'gameSecrets', gameId)),
      getDoc(doc(db, 'games', gameId, 'commands', commandId)),
    ]);
    state = { game: game.data(), secret: secret.data(), operation };
  });
  return state;
}

test('TV-27 Firestore callback retry recomputes one stable plan and commits once', async () => {
  const testFixture = fixture('tv-27-durable-dice-draw');
  const gameId = await seedRandomOperation(testFixture, 'callback-retry');

  const applied = await applyRandomOperation({
    testFixture,
    gameId,
    forceCallbackRetry: true,
  });

  assert.equal(applied.result.disposition, 'accepted');
  assert.ok(applied.callbackAttempts >= 2, 'expected a transaction callback retry');
  assert.deepEqual(
    applied.callbackPlans,
    Array(applied.callbackAttempts).fill(testFixture.expectedPlan),
  );

  const durable = await readDurableState({
    gameId,
    commandId: testFixture.operation.commandId,
  });
  assert.equal(
    durable.game.stateVersion,
    testFixture.operation.expectedStateVersion + 1,
  );
  assert.deepEqual(durable.game.lastRandomResult.values, [5, 1]);
  assert.deepEqual(
    durable.secret.streamCounters,
    testFixture.expectedPlan.successorCounters,
  );
  assert.equal(durable.operation.exists(), true);
  assert.equal(durable.operation.data().stateVersionAfter, durable.game.stateVersion);
  assert.equal(durable.operation.data().resultSummary.values.join(','), '5,1');
  assert.equal(durable.operation.data().resultSummary.successorCounters, undefined);
});

test('TV-27 commit-before-ACK retry returns prior result with no second RNG effect', async () => {
  const testFixture = fixture('tv-27-durable-dice-draw');
  const gameId = await seedRandomOperation(testFixture, 'lost-ack');

  const accepted = await applyRandomOperation({ testFixture, gameId });
  const retried = await applyRandomOperation({ testFixture, gameId });

  assert.deepEqual(accepted.result, {
    disposition: 'accepted',
    stateVersion: testFixture.operation.expectedStateVersion + 1,
    values: [5, 1],
  });
  assert.deepEqual(retried.result, {
    disposition: 'duplicate',
    stateVersion: testFixture.operation.expectedStateVersion + 1,
    values: [5, 1],
  });
  assert.equal(retried.callbackPlans.length, 0, 'duplicate must not invoke RNG');

  const durable = await readDurableState({
    gameId,
    commandId: testFixture.operation.commandId,
  });
  assert.equal(
    durable.game.stateVersion,
    testFixture.operation.expectedStateVersion + 1,
  );
  assert.equal(durable.secret.streamCounters.dice, 2);
  assert.deepEqual(durable.operation.data().resultSummary.values, [5, 1]);
});

test('TV-27 commandId collision fails closed without RNG or public mutation', async () => {
  const testFixture = fixture('tv-27-durable-dice-draw');
  const gameId = await seedRandomOperation(testFixture, 'collision');
  await applyRandomOperation({ testFixture, gameId });

  const collision = await applyRandomOperation({
    testFixture,
    gameId,
    inputHash: 'different-semantic-payload-hash',
  });
  assert.deepEqual(collision.result, { disposition: 'commandIdCollision' });
  assert.equal(collision.callbackPlans.length, 0);

  const durable = await readDurableState({
    gameId,
    commandId: testFixture.operation.commandId,
  });
  assert.equal(durable.secret.streamCounters.dice, 2);
  assert.equal(
    durable.game.stateVersion,
    testFixture.operation.expectedStateVersion + 1,
  );
});

test('stale stateVersion fails before private RNG evaluation', async () => {
  const testFixture = fixture('tv-27-durable-dice-draw');
  const gameId = await seedRandomOperation(testFixture, 'stale');
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'games', gameId),
      { stateVersion: testFixture.operation.expectedStateVersion + 4 },
      { merge: true },
    );
  });

  const stale = await applyRandomOperation({ testFixture, gameId });
  assert.deepEqual(stale.result, {
    disposition: 'staleStateVersion',
    stateVersion: testFixture.operation.expectedStateVersion + 4,
  });
  assert.equal(stale.callbackPlans.length, 0);

  const durable = await readDurableState({
    gameId,
    commandId: testFixture.operation.commandId,
  });
  assert.equal(durable.secret.streamCounters.dice, 0);
  assert.equal(durable.operation.exists(), false);
});
