import 'dart:io';

import '../ingress/command_ingress.dart';
import '../observability/authority_observability.dart';
import '../security/firebase_identity_verifier.dart';
import 'authority_http_ingress.dart';
import 'first_playable_authority_executor.dart';

/// Composition root for the live Flutter -> HTTP -> Authority vertical slice.
///
/// The runtime deliberately accepts the durable store port instead of a
/// Firestore SDK object. This keeps document decoding and persistence behind a
/// single adapter while all gameplay remains in the canonical Engine planners.
final class FirstPlayableAuthorityRuntime {
  FirstPlayableAuthorityRuntime({
    required FirebaseIdentityVerifier identityVerifier,
    required FirstPlayableAuthorityStore store,
    required BestEffortAuthorityObservability observability,
    FirstPlayableStartMaterialFactory? startMaterialFactory,
    DateTime Function()? now,
  }) : _ingress = AuthorityHttpIngress(
         identityVerifier: identityVerifier,
         commandIngress: CommandIngress(observability: observability, now: now),
         executor: FirstPlayableAuthorityExecutor(
           store: store,
           startMaterialFactory: startMaterialFactory,
         ),
         now: now,
       );

  final AuthorityHttpIngress _ingress;

  Future<void> handle(HttpRequest request) => _ingress.handle(request);
}
