import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { after, before, test } from 'node:test';

import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

import {
  FirstPlayableAuthorityFirestoreStore,
  duplicateReply,
} from '../src/first-playable-authority-store.mjs';

const projectId = 'demo-board-game-local';
const [readyFixture] = readFixture('ready_start_plans.json');
const [rollFixture] = readFixture('roll_movement_plans.json');
const buyFixture = readFixture('buy_auction_plans.json');
let env;

function readFixture(name) {
  return JSON.parse(
    readFileSync(
      new URL(`../../../backend/command_service/test/fixtures/${name}`, import.meta.url),
      'utf8',
    ),
  );
}

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

async function adminStore() {
  let store;
  await env.withSecurityRulesDisabled(async (context) => {
    store = new FirstPlayableAuthorityFirestoreStore(context.firestore(), {
      doc,
      getDoc,
      runTransaction,
    });
  });
  return store;
}

function receipt({ commandId, actorUid, inputHash, before, after, result }) {
  return {
    schemaVersion: 1,
    commandId,
    actorUid,
    inputHashVersion: 1,
    inputHash,
    stateVersionBefore: before,
    stateVersionAfter: after,
    status: 'accepted',
    resultSummary: result,
  };
}

function replayOrCollision(storedReceipt, actorUid, inputHash, family) {
  if (storedReceipt == null) return null;
  const duplicate =
    storedReceipt.actorUid === actorUid &&
    storedReceipt.inputHashVersion === 1 &&
    storedReceipt.inputHash === inputHash;
  return {
    schemaVersion: 1,
    family,
    reply: duplicate
      ? duplicateReply(storedReceipt)
      : { status: 'collision', errorCode: 'commandIdCollision' },
  };
}

function projectRoll(stateBefore, plan, commandId) {
  const stateAfter = structuredClone(stateBefore);
  stateAfter.stateVersion = plan.stateVersionAfter;
  stateAfter.turnState = plan.turnStateAfter;
  stateAfter.players = stateAfter.players.map((player) =>
    player.playerId === rollFixture.operation.actorPlayerId
      ? { ...player, position: plan.toPosition }
      : player,
  );
  stateAfter.pendingDecision = plan.pendingDecision;
  stateAfter.lastMutation = {
    type: 'rollMovement',
    commandId,
    actorPlayerId: rollFixture.operation.actorPlayerId,
  };
  return stateAfter;
}

function projectBuy(stateBefore, projection) {
  const stateAfter = structuredClone(stateBefore);
  stateAfter.stateVersion = projection.stateVersionAfter;
  stateAfter.players = projection.players;
  stateAfter.ownership = projection.ownership;
  stateAfter.turnState = projection.turnState;
  stateAfter.lastMutation = projection.lastMutation;
  delete stateAfter.pendingDecision;
  delete stateAfter.activeAuction;
  return stateAfter;
}

test('Ready/Start persists room, public game, private membership and receipt atomically', async () => {
  const roomId = 'room-store-start';
  const gameId = 'game-store-start';
  const commandId = 'cmd-store-start';
  const actorUid = 'uid-1';
  const inputHash = 'start-semantic-fingerprint-v1';
  const store = await adminStore();
  const room = {
    ...structuredClone(readyFixture.initialRoom),
    roomId,
    hostUid: actorUid,
    memberUids: ['uid-1', 'uid-2'],
    readyByUid: { 'uid-1': true, 'uid-2': true },
  };
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'rooms', roomId), room);
  });

  const evaluate = ({ room: current, storedReceipt }) => {
    const replay = replayOrCollision(storedReceipt, actorUid, inputHash, 'room');
    if (replay != null) return replay;
    assert.equal(current.roomVersion, 12);
    const publicState = {
      ...structuredClone(rollFixture.initialPublicState),
      gameId,
      roomId,
    };
    const result = {
      commandId,
      status: 'accepted',
      roomVersionBefore: 12,
      roomVersionAfter: 13,
      gameId,
      stateVersionAfter: 0,
    };
    return {
      schemaVersion: 1,
      family: 'room',
      reply: { status: 'accepted', result },
      roomPatch: {
        status: 'active',
        gameId,
        roomVersion: 13,
        frozenRulesVersion: readyFixture.expectedPlan.rulesVersion,
        frozenPresetConfig: readyFixture.expectedPlan.presetConfig,
      },
      startGame: {
        gameId,
        publicGame: {
          schemaVersion: 1,
          stateVersion: 0,
          memberUids: ['uid-1', 'uid-2'],
          publicState,
        },
        privateGame: {
          ...structuredClone(rollFixture.privateInput),
          memberUidByPlayerId: structuredClone(
            rollFixture.memberUidByPlayerId,
          ),
        },
      },
      receipt: receipt({
        commandId,
        actorUid,
        inputHash,
        before: 12,
        after: 13,
        result,
      }),
    };
  };

  const accepted = await store.transactRoom({ roomId, commandId, evaluate });
  const duplicate = await store.transactRoom({ roomId, commandId, evaluate });
  assert.equal(accepted.status, 'accepted');
  assert.equal(duplicate.status, 'duplicate');

  const durable = await store.readGame({ gameId });
  assert.equal(durable.publicGame.stateVersion, 0);
  assert.equal(durable.publicGame.memberUidByPlayerId, undefined);
  assert.deepEqual(
    durable.privateGame.memberUidByPlayerId,
    rollFixture.memberUidByPlayerId,
  );
  assert.deepEqual(durable.privateGame.seedBytes, rollFixture.privateInput.seedBytes);

  const memberDb = env.authenticatedContext('uid-1').firestore();
  const publicGame = await getDoc(doc(memberDb, 'games', gameId));
  assert.equal(publicGame.data().memberUidByPlayerId, undefined);
  await assertFails(getDoc(doc(memberDb, 'gameSecrets', gameId)));
});

test('Roll, Buy and reconnect converge through one adapter without a second RNG effect', async () => {
  const gameId = 'game-store-flow';
  const store = await adminStore();
  await env.withSecurityRulesDisabled(async (context) => {
    await Promise.all([
      setDoc(doc(context.firestore(), 'games', gameId), {
        schemaVersion: 1,
        stateVersion: 0,
        memberUids: ['uid-1', 'uid-2'],
        publicState: {
          ...structuredClone(rollFixture.initialPublicState),
          gameId,
        },
      }),
      setDoc(doc(context.firestore(), 'gameSecrets', gameId), {
        ...structuredClone(rollFixture.privateInput),
        memberUidByPlayerId: structuredClone(
          rollFixture.memberUidByPlayerId,
        ),
      }),
    ]);
  });

  const rollCommandId = rollFixture.operation.commandId;
  const rollHash = 'roll-semantic-fingerprint-v1';
  const rollEvaluate = ({ publicGame, privateGame, storedReceipt }) => {
    const replay = replayOrCollision(storedReceipt, 'uid-1', rollHash, 'game');
    if (replay != null) return replay;
    assert.equal(privateGame.memberUidByPlayerId.p1, 'uid-1');
    assert.equal(publicGame.stateVersion, 0);
    const plan = structuredClone(rollFixture.expectedPlan);
    const publicState = projectRoll(
      publicGame.publicState,
      plan,
      rollCommandId,
    );
    const result = {
      commandId: rollCommandId,
      status: 'accepted',
      stateVersionBefore: 0,
      stateVersionAfter: 1,
      events: plan.events,
    };
    return {
      schemaVersion: 1,
      family: 'game',
      reply: { status: 'accepted', result },
      publicPatch: { stateVersion: 1, publicState },
      privatePatch: { streamCounters: plan.successorCounters },
      receipt: receipt({
        commandId: rollCommandId,
        actorUid: 'uid-1',
        inputHash: rollHash,
        before: 0,
        after: 1,
        result,
      }),
    };
  };
  const roll = await store.transactGame({
    gameId,
    commandId: rollCommandId,
    evaluate: rollEvaluate,
  });
  const lostAckRetry = await store.transactGame({
    gameId,
    commandId: rollCommandId,
    evaluate: rollEvaluate,
  });
  assert.equal(roll.status, 'accepted');
  assert.equal(lostAckRetry.status, 'duplicate');

  const buy = buyFixture.buy;
  const buyCommandId = buy.command.commandId;
  const buyEvaluate = ({ publicGame, privateGame, storedReceipt }) => {
    const replay = replayOrCollision(
      storedReceipt,
      'uid-1',
      buy.inputHashMarker,
      'game',
    );
    if (replay != null) return replay;
    assert.equal(privateGame.memberUidByPlayerId.p1, 'uid-1');
    assert.equal(publicGame.stateVersion, 1);
    const publicState = projectBuy(
      publicGame.publicState,
      buy.stateProjection,
    );
    return {
      schemaVersion: 1,
      family: 'game',
      reply: { status: 'accepted', result: buy.resultSummary },
      publicPatch: { stateVersion: 2, publicState },
      receipt: receipt({
        commandId: buyCommandId,
        actorUid: 'uid-1',
        inputHash: buy.inputHashMarker,
        before: 1,
        after: 2,
        result: buy.resultSummary,
      }),
    };
  };
  await store.transactGame({
    gameId,
    commandId: buyCommandId,
    evaluate: buyEvaluate,
  });

  const reconnected = await store.readGame({
    gameId,
    commandId: rollCommandId,
  });
  assert.equal(reconnected.publicGame.stateVersion, 2);
  assert.equal(reconnected.publicGame.publicState.players[0].cash, 1893);
  assert.equal(
    reconnected.publicGame.publicState.ownership.byPropertyId['street-07'],
    'p1',
  );
  assert.equal(reconnected.privateGame.streamCounters.dice, 2);
  assert.equal(reconnected.storedReceipt.commandId, rollCommandId);
});

test('adapter rejects private authority fields before a public write', async () => {
  const gameId = 'game-store-public-guard';
  const commandId = 'cmd-private-leak';
  const store = await adminStore();
  await env.withSecurityRulesDisabled(async (context) => {
    await Promise.all([
      setDoc(doc(context.firestore(), 'games', gameId), {
        stateVersion: 0,
        memberUids: ['uid-1'],
        publicState: { gameId, stateVersion: 0 },
      }),
      setDoc(doc(context.firestore(), 'gameSecrets', gameId), {
        memberUidByPlayerId: { p1: 'uid-1' },
      }),
    ]);
  });

  await assert.rejects(
    store.transactGame({
      gameId,
      commandId,
      evaluate: () => ({
        schemaVersion: 1,
        family: 'game',
        reply: { status: 'accepted' },
        publicPatch: { memberUidByPlayerId: { p1: 'uid-1' } },
        receipt: receipt({
          commandId,
          actorUid: 'uid-1',
          inputHash: 'private-leak-v1',
          before: 0,
          after: 1,
          result: { status: 'accepted' },
        }),
      }),
    }),
    /privateFieldInPublicDocument/,
  );
  const durable = await store.readGame({ gameId });
  assert.equal(durable.publicGame.memberUidByPlayerId, undefined);
});
