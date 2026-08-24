import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { after, before, test } from 'node:test';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

function testOnlyCommitment(seedBase64) {
  return createHash('sha256').update(seedBase64, 'utf8').digest('hex');
}

function candidateStart({ gameId, seedBase64, starterAllocation }) {
  return {
    gameId,
    seedBase64,
    rngCommitment: testOnlyCommitment(seedBase64),
    starterAllocation,
  };
}

async function applyStartGame({
  roomId,
  commandId,
  actorUid,
  expectedRoomVersion,
  requestReceivedAt,
  rulesVersion,
  resolvedPresetConfig,
  candidate,
}) {
  let result;

  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const roomRef = doc(db, 'rooms', roomId);
    const commandRef = doc(db, 'roomCommands', commandId);
    const gameRef = doc(db, 'games', candidate.gameId);
    const secretRef = doc(db, 'gameSecrets', candidate.gameId);

    result = await runTransaction(db, async (tx) => {
      const priorCommand = await tx.get(commandRef);
      if (priorCommand.exists()) {
        const prior = priorCommand.data();
        return {
          disposition: 'duplicate',
          gameId: prior.gameId,
          starterAllocation: prior.resultSummary.starterAllocation,
        };
      }

      const roomSnap = await tx.get(roomRef);
      if (!roomSnap.exists()) {
        return { disposition: 'roomUnavailable' };
      }

      const room = roomSnap.data();
      if (
        room.status !== 'open' ||
        room.roomVersion !== expectedRoomVersion ||
        room.hostUid !== actorUid
      ) {
        return { disposition: 'staleOrUnauthorized' };
      }

      const nextRoomVersion = expectedRoomVersion + 1;
      const publicGame = {
        schemaVersion: 1,
        stateVersion: 0,
        rulesVersion,
        rngVersion: 1,
        rngCommitment: candidate.rngCommitment,
        status: 'active',
        roomId,
        memberUids: room.memberUids,
        state: {
          resolvedPresetConfig,
          starterAllocation: candidate.starterAllocation,
        },
      };
      const privateRng = {
        schemaVersion: 1,
        rngVersion: 1,
        seedBase64: candidate.seedBase64,
        streamCounters: {},
      };

      tx.set(gameRef, publicGame);
      tx.set(secretRef, privateRng);
      tx.set(
        roomRef,
        {
          status: 'active',
          gameId: candidate.gameId,
          roomVersion: nextRoomVersion,
          frozenRulesVersion: rulesVersion,
          frozenPresetConfig: resolvedPresetConfig,
        },
        { merge: true },
      );
      tx.set(commandRef, {
        commandId,
        actorUid,
        commandType: 'StartGame',
        status: 'accepted',
        roomId,
        gameId: candidate.gameId,
        roomVersionBefore: expectedRoomVersion,
        roomVersionAfter: nextRoomVersion,
        requestReceivedAt,
        processedAt: requestReceivedAt,
        resultSummary: {
          gameId: candidate.gameId,
          starterAllocation: candidate.starterAllocation,
        },
      });

      return {
        disposition: 'accepted',
        gameId: candidate.gameId,
        starterAllocation: candidate.starterAllocation,
      };
    });
  });

  return result;
}

async function readStartGameState({ roomId, commandId, gameIds }) {
  let snapshot;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const room = await getDoc(doc(db, 'rooms', roomId));
    const command = await getDoc(doc(db, 'roomCommands', commandId));
    const games = await Promise.all(
      gameIds.map((gameId) => getDoc(doc(db, 'games', gameId))),
    );
    const secrets = await Promise.all(
      gameIds.map((gameId) => getDoc(doc(db, 'gameSecrets', gameId))),
    );
    snapshot = { room, command, games, secrets };
  });
  return snapshot;
}

test('TV-18 duplicate StartGame after lost ACK returns same game and allocation', async () => {
  const roomId = 'room-start-duplicate';
  const commandId = 'cmd-start-duplicate';
  const actorUid = 'host-a';
  const rulesVersion = 'rules-synthetic-v1';
  const resolvedPresetConfig = {
    presetId: 'synthetic-express',
    roundCap: 8,
    starterMode: 'synthetic-fixture',
  };
  const firstCandidate = candidateStart({
    gameId: 'game-start-winner',
    seedBase64: 'VEVTVF9PTkxZX1NFRURfQQ==',
    starterAllocation: ['synthetic-prop-a', 'synthetic-prop-b'],
  });
  const retryCandidate = candidateStart({
    gameId: 'game-start-must-not-exist',
    seedBase64: 'VEVTVF9PTkxZX1NFRURfQg==',
    starterAllocation: ['synthetic-prop-x', 'synthetic-prop-y'],
  });

  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'rooms', roomId), {
      roomId,
      roomVersion: 4,
      status: 'open',
      hostUid: actorUid,
      memberUids: [actorUid, 'member-b'],
    });
  });

  const accepted = await applyStartGame({
    roomId,
    commandId,
    actorUid,
    expectedRoomVersion: 4,
    requestReceivedAt: '2026-08-24T04:55:00.000Z',
    rulesVersion,
    resolvedPresetConfig,
    candidate: firstCandidate,
  });
  assert.deepEqual(accepted, {
    disposition: 'accepted',
    gameId: firstCandidate.gameId,
    starterAllocation: firstCandidate.starterAllocation,
  });

  // Simulates commit-before-ACK: the caller retries the same logical command.
  // Even if a new candidate were accidentally prepared outside the transaction,
  // the persisted command result must win and prevent a second game/RNG pair.
  const duplicate = await applyStartGame({
    roomId,
    commandId,
    actorUid,
    expectedRoomVersion: 4,
    requestReceivedAt: '2026-08-24T04:55:00.000Z',
    rulesVersion,
    resolvedPresetConfig,
    candidate: retryCandidate,
  });
  assert.deepEqual(duplicate, {
    disposition: 'duplicate',
    gameId: firstCandidate.gameId,
    starterAllocation: firstCandidate.starterAllocation,
  });

  const persisted = await readStartGameState({
    roomId,
    commandId,
    gameIds: [firstCandidate.gameId, retryCandidate.gameId],
  });
  assert.equal(persisted.room.data().status, 'active');
  assert.equal(persisted.room.data().gameId, firstCandidate.gameId);
  assert.equal(persisted.room.data().roomVersion, 5);
  assert.deepEqual(
    persisted.room.data().frozenPresetConfig,
    resolvedPresetConfig,
  );
  assert.equal(persisted.room.data().frozenRulesVersion, rulesVersion);

  assert.equal(persisted.games[0].exists(), true);
  assert.equal(persisted.secrets[0].exists(), true);
  assert.equal(persisted.games[1].exists(), false);
  assert.equal(persisted.secrets[1].exists(), false);
  assert.equal(
    persisted.games[0].data().rngCommitment,
    firstCandidate.rngCommitment,
  );
  assert.equal(
    persisted.secrets[0].data().seedBase64,
    firstCandidate.seedBase64,
  );
  assert.equal(
    persisted.games[0].data().seedBase64,
    undefined,
    'private seed must not leak into public game state',
  );
});

test('TV-19 competing StartGame on same room leaves no orphan losing game pair', async () => {
  const roomId = 'room-start-race';
  const actorUid = 'host-race';
  const rulesVersion = 'rules-synthetic-v1';
  const resolvedPresetConfig = {
    presetId: 'synthetic-rapida',
    roundCap: 12,
    starterMode: 'synthetic-fixture',
  };
  const candidates = [
    candidateStart({
      gameId: 'game-race-a',
      seedBase64: 'VEVTVF9PTkxZX1JBQ0VfQQ==',
      starterAllocation: ['synthetic-a1', 'synthetic-a2'],
    }),
    candidateStart({
      gameId: 'game-race-b',
      seedBase64: 'VEVTVF9PTkxZX1JBQ0VfQg==',
      starterAllocation: ['synthetic-b1', 'synthetic-b2'],
    }),
  ];

  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'rooms', roomId), {
      roomId,
      roomVersion: 9,
      status: 'open',
      hostUid: actorUid,
      memberUids: [actorUid, 'member-race'],
    });
  });

  const results = await Promise.all(
    candidates.map((candidate, index) =>
      applyStartGame({
        roomId,
        commandId: `cmd-start-race-${index}`,
        actorUid,
        expectedRoomVersion: 9,
        requestReceivedAt: `2026-08-24T04:56:0${index}.000Z`,
        rulesVersion,
        resolvedPresetConfig,
        candidate,
      }),
    ),
  );

  assert.equal(
    results.filter((result) => result.disposition === 'accepted').length,
    1,
  );
  assert.equal(
    results.filter((result) => result.disposition === 'staleOrUnauthorized')
      .length,
    1,
  );

  let persisted;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const room = await getDoc(doc(db, 'rooms', roomId));
    const games = await Promise.all(
      candidates.map((candidate) => getDoc(doc(db, 'games', candidate.gameId))),
    );
    const secrets = await Promise.all(
      candidates.map((candidate) =>
        getDoc(doc(db, 'gameSecrets', candidate.gameId)),
      ),
    );
    persisted = { room, games, secrets };
  });

  const winnerGameId = persisted.room.data().gameId;
  assert.equal(persisted.room.data().status, 'active');
  assert.equal(persisted.room.data().roomVersion, 10);
  assert.equal(
    persisted.games.filter((snap) => snap.exists()).length,
    1,
  );
  assert.equal(
    persisted.secrets.filter((snap) => snap.exists()).length,
    1,
  );
  assert.equal(
    persisted.games.find((snap) => snap.exists()).id,
    winnerGameId,
  );
  assert.equal(
    persisted.secrets.find((snap) => snap.exists()).id,
    winnerGameId,
  );
});
