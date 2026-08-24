import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  test('TV-40 expired locator is unavailable while document still exists', () {
    const locator = RoomCodeLocator(
      codeHash: 'hash-a',
      roomId: 'room-old',
      expiresAtMs: 1000,
      roomClosed: false,
    );

    expect(
      locator.resolveForJoin(serverNowMs: 1000),
      RoomLocatorResult.roomUnavailable,
    );
  });

  test('TV-41 expired mapping can be reclaimed only once per transaction', () {
    final transaction = RoomCodeClaimTransaction(
      current: const RoomCodeLocator(
        codeHash: 'hash-a',
        roomId: 'room-old',
        expiresAtMs: 1000,
        roomClosed: false,
      ),
    );

    final first = transaction.claim(
      codeHash: 'hash-a',
      roomId: 'room-new',
      serverNowMs: 1000,
      expiresAtMs: 2000,
    );
    final second = transaction.claim(
      codeHash: 'hash-a',
      roomId: 'room-racing',
      serverNowMs: 1000,
      expiresAtMs: 2000,
    );

    expect(first?.roomId, 'room-new');
    expect(second, isNull);
    expect(transaction.current?.roomId, 'room-new');
  });

  test(
    'deadline eligibility uses ingress requestReceivedAt, not retry time',
    () {
      const deadline = PersistedDecisionDeadline(
        decisionId: 'decision-1',
        deadlineAtMs: 5000,
      );

      expect(
        deadline.classifyHumanCommand(requestReceivedAtMs: 4999),
        DeadlineEligibility.eligible,
      );
      expect(
        deadline.classifyHumanCommand(requestReceivedAtMs: 5000),
        DeadlineEligibility.decisionClosed,
      );
    },
  );

  test(
    'deadline operation id is deterministic and effects are at-most-once',
    () {
      const deadline = PersistedDecisionDeadline(
        decisionId: 'decision-1',
        deadlineAtMs: 5000,
      );
      final guard = DeadlineOperationGuard();

      expect(deadline.operationId, 'deadline:v1:decision-1');
      expect(guard.begin(deadline), isTrue);
      expect(guard.begin(deadline), isFalse);
    },
  );
}
