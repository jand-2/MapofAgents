#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MINIMUM_LINE_COVERAGE="${MAPOFAGENTS_MIN_CORE_LINE_COVERAGE:-50}"

cd "$ROOT_DIR"

swift build --configuration release \
  -Xswiftc -warnings-as-errors \
  -Xswiftc -strict-concurrency=complete
swift test --enable-code-coverage

coverage_path="$(swift test --show-codecov-path)"
if [[ ! -s "$coverage_path" ]]; then
  echo "SwiftPM did not produce a coverage report at $coverage_path" >&2
  exit 1
fi

python3 - "$coverage_path" "$MINIMUM_LINE_COVERAGE" <<'PY'
import json
import pathlib
import sys

coverage_path = pathlib.Path(sys.argv[1])
minimum = float(sys.argv[2])
with coverage_path.open("r", encoding="utf-8") as handle:
    payload = json.load(handle)

try:
    files = payload["data"][0]["files"]
except (KeyError, IndexError, TypeError) as error:
    raise SystemExit(f"Malformed Swift coverage report: {error}")

core_files = [item for item in files if "/Sources/MapofAgentsCore/" in item["filename"].replace("\\", "/")]
if not core_files:
    raise SystemExit("Swift coverage report contains no MapofAgentsCore source files")

line_count = sum(item["summary"]["lines"]["count"] for item in core_files)
covered = sum(item["summary"]["lines"]["covered"] for item in core_files)
if line_count <= 0:
    raise SystemExit("MapofAgentsCore coverage report contains no executable lines")

percent = covered * 100.0 / line_count
print(
    f"MapofAgentsCore line coverage: {covered}/{line_count} "
    f"({percent:.2f}%; required {minimum:.2f}%)"
)
if percent < minimum:
    raise SystemExit("MapofAgentsCore line coverage is below the required baseline")
PY
