# La Vuelta mobile

Flutter application for the live First Playable Authority vertical.

The default entrypoint is fail-closed: it shows a configuration error instead
of silently running the non-authoritative preview when Firebase or Authority
configuration is absent.

## Emulator run

Start Firebase Auth/Firestore and the Authority HTTP service, then expose their
ports to the connected Android device with `adb reverse`. Run Flutter with these
compile-time values:

- `AUTHORITY_BASE_URL` (loopback HTTP for Emulator or production HTTPS)
- `FIREBASE_API_KEY`
- `FIREBASE_APP_ID`
- `FIREBASE_MESSAGING_SENDER_ID`
- `FIREBASE_PROJECT_ID`
- `FIRST_PLAYABLE_PRESET_ID`
- `FIREBASE_AUTH_EMULATOR_HOST` and `FIREBASE_AUTH_EMULATOR_PORT` for Emulator

Never commit production Firebase configuration or Authority credentials.
Firebase Auth owns anonymous identity and ID-token refresh. SharedPreferences
persists only the client instance ID plus the versioned pending-command and
public session-locator values owned by `board_backend_api`.
