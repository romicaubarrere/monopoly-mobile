# Join after Ready preserves monotonic room version — #111

## Canon and reproduced defect

[Ticket #111](https://trello.com/c/a1zlLfBm) fixes an existing room-entry
validation, not a new lobby rule. The
[Manifest](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/819338), v173,
promotes [Persistence v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/852041)
and [Domain v0.7](https://personal-romi.atlassian.net/wiki/spaces/PM/pages/1146948).
Room version is monotonic concurrency state. Join resolves a live/open locator,
checks capacity and atomically adds membership, increments the version and
persists its result. Version is not the number of members.

`FirstPlayableRoomEntryMutation` previously required
`roomVersion == membersAfter.length` for both Create and Join. SetReady correctly
increments roomVersion without adding anyone. Consequently, Create v1 followed
by Ready v2 leaves one member; a valid Join proposes v3 with two members and
throws `invalidRoomEntryMutation` before persistence. Create → Join B → Ready B
→ Join C has the same contradiction.

An isolated diagnostic with the real executor and a shared in-memory room
confirmed the difference: without Ready, Join accepted at v2 with two members;
with Ready, Join failed while retaining v2 and one member, with no new receipt.
The fake's receipt counter is not a Firestore write measurement. The generic
HTTP mapping is `authorityUnavailable`, not a canonical rejection or permission
to discard the pending command identity.

## Smallest validation correction

Room-entry mutations require a positive version. Create retains its previous
version/cardinality equality and all its other checks. Join no longer equates
version with cardinality: any positive version may be represented by the DTO.
It does not know the previous room version and does not gain a new field for it.

`_evaluateJoinRoom` already derives `room.roomVersion + 1`; the accepted reply
already validates a one-step increment. The persistence codec copies that
version and the REST store decodes it independently from membership. Those
boundaries do not need a schema or serialization change.

Empty/duplicate members, duplicate player IDs, missing host, invalid identifiers,
Create timestamps/expiry and nonpositive versions still fail. Locator ownership,
logical expiry, open-room status, duplicate membership, pinned catalog and
capacity checks are unchanged. Join does not reset prior readiness, rewrite the
locator/expiry, change host or rules, or expose the private UID mapping.

Receipt replay retains its historical result and versions, even after another
Ready. Current room reads retain the later version/readiness. Existing room-entry
collision versions also come from the stored result when present; this change
does not reinterpret that separate behavior.

No Create/Join material policy, authentication, Ready/Start transition, game
command, Engine/RNG, UI, SDK, dependency, timeout, cloud service, DEC-065 content
or other canonical rule is changed.

## Regression layers

The shared REST peer uses actual executor, codec and REST store paths for
Create, Ready and Join against the same documents. It does not derive a version
from the member count, unlike the old unit fixture that hid this interleaving.
The peer measures requests/responses and checks persisted documents in memory;
it is not proof of real Firestore isolation, concurrent clients or billed cost.
With a valid locator, Join reads four documents and confirms three writes;
Ready reads three. Missing-locator cases can read fewer documents and are not
forced into the same metric expectation.

The existing real HTTP/Firestore test now exercises two orderings:

- Buy flow: Create1 → hostReady2 → Join3 → guestReady4 → Start5.
- Auction control: Create1 → Join2 → hostReady3 → guestReady4 → Start5.

It checks the accepted Join increment, prior host readiness and new-member
`ready=false`. After guestReady, exact Join replay keeps the historical reply;
actor collision exposes no assigned player result. Both write zero documents
and leave the guest's current room snapshot unchanged at v4. Both complete
gameplay chains and the earlier #105–110 regression assertions remain in place.
Public room snapshots and measured writes are the real HTTP evidence; full
private-room document equality belongs to the scripted peer layer.

## RED/GREEN evidence — 9 September 2026

The 15-case REST regression first produced seven PASS and eight FAIL, with the
failures reporting `invalidRoomEntryMutation`. The unchanged file then passed
all 15 cases after the production validation correction, with zero skips. Its
SHA-256 is `73519db47446036d37c5cac6d21bd09166e6b24080bf8b14f11093e6ca74c067`.
It covers zero/one/three Ready transitions, one/two transaction conflicts,
historical replay after another Ready, actor/code collisions, already-member
rejection/replay, decoder failures and retained DTO/Create guards.

The real Dart emulator RED completed with two PASS and one FAIL, zero skips,
in 11.7 seconds. The HTTP vertical failed at Join after hostReady with
`AuthorityTransportException(authorityUnavailable)`, before the later gameplay
assertions; it was not a timeout. The frozen HTTP SHA-256 is
`55762d5d349bcc64037bf3b3a3b890b6b817c3819f3af322172a0306348a78ce`.
After the correction, the canonical complete emulator command passed 105
JavaScript tests and all three Dart tests, zero skips, without editing that
frozen regression. The Dart-only RED does not claim a new JavaScript RED run.

Independent review ran another 58 focused tests with zero skips and found no
issues in the four-file change. Final-commit local gates and remote acceptance
remain separate requirements, recorded in the associated PR and ticket.

Run the new REST regression, pinned `./tool/preflight.py` / `./tool/ci.sh`,
secret checks and `env -u DEBUG npm --prefix tool/firebase run emulators:test:all`.
Skips do not count as PASS. Acceptance still requires all eight exact-head jobs,
Android PASS/artifact, a protected merge with the reviewed tree and post-main CI.
