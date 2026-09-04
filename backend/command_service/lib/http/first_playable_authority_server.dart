import 'dart:async';
import 'dart:io';

import 'first_playable_authority_runtime.dart';

final class FirstPlayableAuthorityServerViolation implements Exception {
  const FirstPlayableAuthorityServerViolation(this.code);

  final String code;

  @override
  String toString() => 'FirstPlayableAuthorityServerViolation: $code';
}

/// Loopback-only HTTP listener for the local First Playable Emulator chain.
///
/// Android reaches this listener through `adb reverse`; binding to a remote
/// interface is deliberately rejected so Emulator credentials and unsigned
/// Firebase Auth tokens cannot leave the developer machine.
final class FirstPlayableAuthorityServer {
  FirstPlayableAuthorityServer._(this._server, this._subscription);

  static Future<FirstPlayableAuthorityServer> bind({
    required FirstPlayableAuthorityRuntime runtime,
    String host = '127.0.0.1',
    int port = 8787,
  }) async {
    final address = InternetAddress.tryParse(host);
    if (address == null || !address.isLoopback || port < 0 || port > 65535) {
      throw const FirstPlayableAuthorityServerViolation(
        'emulatorListenerMustBeNumericLoopback',
      );
    }
    final server = await HttpServer.bind(address, port);
    final subscription = server.listen(runtime.handle);
    return FirstPlayableAuthorityServer._(server, subscription);
  }

  final HttpServer _server;
  final StreamSubscription<HttpRequest> _subscription;

  Uri get baseUri =>
      Uri(scheme: 'http', host: _server.address.address, port: _server.port);

  Future<void> close({bool force = false}) async {
    await _subscription.cancel();
    await _server.close(force: force);
  }
}
