# M1 UX — Home, create/join, lobby and presets

Status: executable UX surfaces on `feat/ux-room-entry-lobby`.

Canonical authority remains Confluence. These widgets are presentation contracts only: they do not implement `RoomCommand`, repositories, backend calls, authority checks, room lifecycle or routing architecture.

## Decision record

Problem → after the M1 Design System/App Shell landed, Home had entry affordances but Create, Join, Lobby and Preset states existed only in specification. Building them directly against backend contracts would couple UX iteration to technical work owned by other M1 cards.

Alternatives → wait for RoomCommand/routing integration; implement local fake business logic that could drift from authority; or materialize pure presentation surfaces that receive data/callbacks and keep all authoritative behavior outside the widgets.

Decision → implement pure presentation surfaces with typed UX view data and callbacks.

Rationale → UX can now test hierarchy, density, input persistence, disabled reasons, room-code readability, preset comparison and compact/text-scale behavior without changing rules or pretending local state is authoritative.

Impact → Flutter now includes `CreateRoomScreen`, `JoinRoomScreen`, `LobbyScreen`, `PresetOptionCard`, inline error/status treatment and presentation-only view data. A future ViewModel/router can wire these widgets without redesigning them.

## UX contracts represented

- room code is six characters, displayed grouped 3+3 and suitable for copy/share callbacks;
- Join preserves the typed code across recoverable errors and normalizes the submitted value to uppercase;
- preset cards show duration as an objective, end condition and differences from data supplied by the caller;
- no final Express/Rápida round caps are hardcoded;
- lobby exposes host/self/bot/ready signals with text/icon/badges, not color alone;
- host Start stays visible but disabled with a reason until authority-derived room state allows it;
- non-host Ready is the single primary lobby action;
- pending states change CTA copy and prevent duplicate interaction;
- empty/error states preserve surrounding context;
- compact mode changes gutters, not the 44dp touch-target floor.

## Evidence boundary

Widget tests use synthetic preset/seat data. They do not prove backend membership, `roomVersion`, StartGame atomicity, deep links, network recovery or actual duration targets. Those remain owned by technical/runtime tickets.

Full VoiceOver/TalkBack, device goldens and physical Tier-1 evidence also remain separate gates.
