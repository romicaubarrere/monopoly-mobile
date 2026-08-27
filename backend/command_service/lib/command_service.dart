library;

export 'buy_auction_planner.dart';
export 'deadline_resolution_planner.dart';
export 'http/authority_http_ingress.dart';
export 'http/first_playable_authority_executor.dart';
export 'http/first_playable_response_adapter.dart';
export 'http/first_playable_authority_runtime.dart';
export 'http/first_playable_persistence_codec.dart';
export 'http/first_playable_authority_material_factory.dart';
export 'http/first_playable_rules_catalog_repository.dart';
export 'reconnect_planner.dart';
export 'ready_start_planner.dart';
export 'rng_operation_planner.dart';
export 'roll_movement_planner.dart';
export 'security/firebase_identity_verifier.dart';
export 'security/google_firebase_id_token_signature_verifier.dart';

/// Authority-side composition root placeholder.
///
/// Gameplay rules remain owned by Engine. Authority adapters in this package
/// only compose canonical Engine/core outputs with ingress and persistence.
final class CommandServiceFoundation {
  const CommandServiceFoundation();
}
