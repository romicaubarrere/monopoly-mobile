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
      '../../../backend/command_service/test/fixtures/ready_start_plans.json',
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

function semanticHash({ type, roomId, expectedRoomVersion, payload }) {
  const material = canonicalize({
    v: 1,
    family: 'room',
    type,
    target: roomId,
    expectedVersion: expectedRoomVersion,
    payload,
  });
  return createHash('sha256').update(JSON.stringify(material)).digest('hex');
}

function commitment(seedBytes) {
  return createHash('sha256')
    .update(Buffer.from('monopoly-rng-v1-commit', 'utf8'))
    .update(Buffer.from([0]))
    .update(Buffer.from(seedBytes))
    .digest('hex');
}

async function seedRoom(suffix, room = fixture.initialRoom) {
  const roomId = `${room.roomId}-${suffix}`;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'rooms', roomId), {...structuredClone(room), roomId}),
      setDoc(doc(db, 'readyStartRetryBarriers', roomId), {revision: 0}),
    ]);
  });
  return roomId;
}

async function applySetReady({
  roomId,
  commandId,
  actorUid,
  expectedRoomVersion,
  ready,
}) {
  const inputHash = semanticHash({
    type: 'SetReady',
    roomId,
    expectedRoomVersion,
    payload: {ready},
  });
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const roomRef = doc(db, 'rooms', roomId);
    const commandRef = doc(db, 'roomCommands', commandId);
    result = await runTransaction(db, async (tx) => {
      const prior = await tx.get(commandRef);
      if (prior.exists()) {
        const record = prior.data();
        const duplicate =
          record.actorUid === actorUid && record.inputHash === inputHash;
        return duplicate
          ? {disposition: 'duplicate', ...record.resultSummary}
          : {disposition: 'commandIdCollision'};
      }
      const snapshot = await tx.get(roomRef);
      if (!snapshot.exists()) return {disposition: 'roomUnavailable'};
      const room = snapshot.data();
      if (!room.memberUids.includes(actorUid)) {
        return {disposition: 'memberNotInRoom'};
      }
      if (room.status !== 'open' || room.roomVersion !== expectedRoomVersion) {
        return {disposition: 'staleRoomVersion'};
      }
      const roomVersion = expectedRoomVersion + 1;
      const readyByUid = {...room.readyByUid, [actorUid]: ready};
      const resultSummary = {roomId, roomVersion, readyByUid};
      tx.set(roomRef, {roomVersion, readyByUid}, {merge: true});
      tx.set(commandRef, {
        commandId,
        actorUid,
        commandType: 'SetReady',
        inputHashVersion: 1,
        inputHash,
        status: 'accepted',
        roomId,
        roomVersionBefore: expectedRoomVersion,
        roomVersionAfter: roomVersion,
        resultSummary,
      });
      return {disposition: 'accepted', ...resultSummary};
    });
  });
  return result;
}

async function applyStartGame({
  roomId,
  commandId = `${fixture.operation.commandId}-${roomId}`,
  actorUid = fixture.operation.actorUid,
  expectedRoomVersion = fixture.operation.expectedRoomVersion,
  forceCallbackRetry = false,
}) {
  const inputHash = semanticHash({
    type: 'StartGame',
    roomId,
    expectedRoomVersion,
    payload: {},
  });
  const plan = fixture.expectedPlan;
  const gameId = `${plan.gameId}-${roomId}`;
  let callbackAttempts = 0;
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const roomRef = doc(db, 'rooms', roomId);
    const commandRef = doc(db, 'roomCommands', commandId);
    const gameRef = doc(db, 'games', gameId);
    const secretRef = doc(db, 'gameSecrets', gameId);
    const barrierRef = doc(db, 'readyStartRetryBarriers', roomId);

    result = await runTransaction(db, async (tx) => {
      callbackAttempts += 1;
      const prior = await tx.get(commandRef);
      if (prior.exists()) {
        const record = prior.data();
        const duplicate =
          record.actorUid === actorUid && record.inputHash === inputHash;
        return duplicate
          ? {disposition: 'duplicate', ...record.resultSummary}
          : {disposition: 'commandIdCollision'};
      }
      const [roomSnapshot, barrierSnapshot] = await Promise.all([
        tx.get(roomRef),
        tx.get(barrierRef),
      ]);
      if (!roomSnapshot.exists()) return {disposition: 'roomUnavailable'};
      const room = roomSnapshot.data();
      if (room.hostUid !== actorUid) return {disposition: 'notRoomHost'};
      if (
        room.status !== 'open' ||
        room.roomVersion !== expectedRoomVersion
      ) {
        return {disposition: 'staleRoomVersion'};
      }
      if (
        room.memberUids.some((uid) => room.readyByUid?.[uid] !== true)
      ) {
        return {disposition: 'notAllPlayersReady'};
      }
      if (forceCallbackRetry && callbackAttempts === 1) {
        await setDoc(barrierRef, {
          revision: barrierSnapshot.data().revision + 1,
        });
      }

      const rngCommitment = commitment(fixture.privateInput.seedBytes);
      const publicState = {
        schemaVersion: 1,
        stateVersion: plan.stateVersion,
        rulesVersion: plan.rulesVersion,
        rngVersion: plan.rngVersion,
        rngCommitment,
        gameId,
        roomId,
        status: 'active',
        memberUids: room.memberUids,
        presetConfig: plan.presetConfig,
        seatOrder: plan.seatOrder,
        starterAllocation: plan.starterAllocation,
      };
      const privateState = {
        schemaVersion: 1,
        rngVersion: plan.rngVersion,
        seedBytes: fixture.privateInput.seedBytes,
        streamCounters: plan.streamCounters,
        privateDeckState: plan.privateDeckState,
      };
      const roomVersion = expectedRoomVersion + 1;
      const resultSummary = {
        gameId,
        stateVersion: plan.stateVersion,
        rulesVersion: plan.rulesVersion,
        presetConfig: plan.presetConfig,
        seatOrder: plan.seatOrder,
        starterAllocation: plan.starterAllocation,
      };
      tx.set(gameRef, publicState);
      tx.set(secretRef, privateState);
      tx.set(
        roomRef,
        {
          status: 'active',
          gameId,
          roomVersion,
          frozenRulesVersion: plan.rulesVersion,
          frozenPresetConfig: plan.presetConfig,
        },
        {merge: true},
      );
      tx.set(commandRef, {
        commandId,
        actorUid,
        commandType: 'StartGame',
        inputHashVersion: fixture.operation.inputHashVersion,
        inputHash,
        status: 'accepted',
        roomId,
        gameId,
        roomVersionBefore: expectedRoomVersion,
        roomVersionAfter: roomVersion,
        resultSummary,
      });
      return {disposition: 'accepted', ...resultSummary};
    });
  });
  return {result, callbackAttempts, commandId, gameId};
}

test('VP0 SetReady is versioned, idempotent, and collision-safe', async () => {
  const room = structuredClone(fixture.initialRoom);
  room.readyByUid['uid-b'] = false;
  const roomId = await seedRoom('set-ready', room);
  const first = await applySetReady({
    roomId,
    commandId: 'cmd-ready-vp0',
    actorUid: 'uid-b',
    expectedRoomVersion: 12,
    ready: true,
  });
  const duplicate = await applySetReady({
    roomId,
    commandId: 'cmd-ready-vp0',
    actorUid: 'uid-b',
    expectedRoomVersion: 12,
    ready: true,
  });
  const collision = await applySetReady({
    roomId,
    commandId: 'cmd-ready-vp0',
    actorUid: 'uid-b',
    expectedRoomVersion: 12,
    ready: false,
  });

  assert.equal(first.disposition, 'accepted');
  assert.equal(first.roomVersion, 13);
  assert.equal(duplicate.disposition, 'duplicate');
  assert.deepEqual(duplicate.readyByUid, first.readyByUid);
  assert.deepEqual(collision, {disposition: 'commandIdCollision'});
});

test('VP0 StartGame commits the shared Dart plan atomically under callback retry', async () => {
  const roomId = await seedRoom('callback-retry');
  const {result, callbackAttempts, commandId, gameId} = await applyStartGame({
    roomId,
    forceCallbackRetry: true,
  });

  assert.ok(callbackAttempts >= 2);
  assert.equal(result.disposition, 'accepted');
  assert.deepEqual(result.seatOrder, fixture.expectedPlan.seatOrder);
  assert.deepEqual(
    result.starterAllocation,
    fixture.expectedPlan.starterAllocation,
  );

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [room, game, secret, command] = await Promise.all([
      getDoc(doc(db, 'rooms', roomId)),
      getDoc(doc(db, 'games', gameId)),
      getDoc(doc(db, 'gameSecrets', gameId)),
      getDoc(doc(db, 'roomCommands', commandId)),
    ]);
    assert.equal(room.data().status, 'active');
    assert.equal(room.data().roomVersion, 13);
    assert.equal(game.data().stateVersion, 0);
    assert.deepEqual(game.data().seatOrder, fixture.expectedPlan.seatOrder);
    assert.deepEqual(
      game.data().starterAllocation,
      fixture.expectedPlan.starterAllocation,
    );
    assert.deepEqual(
      secret.data().streamCounters,
      fixture.expectedPlan.streamCounters,
    );
    assert.equal(game.data().seedBytes, undefined);
    assert.equal(game.data().privateDeckState, undefined);
    assert.equal(command.data().gameId, gameId);
  });
});

test('VP0 lost ACK and two clients converge without a second RNG effect', async () => {
  const roomId = await seedRoom('lost-ack');
  const accepted = await applyStartGame({roomId});
  const duplicate = await applyStartGame({roomId});

  assert.equal(accepted.result.disposition, 'accepted');
  assert.equal(duplicate.result.disposition, 'duplicate');
  assert.deepEqual(duplicate.result, {
    disposition: 'duplicate',
    gameId: accepted.gameId,
    stateVersion: fixture.expectedPlan.stateVersion,
    rulesVersion: fixture.expectedPlan.rulesVersion,
    presetConfig: fixture.expectedPlan.presetConfig,
    seatOrder: fixture.expectedPlan.seatOrder,
    starterAllocation: fixture.expectedPlan.starterAllocation,
  });

  await env.withSecurityRulesDisabled(async (firstContext) => {
    const first = await getDoc(
      doc(firstContext.firestore(), 'games', accepted.gameId),
    );
    await env.withSecurityRulesDisabled(async (secondContext) => {
      const second = await getDoc(
        doc(secondContext.firestore(), 'games', accepted.gameId),
      );
      assert.deepEqual(first.data(), second.data());
      assert.equal(first.data().gameId, accepted.gameId);
      assert.equal(first.data().stateVersion, 0);
      assert.deepEqual(first.data().seatOrder, fixture.expectedPlan.seatOrder);
      assert.deepEqual(first.data().presetConfig, fixture.expectedPlan.presetConfig);
    });
  });
});

test('VP0 StartGame guards reject before public/private persistence', async () => {
  const notReadyRoom = structuredClone(fixture.initialRoom);
  notReadyRoom.readyByUid['uid-b'] = false;
  const roomId = await seedRoom('not-ready', notReadyRoom);
  const rejected = await applyStartGame({roomId});

  assert.equal(rejected.result.disposition, 'notAllPlayersReady');
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const [game, secret] = await Promise.all([
      getDoc(doc(db, 'games', rejected.gameId)),
      getDoc(doc(db, 'gameSecrets', rejected.gameId)),
    ]);
    assert.equal(game.exists(), false);
    assert.equal(secret.exists(), false);
  });
});
