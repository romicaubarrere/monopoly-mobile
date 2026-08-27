import 'dart:convert';
import 'dart:io';

import 'package:board_command_service/security/firebase_identity_verifier.dart';

Future<void> main() async {
  final environment = Platform.environment;
  final emulatorHost = environment['FIREBASE_AUTH_EMULATOR_HOST'];
  final projectId = environment['GCLOUD_PROJECT'];
  if (emulatorHost == null || emulatorHost.isEmpty) {
    throw StateError('firebaseAuthEmulatorHostMissing');
  }
  if (projectId == null || projectId.isEmpty) {
    throw StateError('firebaseProjectIdMissing');
  }

  final client = HttpClient();
  try {
    final request = await client.postUrl(
      Uri.parse(
        'http://$emulatorHost/identitytoolkit.googleapis.com/v1/'
        'accounts:signUp?key=fake-api-key',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode(const <String, Object?>{'returnSecureToken': true}),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw StateError('firebaseAuthEmulatorSignInFailed');
    }
    final body = await utf8.decoder.bind(response).join();
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?>) {
      throw StateError('firebaseAuthEmulatorResponseInvalid');
    }
    final localId = decoded['localId'];
    final token = decoded['idToken'];
    if (localId is! String || localId.isEmpty || token is! String) {
      throw StateError('firebaseAuthEmulatorResponseInvalid');
    }

    final identity = await FirebaseAuthEmulatorIdentityVerifier.fromEnvironment(
      projectId: projectId,
    ).verify(token);
    if (identity.uid != localId) {
      throw StateError('firebaseAuthEmulatorIdentityMismatch');
    }
  } finally {
    client.close(force: true);
  }
}
