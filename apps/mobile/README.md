# La Vuelta mobile

Flutter application for the live First Playable Authority vertical.

The default entrypoint is fail-closed: it shows a configuration error instead
of silently running the non-authoritative preview when Firebase or Authority
configuration is absent.

## Android Emulator run

The repository includes a loopback-only Authority server for the local Android
Tier-1 chain. It uses the same synthetic catalog as the VP0 Emulator tests; it
is not a production catalog and does not define or promote DEC-065.

From the repository root, start Firebase Auth and Firestore:

```sh
npx firebase emulators:start --only auth,firestore \
  --project demo-board-game-local
```

In another terminal, start Authority. The HMAC key is ephemeral and remains in
the server process environment:

```sh
export GCLOUD_PROJECT=demo-board-game-local
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
export FIRST_PLAYABLE_AUTHORITY_HMAC_KEY_BASE64="$(openssl rand -base64 32)"
dart run backend/command_service/tool/first_playable_authority_emulator_server.dart
```

Expose only the two ports consumed by the Android app:

```sh
adb reverse tcp:8787 tcp:8787
adb reverse tcp:9099 tcp:9099
```

Then run Flutter with local demo Firebase values and the synthetic `express`
preset:

```sh
flutter run -d android \
  --dart-define=AUTHORITY_BASE_URL=http://127.0.0.1:8787 \
  --dart-define=FIREBASE_API_KEY=demo-api-key \
  --dart-define=FIREBASE_APP_ID=1:000000000000:android:demo \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=000000000000 \
  --dart-define=FIREBASE_PROJECT_ID=demo-board-game-local \
  --dart-define=FIRST_PLAYABLE_PRESET_ID=express \
  --dart-define=FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1 \
  --dart-define=FIREBASE_AUTH_EMULATOR_PORT=9099
```

Never commit production Firebase configuration or Authority credentials.
Firebase Auth owns anonymous identity and ID-token refresh. SharedPreferences
persists only the client instance ID plus the versioned pending-command and
public session-locator values owned by `board_backend_api`.
