#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/mapofagents.xcodeproj"

cd "$ROOT_DIR"

if ! /usr/bin/xcodebuild -version >/dev/null 2>&1; then
  cat >&2 <<'MSG'
Full Xcode is required for iOS project generation/builds.

Install Xcode, then select it:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
MSG
  exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  LOCAL_XCODEGEN="$ROOT_DIR/.generated/XcodeGen/.build/release/xcodegen"
  if [[ -x "$LOCAL_XCODEGEN" ]]; then
    XCODEGEN="$LOCAL_XCODEGEN"
  else
    cat >&2 <<'MSG'
XcodeGen is required to generate mapofagents.xcodeproj from project.yml.

Install it with:
  brew install xcodegen

Or build the repo-local copy:
  git clone --depth 1 https://github.com/yonaskolb/XcodeGen.git .generated/XcodeGen
  (cd .generated/XcodeGen && swift build -c release --product xcodegen)
MSG
    exit 1
  fi
else
  XCODEGEN="$(command -v xcodegen)"
fi

"$XCODEGEN" generate --spec "$ROOT_DIR/project.yml"
echo "$PROJECT_PATH"
