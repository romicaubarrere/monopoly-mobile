library;

/// Transport-neutral backend API boundary.
///
/// HTTP/Firebase adapters belong outside game_core/game_contracts and must invoke
/// canonical Engine contracts rather than duplicating gameplay rules.
abstract interface class CommandGateway {}
