import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const fixture = JSON.parse(
  readFileSync(
    new URL(
      '../../../backend/command_service/test/fixtures/buy_auction_plans.json',
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

function initialOfferState() {
  return {
    schemaVersion: 1,
    stateVersion: 1,
    rulesVersion: 'synthetic-rules-vp0',
    rngVersion: 'hmac_sha256_counter_v1',
    rngCommitment: '0'.repeat(64),
    gameId: 'game-vp0',
    roomId: 'room-vp0',
    status: 'active',
    presetConfig: {
      presetId: 'express',
      auctionPolicy: { minimumIncrement: 10 },
      mandatoryDecisionSeconds: 12,
      auctionBidSeconds: 6,
      auctionHardCapSeconds: 45,
    },
    roundState: { round: 1 },
    turnState: {
    turnNumber: 1,
    phase: 'awaitingPropertyDecision',
    currentPlayerId: 'p1',
    landingPropertyId: 'street-07',
    },
    players: [
      {
        playerId: 'p1', seat: 0, kind: 'human', status: 'active',
        cash: 2000, position: 8, ownedPropertyIds: [], keepCards: [],
        inCucha: false, cuchaAttempts: 0, consecutiveDoubles: 0,
        connectivityStatus: 'online',
      },
      {
        playerId: 'p2', seat: 1, kind: 'human', status: 'active',
        cash: 2000, position: 0, ownedPropertyIds: [], keepCards: [],
        inCucha: false, cuchaAttempts: 0, consecutiveDoubles: 0,
        connectivityStatus: 'online',
      },
    ],
    seatControllers: [
      { playerId: 'p1', controller: 'human', humanReclaimPending: false },
      { playerId: 'p2', controller: 'human', humanReclaimPending: false },
    ],
    board: {
      boardId: 'synthetic-board',
      boardDefinitionVersion: 'synthetic-board-vp0',
    },
    ownership: {},
    bank: { currencyUnit: 'synthetic-unit' },
    freeParkingPot: 0,
    deckPublicState: {},
    pendingDecision: {
    decisionId: 'cmd-roll-1:propertyOffer',
    kind: 'propertyOffer',
    allowedPlayerIds: ['p1'],
    stateVersionCreated: 1,
    createdAt: '2026-08-25T02:29:48.000Z',
    deadlineAt: '2026-08-25T02:30:12.000Z',
    timeoutPolicy: 'pass',
    payload: { propertyId: 'street-07', purchasePrice: 107 },
    },
    lastMutation: { type: 'rollMovement', commandId: 'cmd-roll-1' },
  };
}

function applyStateProjection(stateBefore, projection) {
  const stateAfter = structuredClone(stateBefore);
  stateAfter.stateVersion = projection.stateVersionAfter;
  stateAfter.players = projection.players;
  stateAfter.ownership = projection.ownership;
  stateAfter.turnState = projection.turnState;
  stateAfter.lastMutation = projection.lastMutation;
  if (projection.pendingDecision == null) delete stateAfter.pendingDecision;
  else stateAfter.pendingDecision = projection.pendingDecision;
  if (projection.activeAuction == null) delete stateAfter.activeAuction;
  else stateAfter.activeAuction = projection.activeAuction;
  return stateAfter;
}

async function seedGame(suffix) {
  const gameId = `game-buy-auction-${suffix}`;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'games', gameId), {
        stateVersion: 1,
        memberUidByPlayerId: { p1: 'uid-1', p2: 'uid-2' },
        publicState: initialOfferState(),
      }),
      setDoc(doc(db, 'gameSecrets', gameId), fixture.privateSentinel),
      setDoc(doc(db, 'buyAuctionRetryBarriers', gameId), { revision: 0 }),
    ]);
  });
  return gameId;
}

async function applyFixturePlan({
  gameId,
  planKey,
  actorUid,
  requestReceivedAt,
  authorityNow,
  semanticHash,
  commandOverride,
  forceCallbackRetry = false,
}) {
  const contract = fixture[planKey];
  const command = { ...contract.command, ...commandOverride };
  const inputHash = semanticHash ?? contract.inputHashMarker;
  const source = planKey === 'deadlinePass' ? 'system' : 'human';
  let callbackAttempts = 0;
  const callbackPlans = [];
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const secretRef = doc(db, 'gameSecrets', gameId);
    const operationRef = doc(db, 'games', gameId, 'commands', command.commandId);
    const barrierRef = doc(db, 'buyAuctionRetryBarriers', gameId);

    result = await runTransaction(db, async (tx) => {
      callbackAttempts += 1;
      const priorSnapshot = await tx.get(operationRef);
      if (priorSnapshot.exists()) {
        const prior = priorSnapshot.data();
        const duplicate =
          prior.actorUid === (actorUid ?? 'authority-system') &&
          prior.inputHashVersion === 1 &&
          prior.inputHash === inputHash;
        return duplicate
          ? { disposition: 'duplicate', ...prior.resultSummary }
          : { disposition: 'commandIdCollision' };
      }

      const gameSnapshot = await tx.get(gameRef);
      if (!gameSnapshot.exists()) return { disposition: 'gameUnavailable' };
      const game = gameSnapshot.data();
      const publicState = game.publicState;
      if (source === 'human') {
        if (game.memberUidByPlayerId?.[command.actorPlayerId] !== actorUid) {
          return { disposition: 'actorNotAuthenticatedMember' };
        }
        const allowed = publicState.pendingDecision?.allowedPlayerIds ?? [];
        if (!allowed.includes(command.actorPlayerId)) {
          return { disposition: 'decisionClosed' };
        }
        if (
          requestReceivedAt >= publicState.pendingDecision?.deadlineAt
        ) {
          return { disposition: 'decisionClosed', reason: 'deadlineReached' };
        }
      } else {
        const pending = publicState.pendingDecision;
        if (
          command.commandId !== `deadline:v1:${pending?.decisionId}` ||
          pending?.timeoutPolicy !== 'pass'
        ) {
          return { disposition: 'staleDeadline' };
        }
        if (authorityNow < pending.deadlineAt) {
          return { disposition: 'notDue' };
        }
      }
      if (game.stateVersion !== command.expectedStateVersion) {
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

      // The shared fixture is asserted against canonical Dart Engine plans.
      // JavaScript proves transaction behavior only; it never calculates cash,
      // ownership, bidder rotation, deadlines, or winners.
      const plan = structuredClone(contract);
      callbackPlans.push(plan);
      if (forceCallbackRetry && callbackAttempts === 1) {
        await setDoc(barrierRef, {
          revision: barrierSnapshot.data().revision + 1,
        });
      }

      const publicStateAfter = applyStateProjection(
        publicState,
        plan.stateProjection,
      );
      tx.update(gameRef, {
        stateVersion: plan.resultSummary.stateVersionAfter,
        publicState: publicStateAfter,
        lastBuyAuctionResult: plan.resultSummary,
      });
      tx.set(operationRef, {
        source,
        operationId: command.commandId,
        commandId: command.commandId,
        commandType: command.type,
        actorUid: actorUid ?? 'authority-system',
        inputHashVersion: 1,
        inputHash,
        stateVersionBefore: plan.resultSummary.stateVersionBefore,
        stateVersionAfter: plan.resultSummary.stateVersionAfter,
        status: 'accepted',
        resultSummary: plan.resultSummary,
      });
      return { disposition: 'accepted', ...plan.resultSummary };
    });
  });

  return { result, callbackAttempts, callbackPlans };
}

async function readDurable(gameId, commandId) {
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [game, secret, operation] = await Promise.all([
      getDoc(doc(db, 'games', gameId)),
      getDoc(doc(db, 'gameSecrets', gameId)),
      getDoc(doc(db, 'games', gameId, 'commands', commandId)),
    ]);
    result = { game: game.data(), secret: secret.data(), operation };
  });
  return result;
}

test('Buy retry and lost ACK charge and transfer exactly once', async () => {
  const gameId = await seedGame('buy-retry');
  const accepted = await applyFixturePlan({
    gameId,
    planKey: 'buy',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:00.000Z',
    forceCallbackRetry: true,
  });
  const duplicate = await applyFixturePlan({
    gameId,
    planKey: 'buy',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:00.000Z',
  });

  assert.equal(accepted.result.disposition, 'accepted');
  assert.ok(accepted.callbackAttempts >= 2);
  assert.deepEqual(
    accepted.callbackPlans,
    Array(accepted.callbackAttempts).fill(fixture.buy),
  );
  assert.equal(duplicate.result.disposition, 'duplicate');
  assert.equal(duplicate.callbackPlans.length, 0);

  const durable = await readDurable(gameId, fixture.buy.command.commandId);
  const buyer = durable.game.publicState.players.find(
    (player) => player.playerId === 'p1',
  );
  assert.equal(durable.game.stateVersion, 2);
  assert.equal(buyer.cash, 1893);
  assert.deepEqual(buyer.ownedPropertyIds, ['street-07']);
  assert.equal(
    durable.game.publicState.ownership.byPropertyId['street-07'],
    'p1',
  );
  assert.deepEqual(durable.secret, fixture.privateSentinel);
});

test('collision, non-member, stale and deadline boundary mutate nothing', async () => {
  const collisionGameId = await seedGame('collision');
  await applyFixturePlan({
    gameId: collisionGameId,
    planKey: 'buy',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:00.000Z',
  });
  const collision = await applyFixturePlan({
    gameId: collisionGameId,
    planKey: 'buy',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:00.000Z',
    semanticHash: 'different-semantic-input',
  });
  assert.equal(collision.result.disposition, 'commandIdCollision');

  const cases = [
    {
      suffix: 'non-member',
      actorUid: 'uid-other',
      at: '2026-08-25T02:30:00.000Z',
      expected: 'actorNotAuthenticatedMember',
    },
    {
      suffix: 'at-deadline',
      actorUid: 'uid-1',
      at: '2026-08-25T02:30:12.000Z',
      expected: 'decisionClosed',
    },
  ];
  for (const item of cases) {
    const gameId = await seedGame(item.suffix);
    const applied = await applyFixturePlan({
      gameId,
      planKey: 'buy',
      actorUid: item.actorUid,
      requestReceivedAt: item.at,
    });
    assert.equal(applied.result.disposition, item.expected);
    assert.equal(applied.callbackPlans.length, 0);
    const durable = await readDurable(gameId, fixture.buy.command.commandId);
    assert.equal(durable.game.stateVersion, 1);
    assert.equal(durable.operation.exists(), false);
    assert.deepEqual(durable.secret, fixture.privateSentinel);
  }

  const staleGameId = await seedGame('stale');
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'games', staleGameId),
      { stateVersion: 9 },
      { merge: true },
    );
  });
  const stale = await applyFixturePlan({
    gameId: staleGameId,
    planKey: 'buy',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:00.000Z',
  });
  assert.deepEqual(stale.result, {
    disposition: 'staleStateVersion',
    stateVersion: 9,
  });
  assert.equal(stale.callbackPlans.length, 0);

  const invalidBidderGameId = await seedGame('invalid-bidder');
  await applyFixturePlan({
    gameId: invalidBidderGameId,
    planKey: 'decline',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:00.000Z',
  });
  const invalidBidder = await applyFixturePlan({
    gameId: invalidBidderGameId,
    planKey: 'bid',
    actorUid: 'uid-2',
    requestReceivedAt: '2026-08-25T02:30:02.000Z',
    commandOverride: { actorPlayerId: 'p2' },
  });
  assert.equal(invalidBidder.result.disposition, 'decisionClosed');
  assert.equal(invalidBidder.callbackPlans.length, 0);
  const invalidBidderDurable = await readDurable(
    invalidBidderGameId,
    fixture.bid.command.commandId,
  );
  assert.equal(invalidBidderDurable.game.stateVersion, 2);
  assert.equal(invalidBidderDurable.operation.exists(), false);
});

test('Decline, Bid and deadline Pass converge once on auction winner', async () => {
  const gameId = await seedGame('auction-loop');
  await applyFixturePlan({
    gameId,
    planKey: 'decline',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:00.000Z',
  });
  await applyFixturePlan({
    gameId,
    planKey: 'bid',
    actorUid: 'uid-1',
    requestReceivedAt: '2026-08-25T02:30:02.000Z',
  });

  const early = await applyFixturePlan({
    gameId,
    planKey: 'deadlinePass',
    authorityNow: '2026-08-25T02:30:07.999Z',
  });
  assert.equal(early.result.disposition, 'notDue');
  assert.equal(early.callbackPlans.length, 0);

  const results = await Promise.all([
    applyFixturePlan({
      gameId,
      planKey: 'deadlinePass',
      authorityNow: '2026-08-25T02:30:08.000Z',
    }),
    applyFixturePlan({
      gameId,
      planKey: 'deadlinePass',
      authorityNow: '2026-08-25T02:30:08.000Z',
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

  const commandId = fixture.deadlinePass.command.commandId;
  const durable = await readDurable(gameId, commandId);
  const winner = durable.game.publicState.players.find(
    (player) => player.playerId === 'p1',
  );
  assert.equal(durable.game.stateVersion, 4);
  assert.equal(winner.cash, 1960);
  assert.deepEqual(winner.ownedPropertyIds, ['street-07']);
  assert.equal(durable.game.publicState.pendingDecision, undefined);
  assert.equal(durable.game.publicState.activeAuction, undefined);
  assert.deepEqual(durable.secret, fixture.privateSentinel);

  await env.withSecurityRulesDisabled(async (firstContext) => {
    const first = await getDoc(doc(firstContext.firestore(), 'games', gameId));
    await env.withSecurityRulesDisabled(async (secondContext) => {
      const second = await getDoc(doc(secondContext.firestore(), 'games', gameId));
      assert.deepEqual(first.data().publicState, second.data().publicState);
      assert.equal(first.data().publicState.seedBytes, undefined);
      assert.equal(first.data().publicState.streamCounters, undefined);
      assert.equal(first.data().publicState.futureDeckOrder, undefined);
    });
  });
});
