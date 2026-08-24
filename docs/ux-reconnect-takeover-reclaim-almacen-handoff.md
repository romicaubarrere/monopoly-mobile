# M1 UX Reconnect / Takeover / Reclaim Almacén — Handoff

## Scope

Layer U / presentation only. This handoff materializes the existing reconnect, temporary takeover and reclaim UX contract in Flutter without moving controller, deadline, retry or gameplay authority into the client.

Canonical inputs: M1 Specification Manifest & Evidence Registry v1.2; M1 UX Reconnect, Temporary Takeover & Reclaim Specification v0.1; Visual Direction — Almacén uruguayo intervenido + Character System v0.2; M1 UX Accessibility, Motion & Haptics Acceptance Specification v0.1; DEC-060; NFR/Quality v1.0.

DEC-065 remains provenance-incomplete. No board names, values, transports or card content are reconstructed here; tests use explicit PLACEHOLDER data.

## Problem

Reconnect is visually dangerous because a client-side countdown, spinner or bot indicator can accidentally imply authority that the mobile app does not own. A local transition from “grace expired” to “bot playing”, an optimistic command success, or a “Recover now” control would contradict stable-boundary reclaim and could make stale state look authoritative.

## Alternatives

### A. Full-screen offline dead end

Replace the board with a blocking reconnect screen until connectivity returns.

Rejected because it destroys the last confirmed context, makes short interruptions more disruptive and conflicts with the non-destructive reconnect contract.

### B. Client-owned reconnect state machine

Let Flutter advance countdown → takeover → reclaim and update the UI immediately.

Rejected because controller assignment, deadline resolution and reclaim are authority decisions. The client cannot infer them safely from elapsed local time.

### C. Caller-owned phase renderer over confirmed context

Render only a phase already supplied by the caller/authority adapter; keep the last confirmed context visible and read-only; treat countdown text and “while you were away” rows as caller-owned confirmed presentation data.

Selected.

## Decision

`ReconnectTakeoverSurface` is a presentation-only surface with explicit phases for:

- network unstable;
- reconnecting / grace active;
- command uncertain;
- grace expired without confirmed takeover;
- temporary bot active;
- human reconnected while waiting for stable-boundary reclaim;
- reclaim confirmed;
- authority unavailable / offline.

The surface always keeps an explicit “Último estado confirmado” block visible. It never calculates time, starts takeover, retries a command, reclaims control, resolves a decision or executes a bot action.

Temporary takeover preserves the human seat identity and adds a separate `Bot temporal` badge. The waiting-reclaim state contains no “Recuperar ahora” action. Optional `Mientras estabas fuera…` content is capped at three caller-confirmed rows, matching the specification’s summary-over-replay decision.

## Rationale

This structure keeps the user informed while respecting DEC-060 and the authority boundary. It also makes uncertain outcomes visibly different from success, avoids deadline resets, and allows later ViewModel/router/network integration without embedding policy in UI widgets.

The Almacén visual language is applied through existing `PaperPanel` and `StampBadge` primitives so identity lives in materiality and hierarchy rather than obscuring connection/controller status.

## Impact

Positive:

- reconnect is non-destructive and keeps confirmed context visible;
- bot takeover is never fabricated from a local timer;
- human seat identity survives temporary controller changes;
- stable-boundary reclaim is explained without an unsafe instant-reclaim affordance;
- missed activity is summarized without replaying an animation backlog;
- the surface is independently testable at compact width and increased text scale.

Trade-offs / evidence boundary:

- this does not prove networking, command retry, lost-ACK recovery, deadline persistence, exactly-once takeover/reclaim or controller correctness;
- no background/foreground integration is introduced;
- no manual VoiceOver/TalkBack, physical-device, haptic or human-comprehension PASS is claimed;
- Engine, backend, persistence, rules, economy, RNG and DEC-065 fixture content remain untouched.
