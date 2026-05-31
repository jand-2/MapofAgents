#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INTERVAL_SECONDS="${MAPOFAGENTS_WAIT_INTERVAL:-5}"
TIMEOUT_SECONDS="${MAPOFAGENTS_WAIT_TIMEOUT:-0}"
STARTED_AT="$(/bin/date +%s)"

cd "$ROOT_DIR"

has_codesigning_identity() {
  local count
  count="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/sed -n 's/.*\([0-9][0-9]*\) valid identities found.*/\1/p' | /usr/bin/tail -n 1)"
  [[ "${count:-0}" != "0" ]]
}

visible_ios_device_count() {
  local json_path
  json_path="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mapofagents-wait-devices.XXXXXX.json")"
  if ! /usr/bin/xcrun devicectl list devices --json-output "$json_path" >/dev/null 2>&1; then
    /bin/rm -f "$json_path"
    echo 0
    return
  fi

  /usr/bin/python3 - "$json_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

count = 0
for device in payload.get("result", {}).get("devices", []):
    hardware = device.get("hardwareProperties", {})
    platform = str(hardware.get("platform", "")).lower()
    device_type = str(hardware.get("deviceType", "")).lower()
    if platform == "ios" or device_type == "iphone":
        count += 1
print(count)
PY
  /bin/rm -f "$json_path"
}

while true; do
  device_count="$(visible_ios_device_count)"
  identity_status="missing"
  if has_codesigning_identity; then
    identity_status="ready"
  fi

  if [[ "$device_count" != "0" && ( "$identity_status" == "ready" || -n "${MAPOFAGENTS_DEVELOPMENT_TEAM:-}" ) ]]; then
    echo "iPhone and signing inputs are visible; building, installing, and launching mapofagents."
    exec "$ROOT_DIR/script/build_ios.sh" install
  fi

  echo "Waiting for iPhone/signing: devices=$device_count, signing=$identity_status, team=${MAPOFAGENTS_DEVELOPMENT_TEAM:-unset}"

  if [[ "$TIMEOUT_SECONDS" != "0" ]]; then
    now="$(/bin/date +%s)"
    elapsed=$((now - STARTED_AT))
    if (( elapsed >= TIMEOUT_SECONDS )); then
      cat >&2 <<'MSG'
Timed out waiting for iPhone install prerequisites.

Open Xcode, sign into your Apple ID, create/download an Apple Development certificate,
then connect, unlock, and trust one iPhone.
MSG
      exit 1
    fi
  fi

  /bin/sleep "$INTERVAL_SECONDS"
done
