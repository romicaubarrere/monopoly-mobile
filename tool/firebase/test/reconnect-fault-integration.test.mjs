import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';

import {
  assertFails,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, runTransaction, setDoc } from 'firebase/firestore';

const projectId = 'demo-board-game-local';
const deadlineAt = '2026-08-25T04:00:12.000Z';
const inputHash = 'reconnect-fingerprint-v1';

let env;

before(async () => {
  env = await initializeTestEnvironment({ projectId });
});

after(async () => {
  await env?.cleanup();
});

function publicState(gameId) {
  return {
    schemaVersion: 1,
    stateVersion: 1,
    rulesVersion: 'synthetic-rules-vp0',
    rngVersion: 'hmac_sha256_counter_v1',
    rngCommitment: '0'.repeat(64),
    gameId,
    roomId: `room-${gameId}`,
    status: 'active',
    players: [{ playerId: 'p1', cash: 2000, connectivityStatus: 'online' }],
    pendingDecision: {
      decisionId: 'decision-property-1',
      kind: 'propertyOffer',
      stateVersionCreated: 1,
      deadlineAt,
    },
    lastMutation: { type: 'rollMovement', commandId: 'cmd-roll-1' },
  };
}

async function seed(gameId) {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await Promise.all([
      setDoc(doc(db, 'games', gameId), {
        memberUids: ['uid-1'],
        memberUidByPlayerId: { p1: 'uid-1' },
        stateVersion: 1,
        mutationCount: 0,
        publicState: publicState(gameId),
      }),
      setDoc(doc(db, 'gameSecrets', gameId), {
        seedSentinel: 'private-seed-never-public',
        streamCounters: { dice: 7 },
        futureDeck: ['private-card'],
      }),
    ]);
  });
}

async function applyCommand({ gameId, commandId, hash = inputHash }) {
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const operationRef = doc(db, 'games', gameId, 'commands', commandId);
    result = await runTransaction(db, async (tx) => {
      const [gameSnapshot, operationSnapshot] = await Promise.all([
        tx.get(gameRef),
        tx.get(operationRef),
      ]);
      const game = gameSnapshot.data();
      if (operationSnapshot.exists()) {
        const operation = operationSnapshot.data();
        if (operation.inputHash !== hash) {
          return { disposition: 'collision', stateVersion: game.stateVersion };
        }
        return {
          disposition: 'duplicate',
          stateVersion: operation.stateVersionAfter,
          result: operation.publicResult,
        };
      }

      const stateVersionAfter = game.stateVersion + 1;
      const publicStateAfter = structuredClone(game.publicState);
      publicStateAfter.stateVersion = stateVersionAfter;
      publicStateAfter.lastMutation = { type: 'syntheticFaultCommand', commandId };
      const result = {
        commandId,
        status: 'accepted',
        stateVersionBefore: game.stateVersion,
        stateVersionAfter,
      };
      tx.update(gameRef, {
        stateVersion: stateVersionAfter,
        mutationCount: game.mutationCount + 1,
        publicState: publicStateAfter,
      });
      tx.set(operationRef, {
        schemaVersion: 1,
        inputHashVersion: 1,
        inputHash: hash,
        stateVersionBefore: game.stateVersion,
        stateVersionAfter,
        publicResult: result,
      });
      return { disposition: 'accepted', stateVersion: stateVersionAfter, result };
    });
  });
  return result;
}

async function reconnect({
  gameId,
  actorUid = 'uid-1',
  clientStateVersion,
  uncertainCommand,
}) {
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameSnapshot = await getDoc(doc(db, 'games', gameId));
    const game = gameSnapshot.data();
    if (game.memberUidByPlayerId.p1 !== actorUid) {
      result = { disposition: 'notMember' };
      return;
    }
    if (clientStateVersion > game.stateVersion) {
      result = { disposition: 'clientVersionAhead' };
      return;
    }

    let commandResolution;
    if (uncertainCommand) {
      const operation = await getDoc(
        doc(db, 'games', gameId, 'commands', uncertainCommand.commandId),
      );
      if (!operation.exists()) {
        commandResolution = {
          action: 'retrySameCommand',
          commandId: uncertainCommand.commandId,
        };
      } else if (operation.data().inputHash !== uncertainCommand.inputHash) {
        commandResolution = {
          action: 'failClosed',
          errorCode: 'commandIdCollision',
          commandId: uncertainCommand.commandId,
        };
      } else {
        commandResolution = {
          action: 'useDurableResult',
          commandId: uncertainCommand.commandId,
          result: operation.data().publicResult,
        };
      }
    }
    result = {
      disposition: clientStateVersion === game.stateVersion
        ? 'upToDate'
        : 'snapshotAdvanced',
      stateVersion: game.stateVersion,
      snapshot: game.publicState,
      commandResolution,
    };
  });
  return result;
}

async function resolveDeadline(gameId) {
  let result;
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const gameRef = doc(db, 'games', gameId);
    const operationId = 'deadline:v1:decision-property-1';
    const operationRef = doc(db, 'games', gameId, 'commands', operationId);
    result = await runTransaction(db, async (tx) => {
      const [gameSnapshot, operationSnapshot] = await Promise.all([
        tx.get(gameRef),
        tx.get(operationRef),
      ]);
      if (operationSnapshot.exists()) return 'duplicate';
      const game = gameSnapshot.data();
      if (game.publicState.pendingDecision?.deadlineAt !== deadlineAt) {
        return 'staleDecision';
      }
      const stateVersionAfter = game.stateVersion + 1;
      const stateAfter = structuredClone(game.publicState);
      stateAfter.stateVersion = stateVersionAfter;
      delete stateAfter.pendingDecision;
      stateAfter.lastMutation = { type: 'deadlineResolved', operationId };
      tx.update(gameRef, {
        stateVersion: stateVersionAfter,
        mutationCount: game.mutationCount + 1,
        publicState: stateAfter,
      });
      tx.set(operationRef, {
        inputHashVersion: 1,
        inputHash: 'deadline-operation-v1',
        stateVersionBefore: game.stateVersion,
        stateVersionAfter,
        publicResult: { status: 'accepted', stateVersionAfter },
      });
      return 'accepted';
    });
  });
  return result;
}

test('listener interruption and foreground replace with newer authority snapshot', async () => {
  const gameId = 'reconnect-listener';
  await seed(gameId);
  const member = env.authenticatedContext('uid-1').firestore();
  const before = await getDoc(doc(member, 'games', gameId));
  assert.equal(before.data().stateVersion, 1);

  await applyCommand({ gameId, commandId: 'cmd-background-1' });
  const plan = await reconnect({ gameId, clientStateVersion: 1 });

  assert.equal(plan.disposition, 'snapshotAdvanced');
  assert.equal(plan.stateVersion, 2);
  assert.equal(plan.snapshot.lastMutation.commandId, 'cmd-background-1');
});

test('commit-before-ACK resolves from receipt and retry has zero second effect', async () => {
  const gameId = 'reconnect-lost-ack';
  await seed(gameId);
  const accepted = await applyCommand({ gameId, commandId: 'cmd-uncertain-1' });
  assert.equal(accepted.disposition, 'accepted');

  const plan = await reconnect({
    gameId,
    clientStateVersion: 1,
    uncertainCommand: { commandId: 'cmd-uncertain-1', inputHash },
  });
  const retry = await applyCommand({ gameId, commandId: 'cmd-uncertain-1' });

  assert.equal(plan.commandResolution.action, 'useDurableResult');
  assert.deepEqual(plan.commandResolution.result, accepted.result);
  assert.equal(retry.disposition, 'duplicate');
  await env.withSecurityRulesDisabled(async (context) => {
    const game = await getDoc(doc(context.firestore(), 'games', gameId));
    assert.equal(game.data().mutationCount, 1);
    assert.equal(game.data().stateVersion, 2);
  });
});

test('missing receipt retries same identity; collision and client-ahead fail closed', async () => {
  const gameId = 'reconnect-fail-closed';
  await seed(gameId);
  const missing = await reconnect({
    gameId,
    clientStateVersion: 1,
    uncertainCommand: { commandId: 'cmd-not-sent', inputHash },
  });
  assert.deepEqual(missing.commandResolution, {
    action: 'retrySameCommand',
    commandId: 'cmd-not-sent',
  });

  await applyCommand({ gameId, commandId: 'cmd-collision' });
  const collision = await reconnect({
    gameId,
    clientStateVersion: 1,
    uncertainCommand: {
      commandId: 'cmd-collision',
      inputHash: 'different-fingerprint-v1',
    },
  });
  assert.equal(collision.commandResolution.errorCode, 'commandIdCollision');
  assert.equal(
    (await reconnect({ gameId, clientStateVersion: 99 })).disposition,
    'clientVersionAhead',
  );
});

test('background reconnect never restarts deadline and concurrent wake is once', async () => {
  const gameId = 'reconnect-deadline';
  await seed(gameId);
  await applyCommand({ gameId, commandId: 'cmd-before-deadline' });
  const beforeWake = await reconnect({ gameId, clientStateVersion: 1 });
  assert.equal(beforeWake.snapshot.pendingDecision.deadlineAt, deadlineAt);

  const wakeResults = await Promise.all([
    resolveDeadline(gameId),
    resolveDeadline(gameId),
    resolveDeadline(gameId),
  ]);
  assert.equal(wakeResults.filter((result) => result === 'accepted').length, 1);
  assert.equal(wakeResults.filter((result) => result === 'duplicate').length, 2);

  const afterWake = await reconnect({ gameId, clientStateVersion: 2 });
  assert.equal(afterWake.stateVersion, 3);
  assert.equal(afterWake.snapshot.pendingDecision, undefined);
  assert.equal(afterWake.snapshot.lastMutation.type, 'deadlineResolved');
});

test('member reads public snapshot while private RNG remains inaccessible', async () => {
  const gameId = 'reconnect-privacy';
  await seed(gameId);
  const member = env.authenticatedContext('uid-1').firestore();
  const publicSnapshot = await getDoc(doc(member, 'games', gameId));
  assert.equal(publicSnapshot.data().publicState.rngVersion, 'hmac_sha256_counter_v1');
  assert.equal(JSON.stringify(publicSnapshot.data()).includes('seedSentinel'), false);
  await assertFails(getDoc(doc(member, 'gameSecrets', gameId)));
});
