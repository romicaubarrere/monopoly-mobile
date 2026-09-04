import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1 || !RegExp(r'^[A-Z0-9]{6}$').hasMatch(args.single)) {
    stderr.writeln('usage: dart run tool/tier1_guest_client.dart ROOMCODE');
    exitCode = 64;
    return;
  }

  final token = await _anonymousEmulatorToken();
  final values = <String, String>{};
  final storage = FirstPlayableAuthorityDeviceStorage(
    read: (key) async => values[key],
    write: (key, value) async {
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
    },
  );
  final client = FirstPlayableAuthorityClient.httpWithDeviceStorage(
    baseUri: Uri.parse('http://127.0.0.1:8787'),
    idTokenProvider: () async => token,
    deviceStorage: storage,
    commandIds: _CommandIds(),
    clientInstanceId: 'tier1-guest-client',
    presetId: 'express',
    snapshotPollInterval: const Duration(milliseconds: 250),
    snapshotRetryMaxDelay: const Duration(seconds: 2),
    snapshotReadTimeout: const Duration(seconds: 5),
  );

  try {
    _requireAccepted(
      await client.perform(
        FirstPlayableAuthorityAction.joinRoom,
        input: args.single,
      ),
      'join',
    );
    _requireAccepted(
      await client.perform(FirstPlayableAuthorityAction.setReady),
      'ready',
    );
    stdout.writeln('TIER1_GUEST_READY');

    final actorPlayerId = await _waitForActor(client);
    await _playUntilAuctionPass(client, actorPlayerId);
    stdout.writeln('TIER1_GUEST_AUCTION_PASS');
  } finally {
    await client.close(forceTransport: true);
  }
}

Future<String> _anonymousEmulatorToken() async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(
        'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=tier1-emulator-key',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(<String, Object?>{'returnSecureToken': true}));
    final response = await request.close();
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('authEmulatorSignUpFailed:${response.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['idToken'] is! String) {
      throw StateError('authEmulatorTokenMissing');
    }
    return decoded['idToken'] as String;
  } finally {
    client.close(force: true);
  }
}

Future<String> _waitForActor(FirstPlayableAuthorityClient client) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final snapshot = await client.refreshConfirmedRoom();
    final actor = snapshot.snapshot['actorPlayerId'];
    if (actor is String && actor.isNotEmpty) return actor;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('guestActorUnavailable');
}

Future<void> _playUntilAuctionPass(
  FirstPlayableAuthorityClient client,
  String actorPlayerId,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      await client.refreshConfirmedRoom();
      final game = client.confirmedGameSnapshot;
      final snapshot = game?.snapshot;
      if (snapshot != null) {
        final turn = snapshot['turnState'];
        if (turn is Map<String, Object?> &&
            turn['currentPlayerId'] == actorPlayerId) {
          switch (turn['phase']) {
            case 'awaitingRoll':
              _requireAccepted(
                await client.perform(FirstPlayableAuthorityAction.roll),
                'guest-roll',
              );
              continue;
            case 'awaitingPropertyDecision':
              _requireAccepted(
                await client.perform(
                  FirstPlayableAuthorityAction.declineProperty,
                ),
                'guest-decline-property',
              );
              continue;
            case 'awaitingAuctionBid':
              _requireAccepted(
                await client.perform(FirstPlayableAuthorityAction.passAuction),
                'guest-pass-auction',
              );
              return;
          }
        }
      }
    } on TimeoutException {
      // Authority is deliberately restarted by the Android reconnect smoke.
      // A same-room refresh restarts the authenticated game watch once the
      // service is available again.
    } on AuthorityTransportException {
      // The bounded poll retries only transport loss; contract failures remain
      // fatal so the gate cannot hide an invalid public snapshot.
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
  throw StateError('guestAuctionTurnTimeout');
}

void _requireAccepted(FirstPlayableAuthorityResult result, String stage) {
  if (!result.accepted) {
    throw StateError(
      '$stage:${result.outcome.name}:${result.safeErrorCode ?? 'unknown'}',
    );
  }
}

final class _CommandIds implements AuthorityCommandIdSource {
  int _counter = 0;

  @override
  String nextCommandId() => 'tier1-guest-${++_counter}';
}
