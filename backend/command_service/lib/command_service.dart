library;

export 'deadline_resolution_planner.dart';
export 'rng_operation_planner.dart';

/// Authority-side composition root placeholder.
///
/// Gameplay rules remain owned by Engine. Authority adapters in this package
/// only compose canonical Engine/core outputs with ingress and persistence.
final class CommandServiceFoundation {
  const CommandServiceFoundation();
}
