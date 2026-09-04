#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
ARTIFACTS="$ROOT/build/tier1-android"
mkdir -p "$ARTIFACTS"
# Preserve the foreground build/ADB/UI failure in the uploaded artifact. Avoid
# shell xtrace here because the Authority HMAC is intentionally process-private.
exec > >(tee "$ARTIFACTS/tier1.log") 2>&1

firebase_pid=""
authority_pid=""
guest_pid=""
cleanup() {
  local status=$?
  set +e
  if [[ "$status" -ne 0 ]]; then
    adb exec-out screencap -p >"$ARTIFACTS/failure-screen.png" 2>/dev/null || true
    adb shell uiautomator dump /sdcard/window.xml >/dev/null 2>&1 || true
    adb exec-out cat /sdcard/window.xml >"$ARTIFACTS/failure-window.xml" 2>/dev/null || true
    adb logcat -d -v threadtime >"$ARTIFACTS/logcat.txt" 2>&1 || true
    adb shell dumpsys activity activities >"$ARTIFACTS/activity.txt" 2>&1 || true
  fi
  [[ -n "$guest_pid" ]] && kill "$guest_pid" 2>/dev/null
  [[ -n "$authority_pid" ]] && kill "$authority_pid" 2>/dev/null
  [[ -n "$firebase_pid" ]] && kill "$firebase_pid" 2>/dev/null
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

wait_port() {
  local port="$1"
  python3 - "$port" <<'PY'
import socket, sys, time
port = int(sys.argv[1])
deadline = time.time() + 45
while time.time() < deadline:
    with socket.socket() as sock:
        sock.settimeout(.3)
        if sock.connect_ex(('127.0.0.1', port)) == 0:
            raise SystemExit(0)
    time.sleep(.25)
raise SystemExit(f'port {port} did not open')
PY
}

wait_log() {
  local file="$1" marker="$2"
  for _ in $(seq 1 120); do
    grep -q "$marker" "$file" 2>/dev/null && return 0
    sleep .5
  done
  echo "missing log marker: $marker" >&2
  cat "$file" >&2 || true
  return 1
}

npm --prefix tool/firebase ci --ignore-scripts --no-audit --no-fund
npm --prefix tool/firebase run prepare:stream-json-v3-compat
./tool/firebase/node_modules/.bin/firebase emulators:start \
  --config "$ROOT/firebase.json" \
  --project demo-board-game-local --only auth,firestore \
  >"$ARTIFACTS/firebase.log" 2>&1 &
firebase_pid=$!
wait_port 9099
wait_port 8080

export GCLOUD_PROJECT=demo-board-game-local
export FIREBASE_PROJECT_ID=demo-board-game-local
export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
export FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099
export AUTHORITY_EMULATOR_HOST=127.0.0.1
export AUTHORITY_EMULATOR_PORT=8787
export FIRST_PLAYABLE_AUTHORITY_HMAC_KEY_BASE64
FIRST_PLAYABLE_AUTHORITY_HMAC_KEY_BASE64="$(python3 - <<'PY'
import base64
print(base64.b64encode(bytes(range(32))).decode())
PY
)"

start_authority() {
  dart run backend/command_service/tool/first_playable_authority_emulator_server.dart \
    >>"$ARTIFACTS/authority.log" 2>&1 &
  authority_pid=$!
  wait_port 8787
}

: >"$ARTIFACTS/authority.log"
start_authority

adb reverse tcp:9099 tcp:9099
adb reverse tcp:8787 tcp:8787

flutter pub get --enforce-lockfile
(
  cd apps/mobile
  flutter build apk --debug \
    --dart-define=AUTHORITY_BASE_URL=http://127.0.0.1:8787 \
    --dart-define=FIREBASE_API_KEY=tier1-emulator-key \
    --dart-define=FIREBASE_APP_ID=1:1234567890:android:abcdef123456 \
    --dart-define=FIREBASE_MESSAGING_SENDER_ID=1234567890 \
    --dart-define=FIREBASE_PROJECT_ID=demo-board-game-local \
    --dart-define=FIRST_PLAYABLE_PRESET_ID=express \
    --dart-define=FIRST_PLAYABLE_COMMAND_ID_PREFIX=tier1-host \
    --dart-define=FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1 \
    --dart-define=FIREBASE_AUTH_EMULATOR_PORT=9099
)

adb install -r apps/mobile/build/app/outputs/flutter-apk/app-debug.apk
adb shell pm clear uy.romicaubarrere.board_mobile >/dev/null
adb shell monkey -p uy.romicaubarrere.board_mobile 1 >/dev/null
# The heavily loaded CI emulator can surface a stale Quickstep ANR above the
# app after Gradle finishes. Close only that system ANR, then explicitly
# foreground La Vuelta before asserting its semantics tree.
python3 tool/tier1_android_ui.py dismiss-anr
adb shell am start -W -n uy.romicaubarrere.board_mobile/.MainActivity >/dev/null

python3 tool/tier1_android_ui.py wait "Crear partida"
python3 tool/tier1_android_ui.py tap "Crear partida"
# Exercise durable recovery before the guest starts, so every later public
# snapshot watch is established against the restarted Authority process.
kill "$authority_pid"
wait "$authority_pid" || true
authority_pid=""
python3 tool/tier1_android_ui.py tap "Crear sala"
python3 tool/tier1_android_ui.py wait "Recuperá el estado confirmado"
python3 tool/tier1_android_ui.py screenshot "$ARTIFACTS/01-reconnect-required.png"
start_authority
python3 tool/tier1_android_ui.py tap "Reconciliar"
room_code="$(python3 tool/tier1_android_ui.py room-code)"
python3 tool/tier1_android_ui.py screenshot "$ARTIFACTS/02-created-room.png"
printf 'room_code=%s\n' "$room_code" >"$ARTIFACTS/smoke.txt"

(
  cd packages/backend_api
  dart run tool/tier1_guest_client.dart "$room_code"
) >"$ARTIFACTS/guest.log" 2>&1 &
guest_pid=$!
wait_log "$ARTIFACTS/guest.log" TIER1_GUEST_READY

python3 tool/tier1_android_ui.py tap "Actualizar lobby"
python3 tool/tier1_android_ui.py wait "Estoy lista"
python3 tool/tier1_android_ui.py tap "Estoy lista"
python3 tool/tier1_android_ui.py tap "Actualizar lobby"
python3 tool/tier1_android_ui.py screenshot "$ARTIFACTS/03-two-member-ready-lobby.png"
python3 tool/tier1_android_ui.py tap "Empezar partida"
starter="$(python3 tool/tier1_android_ui.py wait-any "Tu turno" "Esperando turno")"
python3 tool/tier1_android_ui.py screenshot "$ARTIFACTS/04-started-board.png"

if [[ "$starter" == "Tu turno" ]]; then
  python3 tool/tier1_android_ui.py tap "Tirar dados"
  python3 tool/tier1_android_ui.py wait "Decisión confirmada"
  python3 tool/tier1_android_ui.py screenshot "$ARTIFACTS/05-movement-property.png"
  python3 tool/tier1_android_ui.py tap "No comprar · abrir subasta"
fi
python3 tool/tier1_android_ui.py wait "Subasta autoritativa"
python3 tool/tier1_android_ui.py screenshot "$ARTIFACTS/06-auction.png"
# Whichever participant owns the first bid acts first. The guest helper waits
# for its authoritative turn; this tap waits until the host's Pass is exposed.
python3 tool/tier1_android_ui.py tap "Pasar"
wait_log "$ARTIFACTS/guest.log" TIER1_GUEST_AUCTION_PASS
wait "$guest_pid"
guest_pid=""
python3 tool/tier1_android_ui.py wait "RESULTADO CONFIRMADO"
python3 tool/tier1_android_ui.py screenshot "$ARTIFACTS/07-auction-result.png"

printf 'status=PASS\nvertical=Home B -> Create/Join -> Lobby -> Ready/Start -> Roll/reconnect -> movement -> Decline/Auction\n' >>"$ARTIFACTS/smoke.txt"
cat "$ARTIFACTS/smoke.txt"
