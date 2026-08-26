import 'package:board_backend_api/backend_api.dart' as api;
import 'package:board_game_core/game_core.dart';

import '../ready_start_planner.dart';
import '../rng_operation_planner.dart';
import 'first_playable_authority_executor.dart';

/// Versioned document contract between the Dart Authority executor and the
/// concrete Firestore transaction adapter used by the Firebase Emulator.
///
/// This codec only projects an already-evaluated decision. It never derives a
/// game outcome, re-runs Engine logic or accepts client-owned state.
abstract final class FirstPlayablePersistenceCodec {
  static const int schemaVersion = 1;

  static Map<String, Object?> encodeRoomEntryDecision(
    FirstPlayableRoomEntryTransactionDecision decision,
  ) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'family': 'room',
    'reply': decision.reply.toWireJson(),
    if (decision.mutation case final mutation?)
      'roomEntry': <String, Object?>{
        'kind': mutation.kind.name,
        'codeHash': mutation.codeHash,
        'roomId': mutation.roomId,
        if (mutation.updatedAt case final value?)
          'updatedAtMs': value.toUtc().millisecondsSinceEpoch,
        if (mutation.expiresAt case final value?)
          'expiresAtMs': value.toUtc().millisecondsSinceEpoch,
        'publicRoom': <String, Object?>{
          'schemaVersion': schemaVersion,
          'roomId': mutation.roomId,
          'roomVersion': mutation.roomVersion,
          'status': 'open',
          'hostUid': mutation.hostUid,
          'memberUids': mutation.membersAfter
              .map((member) => member.uid)
              .toList(growable: false),
          'readyByUid': <String, Object?>{
            for (final member in mutation.membersAfter)
              member.uid: member.ready,
          },
          'presetId': mutation.presetId,
        },
        'privateRoom': <String, Object?>{
          'schemaVersion': schemaVersion,
          'memberUidByPlayerId': <String, Object?>{
            for (final member in mutation.membersAfter)
              member.playerId: member.uid,
          },
        },
      },
    if (decision.receiptToPersist case final receipt?)
      'receipt': _receipt(receipt, decision.reply),
  };

  static Map<String, Object?> encodeGameDecision(
    FirstPlayableGameTransactionDecision decision,
  ) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'family': 'game',
    'reply': decision.reply.toWireJson(),
    if (decision.publicStateAfter case final state?)
      'publicPatch': _publicGamePatch(state),
    if (decision.privateRngAfter case final privateRng?)
      'privatePatch': _privateRngPatch(privateRng),
    if (decision.receiptToPersist case final receipt?)
      'receipt': _receipt(receipt, decision.reply),
  };

  static Map<String, Object?> encodeRoomDecision(
    FirstPlayableRoomTransactionDecision decision,
  ) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'family': 'room',
    'reply': decision.reply.toWireJson(),
    if (decision.membersAfter case final members?)
      'roomPatch': <String, Object?>{
        'roomVersion': decision.reply.versionAfter,
        'readyByUid': <String, Object?>{
          for (final member in members) member.uid: member.ready,
        },
      },
    if (decision.startPlan case final plan?) ...<String, Object?>{
      'roomPatch': plan.roomMutation,
      'startGame': _startGame(plan, decision.startMemberUidByPlayerId!),
    },
    if (decision.receiptToPersist case final receipt?)
      'receipt': _receipt(receipt, decision.reply),
  };

  static Map<String, Object?> _publicGamePatch(PublicGameState state) =>
      <String, Object?>{
        'schemaVersion': state.header.schemaVersion,
        'stateVersion': state.header.stateVersion,
        'publicState': state.toJson(),
      };

  static Map<String, Object?> _privateRngPatch(
    AuthorityPrivateRngSnapshot privateRng,
  ) => <String, Object?>{
    'rngVersion': privateRng.rngVersion,
    'streamCounters': <String, Object?>{
      for (final stream in RngStream.values)
        stream.label: privateRng.streamCounters[stream],
    },
  };

  static Map<String, Object?> _startGame(
    ReadyStartPlan plan,
    Map<String, String> memberUidByPlayerId,
  ) => <String, Object?>{
    'gameId': plan.gameId,
    'publicGame': <String, Object?>{
      'schemaVersion': plan.publicState.header.schemaVersion,
      'stateVersion': plan.publicState.header.stateVersion,
      'memberUids': memberUidByPlayerId.values.toList(growable: false),
      'publicState': plan.publicState.toJson(),
    },
    'privateGame': <String, Object?>{
      ...plan.privateState.toPersistenceJson(),
      'memberUidByPlayerId': memberUidByPlayerId,
    },
  };

  static Map<String, Object?> _receipt(
    StoredAuthorityCommandReceipt stored,
    api.AuthorityCommandReply reply,
  ) => <String, Object?>{
    'schemaVersion': schemaVersion,
    'commandId': stored.receipt.commandId,
    'actorUid': stored.actorUid,
    'inputHashVersion': stored.receipt.inputHashVersion,
    'inputHash': stored.receipt.inputHash,
    if (stored.roomEntryCodeHash != null)
      'roomEntryCodeHash': stored.roomEntryCodeHash,
    'stateVersionBefore': reply.versionBefore,
    'stateVersionAfter': reply.versionAfter,
    'status': reply.status.wireValue,
    'resultSummary': stored.receipt.publicResult,
  };
}
