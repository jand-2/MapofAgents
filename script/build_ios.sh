#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-sim}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/mapofagents.xcodeproj"
SCHEME="mapofagents-iOS"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData-iOS"
BUNDLE_ID="dev.mapofagents.ios"

cd "$ROOT_DIR"

require_xcode() {
  if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
    cat >&2 <<'MSG'
Full Xcode is required for iOS builds and iPhone install.

Install Xcode, then select it:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
MSG
    exit 1
  fi
}

ensure_project() {
  require_xcode
  if [[ ! -d "$PROJECT_PATH" ]]; then
    "$ROOT_DIR/script/ios_project.sh" >/dev/null
  fi
}

build_sim() {
  ensure_project
  local destination="${MAPOFAGENTS_SIM_DESTINATION:-}"
  if [[ -z "$destination" ]]; then
    local sim_name="${MAPOFAGENTS_SIM_NAME:-}"
    if [[ -z "$sim_name" ]]; then
      local candidates=("iPhone 17 Pro" "iPhone 16 Pro" "iPhone 15 Pro")
      for candidate in "${candidates[@]}"; do
        if /usr/bin/xcrun simctl list devices available | /usr/bin/grep -q "$candidate"; then
          sim_name="$candidate"
          break
        fi
      done
    fi
    if [[ -n "$sim_name" ]]; then
      destination="platform=iOS Simulator,name=$sim_name"
    else
      destination="generic/platform=iOS Simulator"
    fi
  fi

  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "$destination" \
    build
}

detect_development_team() {
  /usr/bin/defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | /usr/bin/awk '/teamID =/ { value=$3; gsub(/[;[:space:]]/, "", value); print value; exit }'
}

build_device() {
  ensure_project
  local team_args=()
  local development_team="${MAPOFAGENTS_DEVELOPMENT_TEAM:-}"
  if [[ -z "$development_team" ]]; then
    development_team="$(detect_development_team || true)"
  fi
  if [[ -n "$development_team" ]]; then
    echo "Using Xcode development team $development_team"
    team_args+=(DEVELOPMENT_TEAM="$development_team")
  fi
  local destination="${MAPOFAGENTS_DEVICE_DESTINATION:-}"
  if [[ -z "$destination" && -n "${MAPOFAGENTS_DEVICE_ID:-}" ]]; then
    destination="id=$MAPOFAGENTS_DEVICE_ID"
  fi
  if [[ -z "$destination" ]]; then
    destination="generic/platform=iOS"
  fi

  /usr/bin/xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "$destination" \
    -allowProvisioningUpdates \
    ${team_args[@]+"${team_args[@]}"} \
    build
}

detect_single_device_id() {
  if ! /usr/bin/xcrun --find devicectl >/dev/null 2>&1; then
    return 1
  fi

  local json_path
  json_path="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mapofagents-devices.XXXXXX.json")"
  if ! /usr/bin/xcrun devicectl list devices --json-output "$json_path" >/dev/null 2>&1; then
    /bin/rm -f "$json_path"
    return 1
  fi

  /usr/bin/python3 - "$json_path" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

devices = payload.get("result", {}).get("devices", [])
ios_devices = []
for device in devices:
    hardware = device.get("hardwareProperties", {})
    platform = str(hardware.get("platform", "")).lower()
    device_type = str(hardware.get("deviceType", "")).lower()
    identifier = device.get("identifier") or hardware.get("udid")
    if identifier and (platform == "ios" or device_type == "iphone"):
        ios_devices.append(str(identifier))

if len(ios_devices) == 1:
    print(ios_devices[0])
    sys.exit(0)

sys.exit(1)
PY
  local result=$?
  /bin/rm -f "$json_path"
  return "$result"
}

install_device() {
  if ! /usr/bin/xcrun --find devicectl >/dev/null 2>&1; then
    echo "devicectl was not found. Install/select full Xcode." >&2
    exit 1
  fi

  local device_id="${MAPOFAGENTS_DEVICE_ID:-}"
  if [[ -z "$device_id" ]]; then
    device_id="$(detect_single_device_id || true)"
  fi

  if [[ -z "$device_id" ]]; then
    cat >&2 <<'MSG'
Connect and unlock one trusted iPhone, or set MAPOFAGENTS_DEVICE_ID to the identifier shown by:
  xcrun devicectl list devices
MSG
    /usr/bin/xcrun devicectl list devices || true
    exit 1
  fi

  MAPOFAGENTS_DEVICE_ID="$device_id" build_device

  local app_path="$DERIVED_DATA_PATH/Build/Products/Debug-iphoneos/mapofagents.app"
  if [[ ! -d "$app_path" ]]; then
    echo "Expected built app at $app_path" >&2
    exit 1
  fi

  /usr/bin/xcrun devicectl device install app --device "$device_id" "$app_path"
  local launch_args=(device process launch --device "$device_id" --terminate-existing)
  if [[ -n "${MAPOFAGENTS_PAIRING_URL:-}" ]]; then
    launch_args+=(--payload-url "$MAPOFAGENTS_PAIRING_URL")
  fi
  launch_args+=("$BUNDLE_ID")
  /usr/bin/xcrun devicectl "${launch_args[@]}"
}

case "$MODE" in
  sim|--sim)
    build_sim
    ;;
  device|--device)
    build_device
    ;;
  install|--install)
    install_device
    ;;
  *)
    echo "usage: $0 [sim|device|install]" >&2
    exit 2
    ;;
esac
