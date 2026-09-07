# Mobile state, routing and serialization — ticket #21

## Governing decisions

[ADR-004](https://personal-romi.atlassian.net/wiki/pages/viewpage.action?pageId=819276)
and [Dependency Baseline v0.2](https://personal-romi.atlassian.net/wiki/pages/viewpage.action?pageId=1048642),
under the M1 Specification Manifest & Evidence Registry, select pragmatic MVVM,
Riverpod 3.x, go_router 17.x and json_serializable. They do not authorize
client-side gameplay or a replacement persistence protocol.

The live VP0 path was already implemented in PR #79. Ticket #21 extracts its
existing subscriptions, projections and action forwarding from the large widget
into the selected boundaries. It preserves Direction B, the original live tests,
the Authority adapter and repository, and the canonical wire representations.

## Ownership

| Component | Responsibility |
| --- | --- |
| `BoardGameApp` | Root provider overrides and `MaterialApp.router`; production still injects the existing bootstrap result. |
| `liveFirstPlayableAuthorityProvider` | Explicit repository-port injection; no Firebase initialization in providers or widgets. |
| `LiveFirstPlayableViewModel` | Riverpod Notifier, subscriptions, transport flags, confirmed-state projection and action forwarding. |
| `LiveFirstPlayableUiState` | Read-only lobby/board projections and unchanged confirmed snapshots; never an editable GameState. |
| `LiveFirstPlayableApp` | Existing layout, semantics, text controllers and intent forwarding; no transport or snapshot parsing. |
| `FirstPlayableAuthorityClient` | Existing command identity, confirmed context, retry, durable pending state and reconciliation. Unchanged. |
| Authority / Engine | Existing authentication, membership, legality, money, RNG, versions, deadlines and durable effects. Unchanged. |

The ViewModel does not create a parallel command taxonomy or reconstruct commands
from widget state. The existing confirmed request resolver remains responsible for
`commandId`, version and decision identity. An accepted ACK without a replacement
snapshot cannot advance the rendered gameplay state. Duplicate snapshots cannot
increment a version or apply a second economic effect in presentation.

Provider disposal cancels subscriptions. A generation fence rejects late results
from a replaced Authority dependency. Foreground reconstructs presentation only
from the repository's confirmed data and preserves required reconciliation; it
does not automatically replay an uncertain command. Device/process restoration
remains owned by the existing bootstrap/repository.

## Routes and access

| Path | Behavior |
| --- | --- |
| `/` | Home, or the already-confirmed lobby/game. |
| `/create` | Existing create form; only an explicit submit invokes Authority. |
| `/join` | Existing join form. |
| `/join/:roomCode` | Valid six-character uppercase code prefills the form; does not join automatically. |
| `/lobby` | Existing confirmed lobby; no membership means Home. |
| `/game/:gameId` | Only the matching game named by the authenticated lobby can render; otherwise a safe access-unavailable surface. |
| `/resume/:gameId` | Same membership check and confirmed repository data; uncertain commands still require the existing reconciliation action. |

Property offers, auctions and reconnect remain derived board states, not separate
URLs. New snapshots remove obsolete decision surfaces without pushing a route.
No trade/debt route, rule or gameplay integration is introduced by this extraction.
Unknown/malformed routes fail safely without a command or a locator write.
Nested entry routes preserve system Back to Home. Transitions use
`NoTransitionPage`, preserving the existing presentation and reduced-motion
behavior; this is not a new visual direction.

These tests cover the Flutter routing boundary and incoming path behavior. No
external HTTPS app-link domain, platform association file, production invitation
service or additional OS URL scheme is provisioned by this Foundation gate.
`initialLocation` is an explicit test/embedding override; production preserves
the initial route supplied by the platform.

## Contract generation

`game_contracts` now generates `RoomCommand` and `RoomCommandResult` JSON adapters.
Their existing constructors still validate semantics; `toCanonicalJson` still
sorts keys using the existing normalizer. Stable `wireValue` enum values, omitted
null fields, UTC timestamps and existing result shape are preserved. In
particular, no new `schemaVersion` field is added to the existing result shape.
Other established Authority/Game wire contracts remain unchanged.

Generated decoding rejects unknown fields, missing required fields, unsupported
command schema versions and malformed enum values. Custom integer decoders
preserve the strict integer boundary: the generator's default `num.toInt` would
otherwise truncate a decimal. Generated parsing failures become the existing
typed `RoomContractViolation`, without exposing the input in a generic error.

The generated output is versioned. Regenerate from `packages/game_contracts`:

```sh
dart run build_runner build
```

After intentional regeneration, run the canonical local formatter and the
read-only verification path from the repository root:

```sh
./tool/preflight.py --format
./tool/preflight.py
```

CI tests the versioned generated adapter and canonical golden fixtures; it does
not silently repair generated files or format source. Regeneration must be
reproducible before committing a changed adapter. No Freezed, Riverpod codegen,
alternative snapshot store or migration policy is added.

## Dependency ownership and evidence

Mobile owns pinned `flutter_riverpod 3.4.2` and `go_router 17.5.0`.
`game_contracts` owns `json_annotation 4.12.0`, with development-only
`json_serializable 6.14.1` and `build_runner 2.16.0`. These are the selected
baselines, not automatic latest/major upgrades. Joint resolution on Flutter
3.47.0 / Dart 3.13.0 preserves existing locked dependency versions. Platform,
Riverpod, Firebase and HTTP dependencies remain outside core/contracts code.

`app_state_routing_test.dart` covers no pre-ACK mutation, repeated confirmed
snapshots, obsolete-sheet invalidation, immutable action/member lists, provider
replacement, fake overrides, safe foreign/invalid links, explicit invite submit,
foreground reconciliation, stable game URLs and system Back. The existing live
widget suite remains intact. The safe-access surface is also tested at 375 dp
portrait / 130% text and landscape / 200% text with reduced motion, a labeled
48 dp return action and Android tap-target checks. Existing Direction B tokens
and the light theme are retained; this does not claim new dark-theme acceptance.
`room_serialization_test.dart` freezes all six room
command wire values and all three result statuses, round trips, schema/field
rejection, integer precision and UTC conversion.

The PR/Trello handoff must attach exact-head local checks, all remote workflow
results and protected merge evidence before Done. This is the ADR-004 Foundation
gate, not broader production, App Check, iOS distribution, Classic migration or
DEC-065 acceptance.
