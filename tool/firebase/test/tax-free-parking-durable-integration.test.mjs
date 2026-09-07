import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const fixture = JSON.parse(
  readFileSync(
    new URL(
      '../../../backend/command_service/test/fixtures/tax_free_parking_plans.json',
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

async function seedScenario(scenarioName, suffix) {
  const scenario = fixture[scenarioName];
  const gameId = `game-us019-${suffix}`;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'games', gameId), {
        stateVersion: scenario.initialState.stateVersion,
        publicState: scenario.initialState,
      }),
      setDoc(doc(db, 'gameSecrets', gameId), fixture.privateSentinel),
      setDoc(doc(db, 'taxFreeParkingRetryBarriers', gameId), { revision: 0 }),
    ]);
  });
  return { gameId, scenario };
}

async function applyPlan({
  gameId,
  plan,
  forceCallbackRetry = false,
}) {
  const operation = plan.operation;
  let callbackAttempts = 0;
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const secretRef = doc(db, 'gameSecrets', gameId);
    const operationRef = doc(
      db,
      'games',
      gameId,
      'commands',
      operation.operationId,
    );
    const barrierRef = doc(db, 'taxFreeParkingRetryBarriers', gameId);

    result = await runTransaction(db, async (tx) => {
      callbackAttempts += 1;
      const priorSnapshot = await tx.get(operationRef);
      if (priorSnapshot.exists()) {
        const prior = priorSnapshot.data();
        const duplicate =
          prior.actorUid === 'authority-system' &&
          prior.inputHashVersion === 1 &&
          prior.inputHash === plan.inputHashMarker;
        return duplicate
          ? { disposition: 'duplicate', ...prior.resultSummary }
          : { disposition: 'commandIdCollision' };
      }

      const gameSnapshot = await tx.get(gameRef);
      const game = gameSnapshot.data();
      if (
        game.stateVersion !== operation.expectedStateVersion ||
        game.publicState.stateVersion !== operation.expectedStateVersion
      ) {
        return { disposition: 'staleStateVersion' };
      }
      const player = game.publicState.players.find(
        (candidate) => candidate.playerId === operation.playerId,
      );
      if (
        game.publicState.turnState.currentPlayerId !== operation.playerId ||
        game.publicState.turnState.phase !== 'resolvingLanding' ||
        player?.position !== operation.expectedLandingIndex
      ) {
        return { disposition: 'staleLanding' };
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

      // Dart proves the canonical Engine result behind this fixture. This
      // emulator layer persists that already-decided plan without recalculating
      // taxes, debt, pot transfer, or any other gameplay rule.
      tx.update(gameRef, {
        stateVersion: plan.resultSummary.stateVersionAfter,
        publicState: plan.stateAfter,
        lastTaxFreeParkingResult: plan.resultSummary,
      });
      tx.set(operationRef, {
        source: 'system',
        actorUid: 'authority-system',
        commandId: operation.operationId,
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

async function readDurable(gameId, operationId) {
  let durable;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [game, secret, operation] = await Promise.all([
      getDoc(doc(db, 'games', gameId)),
      getDoc(doc(db, 'gameSecrets', gameId)),
      getDoc(doc(db, 'games', gameId, 'commands', operationId)),
    ]);
    durable = { game: game.data(), secret: secret.data(), operation };
  });
  return durable;
}

test('TAX-POT-01..03 persist one tax debit and one pot credit', async () => {
  const { gameId, scenario } = await seedScenario('tax', 'tax-retry');
  const plan = scenario.plans.a;
  const accepted = await applyPlan({
    gameId,
    plan,
    forceCallbackRetry: true,
  });
  const duplicate = await applyPlan({ gameId, plan });

  assert.equal(accepted.result.disposition, 'accepted');
  assert.ok(accepted.callbackAttempts >= 2);
  assert.equal(duplicate.result.disposition, 'duplicate');
  assert.deepEqual(duplicate.result.events, accepted.result.events);
  const durable = await readDurable(gameId, plan.operation.operationId);
  assert.equal(durable.game.stateVersion, 2);
  assert.equal(durable.game.publicState.players[0].cash, 400);
  assert.equal(durable.game.publicState.freeParkingPot, 129);
  assert.deepEqual(durable.secret, fixture.privateSentinel);
  assert.equal(durable.operation.exists(), true);
});

test('FREE-POT-01/03/04 persist atomic collection exactly once', async () => {
  const { gameId, scenario } = await seedScenario(
    'collection',
    'collection-retry',
  );
  const plan = scenario.plans.a;
  const accepted = await applyPlan({
    gameId,
    plan,
    forceCallbackRetry: true,
  });
  const duplicate = await applyPlan({ gameId, plan });

  assert.equal(accepted.result.disposition, 'accepted');
  assert.ok(accepted.callbackAttempts >= 2);
  assert.equal(duplicate.result.disposition, 'duplicate');
  const durable = await readDurable(gameId, plan.operation.operationId);
  assert.equal(durable.game.publicState.players[0].cash, 763);
  assert.equal(durable.game.publicState.freeParkingPot, 0);
  assert.deepEqual(durable.secret, fixture.privateSentinel);
});

test('FREE-POT-02 persists zero-pot collection deterministically', async () => {
  const { gameId, scenario } = await seedScenario(
    'zeroCollection',
    'zero-collection',
  );
  const plan = scenario.plans.a;
  const accepted = await applyPlan({ gameId, plan });

  assert.equal(accepted.result.disposition, 'accepted');
  assert.equal(accepted.result.amount, 0);
  const durable = await readDurable(gameId, plan.operation.operationId);
  assert.equal(durable.game.stateVersion, 2);
  assert.equal(durable.game.publicState.players[0].cash, 500);
  assert.equal(durable.game.publicState.freeParkingPot, 0);
});

test('TAX-POT-04 persists canonical debt without partial debit', async () => {
  const { gameId, scenario } = await seedScenario('debt', 'debt');
  const plan = scenario.plans.a;
  const accepted = await applyPlan({ gameId, plan });

  assert.equal(accepted.result.disposition, 'accepted');
  const durable = await readDurable(gameId, plan.operation.operationId);
  assert.equal(durable.game.publicState.players[0].cash, 99);
  assert.equal(durable.game.publicState.freeParkingPot, 29);
  assert.equal(
    durable.game.publicState.debtCase.purpose,
    'taxToFreeParkingPot',
  );
  assert.equal(
    durable.game.publicState.pendingDecision.kind,
    'debtResolution',
  );
});

test('stale version and stale landing write no economic effect', async () => {
  const staleVersionSeed = await seedScenario('tax', 'stale-version');
  const plan = staleVersionSeed.scenario.plans.a;
  await env.withSecurityRulesDisabled(async (context) => {
    const state = staleVersionSeed.scenario.initialState;
    await setDoc(
      doc(context.firestore(), 'games', staleVersionSeed.gameId),
      {
        stateVersion: 9,
        publicState: {
          ...state,
          stateVersion: 9,
        },
      },
      { merge: true },
    );
  });
  const staleVersion = await applyPlan({
    gameId: staleVersionSeed.gameId,
    plan,
  });
  assert.equal(staleVersion.result.disposition, 'staleStateVersion');

  const staleLandingSeed = await seedScenario('tax', 'stale-landing');
  await env.withSecurityRulesDisabled(async (context) => {
    const state = staleLandingSeed.scenario.initialState;
    await setDoc(
      doc(context.firestore(), 'games', staleLandingSeed.gameId),
      {
        publicState: {
          ...state,
          players: state.players.map((player) =>
            player.playerId === 'p1' ? { ...player, position: 33 } : player,
          ),
        },
      },
      { merge: true },
    );
  });
  const staleLanding = await applyPlan({
    gameId: staleLandingSeed.gameId,
    plan: staleLandingSeed.scenario.plans.a,
  });
  assert.equal(staleLanding.result.disposition, 'staleLanding');

  for (const [gameId, attemptedPlan] of [
    [staleVersionSeed.gameId, plan],
    [staleLandingSeed.gameId, staleLandingSeed.scenario.plans.a],
  ]) {
    const durable = await readDurable(
      gameId,
      attemptedPlan.operation.operationId,
    );
    assert.equal(durable.operation.exists(), false);
    assert.notEqual(durable.game.publicState.freeParkingPot, 129);
    assert.deepEqual(durable.secret, fixture.privateSentinel);
  }
});

test('FREE-POT-05 competing resolutions accept at most one effect', async () => {
  const { gameId, scenario } = await seedScenario('collection', 'concurrent');
  const results = await Promise.all([
    applyPlan({ gameId, plan: scenario.plans.a }),
    applyPlan({ gameId, plan: scenario.plans.b }),
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
  const accepted = results.find(
    (item) => item.result.disposition === 'accepted',
  );
  const durable = await readDurable(gameId, accepted.result.operationId);
  assert.equal(durable.game.stateVersion, 2);
  assert.equal(durable.game.publicState.players[0].cash, 763);
  assert.equal(durable.game.publicState.freeParkingPot, 0);
  assert.deepEqual(durable.secret, fixture.privateSentinel);
});
