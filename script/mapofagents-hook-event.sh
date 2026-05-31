#!/usr/bin/env bash
set -euo pipefail

event_name="${1:-${CODEX_HOOK_EVENT:-turn-ended}}"
if [ -t 0 ]; then
  stdin_payload=""
else
  stdin_payload="$(cat || true)"
fi
event_file="${MAPOFAGENTS_HOOK_EVENT_FILE:-$HOME/.codex/mapofagents/hook-events.jsonl}"

mkdir -p "$(dirname "$event_file")"

/usr/bin/python3 - "$event_name" "$stdin_payload" "$event_file" <<'PY'
import datetime
import json
import os
import sys
import uuid

event_name = sys.argv[1] if len(sys.argv) > 1 else "turn-ended"
stdin_payload = sys.argv[2] if len(sys.argv) > 2 else ""
event_file = sys.argv[3]

payload = {}
if stdin_payload.strip():
    try:
        payload = json.loads(stdin_payload)
    except Exception:
        payload = {"stdin": stdin_payload}

def find_key(value, keys):
    if isinstance(value, dict):
        for key, child in value.items():
            if key in keys and isinstance(child, (str, int, float)) and str(child):
                return str(child)
        for child in value.values():
            found = find_key(child, keys)
            if found:
                return found
    if isinstance(value, list):
        for child in value:
            found = find_key(child, keys)
            if found:
                return found
    return None

def first_string(*keys):
    key_set = set(keys)
    for key in keys:
        value = os.environ.get(key)
        if value:
            return value
    return find_key(payload, key_set)

def nested_id(*container_keys):
    if not isinstance(payload, dict):
        return None
    for key in container_keys:
        child = payload.get(key)
        if isinstance(child, dict):
            value = child.get("id")
            if isinstance(value, (str, int, float)) and str(value):
                return str(value)
    return None

thread_id = first_string(
    "CODEX_THREAD_ID",
    "CODEX_SESSION_ID",
    "THREAD_ID",
    "SESSION_ID",
    "threadId",
    "threadID",
    "thread_id",
    "sessionId",
    "sessionID",
    "session_id",
) or nested_id("thread", "session")
turn_id = first_string(
    "CODEX_TURN_ID",
    "TURN_ID",
    "turnId",
    "turnID",
    "turn_id",
) or nested_id("turn", "rollout")
host_id = os.environ.get("MAPOFAGENTS_HOST_ID")
source_host_id = first_string("MAPOFAGENTS_SOURCE_HOST_ID", "SOURCE_HOST_ID", "sourceHostID", "sourceHostId", "source_host_id") or host_id
source_thread_id = first_string(
    "MAPOFAGENTS_SOURCE_THREAD_ID",
    "SOURCE_THREAD_ID",
    "sourceThreadID",
    "sourceThreadId",
    "source_thread_id",
) or thread_id
source_turn_id = first_string(
    "MAPOFAGENTS_SOURCE_TURN_ID",
    "SOURCE_TURN_ID",
    "sourceTurnID",
    "sourceTurnId",
    "source_turn_id",
) or turn_id
child_host_id = first_string(
    "MAPOFAGENTS_CHILD_HOST_ID",
    "CHILD_HOST_ID",
    "childHostID",
    "childHostId",
    "child_host_id",
    "targetHostID",
    "targetHostId",
    "target_host_id",
)
child_thread_id = first_string(
    "MAPOFAGENTS_CHILD_THREAD_ID",
    "CHILD_THREAD_ID",
    "childThreadID",
    "childThreadId",
    "child_thread_id",
    "targetThreadID",
    "targetThreadId",
    "target_thread_id",
)
child_cwd = first_string(
    "MAPOFAGENTS_CHILD_CWD",
    "CHILD_CWD",
    "childCWD",
    "childCwd",
    "child_cwd",
    "cwd",
)
child_title = first_string(
    "MAPOFAGENTS_CHILD_TITLE",
    "CHILD_TITLE",
    "childTitle",
    "child_title",
    "title",
    "name",
)
child_kind = first_string(
    "MAPOFAGENTS_CHILD_KIND",
    "CHILD_KIND",
    "childKind",
    "child_kind",
    "kind",
)

normalized = event_name.lower().replace("_", "-").replace("/", "-")
if normalized in ("thread.created", "thread-created", "thread-create") or normalized.endswith("-thread-created"):
    record = {
        "id": os.environ.get("MAPOFAGENTS_HOOK_EVENT_ID") or str(uuid.uuid4()),
        "source": "codex-hook",
        "type": "thread.created",
        "method": "thread/created",
        "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
        "kind": child_kind or "thread",
    }
    if source_host_id:
        record["sourceHostID"] = source_host_id
    if source_thread_id:
        record["sourceThreadID"] = source_thread_id
    if source_turn_id:
        record["sourceTurnID"] = source_turn_id
    if child_host_id or source_host_id:
        record["childHostID"] = child_host_id or source_host_id
    if child_thread_id:
        record["childThreadID"] = child_thread_id
    if child_cwd:
        record["cwd"] = child_cwd
    if child_title:
        record["title"] = child_title
    if stdin_payload.strip():
        record["raw"] = payload

    with open(event_file, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, separators=(",", ":")) + "\n")
    raise SystemExit(0)

if "fail" in normalized or "error" in normalized:
    kind = "failed"
    method = "hook/failed"
    summary = "Turn failed"
elif "approval" in normalized or "input" in normalized:
    kind = "needsInput"
    method = "hook/needsInput"
    summary = "Needs input"
elif "start" in normalized:
    kind = "turnStarted"
    method = "turn/started"
    summary = "Turn started"
else:
    kind = "turnCompleted"
    method = "turn/completed"
    summary = "Turn completed"

record = {
    "id": os.environ.get("MAPOFAGENTS_HOOK_EVENT_ID") or str(uuid.uuid4()),
    "source": "codex-hook",
    "event": event_name,
    "kind": kind,
    "method": method,
    "summary": os.environ.get("MAPOFAGENTS_HOOK_SUMMARY") or summary,
    "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    "cwd": os.getcwd(),
}
if host_id:
    record["hostID"] = host_id
if thread_id:
    record["threadID"] = thread_id
if turn_id:
    record["turnID"] = turn_id
if stdin_payload.strip():
    record["raw"] = payload

with open(event_file, "a", encoding="utf-8") as handle:
    handle.write(json.dumps(record, separators=(",", ":")) + "\n")
PY
