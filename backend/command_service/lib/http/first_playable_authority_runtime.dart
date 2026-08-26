import 'dart:io';

import '../ingress/command_ingress.dart';
import '../observability/authority_observability.dart';
import '../security/firebase_identity_verifier.dart';
import 'authority_http_ingress.dart';
import 'first_playable_authority_executor.dart';
import 'first_playable_authority_material_factory.dart';

/// Composition root for the live Flutter -> HTTP -> Authority vertical slice.
///
/// The runtime deliberately accepts the durable store port instead of a
/// Firestore SDK object. This keeps document decoding and persistence behind a
/// single adapter while all gameplay remains in the canonical Engine planners.
final class FirstPlayableAuthorityRuntime {
  FirstPlayableAuthorityRuntime.withHmacMaterials({
    required FirebaseIdentityVerifier identityVerifier,
    required FirstPlayableAuthorityStore store,
    required BestEffortAuthorityObservability observability,
    required FirstPlayableAuthorityMaterialFactory materialFactory,
    DateTime Function()? now,
  }) : this(
         identityVerifier: identityVerifier,
         store: store,
         observability: observability,
         startMaterialFactory: materialFactory.startGame,
         roomEntryMaterialFactory: materialFactory.roomEntry,
         now: now,
       );

  FirstPlayableAuthorityRuntime({
    required FirebaseIdentityVerifier identityVerifier,
    required FirstPlayableAuthorityStore store,
    required BestEffortAuthorityObservability observability,
    FirstPlayableStartMaterialFactory? startMaterialFactory,
    FirstPlayableRoomEntryMaterialFactory? roomEntryMaterialFactory,
    DateTime Function()? now,
  }) : _ingress = AuthorityHttpIngress(
         identityVerifier: identityVerifier,
         commandIngress: CommandIngress(observability: observability, now: now),
         executor: FirstPlayableAuthorityExecutor(
           store: store,
           startMaterialFactory: startMaterialFactory,
           roomEntryMaterialFactory: roomEntryMaterialFactory,
         ),
         now: now,
       );

  final AuthorityHttpIngress _ingress;

  Future<void> handle(HttpRequest request) => _ingress.handle(request);
}
