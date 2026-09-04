import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const fixture = JSON.parse(
  readFileSync(
    new URL(
      '../../../backend/command_service/test/fixtures/bankruptcy_plans.json',
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

async function seedGame(suffix) {
  const gameId = `game-bankruptcy-${suffix}`;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'games', gameId), {
        stateVersion: 1,
        memberUidByPlayerId: { p1: 'uid-p1', p2: 'uid-p2' },
        publicState: fixture.declareA.initialState,
      }),
      setDoc(doc(db, 'gameSecrets', gameId), fixture.privateSentinel),
      setDoc(doc(db, 'bankruptcyRetryBarriers', gameId), { revision: 0 }),
    ]);
  });
  return gameId;
}

async function applyPlan({
  gameId,
  planKey,
  actorUid,
  requestReceivedAt,
  authorityNow,
  forceCallbackRetry = false,
}) {
  const plan = fixture[planKey];
  const command = plan.command;
  const system = planKey === 'deadline';
  let callbackAttempts = 0;
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const secretRef = doc(db, 'gameSecrets', gameId);
    const operationRef = doc(db, 'games', gameId, 'commands', command.commandId);
    const barrierRef = doc(db, 'bankruptcyRetryBarriers', gameId);

    result = await runTransaction(db, async (tx) => {
      callbackAttempts += 1;
      const priorSnapshot = await tx.get(operationRef);
      if (priorSnapshot.exists()) {
        const prior = priorSnapshot.data();
        const duplicate =
          prior.actorUid === (actorUid ?? 'authority-system') &&
          prior.inputHashVersion === 1 &&
          prior.inputHash === plan.inputHashMarker;
        return duplicate
          ? { disposition: 'duplicate', ...prior.resultSummary }
          : { disposition: 'commandIdCollision' };
      }

      const gameSnapshot = await tx.get(gameRef);
      const game = gameSnapshot.data();
      const pending = game.publicState.pendingDecision;
      if (system) {
        if (
          command.commandId !== `deadline:v1:${pending?.decisionId}` ||
          pending?.timeoutPolicy !== 'declareBankruptcy'
        ) {
          return { disposition: 'staleDecision' };
        }
        if (authorityNow < pending.deadlineAt) {
          return { disposition: 'notDue' };
        }
      } else {
        if (game.memberUidByPlayerId?.[command.actorPlayerId] !== actorUid) {
          return { disposition: 'actorNotAuthenticatedMember' };
        }
        if (requestReceivedAt >= pending?.deadlineAt) {
          return { disposition: 'decisionClosed' };
        }
      }
      if (game.stateVersion !== command.expectedStateVersion) {
        return { disposition: 'staleStateVersion' };
      }

      const [secretSnapshot, barrierSnapshot] = await Promise.all([
        tx.get(secretRef),
        tx.get(barrierRef),
      ]);
      assert.equal(secretSnapshot.exists(), true);
      if (forceCallbackRetry && callbackAttempts === 1) {
        await setDoc(barrierRef, {
          revision: barrierSnapshot.data().revision + 1,
        });
      }

      // Dart asserts this fixture against the canonical Engine plan. This
      // integration test proves persistence only and never recalculates rules.
      tx.update(gameRef, {
        stateVersion: plan.resultSummary.stateVersionAfter,
        publicState: plan.stateAfter,
        lastBankruptcyResult: plan.resultSummary,
      });
      tx.set(operationRef, {
        source: system ? 'system' : 'human',
        actorUid: actorUid ?? 'authority-system',
        commandId: command.commandId,
        commandType: command.type,
        inputHashVersion: 1,
        inputHash: plan.inputHashMarker,
        stateVersionBefore: plan.resultSummary.stateVersionBefore,
        stateVersionAfter: plan.resultSummary.stateVersionAfter,
        status: 'accepted',
        resultSummary: plan.resultSummary,
      });
      return { disposition: 'accepted', ...plan.resultSummary };
    });
  });
  return { result, callbackAttempts };
}

async function readDurable(gameId, commandId) {
  let durable;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [game, secret, operation] = await Promise.all([
      getDoc(doc(db, 'games', gameId)),
      getDoc(doc(db, 'gameSecrets', gameId)),
      getDoc(doc(db, 'games', gameId, 'commands', commandId)),
    ]);
    durable = { game: game.data(), secret: secret.data(), operation };
  });
  return durable;
}

test('retry and lost ACK apply bankruptcy exactly once', async () => {
  const gameId = await seedGame('retry');
  const accepted = await applyPlan({
    gameId,
    planKey: 'declareA',
    actorUid: 'uid-p1',
    requestReceivedAt: '2026-08-25T04:29:00.000Z',
    forceCallbackRetry: true,
  });
  const duplicate = await applyPlan({
    gameId,
    planKey: 'declareA',
    actorUid: 'uid-p1',
    requestReceivedAt: '2026-08-25T04:29:00.000Z',
  });

  assert.equal(accepted.result.disposition, 'accepted');
  assert.ok(accepted.callbackAttempts >= 2);
  assert.equal(duplicate.result.disposition, 'duplicate');
  const durable = await readDurable(
    gameId,
    fixture.declareA.command.commandId,
  );
  assert.equal(durable.game.stateVersion, 2);
  assert.equal(durable.game.publicState.players[0].status, 'bankrupt');
  assert.deepEqual(durable.secret, fixture.privateSentinel);
  assert.equal(durable.operation.exists(), true);
});

test('stale version and deadline boundary write no gameplay effect', async () => {
  const deadlineGame = await seedGame('human-deadline');
  const closed = await applyPlan({
    gameId: deadlineGame,
    planKey: 'declareA',
    actorUid: 'uid-p1',
    requestReceivedAt: '2026-08-25T04:30:00.000Z',
  });
  assert.equal(closed.result.disposition, 'decisionClosed');

  const staleGame = await seedGame('stale');
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'games', staleGame),
      { stateVersion: 9 },
      { merge: true },
    );
  });
  const stale = await applyPlan({
    gameId: staleGame,
    planKey: 'declareA',
    actorUid: 'uid-p1',
    requestReceivedAt: '2026-08-25T04:29:00.000Z',
  });
  assert.equal(stale.result.disposition, 'staleStateVersion');

  for (const [gameId, commandId] of [
    [deadlineGame, fixture.declareA.command.commandId],
    [staleGame, fixture.declareA.command.commandId],
  ]) {
    const durable = await readDurable(gameId, commandId);
    assert.equal(durable.operation.exists(), false);
    assert.notEqual(durable.game.publicState.players[0].status, 'bankrupt');
    assert.deepEqual(durable.secret, fixture.privateSentinel);
  }
});

test('concurrent triggers accept at most one state transition', async () => {
  const gameId = await seedGame('concurrent');
  const results = await Promise.all([
    applyPlan({
      gameId,
      planKey: 'declareA',
      actorUid: 'uid-p1',
      requestReceivedAt: '2026-08-25T04:29:00.000Z',
    }),
    applyPlan({
      gameId,
      planKey: 'declareB',
      actorUid: 'uid-p1',
      requestReceivedAt: '2026-08-25T04:29:00.000Z',
    }),
  ]);
  assert.equal(
    results.filter((item) => item.result.disposition === 'accepted').length,
    1,
  );
  assert.equal(
    results.filter((item) => item.result.disposition === 'staleStateVersion')
      .length,
    1,
  );
  const durable = await readDurable(
    gameId,
    fixture.declareA.command.commandId,
  );
  assert.equal(durable.game.stateVersion, 2);
  assert.deepEqual(durable.secret, fixture.privateSentinel);
});

test('deadline trigger is early-safe and duplicate-safe', async () => {
  const gameId = await seedGame('deadline');
  const early = await applyPlan({
    gameId,
    planKey: 'deadline',
    authorityNow: '2026-08-25T04:29:59.999Z',
  });
  assert.equal(early.result.disposition, 'notDue');

  const results = await Promise.all([
    applyPlan({
      gameId,
      planKey: 'deadline',
      authorityNow: '2026-08-25T04:30:00.000Z',
    }),
    applyPlan({
      gameId,
      planKey: 'deadline',
      authorityNow: '2026-08-25T04:30:00.000Z',
    }),
  ]);
  assert.equal(
    results.filter((item) => item.result.disposition === 'accepted').length,
    1,
  );
  assert.equal(
    results.filter((item) => item.result.disposition === 'duplicate').length,
    1,
  );
  const durable = await readDurable(
    gameId,
    fixture.deadline.command.commandId,
  );
  assert.equal(durable.game.stateVersion, 2);
  assert.deepEqual(durable.secret, fixture.privateSentinel);
});
