# M1 UX Emotes Almacén — handoff

## Scope

Presentation-only M1 UX/UI implementation for the curated emote interaction defined by the canonical UX specification. This handoff does not define transport, backend rate limiting, gameplay rules, authority, analytics, sound policy, timers, RNG, economy, or character artwork.

DEC-065 exact content remains provenance-incomplete and is unrelated to emote behavior. Executable examples intentionally use `EMOTE_PLACEHOLDER_*`. Character artwork remains caller-supplied so the source-photo Character Sheet can replace placeholders without changing the interaction contract.

## Problem

The canonical UX inventory required an MVP emote tray and bubble, but the Flutter scaffold had no executable component. Adding a chat-like surface would violate scope, while hardcoding final family-character reactions would invent visual evidence that is still pending source photos. A client-owned cooldown or dismissal timer would also blur the authority/presentation boundary.

## Alternatives

1. Wait for final character artwork before implementing emotes.
2. Add a free-text chat/reaction composer and generic mascot icons.
3. Build a caller-owned curated emote contract now: 6–8 options, no free text, secondary board trigger, caller-owned selection ID, presentation-only cooldown state, caller-owned bubble lifecycle, and swappable optional artwork.

## Decision

Use alternative 3.

`EmoteTray` renders exactly the curated caller-provided options and emits only the selected ID. `BoardEmoteAccess` is a secondary board control that opens the tray without creating a persistent route or navigation destination. `EmoteBubble` renders a caller-provided sender/reaction and never starts its own expiry timer. Cooldown/availability are presentation inputs; the widget does not calculate or enforce a backend rate limit.

## Rationale

This closes the executable UX gap while preserving the canonical product boundary: emotes are lightweight reactions, not chat. It also keeps final character art replaceable, preserves the A+C / Almacén visual language through shared Design System primitives, and avoids presenting local time or local state as authoritative.

## Impact

- 6–8 curated reactions are supported; no free-text field exists.
- Selection emits only caller-owned `emoteId`/action identity; no optimistic game mutation occurs.
- Visual cooldown/disabled reasons remain visible and accessible.
- Bubble lifecycle remains caller-owned; reduced motion uses zero-duration opacity change.
- Touch targets remain at least 44dp and the tray is scroll-safe at 360dp / ~130% text scale.
- Optional artwork is a replaceable slot; no generic Maní/Popón/Almendra anatomy is invented.
- No backend send/rate-limit implementation, sound decision, Engine/rules/economy/RNG/authority/timer behavior, or DEC-065 payload is introduced.

## Evidence target

Widget evidence covers curated/no-free-text behavior, ID emission, cooldown blocking, secondary board access, sender/reaction semantics, 360dp + ~130% text scale, and reduced motion. Exact-final-head CI and PR review remain required before merge. Manual VoiceOver/TalkBack, physical device, final character recognition, sound/haptics, and human usability remain separate evidence layers.
