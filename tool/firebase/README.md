# Firebase emulator baseline

M1 uses a local-only Firebase project ID: `demo-board-game-local`.

This baseline starts Auth and Firestore emulators. It never deploys, requires no production Firebase project, and contains no production credentials.

Security intent follows the canonical Threat Model + M1 Security Addendum v0.3 and Persistence v0.7:

- rooms and confirmed public games are member-readable and client-write-denied;
- room-code locators are client inaccessible;
- room/game operation records are client inaccessible;
- `gameSecrets` is client inaccessible;
- unknown collections are deny-by-default;
- anonymous identity continuity can be exercised locally through Auth emulator.

The fixtures are synthetic Foundation fixtures, not DEC-065 game content.

Run from repository root after installing dependencies in this directory:

```bash
cd tool/firebase
npm install
npm run emulators:test
```
