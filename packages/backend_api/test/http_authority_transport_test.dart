import 'dart:convert';
import 'dart:io';

import 'package:board_backend_api/backend_api.dart';
import 'package:test/test.dart';

void main() {
  test('sends bearer out-of-band and decodes a public response', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    late Map<String, Object?> receivedBody;
    late String? receivedAuthorization;
    server.listen((request) async {
      receivedAuthorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      receivedBody = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(<String, Object?>{'ok': true}));
      await request.response.close();
    });
    final transport = HttpAuthorityWireTransport(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      idTokenProvider: () async => 'synthetic.id.token',
    );
    addTearDown(() async {
      transport.close(force: true);
      await server.close(force: true);
    });

    final response = await transport.sendCommand(<String, Object?>{
      'family': 'game',
      'command': const <String, Object?>{'commandId': 'cmd-1'},
    });

    expect(response, <String, Object?>{'ok': true});
    expect(receivedAuthorization, 'Bearer synthetic.id.token');
    expect(receivedBody, isNot(contains('authorization')));
    expect(receivedBody, isNot(contains('token')));
  });

  test('permits HTTP only for local emulator origins', () {
    expect(
      () => HttpAuthorityWireTransport(
        baseUri: Uri.parse('http://authority.example.test'),
        idTokenProvider: () async => 'token',
      ),
      throwsArgumentError,
    );
    final local = HttpAuthorityWireTransport(
      baseUri: Uri.parse('http://localhost:8080'),
      idTokenProvider: () async => 'token',
    );
    local.close(force: true);
  });
}
