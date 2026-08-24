library;

export 'deadline_resolution_planner.dart';

/// Authority-side composition root placeholder.
///
/// requestReceivedAt, authentication, idempotency, persistence and RNG wiring are
/// intentionally deferred to their owned M1 tickets; no gameplay rule lives here.
final class CommandServiceFoundation {
  const CommandServiceFoundation();
}
