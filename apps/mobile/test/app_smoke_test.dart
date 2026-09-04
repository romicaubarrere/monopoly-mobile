import 'dart:async';

import 'package:board_backend_api/backend_api.dart';
import 'package:board_mobile/main.dart';
import 'package:board_mobile/ui/first_playable/live_first_playable_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile-first shell renders primary entry actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BoardGameApp(authority: _NoopLiveAuthority()),
    );

    expect(find.text('Una vuelta más.\nUna historia nueva.'), findsOneWidget);
    expect(find.text('Crear partida'), findsOneWidget);
    expect(find.text('Unirse con código'), findsOneWidget);
    expect(find.text('PRIMERA VUELTA'), findsOneWidget);
    expect(find.textContaining('DEC-065'), findsOneWidget);
  });
}

final class _NoopLiveAuthority implements LiveFirstPlayableAuthority {
  const _NoopLiveAuthority();

  @override
  String? get latestCreatedRoomCode => null;

  @override
  AuthorityPublicRoomSnapshot? get confirmedLobbySnapshot => null;

  @override
  AuthorityPublicSnapshot? get confirmedGameSnapshot => null;

  @override
  bool get requiresReconciliation => false;

  @override
  Stream<AuthorityPublicRoomSnapshot> get lobbySnapshots =>
      const Stream<AuthorityPublicRoomSnapshot>.empty();

  @override
  Stream<AuthorityPublicSnapshot> get gameSnapshots =>
      const Stream<AuthorityPublicSnapshot>.empty();

  @override
  Future<FirstPlayableAuthorityResult> perform(
    FirstPlayableAuthorityAction action, {
    String? input,
  }) async => const FirstPlayableAuthorityResult(
    outcome: FirstPlayableAuthorityOutcome.blocked,
    safeErrorCode: 'testOnly',
  );

  @override
  Future<AuthorityPublicRoomSnapshot> refreshLobby() =>
      Future<AuthorityPublicRoomSnapshot>.error(
        const ClientAuthorityContractViolation('testOnly'),
      );
}
