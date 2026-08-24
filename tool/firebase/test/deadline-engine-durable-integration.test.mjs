import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { Timestamp, doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const vectors = JSON.parse(
  readFileSync(
    new URL(
      '../../../backend/command_service/test/fixtures/deadline_engine_plans.json',
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

function vector(id) {
  const found = vectors.find((candidate) => candidate.id === id);
  assert.ok(found, `missing shared Engine contract vector ${id}`);
  return found;
}

function persistencePlan(contractVector) {
  return {
    decisionId: contractVector.decisionId,
    expectedStateVersion: contractVector.stateVersionCreated,
    disposition: contractVector.expectedDisposition,
    action: contractVector.expectedAction,
    operationId: contractVector.expectedOperationId,
  };
}

async function seedGame({ gameId, contractVector, stateVersion }) {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'games', gameId), {
      stateVersion: stateVersion ?? contractVector.stateVersionCreated,
      pendingDecision: {
        decisionId: contractVector.decisionId,
        stateVersionCreated: contractVector.stateVersionCreated,
        deadlineAt: Timestamp.fromMillis(contractVector.deadlineAtMs),
      },
    });
  });
}

async function persistDeadlinePlan({ gameId, plan, authorityNowMs }) {
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const operationRef = doc(db, 'games', gameId, 'commands', plan.operationId);

    result = await runTransaction(db, async (tx) => {
      const operationSnap = await tx.get(operationRef);
      if (operationSnap.exists()) {
        const operation = operationSnap.data();
        return {
          disposition: 'duplicate',
          action: operation.action,
          stateVersion: operation.stateVersionAfter,
        };
      }

      const gameSnap = await tx.get(gameRef);
      if (!gameSnap.exists()) {
        return { disposition: 'no_op', reason: 'missingGame' };
      }

      const game = gameSnap.data();
      const pending = game.pendingDecision;
      if (pending?.decisionId !== plan.decisionId) {
        return { disposition: 'no_op', reason: 'staleDecision' };
      }
      if (
        pending.stateVersionCreated !== plan.expectedStateVersion ||
        game.stateVersion !== plan.expectedStateVersion
      ) {
        return { disposition: 'no_op', reason: 'staleStateVersion' };
      }
      if (authorityNowMs < pending.deadlineAt.toMillis()) {
        return { disposition: 'no_op', reason: 'notExpired' };
      }

      if (plan.disposition !== 'terminal') {
        return { disposition: 'delegate', action: plan.action };
      }

      const stateVersionAfter = game.stateVersion + 1;
      const resolution = {
        decisionId: plan.decisionId,
        operationId: plan.operationId,
        action: plan.action,
        reason: 'expired',
      };

      tx.set(
        gameRef,
        {
          stateVersion: stateVersionAfter,
          pendingDecision: null,
          lastDeadlineResolution: resolution,
        },
        { merge: true },
      );
      tx.set(operationRef, {
        operationId: plan.operationId,
        source: 'system',
        operationType: 'ResolveExpiredDecision',
        decisionId: plan.decisionId,
        action: plan.action,
        stateVersionBefore: game.stateVersion,
        stateVersionAfter,
        status: 'accepted',
        reason: 'expired',
        processedAt: Timestamp.fromMillis(authorityNowMs),
      });

      return {
        disposition: 'accepted',
        action: plan.action,
        stateVersion: stateVersionAfter,
      };
    });
  });

  return result;
}

async function classifyHumanDecisionIngress({
  gameId,
  decisionId,
  requestReceivedAtMs,
}) {
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    result = await runTransaction(db, async (tx) => {
      const gameSnap = await tx.get(doc(db, 'games', gameId));
      if (!gameSnap.exists()) {
        return { disposition: 'decisionClosed', reason: 'missingGame' };
      }

      const pending = gameSnap.data().pendingDecision;
      if (pending?.decisionId !== decisionId) {
        return { disposition: 'decisionClosed', reason: 'staleDecision' };
      }

      return requestReceivedAtMs < pending.deadlineAt.toMillis()
        ? { disposition: 'eligible' }
        : { disposition: 'decisionClosed', reason: 'deadlineReached' };
    });
  });

  return result;
}

async function readGameAndOperation({ gameId, operationId }) {
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const game = await getDoc(doc(db, 'games', gameId));
    const operation = await getDoc(doc(db, 'games', gameId, 'commands', operationId));
    result = { game: game.data(), operation };
  });
  return result;
}

test('captured human ingress before deadline stays eligible across late retry', async () => {
  const contractVector = vector('auction-pass');
  const gameId = 'game-human-before-deadline';
  await seedGame({ gameId, contractVector });

  const result = await classifyHumanDecisionIngress({
    gameId,
    decisionId: contractVector.decisionId,
    requestReceivedAtMs: contractVector.deadlineAtMs - 1,
  });

  assert.deepEqual(result, { disposition: 'eligible' });
  const persisted = await readGameAndOperation({
    gameId,
    operationId: contractVector.expectedOperationId,
  });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated);
  assert.equal(persisted.operation.exists(), false);
});

test('human ingress at deadline is closed with zero mutation', async () => {
  const contractVector = vector('auction-pass');
  const gameId = 'game-human-at-deadline';
  await seedGame({ gameId, contractVector });

  const result = await classifyHumanDecisionIngress({
    gameId,
    decisionId: contractVector.decisionId,
    requestReceivedAtMs: contractVector.deadlineAtMs,
  });

  assert.deepEqual(result, {
    disposition: 'decisionClosed',
    reason: 'deadlineReached',
  });
  const persisted = await readGameAndOperation({
    gameId,
    operationId: contractVector.expectedOperationId,
  });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated);
  assert.equal(persisted.game.pendingDecision.decisionId, contractVector.decisionId);
  assert.equal(persisted.operation.exists(), false);
});

test('early deadline wake is a durable read-only no-op', async () => {
  const contractVector = vector('auction-pass');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-durable-early';
  await seedGame({ gameId, contractVector });

  const result = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.deadlineAtMs - 1,
  });

  assert.deepEqual(result, { disposition: 'no_op', reason: 'notExpired' });
  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated);
  assert.equal(persisted.game.pendingDecision.decisionId, contractVector.decisionId);
  assert.equal(persisted.operation.exists(), false);
});

test('auction pass plan persists one terminal outcome under concurrent wakeups', async () => {
  const contractVector = vector('auction-pass');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-auction-pass-race';
  await seedGame({ gameId, contractVector });

  const results = await Promise.all([
    persistDeadlinePlan({
      gameId,
      plan,
      authorityNowMs: contractVector.authorityNowMs,
    }),
    persistDeadlinePlan({
      gameId,
      plan,
      authorityNowMs: contractVector.authorityNowMs,
    }),
  ]);

  assert.equal(results.filter((item) => item.disposition === 'accepted').length, 1);
  assert.equal(results.filter((item) => item.disposition === 'duplicate').length, 1);
  assert.equal(results.every((item) => item.action === 'pass'), true);

  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated + 1);
  assert.equal(persisted.game.pendingDecision, null);
  assert.deepEqual(persisted.game.lastDeadlineResolution, {
    decisionId: contractVector.decisionId,
    operationId: contractVector.expectedOperationId,
    action: 'pass',
    reason: 'expired',
  });
  assert.equal(persisted.operation.exists(), true);
  assert.equal(persisted.operation.data().action, 'pass');
});

test('lost ACK retry returns prior persisted result with zero second effect', async () => {
  const contractVector = vector('auction-pass');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-auction-pass-lost-ack';
  await seedGame({ gameId, contractVector });

  const accepted = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.authorityNowMs,
  });
  const retry = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.authorityNowMs + 1000,
  });

  assert.deepEqual(accepted, {
    disposition: 'accepted',
    action: 'pass',
    stateVersion: contractVector.stateVersionCreated + 1,
  });
  assert.deepEqual(retry, {
    disposition: 'duplicate',
    action: 'pass',
    stateVersion: contractVector.stateVersionCreated + 1,
  });

  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated + 1);
  assert.equal(persisted.operation.data().stateVersionBefore, contractVector.stateVersionCreated);
  assert.equal(
    persisted.operation.data().stateVersionAfter,
    contractVector.stateVersionCreated + 1,
  );
});

test('trade timeout persists reject and never invents acceptance', async () => {
  const contractVector = vector('trade-reject');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-trade-reject';
  await seedGame({ gameId, contractVector });

  const result = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.authorityNowMs,
  });

  assert.deepEqual(result, {
    disposition: 'accepted',
    action: 'reject',
    stateVersion: contractVector.stateVersionCreated + 1,
  });
  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.lastDeadlineResolution.action, 'reject');
  assert.notEqual(persisted.game.lastDeadlineResolution.action, 'accept');
});

test('stale state version fails closed with zero writes', async () => {
  const contractVector = vector('auction-pass');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-stale-state-version';
  await seedGame({
    gameId,
    contractVector,
    stateVersion: contractVector.stateVersionCreated + 1,
  });

  const result = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.authorityNowMs,
  });

  assert.deepEqual(result, {
    disposition: 'no_op',
    reason: 'staleStateVersion',
  });
  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated + 1);
  assert.equal(persisted.game.pendingDecision.decisionId, contractVector.decisionId);
  assert.equal(persisted.operation.exists(), false);
});

test('stale decision id fails closed with zero writes', async () => {
  const contractVector = vector('auction-pass');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-stale-decision-id';
  await seedGame({ gameId, contractVector });

  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'games', gameId),
      { pendingDecision: { decisionId: 'newer-decision' } },
      { merge: true },
    );
  });

  const result = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.authorityNowMs,
  });

  assert.deepEqual(result, { disposition: 'no_op', reason: 'staleDecision' });
  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated);
  assert.equal(persisted.operation.exists(), false);
});

test('delegated bot decision remains pending and persists no false terminal result', async () => {
  const contractVector = vector('property-bot-delegate');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-bot-delegate';
  await seedGame({ gameId, contractVector });

  const result = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.authorityNowMs,
  });

  assert.deepEqual(result, {
    disposition: 'delegate',
    action: 'delegateBotDecision',
  });
  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated);
  assert.equal(persisted.game.pendingDecision.decisionId, contractVector.decisionId);
  assert.equal(persisted.operation.exists(), false);
});

test('delegated auto liquidation remains pending and persists no false terminal result', async () => {
  const contractVector = vector('debt-auto-liquidate-delegate');
  const plan = persistencePlan(contractVector);
  const gameId = 'game-liquidation-delegate';
  await seedGame({ gameId, contractVector });

  const result = await persistDeadlinePlan({
    gameId,
    plan,
    authorityNowMs: contractVector.authorityNowMs,
  });

  assert.deepEqual(result, {
    disposition: 'delegate',
    action: 'delegateAutoLiquidation',
  });
  const persisted = await readGameAndOperation({ gameId, operationId: plan.operationId });
  assert.equal(persisted.game.stateVersion, contractVector.stateVersionCreated);
  assert.equal(persisted.game.pendingDecision.decisionId, contractVector.decisionId);
  assert.equal(persisted.operation.exists(), false);
});
