import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const [fixture] = JSON.parse(
  readFileSync(
    new URL(
      '../../../backend/command_service/test/fixtures/roll_movement_plans.json',
      import.meta.url,
    ),
    'utf8',
  ),
);
let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === 'object') {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, canonicalize(value[key])]),
    );
  }
  return value;
}

function inputHash({ gameId, expectedStateVersion, actorPlayerId }) {
  const material = canonicalize({
    v: 1,
    family: 'game',
    type: 'RollDice',
    target: gameId,
    expectedVersion: expectedStateVersion,
    actorPlayerId,
    payload: {},
  });
  return createHash('sha256').update(JSON.stringify(material)).digest('hex');
}

async function seedGame(suffix) {
  const gameId = `${fixture.operation.gameId}-${suffix}`;
  const publicState = structuredClone(fixture.initialPublicState);
  publicState.gameId = gameId;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'games', gameId), {
        ...publicState,
        memberUids: Object.values(fixture.memberUidByPlayerId),
        memberUidByPlayerId: fixture.memberUidByPlayerId,
        publicState,
        lastRollResult: null,
      }),
      setDoc(doc(db, 'gameSecrets', gameId), fixture.privateInput),
      setDoc(doc(db, 'rollRetryBarriers', gameId), { revision: 0 }),
    ]);
  });
  return gameId;
}

async function applyRoll({
  gameId,
  actorUid = fixture.operation.actorUid,
  actorPlayerId = fixture.operation.actorPlayerId,
  expectedStateVersion = fixture.operation.expectedStateVersion,
  semanticHash = inputHash({ gameId, expectedStateVersion, actorPlayerId }),
  forceCallbackRetry = false,
}) {
  const { commandId, inputHashVersion } = fixture.operation;
  let callbackAttempts = 0;
  const callbackPlans = [];
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const secretRef = doc(db, 'gameSecrets', gameId);
    const operationRef = doc(db, 'games', gameId, 'commands', commandId);
    const barrierRef = doc(db, 'rollRetryBarriers', gameId);

    result = await runTransaction(db, async (tx) => {
      callbackAttempts += 1;
      const priorSnapshot = await tx.get(operationRef);
      if (priorSnapshot.exists()) {
        const prior = priorSnapshot.data();
        const duplicate =
          prior.actorUid === actorUid &&
          prior.inputHashVersion === inputHashVersion &&
          prior.inputHash === semanticHash;
        return duplicate
          ? { disposition: 'duplicate', ...prior.resultSummary }
          : { disposition: 'commandIdCollision' };
      }

      const gameSnapshot = await tx.get(gameRef);
      if (!gameSnapshot.exists()) return { disposition: 'gameUnavailable' };
      const game = gameSnapshot.data();
      if (game.memberUidByPlayerId?.[actorPlayerId] !== actorUid) {
        return { disposition: 'actorNotAuthenticatedMember' };
      }
      if (game.stateVersion !== expectedStateVersion) {
        return {
          disposition: 'staleStateVersion',
          stateVersion: game.stateVersion,
        };
      }

      const [secretSnapshot, barrierSnapshot] = await Promise.all([
        tx.get(secretRef),
        tx.get(barrierRef),
      ]);
      if (!secretSnapshot.exists()) {
        return { disposition: 'privateStateUnavailable' };
      }
      const privateState = secretSnapshot.data();
      if (
        privateState.rngVersion !== fixture.rngVersion ||
        game.rngVersion !== fixture.rngVersion
      ) {
        return { disposition: 'rngVersionMismatch' };
      }

      // Shared fixture is generated and asserted by the canonical Dart
      // AuthorityRollMovementPlanner test. JavaScript only proves the durable
      // transaction shape; it does not implement RNG, movement, or gameplay.
      const plan = structuredClone(fixture.expectedPlan);
      callbackPlans.push(plan);
      if (forceCallbackRetry && callbackAttempts === 1) {
        await setDoc(barrierRef, {
          revision: barrierSnapshot.data().revision + 1,
        });
      }

      const publicStateAfter = structuredClone(game.publicState);
      publicStateAfter.stateVersion = plan.stateVersionAfter;
      publicStateAfter.turnState = plan.turnStateAfter;
      publicStateAfter.players = publicStateAfter.players.map((player) =>
        player.playerId === actorPlayerId
          ? { ...player, position: plan.toPosition }
          : player,
      );
      publicStateAfter.pendingDecision = plan.pendingDecision;
      publicStateAfter.lastMutation = {
        type: 'rollMovement',
        commandId,
        actorPlayerId,
      };
      const resultSummary = {
        commandId,
        status: 'accepted',
        stateVersionBefore: expectedStateVersion,
        stateVersionAfter: plan.stateVersionAfter,
        events: plan.events,
      };

      tx.set(
        gameRef,
        {
          stateVersion: plan.stateVersionAfter,
          publicState: publicStateAfter,
          lastRollResult: resultSummary,
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
        operationId: commandId,
        commandId,
        commandType: 'RollDice',
        actorUid,
        inputHashVersion,
        inputHash: semanticHash,
        stateVersionBefore: expectedStateVersion,
        stateVersionAfter: plan.stateVersionAfter,
        status: 'accepted',
        resultSummary,
      });
      return { disposition: 'accepted', ...resultSummary };
    });
  });

  return { result, callbackAttempts, callbackPlans };
}

async function readDurableState(gameId) {
  let state;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [game, secret, operation] = await Promise.all([
      getDoc(doc(db, 'games', gameId)),
      getDoc(doc(db, 'gameSecrets', gameId)),
      getDoc(
        doc(db, 'games', gameId, 'commands', fixture.operation.commandId),
      ),
    ]);
    state = { game: game.data(), secret: secret.data(), operation };
  });
  return state;
}

test('VP0 Roll transaction retry commits one stable Engine plan atomically', async () => {
  const gameId = await seedGame('callback-retry');
  const applied = await applyRoll({
    gameId,
    forceCallbackRetry: true,
  });

  assert.equal(applied.result.disposition, 'accepted');
  assert.ok(applied.callbackAttempts >= 2);
  assert.deepEqual(
    applied.callbackPlans,
    Array(applied.callbackAttempts).fill(fixture.expectedPlan),
  );

  const durable = await readDurableState(gameId);
  assert.equal(durable.game.stateVersion, 1);
  assert.equal(durable.game.publicState.players[0].position, 8);
  assert.equal(
    durable.game.publicState.turnState.phase,
    'awaitingPropertyDecision',
  );
  assert.deepEqual(
    durable.secret.streamCounters,
    fixture.expectedPlan.successorCounters,
  );
  assert.equal(durable.operation.data().stateVersionAfter, 1);
});

test('VP0 Roll lost ACK returns prior result without a second RNG effect', async () => {
  const gameId = await seedGame('lost-ack');
  const accepted = await applyRoll({ gameId });
  const duplicate = await applyRoll({ gameId });

  assert.equal(accepted.result.disposition, 'accepted');
  assert.equal(duplicate.result.disposition, 'duplicate');
  assert.deepEqual(duplicate.result.events, accepted.result.events);
  assert.equal(duplicate.callbackPlans.length, 0);

  const durable = await readDurableState(gameId);
  assert.equal(durable.game.stateVersion, 1);
  assert.equal(durable.secret.streamCounters.dice, 2);
});

test('VP0 Roll collision, non-member and stale commands fail before Engine plan', async () => {
  const collisionGameId = await seedGame('collision');
  await applyRoll({ gameId: collisionGameId });
  const collision = await applyRoll({
    gameId: collisionGameId,
    semanticHash: 'different-semantic-input',
  });
  assert.deepEqual(collision.result, { disposition: 'commandIdCollision' });
  assert.equal(collision.callbackPlans.length, 0);

  const nonMemberGameId = await seedGame('non-member');
  const nonMember = await applyRoll({
    gameId: nonMemberGameId,
    actorUid: 'uid-other',
  });
  assert.deepEqual(nonMember.result, {
    disposition: 'actorNotAuthenticatedMember',
  });
  assert.equal(nonMember.callbackPlans.length, 0);

  const staleGameId = await seedGame('stale');
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'games', staleGameId),
      { stateVersion: 4 },
      { merge: true },
    );
  });
  const stale = await applyRoll({ gameId: staleGameId });
  assert.deepEqual(stale.result, {
    disposition: 'staleStateVersion',
    stateVersion: 4,
  });
  assert.equal(stale.callbackPlans.length, 0);

  for (const gameId of [nonMemberGameId, staleGameId]) {
    const durable = await readDurableState(gameId);
    assert.equal(durable.secret.streamCounters.dice, 0);
    assert.equal(durable.operation.exists(), false);
  }
});

test('VP0 Roll two clients converge on public state without private leakage', async () => {
  const gameId = await seedGame('two-client');
  await applyRoll({ gameId });

  await env.withSecurityRulesDisabled(async (firstContext) => {
    const first = await getDoc(doc(firstContext.firestore(), 'games', gameId));
    await env.withSecurityRulesDisabled(async (secondContext) => {
      const second = await getDoc(
        doc(secondContext.firestore(), 'games', gameId),
      );
      assert.deepEqual(first.data().publicState, second.data().publicState);
      assert.equal(first.data().publicState.stateVersion, 1);
      assert.equal(first.data().publicState.players[0].position, 8);
      assert.equal(first.data().seedBytes, undefined);
      assert.equal(first.data().streamCounters, undefined);
      assert.equal(first.data().futureDeckOrder, undefined);
      assert.equal(first.data().lastRollResult.seedBytes, undefined);
      assert.equal(first.data().lastRollResult.streamCounters, undefined);
    });
  });
});
