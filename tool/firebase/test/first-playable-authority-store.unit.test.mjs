import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  FirstPlayableAuthorityFirestoreStore,
  duplicateReply,
} from '../src/first-playable-authority-store.mjs';

function fakeFirestore(initial = {}) {
  const documents = new Map(Object.entries(structuredClone(initial)));
  const snapshot = (path) => ({
    exists: () => documents.has(path),
    data: () => structuredClone(documents.get(path)),
  });
  const merge = (before, after) => ({ ...(before ?? {}), ...after });
  const api = {
    doc: (_db, ...segments) => segments.join('/'),
    getDoc: async (path) => snapshot(path),
    runTransaction: async (_db, callback) => callback({
      get: async (path) => snapshot(path),
      set: (path, value, options) => {
        documents.set(
          path,
          structuredClone(
            options?.merge ? merge(documents.get(path), value) : value,
          ),
        );
      },
    }),
    timestampFromMillis: (value) => ({ _millis: value }),
  };
  return { documents, api, db: {} };
}

function roomEntryDecision({ kind, commandId, codeHash, roomId, members }) {
  const memberUids = members.map((member) => member.uid);
  const memberUidByPlayerId = Object.fromEntries(
    members.map((member) => [member.playerId, member.uid]),
  );
  const roomVersion = members.length;
  const result = {
    commandId,
    status: 'accepted',
    roomId,
    roomVersion,
    actorPlayerId: members.at(-1).playerId,
  };
  return {
    schemaVersion: 1,
    family: 'room',
    reply: { status: 'accepted', result },
    roomEntry: {
      kind,
      codeHash,
      roomId,
      ...(kind === 'create'
        ? { updatedAtMs: 1_000, expiresAtMs: 61_000 }
        : {}),
      publicRoom: {
        schemaVersion: 1,
        roomId,
        roomVersion,
        status: 'open',
        hostUid: memberUids[0],
        memberUids,
        readyByUid: Object.fromEntries(memberUids.map((uid) => [uid, false])),
        presetId: 'express',
      },
      privateRoom: { schemaVersion: 1, memberUidByPlayerId },
    },
    receipt: receipt(commandId, result),
  };
}

test('CreateRoom persists hashed locator and private membership exactly once', async () => {
  const fake = fakeFirestore();
  const store = new FirstPlayableAuthorityFirestoreStore(fake.db, fake.api);
  const input = {
    kind: 'create',
    codeHash: 'sha256-code-a',
    roomId: 'room-create-1',
    commandId: 'cmd-create-1',
  };
  const evaluate = ({ storedReceipt }) => storedReceipt == null
    ? roomEntryDecision({
        ...input,
        members: [{ uid: 'uid-1', playerId: 'player-1' }],
      })
    : {
        schemaVersion: 1,
        family: 'room',
        reply: duplicateReply(storedReceipt),
      };

  const accepted = await store.transactRoomEntry({ ...input, evaluate });
  const duplicate = await store.transactRoomEntry({ ...input, evaluate });

  assert.equal(accepted.status, 'accepted');
  assert.equal(duplicate.status, 'duplicate');
  assert.equal(
    fake.documents.get('roomCodes/sha256-code-a').expiresAt._millis,
    61_000,
  );
  assert.equal(fake.documents.get('rooms/room-create-1').roomCode, undefined);
  assert.deepEqual(
    fake.documents.get('roomSecrets/room-create-1').memberUidByPlayerId,
    { 'player-1': 'uid-1' },
  );
  assert.equal(
    fake.documents.get('roomCommands/cmd-create-1').commandId,
    'cmd-create-1',
  );
});

test('JoinRoom updates public/private membership atomically and duplicate-safe', async () => {
  const fake = fakeFirestore({
    'roomCodes/sha256-code-b': {
      codeHash: 'sha256-code-b',
      roomId: 'room-join-1',
      expiresAt: { value: 61_000 },
    },
    'rooms/room-join-1': {
      schemaVersion: 1,
      roomId: 'room-join-1',
      roomVersion: 1,
      status: 'open',
      hostUid: 'uid-1',
      memberUids: ['uid-1'],
      readyByUid: { 'uid-1': false },
      presetId: 'express',
    },
    'roomSecrets/room-join-1': {
      schemaVersion: 1,
      memberUidByPlayerId: { 'player-1': 'uid-1' },
    },
  });
  const store = new FirstPlayableAuthorityFirestoreStore(fake.db, fake.api);
  const input = {
    kind: 'join',
    codeHash: 'sha256-code-b',
    commandId: 'cmd-join-1',
  };
  const evaluate = ({ storedReceipt }) => storedReceipt == null
    ? roomEntryDecision({
        ...input,
        roomId: 'room-join-1',
        members: [
          { uid: 'uid-1', playerId: 'player-1' },
          { uid: 'uid-2', playerId: 'player-2' },
        ],
      })
    : {
        schemaVersion: 1,
        family: 'room',
        reply: duplicateReply(storedReceipt),
      };

  await store.transactRoomEntry({ ...input, evaluate });
  await store.transactRoomEntry({ ...input, evaluate });

  assert.deepEqual(fake.documents.get('rooms/room-join-1').memberUids, [
    'uid-1',
    'uid-2',
  ]);
  assert.deepEqual(
    fake.documents.get('roomSecrets/room-join-1').memberUidByPlayerId,
    { 'player-1': 'uid-1', 'player-2': 'uid-2' },
  );
});

test('room entry rejects plaintext code or inconsistent private membership', async () => {
  const fake = fakeFirestore();
  const store = new FirstPlayableAuthorityFirestoreStore(fake.db, fake.api);
  const input = {
    kind: 'create',
    codeHash: 'sha256-code-c',
    roomId: 'room-create-leak',
    commandId: 'cmd-create-leak',
  };
  const base = roomEntryDecision({
    ...input,
    members: [{ uid: 'uid-1', playerId: 'player-1' }],
  });

  await assert.rejects(
    store.transactRoomEntry({
      ...input,
      evaluate: () => ({
        ...base,
        roomEntry: {
          ...base.roomEntry,
          publicRoom: { ...base.roomEntry.publicRoom, roomCode: 'ABC123' },
        },
      }),
    }),
    /plaintextRoomCodeInPersistence/,
  );
  await assert.rejects(
    store.transactRoomEntry({
      ...input,
      evaluate: () => ({
        ...base,
        roomEntry: {
          ...base.roomEntry,
          privateRoom: {
            schemaVersion: 1,
            memberUidByPlayerId: { 'player-x': 'uid-x' },
          },
        },
      }),
    }),
    /invalidRoomEntryDecision/,
  );
  await assert.rejects(
    store.transactRoomEntry({
      ...input,
      evaluate: () => ({
        ...base,
        receipt: {
          ...base.receipt,
          resultSummary: {
            ...base.receipt.resultSummary,
            roomCode: 'ABC123',
          },
        },
      }),
    }),
    /plaintextRoomCodeInPersistence/,
  );
  assert.equal(fake.documents.size, 0);
});

function receipt(commandId, result = { stateVersionAfter: 1 }) {
  return {
    commandId,
    actorUid: 'uid-1',
    inputHashVersion: 1,
    inputHash: 'semantic-fingerprint-v1',
    resultSummary: result,
  };
}

test('room entry semantic collision performs zero membership writes', async () => {
  const stored = receipt('cmd-entry-collision', { roomId: 'room-existing' });
  const fake = fakeFirestore({
    'roomCommands/cmd-entry-collision': stored,
  });
  const store = new FirstPlayableAuthorityFirestoreStore(fake.db, fake.api);

  const reply = await store.transactRoomEntry({
    kind: 'create',
    codeHash: 'sha256-code-collision',
    roomId: 'room-candidate',
    commandId: 'cmd-entry-collision',
    evaluate: ({ storedReceipt }) => {
      assert.deepEqual(storedReceipt, stored);
      return {
        schemaVersion: 1,
        family: 'room',
        reply: { status: 'collision', errorCode: 'commandIdCollision' },
      };
    },
  });

  assert.equal(reply.status, 'collision');
  assert.deepEqual(
    [...fake.documents.entries()],
    [['roomCommands/cmd-entry-collision', stored]],
  );
});

test('accepted game decision persists public/private state and receipt once', async () => {
  const fake = fakeFirestore({
    'games/game-1': { stateVersion: 0, publicState: { stateVersion: 0 } },
    'gameSecrets/game-1': {
      memberUidByPlayerId: { p1: 'uid-1' },
      streamCounters: { dice: 0 },
    },
  });
  const store = new FirstPlayableAuthorityFirestoreStore(
    fake.db,
    fake.api,
  );
  const evaluate = ({ storedReceipt }) => {
    if (storedReceipt != null) {
      return {
        schemaVersion: 1,
        family: 'game',
        reply: duplicateReply(storedReceipt),
      };
    }
    return {
      schemaVersion: 1,
      family: 'game',
      reply: { status: 'accepted', stateVersion: 1 },
      publicPatch: {
        stateVersion: 1,
        publicState: { stateVersion: 1, lastMutation: 'rollMovement' },
      },
      privatePatch: { streamCounters: { dice: 2 } },
      receipt: receipt('cmd-1'),
    };
  };

  const accepted = await store.transactGame({
    gameId: 'game-1',
    commandId: 'cmd-1',
    evaluate,
  });
  const duplicate = await store.transactGame({
    gameId: 'game-1',
    commandId: 'cmd-1',
    evaluate,
  });

  assert.equal(accepted.status, 'accepted');
  assert.equal(duplicate.status, 'duplicate');
  assert.equal(fake.documents.get('games/game-1').stateVersion, 1);
  assert.equal(
    fake.documents.get('gameSecrets/game-1').streamCounters.dice,
    2,
  );
  assert.equal(
    fake.documents.get('games/game-1/commands/cmd-1').commandId,
    'cmd-1',
  );
});

test('public/private guard fails closed before persisting a leaking decision', async () => {
  const fake = fakeFirestore({
    'games/game-1': { stateVersion: 0 },
    'gameSecrets/game-1': { memberUidByPlayerId: { p1: 'uid-1' } },
  });
  const store = new FirstPlayableAuthorityFirestoreStore(
    fake.db,
    fake.api,
  );

  await assert.rejects(
    store.transactGame({
      gameId: 'game-1',
      commandId: 'cmd-leak',
      evaluate: () => ({
        schemaVersion: 1,
        family: 'game',
        reply: { status: 'accepted' },
        publicPatch: { seedBytes: [1, 2, 3] },
        receipt: receipt('cmd-leak'),
      }),
    }),
    /privateFieldInPublicDocument/,
  );
  assert.equal(fake.documents.get('games/game-1').stateVersion, 0);
  assert.equal(
    fake.documents.has('games/game-1/commands/cmd-leak'),
    false,
  );
});

test('StartGame fails closed when the Dart decision omits private membership', async () => {
  const fake = fakeFirestore({
    'rooms/room-1': { roomVersion: 1, memberUids: ['uid-1'] },
  });
  const store = new FirstPlayableAuthorityFirestoreStore(fake.db, fake.api);

  await assert.rejects(
    store.transactRoom({
      roomId: 'room-1',
      commandId: 'cmd-start',
      evaluate: () => ({
        schemaVersion: 1,
        family: 'room',
        reply: { status: 'accepted' },
        roomPatch: { status: 'active', gameId: 'game-1', roomVersion: 2 },
        startGame: {
          gameId: 'game-1',
          publicGame: {
            stateVersion: 0,
            memberUids: ['uid-1'],
            publicState: { stateVersion: 0 },
          },
          privateGame: { seedBytes: Array(32).fill(7) },
        },
        receipt: receipt('cmd-start'),
      }),
    }),
    /missingPrivateMemberMapping/,
  );
  assert.equal(fake.documents.has('games/game-1'), false);
  assert.equal(fake.documents.has('gameSecrets/game-1'), false);
  assert.equal(fake.documents.has('roomCommands/cmd-start'), false);
});
