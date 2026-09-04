import 'client_authority.dart';
import 'client_authority_session.dart';
import 'first_playable_session_locator.dart';

typedef FirstPlayableDeviceStringRead = Future<String?> Function(String key);
typedef FirstPlayableDeviceStringWrite = Future<void> Function(
  String key,
  String? value,
);

/// Owns the two durable Authority values that Flutter must persist.
///
/// Flutter supplies one device key-value port. This adapter owns stable,
/// versioned keys plus the canonical pending-command and public-locator codecs,
/// so the application cannot accidentally serialize Authority contracts or
/// reuse one key for both values.
final class FirstPlayableAuthorityDeviceStorage {
  FirstPlayableAuthorityDeviceStorage({
    required FirstPlayableDeviceStringRead read,
    required FirstPlayableDeviceStringWrite write,
    String namespace = 'la_vuelta.authority.v1',
  }) : this._(_namespace(namespace), read, write);

  FirstPlayableAuthorityDeviceStorage._(
    String namespace,
    FirstPlayableDeviceStringRead read,
    FirstPlayableDeviceStringWrite write,
  ) : pendingCommands = JsonPendingAuthorityCommandStore(
        read: () => read('$namespace.pending-command'),
        write: (value) => write('$namespace.pending-command', value),
      ),
      sessionLocator = JsonFirstPlayableSessionLocatorStore(
        read: () => read('$namespace.session-locator'),
        write: (value) => write('$namespace.session-locator', value),
      );

  final PendingAuthorityCommandStore pendingCommands;
  final FirstPlayableSessionLocatorStore sessionLocator;
}

String _namespace(String value) {
  if (value.isEmpty ||
      value.length > 96 ||
      value.trim() != value ||
      !RegExp(r'^[a-z][a-z0-9._-]*$').hasMatch(value)) {
    throw const ClientAuthorityContractViolation(
      'invalidAuthorityStorageNamespace',
    );
  }
  return value;
}
