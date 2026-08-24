library;

export 'src/deadline_authority.dart';
export 'src/idempotency_guard.dart';
export 'src/room_locator_lifecycle.dart';
export 'src/semantic_fingerprint.dart';

/// Transport-neutral backend API boundary.
///
/// HTTP/Firebase adapters belong outside game_core/game_contracts and must invoke
/// canonical Engine contracts rather than duplicating gameplay rules.
abstract interface class CommandGateway {}
