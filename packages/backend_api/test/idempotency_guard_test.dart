import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  const PersistedCommandIdentity existing = PersistedCommandIdentity(
    actorUid: 'uid-a',
    inputHashVersion: 1,
    inputHash: 'hash-a',
  );

  test('TV-39 same actor and semantic hash is duplicate despite transport metadata changes', () {
    final IdempotencyDisposition disposition = IdempotencyGuard.classify(
      existing: existing,
      actorUid: 'uid-a',
      inputHashVersion: 1,
      inputHash: 'hash-a',
    );

    expect(disposition, IdempotencyDisposition.duplicate);
  });

  test('TV-37/38 collision path invokes no gameplay mutation', () {
    var mutationCount = 0;

    final int? result = IdempotencyGuard.executeIfNew<int>(
      existing: existing,
      actorUid: 'uid-a',
      inputHashVersion: 1,
      inputHash: 'different-semantic-hash',
      applyNewCommand: () {
        mutationCount += 1;
        return 1;
      },
    );

    expect(result, isNull);
    expect(mutationCount, 0);
    expect(
      IdempotencyGuard.classify(
        existing: existing,
        actorUid: 'uid-a',
        inputHashVersion: 1,
        inputHash: 'different-semantic-hash',
      ),
      IdempotencyDisposition.commandIdCollision,
    );
  });

  test(
    'different authenticated actor is commandIdCollision with zero mutation',
    () {
      var mutationCount = 0;

      IdempotencyGuard.executeIfNew<void>(
        existing: existing,
        actorUid: 'uid-b',
        inputHashVersion: 1,
        inputHash: 'hash-a',
        applyNewCommand: () => mutationCount += 1,
      );

      expect(mutationCount, 0);
      expect(
        IdempotencyGuard.classify(
          existing: existing,
          actorUid: 'uid-b',
          inputHashVersion: 1,
          inputHash: 'hash-a',
        ),
        IdempotencyDisposition.commandIdCollision,
      );
    },
  );

  test('new command is the only path that invokes mutation callback', () {
    var mutationCount = 0;

    final int? result = IdempotencyGuard.executeIfNew<int>(
      existing: null,
      actorUid: 'uid-a',
      inputHashVersion: 1,
      inputHash: 'hash-a',
      applyNewCommand: () {
        mutationCount += 1;
        return 7;
      },
    );

    expect(result, 7);
    expect(mutationCount, 1);
  });
}
