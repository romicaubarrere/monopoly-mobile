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

Run the executable Foundation gates with:

```bash
./tool/ci.sh
```
