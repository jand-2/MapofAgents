#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook_script="$repo_root/script/mapofagents-post-tool-use-hook.py"
hooks_file="${CODEX_HOME:-$HOME/.codex}/hooks.json"

if [ ! -f "$hook_script" ]; then
  echo "Missing hook script: $hook_script" >&2
  exit 1
fi

mkdir -p "$(dirname "$hooks_file")"

/usr/bin/python3 - "$hooks_file" "$hook_script" <<'PY'
import json
import sys
from pathlib import Path

hooks_file = Path(sys.argv[1])
hook_script = Path(sys.argv[2]).resolve()
command = f'/usr/bin/python3 "{hook_script}"'
matcher = "Bash|exec_command|shell|functions.exec_command"
entry = {
    "matcher": matcher,
    "hooks": [
        {
            "type": "command",
            "command": command,
            "timeout": 10,
            "statusMessage": "Checking folder creation",
        }
    ],
}

if hooks_file.exists():
    data = json.loads(hooks_file.read_text(encoding="utf-8"))
else:
    data = {}

hooks = data.setdefault("hooks", {})
post_tool_use = hooks.setdefault("PostToolUse", [])

for group in post_tool_use:
    for hook in group.get("hooks", []):
        if hook.get("command") == command:
            hook.update(entry["hooks"][0])
            group["matcher"] = group.get("matcher") or matcher
            break
    else:
        continue
    break
else:
    post_tool_use.append(entry)

hooks_file.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY

echo "Installed MapofAgents PostToolUse hook in $hooks_file"
echo "Run /hooks in Codex to review and trust the hook if prompted."
