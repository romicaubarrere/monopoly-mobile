const forbiddenPublicKeys = new Set([
  'actorUid',
  'futureDeck',
  'memberUidByPlayerId',
  'privateDeckState',
  'seed',
  'seedBytes',
  'streamCounters',
]);

const forbiddenPersistedRoomKeys = new Set(['roomCode']);

function assertObject(value, code) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error(code);
  }
}

function assertPublicOnly(value, path = 'public') {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertPublicOnly(entry, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== 'object') return;
  for (const [key, entry] of Object.entries(value)) {
    if (forbiddenPublicKeys.has(key)) {
      throw new Error(`privateFieldInPublicDocument:${path}.${key}`);
    }
    assertPublicOnly(entry, `${path}.${key}`);
  }
}

function assertNoPlaintextRoomCode(value, path = 'roomEntry') {
  if (Array.isArray(value)) {
    value.forEach((entry, index) =>
      assertNoPlaintextRoomCode(entry, `${path}[${index}]`));
    return;
  }
  if (value === null || typeof value !== 'object') return;
  for (const [key, entry] of Object.entries(value)) {
    if (forbiddenPersistedRoomKeys.has(key)) {
      throw new Error(`plaintextRoomCodeInPersistence:${path}.${key}`);
    }
    assertNoPlaintextRoomCode(entry, `${path}.${key}`);
  }
}

function assertReceipt(receipt, commandId) {
  assertObject(receipt, 'invalidReceipt');
  assertNoPlaintextRoomCode(receipt, 'receipt');
  if (
    receipt.commandId !== commandId ||
    typeof receipt.actorUid !== 'string' ||
    receipt.actorUid.length === 0 ||
    receipt.inputHashVersion !== 1 ||
    typeof receipt.inputHash !== 'string' ||
    receipt.inputHash.length === 0
  ) {
    throw new Error('invalidReceiptIdentity');
  }
}

function assertDecision(decision, commandId, family) {
  assertObject(decision, 'invalidAuthorityDecision');
  if (decision.schemaVersion !== 1 || decision.family !== family) {
    throw new Error('authorityDecisionContractMismatch');
  }
  assertObject(decision.reply, 'invalidAuthorityReply');
  const status = decision.reply.status;
  const hasMutation = family === 'room'
    ? decision.roomPatch != null ||
      decision.startGame != null ||
      decision.roomEntry != null
    : decision.publicPatch != null;
  const hasReceipt = decision.receipt != null;

  if (status === 'accepted') {
    if (!hasMutation || !hasReceipt) throw new Error('invalidAcceptedDecision');
    assertReceipt(decision.receipt, commandId);
    return;
  }
  if (status === 'duplicate' || status === 'collision') {
    if (hasMutation || hasReceipt) throw new Error('invalidNoWriteDecision');
    return;
  }
  if (hasMutation || !hasReceipt) throw new Error('invalidRejectedDecision');
  assertReceipt(decision.receipt, commandId);
}

function commandResult(receipt) {
  return receipt.resultSummary ?? receipt.publicResult ?? null;
}

/// Concrete Firestore persistence adapter for the VP0 authority executor.
///
/// The evaluator owns authentication, idempotency classification and Engine
/// planning. This adapter owns only consistent reads and atomic persistence of
/// the returned decision. It intentionally never derives gameplay outcomes.
export class FirstPlayableAuthorityFirestoreStore {
  constructor(db, firestoreApi) {
    if (db == null) throw new Error('firestoreRequired');
    if (
      firestoreApi == null ||
      typeof firestoreApi.doc !== 'function' ||
      typeof firestoreApi.getDoc !== 'function' ||
      typeof firestoreApi.runTransaction !== 'function'
    ) {
      throw new Error('firestoreApiRequired');
    }
    this.db = db;
    this.doc = firestoreApi.doc;
    this.getDoc = firestoreApi.getDoc;
    this.runTransaction = firestoreApi.runTransaction;
    this.timestampFromMillis = firestoreApi.timestampFromMillis;
  }

  async transactRoomEntry({ kind, codeHash, roomId, commandId, evaluate }) {
    if (
      (kind !== 'create' && kind !== 'join') ||
      !codeHash ||
      kind === 'create' && !roomId ||
      !commandId ||
      typeof evaluate !== 'function'
    ) {
      throw new Error('invalidRoomEntryTransaction');
    }
    const locatorRef = this.doc(this.db, 'roomCodes', codeHash);
    const receiptRef = this.doc(this.db, 'roomCommands', commandId);

    return this.runTransaction(this.db, async (tx) => {
      const [locatorSnapshot, receiptSnapshot] = await Promise.all([
        tx.get(locatorRef),
        tx.get(receiptRef),
      ]);
      const locator = locatorSnapshot.exists() ? locatorSnapshot.data() : null;
      const resolvedRoomId = kind === 'create' ? roomId : locator?.roomId;
      const roomRef = resolvedRoomId
        ? this.doc(this.db, 'rooms', resolvedRoomId)
        : null;
      const privateRoomRef = resolvedRoomId
        ? this.doc(this.db, 'roomSecrets', resolvedRoomId)
        : null;
      const [roomSnapshot, privateRoomSnapshot] = roomRef == null
        ? [null, null]
        : await Promise.all([tx.get(roomRef), tx.get(privateRoomRef)]);
      const decision = await evaluate({
        locator,
        room: roomSnapshot?.exists() ? roomSnapshot.data() : null,
        privateRoom: privateRoomSnapshot?.exists()
          ? privateRoomSnapshot.data()
          : null,
        storedReceipt: receiptSnapshot.exists()
          ? receiptSnapshot.data()
          : null,
      });
      assertDecision(decision, commandId, 'room');

      if (decision.reply.status === 'accepted') {
        assertRoomEntryDecision(decision.roomEntry, {
          kind,
          codeHash,
          resolvedRoomId,
        });
        const entry = decision.roomEntry;
        assertPublicOnly(entry.publicRoom);
        assertNoPlaintextRoomCode(entry);
        if (kind === 'create') {
          if (typeof this.timestampFromMillis !== 'function') {
            throw new Error('timestampFromMillisRequired');
          }
          tx.set(locatorRef, {
            codeHash,
            roomId: resolvedRoomId,
            expiresAt: this.timestampFromMillis(entry.expiresAtMs),
            updatedAt: this.timestampFromMillis(entry.updatedAtMs),
          });
          tx.set(roomRef, entry.publicRoom);
          tx.set(privateRoomRef, entry.privateRoom);
        } else {
          tx.set(roomRef, entry.publicRoom, { merge: true });
          tx.set(privateRoomRef, entry.privateRoom, { merge: true });
        }
        tx.set(receiptRef, decision.receipt);
      } else if (decision.receipt != null) {
        tx.set(receiptRef, decision.receipt);
      }
      return decision.reply;
    });
  }

  async transactRoom({ roomId, commandId, evaluate }) {
    if (!roomId || !commandId || typeof evaluate !== 'function') {
      throw new Error('invalidRoomTransaction');
    }
    const roomRef = this.doc(this.db, 'rooms', roomId);
    const receiptRef = this.doc(this.db, 'roomCommands', commandId);

    return this.runTransaction(this.db, async (tx) => {
      const [roomSnapshot, receiptSnapshot] = await Promise.all([
        tx.get(roomRef),
        tx.get(receiptRef),
      ]);
      const decision = await evaluate({
        room: roomSnapshot.exists() ? roomSnapshot.data() : null,
        storedReceipt: receiptSnapshot.exists()
          ? receiptSnapshot.data()
          : null,
      });
      assertDecision(decision, commandId, 'room');

      if (decision.reply.status === 'accepted') {
        if (decision.startGame != null) {
          assertObject(decision.startGame, 'invalidStartGameDecision');
          const { gameId, publicGame, privateGame } = decision.startGame;
          if (!gameId || publicGame == null || privateGame == null) {
            throw new Error('invalidStartGameDocuments');
          }
          assertObject(
            privateGame.memberUidByPlayerId,
            'missingPrivateMemberMapping',
          );
          if (
            !Array.isArray(publicGame.memberUids) ||
            publicGame.memberUids.length === 0 ||
            Object.keys(privateGame.memberUidByPlayerId).length !==
              publicGame.memberUids.length ||
            !Object.values(privateGame.memberUidByPlayerId).every((uid) =>
              publicGame.memberUids.includes(uid),
            )
          ) {
            throw new Error('invalidPrivateMemberMapping');
          }
          assertPublicOnly(publicGame);
          tx.set(this.doc(this.db, 'games', gameId), publicGame);
          tx.set(this.doc(this.db, 'gameSecrets', gameId), privateGame);
        }
        tx.set(roomRef, decision.roomPatch, { merge: true });
        tx.set(receiptRef, decision.receipt);
      } else if (decision.receipt != null) {
        tx.set(receiptRef, decision.receipt);
      }
      return decision.reply;
    });
  }

  async transactGame({ gameId, commandId, evaluate }) {
    if (!gameId || !commandId || typeof evaluate !== 'function') {
      throw new Error('invalidGameTransaction');
    }
    const gameRef = this.doc(this.db, 'games', gameId);
    const secretRef = this.doc(this.db, 'gameSecrets', gameId);
    const receiptRef = this.doc(
      this.db,
      'games',
      gameId,
      'commands',
      commandId,
    );

    return this.runTransaction(this.db, async (tx) => {
      const [gameSnapshot, secretSnapshot, receiptSnapshot] = await Promise.all([
        tx.get(gameRef),
        tx.get(secretRef),
        tx.get(receiptRef),
      ]);
      const decision = await evaluate({
        publicGame: gameSnapshot.exists() ? gameSnapshot.data() : null,
        privateGame: secretSnapshot.exists() ? secretSnapshot.data() : null,
        storedReceipt: receiptSnapshot.exists()
          ? receiptSnapshot.data()
          : null,
      });
      assertDecision(decision, commandId, 'game');

      if (decision.reply.status === 'accepted') {
        assertPublicOnly(decision.publicPatch);
        tx.set(gameRef, decision.publicPatch, { merge: true });
        if (decision.privatePatch != null) {
          tx.set(secretRef, decision.privatePatch, { merge: true });
        }
        tx.set(receiptRef, decision.receipt);
      } else if (decision.receipt != null) {
        tx.set(receiptRef, decision.receipt);
      }
      return decision.reply;
    });
  }

  async readGame({ gameId, commandId }) {
    if (!gameId) throw new Error('gameIdRequired');
    const reads = [
      this.getDoc(this.doc(this.db, 'games', gameId)),
      this.getDoc(this.doc(this.db, 'gameSecrets', gameId)),
    ];
    if (commandId != null) {
      reads.push(
        this.getDoc(
          this.doc(this.db, 'games', gameId, 'commands', commandId),
        ),
      );
    }
    const [gameSnapshot, secretSnapshot, receiptSnapshot] = await Promise.all(
      reads,
    );
    return {
      publicGame: gameSnapshot.exists() ? gameSnapshot.data() : null,
      privateGame: secretSnapshot.exists() ? secretSnapshot.data() : null,
      storedReceipt: receiptSnapshot?.exists()
        ? receiptSnapshot.data()
        : null,
    };
  }
}

function assertRoomEntryDecision(entry, { kind, codeHash, resolvedRoomId }) {
  assertObject(entry, 'missingRoomEntryDecision');
  assertObject(entry.publicRoom, 'missingPublicRoomDecision');
  assertObject(entry.privateRoom, 'missingPrivateRoomDecision');
  assertObject(
    entry.privateRoom.memberUidByPlayerId,
    'missingPrivateRoomMembership',
  );
  if (
    entry.kind !== kind ||
    entry.codeHash !== codeHash ||
    entry.roomId !== resolvedRoomId ||
    entry.publicRoom.roomId !== resolvedRoomId ||
    !Array.isArray(entry.publicRoom.memberUids) ||
    entry.publicRoom.memberUids.length === 0 ||
    Object.keys(entry.privateRoom.memberUidByPlayerId).length !==
      entry.publicRoom.memberUids.length ||
    !Object.values(entry.privateRoom.memberUidByPlayerId).every((uid) =>
      entry.publicRoom.memberUids.includes(uid)) ||
    kind === 'create' &&
      (!Number.isSafeInteger(entry.expiresAtMs) ||
        !Number.isSafeInteger(entry.updatedAtMs) ||
        entry.expiresAtMs <= entry.updatedAtMs) ||
    kind === 'join' &&
      (entry.expiresAtMs != null || entry.updatedAtMs != null)
  ) {
    throw new Error('invalidRoomEntryDecision');
  }
}

export function duplicateReply(storedReceipt) {
  return {
    status: 'duplicate',
    result: commandResult(storedReceipt),
  };
}
