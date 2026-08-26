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
  };
  return { documents, api, db: {} };
}

function receipt(commandId, result = { stateVersionAfter: 1 }) {
  return {
    commandId,
    actorUid: 'uid-1',
    inputHashVersion: 1,
    inputHash: 'semantic-fingerprint-v1',
    resultSummary: result,
  };
}

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
      return { reply: duplicateReply(storedReceipt) };
    }
    return {
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
