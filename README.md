# Mobile board game

Foundation workspace for the mobile multiplayer board-game project.

## Structure

- `apps/mobile` — Flutter client.
- `packages/game_core` — pure-Dart gameplay domain, owned by Engine.
- `packages/game_contracts` — pure-Dart canonical contracts.
- `packages/backend_api` — transport-neutral backend boundary.
- `backend/command_service` — authority-side composition root.
- `tool` — deterministic local/CI checks.
- `docs` — implementation-boundary documentation.

The development product name is intentionally not encoded in package identifiers so the application remains rebrandable before external distribution.

## Toolchain

Flutter is pinned to `3.47.0` in `.fvmrc`; Dart 3.13 is required by the workspace. CI prints the resolved Flutter and Dart versions before running any gate.

Put that SDK's `bin` on `PATH` (or use `fvm exec` with the pinned SDK already
installed), then run the canonical local preflight:

```bash
./tool/preflight.py
```

It checks source formatting without modifying it, then runs Foundation,
repository-policy and artifact checks. To explicitly format local Dart source
before running those gates, use `./tool/preflight.py --format`. This option is
rejected in CI. See [preflight modes, regression evidence and the pre-push
checklist](docs/dart-preflight.md). `./tool/ci.sh` remains the Foundation entrypoint
used by CI, with the same read-only format stage.

Canonical Confluence status/evidence writes have a separate
[guarded operator workflow](docs/canonical-document-guard.md). Its regression
tests run offline in Foundation CI; gameplay CI never requires Atlassian access.
