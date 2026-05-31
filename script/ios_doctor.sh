#!/usr/bin/env bash
set -euo pipefail

status=0

check() {
  local label="$1"
  shift
  if "$@" >/tmp/mapofagents-ios-doctor.out 2>&1; then
    printf '✓ %s\n' "$label"
  else
    printf '✗ %s\n' "$label"
    sed 's/^/  /' /tmp/mapofagents-ios-doctor.out
    status=1
  fi
}

check "Full Xcode selected" /usr/bin/xcodebuild -version
check "simctl available" /usr/bin/xcrun --find simctl
check "devicectl available" /usr/bin/xcrun --find devicectl
if command -v xcodegen >/dev/null 2>&1 || [[ -x ".generated/XcodeGen/.build/release/xcodegen" ]]; then
  printf '✓ XcodeGen available\n'
else
  printf '✗ XcodeGen available\n'
  printf '  Install with brew, or build .generated/XcodeGen/.build/release/xcodegen.\n'
  status=1
fi

if [[ -n "${MAPOFAGENTS_DEVELOPMENT_TEAM:-}" ]]; then
  printf '✓ MAPOFAGENTS_DEVELOPMENT_TEAM set\n'
else
  printf '• MAPOFAGENTS_DEVELOPMENT_TEAM not set; device signing will ask Xcode for a team or fail.\n'
fi

if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -q "valid identities found"; then
  identity_count="$(/usr/bin/security find-identity -v -p codesigning | /usr/bin/sed -n 's/.*\([0-9][0-9]*\) valid identities found.*/\1/p' | /usr/bin/tail -n 1)"
  if [[ "${identity_count:-0}" == "0" ]]; then
    printf '• No valid code-signing identities found; sign into Xcode and create/download an Apple Development certificate before installing on iPhone.\n'
  else
    printf '✓ Code-signing identities available\n'
  fi
else
  printf '• Could not inspect code-signing identities.\n'
fi

if /usr/bin/xcrun --find devicectl >/dev/null 2>&1; then
  echo
  /usr/bin/xcrun devicectl list devices || true
  device_json="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/mapofagents-doctor-devices.XXXXXX.json")"
  if /usr/bin/xcrun devicectl list devices --json-output "$device_json" >/dev/null 2>&1; then
    /usr/bin/python3 - "$device_json" <<'PY'
import json
import subprocess
import sys
import tempfile
from pathlib import Path

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    devices = json.load(handle).get("result", {}).get("devices", [])

for device in devices:
    hardware = device.get("hardwareProperties", {})
    platform = str(hardware.get("platform", "")).lower()
    device_type = str(hardware.get("deviceType", "")).lower()
    identifier = device.get("identifier")
    name = device.get("deviceProperties", {}).get("name") or hardware.get("marketingName") or identifier
    if not identifier or (platform != "ios" and device_type != "iphone"):
        continue

    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as temp:
        details_path = temp.name
    try:
        subprocess.run(
            ["xcrun", "devicectl", "device", "info", "details", "--device", identifier, "--json-output", details_path],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        with open(details_path, "r", encoding="utf-8") as details_file:
            details = json.load(details_file)
        properties = details.get("result", {}).get("deviceProperties", {})
        developer_mode = properties.get("developerModeStatus")
        if developer_mode == "enabled":
            print(f"✓ Developer Mode enabled on {name}")
        elif developer_mode:
            print(f"• Developer Mode {developer_mode} on {name}; enable it in iPhone Settings > Privacy & Security before installing.")
        else:
            print(f"• Could not determine Developer Mode status for {name}.")
    finally:
        Path(details_path).unlink(missing_ok=True)
PY
  fi
  /bin/rm -f "$device_json"
fi

rm -f /tmp/mapofagents-ios-doctor.out
exit "$status"
