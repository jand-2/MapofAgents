#!/usr/bin/env bash
set -euo pipefail

# Hook payloads can contain tool arguments, command output, and credentials. Keep
# the on-disk event stream private even when the caller has a permissive umask.
umask 077

event_name="${1:-${CODEX_HOOK_EVENT:-turn-ended}}"
event_file="${MAPOFAGENTS_HOOK_EVENT_FILE:-$HOME/.codex/mapofagents/hook-events.jsonl}"

/usr/bin/python3 - "$event_name" "$event_file" 3<&0 <<'PY'
import datetime
import fcntl
import json
import math
import os
import re
import stat
import sys
import uuid


def bounded_integer(name, default, minimum, maximum):
    try:
        value = int(os.environ.get(name, str(default)))
    except (TypeError, ValueError):
        value = default
    return min(maximum, max(minimum, value))


def enabled(name):
    return os.environ.get(name, "").strip().lower() in {"1", "true", "yes", "on"}


event_name = sys.argv[1] if len(sys.argv) > 1 else "turn-ended"
event_file = sys.argv[2]
event_max_bytes = bounded_integer("MAPOFAGENTS_HOOK_EVENT_MAX_BYTES", 1024 * 1024, 4096, 64 * 1024 * 1024)
rotation_count = bounded_integer("MAPOFAGENTS_HOOK_EVENT_ROTATIONS", 3, 1, 10)
raw_max_bytes = bounded_integer("MAPOFAGENTS_HOOK_RAW_MAX_BYTES", 16 * 1024, 256, 64 * 1024)
raw_max_bytes = min(raw_max_bytes, max(256, event_max_bytes // 2))
input_max_bytes = max(256 * 1024, raw_max_bytes)

with os.fdopen(3, "rb", closefd=True) as payload_stream:
    raw_input = payload_stream.read(input_max_bytes + 1)
input_truncated = len(raw_input) > input_max_bytes
if input_truncated:
    raw_input = raw_input[:input_max_bytes]
stdin_payload = raw_input.decode("utf-8", errors="replace")

payload = {}
if stdin_payload.strip():
    try:
        payload = json.loads(stdin_payload)
    except Exception:
        payload = {"stdin": stdin_payload}


def limited(value, maximum=1024):
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if len(text) <= maximum:
        return text
    return text[: maximum - 1] + "…"


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


def first_string(*keys, maximum=1024):
    key_set = set(keys)
    for key in keys:
        value = os.environ.get(key)
        if value:
            return limited(value, maximum) if maximum is not None else str(value).strip() or None
    found = find_key(payload, key_set)
    return limited(found, maximum) if maximum is not None else (str(found).strip() if found else None)


def nested_id(*container_keys):
    if not isinstance(payload, dict):
        return None
    for key in container_keys:
        child = payload.get(key)
        if isinstance(child, dict):
            value = child.get("id")
            if isinstance(value, (str, int, float)) and str(value):
                return limited(value, 256)
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
    maximum=256,
) or nested_id("thread", "session")
turn_id = first_string(
    "CODEX_TURN_ID",
    "TURN_ID",
    "turnId",
    "turnID",
    "turn_id",
    maximum=256,
) or nested_id("turn", "rollout")
host_id = first_string(
    "MAPOFAGENTS_HOST_ID",
    "HOST_ID",
    "hostID",
    "hostId",
    "host_id",
    maximum=256,
)
source_host_id = first_string(
    "MAPOFAGENTS_SOURCE_HOST_ID",
    "SOURCE_HOST_ID",
    "sourceHostID",
    "sourceHostId",
    "source_host_id",
    maximum=256,
) or host_id
source_thread_id = first_string(
    "MAPOFAGENTS_SOURCE_THREAD_ID",
    "SOURCE_THREAD_ID",
    "sourceThreadID",
    "sourceThreadId",
    "source_thread_id",
    maximum=256,
) or thread_id
source_turn_id = first_string(
    "MAPOFAGENTS_SOURCE_TURN_ID",
    "SOURCE_TURN_ID",
    "sourceTurnID",
    "sourceTurnId",
    "source_turn_id",
    maximum=256,
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
    maximum=256,
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
    maximum=256,
)
child_cwd = first_string(
    "MAPOFAGENTS_CHILD_CWD",
    "CHILD_CWD",
    "childCWD",
    "childCwd",
    "child_cwd",
    "cwd",
    maximum=None,
)
child_folder_path = first_string(
    "MAPOFAGENTS_CHILD_FOLDER_PATH",
    "MAPOFAGENTS_FOLDER_PATH",
    "CHILD_FOLDER_PATH",
    "FOLDER_PATH",
    "childFolderPath",
    "child_folder_path",
    "folderPath",
    "folder_path",
    "path",
    maximum=None,
) or child_cwd
child_title = first_string(
    "MAPOFAGENTS_CHILD_TITLE",
    "CHILD_TITLE",
    "childTitle",
    "child_title",
    "title",
    "name",
    maximum=None,
)
child_kind = first_string(
    "MAPOFAGENTS_CHILD_KIND",
    "CHILD_KIND",
    "childKind",
    "child_kind",
    "kind",
    maximum=64,
)


SENSITIVE_KEY_PARTS = (
    "apikey",
    "authorization",
    "bearer",
    "cookie",
    "credential",
    "password",
    "passphrase",
    "privatekey",
    "secret",
    "token",
)


def sensitive_key(key):
    normalized = re.sub(r"[^a-z0-9]", "", str(key).lower())
    return any(part in normalized for part in SENSITIVE_KEY_PARTS)


def redact_string(value):
    value = re.sub(
        r"-----BEGIN [^-\r\n]*PRIVATE KEY-----.*?(?:-----END [^-\r\n]*PRIVATE KEY-----|\Z)",
        "[REDACTED PRIVATE KEY]",
        value,
        flags=re.IGNORECASE | re.DOTALL,
    )
    value = re.sub(r"(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]+", r"\1[REDACTED]", value)
    value = re.sub(
        r"(?i)\b(api[_-]?key|authorization|cookie|password|passphrase|secret|token)"
        r"(\s*[:=]\s*)(['\"]?)[^\s,'\";&]+\3",
        r"\1\2[REDACTED]",
        value,
    )
    value = re.sub(r"\b(ghp_|github_pat_|sk-)[A-Za-z0-9_-]+", r"\1[REDACTED]", value)
    value = re.sub(
        r"(?i)\b((?:https?|wss?|ssh)://[^/\s:@]+:)[^@\s/]+@",
        r"\1[REDACTED]@",
        value,
    )
    return value


def redacted_limited(value, maximum):
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    return limited(redact_string(text), maximum)


def redact(value, depth=0):
    if depth >= 12:
        return "[TRUNCATED DEPTH]"
    if isinstance(value, dict):
        result = {}
        for index, (key, child) in enumerate(value.items()):
            if index >= 100:
                result["__truncated__"] = True
                break
            result[str(key)] = "[REDACTED]" if sensitive_key(key) else redact(child, depth + 1)
        return result
    if isinstance(value, list):
        result = [redact(child, depth + 1) for child in value[:100]]
        if len(value) > 100:
            result.append("[TRUNCATED ITEMS]")
        return result
    if isinstance(value, str):
        return limited(redact_string(value), 16384)
    if isinstance(value, float) and not math.isfinite(value):
        return None
    return value


def add_bounded_raw(record):
    if not enabled("MAPOFAGENTS_HOOK_CAPTURE_RAW") or not stdin_payload.strip():
        return
    redacted = redact(payload)
    encoded = json.dumps(redacted, ensure_ascii=False, allow_nan=False, separators=(",", ":")).encode("utf-8")
    if len(encoded) <= raw_max_bytes and not input_truncated:
        record["raw"] = redacted
        return

    preview = encoded[: max(0, raw_max_bytes - 128)].decode("utf-8", errors="ignore")
    record["raw"] = {"preview": preview, "truncated": True}
    record["rawTruncated"] = True


def base_record(event_type, method, summary):
    configured_summary = os.environ.get("MAPOFAGENTS_HOOK_SUMMARY") or summary
    return {
        "id": limited(os.environ.get("MAPOFAGENTS_HOOK_EVENT_ID"), 256) or str(uuid.uuid4()),
        "source": "codex-hook",
        "type": event_type,
        "method": method,
        "summary": redacted_limited(configured_summary, 1024),
        "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z"),
    }


normalized = event_name.lower().replace("_", "-").replace("/", "-")
if normalized in ("thread.created", "thread-created", "thread-create") or normalized.endswith("-thread-created"):
    thread_summary = f"Created {child_title}" if child_title else "Created thread"
    record = base_record("thread.created", "thread/created", thread_summary)
    record["kind"] = child_kind if child_kind in ("thread", "subagent") else "thread"
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
        record["cwd"] = redacted_limited(child_cwd, 1024)
    if child_title:
        record["title"] = redacted_limited(child_title, 512)
    add_bounded_raw(record)
elif normalized in ("folder.created", "folder-created", "folder-create", "workspace-created", "workspace-create", "project-created", "project-create") or normalized.endswith("-folder-created"):
    folder_summary = f"Created folder {child_title}" if child_title else "Created folder"
    record = base_record("folder.created", "folder/created", folder_summary)
    if source_host_id:
        record["sourceHostID"] = source_host_id
    if source_thread_id:
        record["sourceThreadID"] = source_thread_id
    if source_turn_id:
        record["sourceTurnID"] = source_turn_id
    if child_host_id or source_host_id:
        record["childHostID"] = child_host_id or source_host_id
    if child_folder_path:
        record["folderPath"] = redacted_limited(child_folder_path, 1024)
    if child_title:
        record["title"] = redacted_limited(child_title, 512)
    add_bounded_raw(record)
else:
    if "fail" in normalized or "error" in normalized:
        event_type = "failed"
        method = "hook/failed"
        summary = "Turn failed"
    elif "approval" in normalized or "input" in normalized:
        event_type = "needs.input"
        method = "hook/needsInput"
        summary = "Needs input"
    elif "start" in normalized:
        event_type = "turn.started"
        method = "turn/started"
        summary = "Turn started"
    else:
        event_type = "turn.completed"
        method = "turn/completed"
        summary = "Turn completed"

    record = base_record(event_type, method, summary)
    if host_id:
        record["hostID"] = host_id
    if thread_id:
        record["threadID"] = thread_id
    if turn_id:
        record["turnID"] = turn_id
    add_bounded_raw(record)


def encoded_record(value):
    line = (json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n").encode("utf-8")
    if len(line) <= event_max_bytes:
        return line

    # A single event must never defeat the stream cap. Raw capture is the only
    # intentionally bulky field, so discard it first and preserve the envelope.
    value.pop("raw", None)
    value["rawTruncated"] = True
    line = (json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n").encode("utf-8")
    if len(line) <= event_max_bytes:
        return line

    for key in ("summary", "title", "cwd", "folderPath"):
        if key in value:
            value[key] = limited(value[key], 256)
    return (json.dumps(value, ensure_ascii=False, allow_nan=False, separators=(",", ":")) + "\n").encode("utf-8")


def open_private(path, flags):
    no_follow = getattr(os, "O_NOFOLLOW", 0)
    close_on_exec = getattr(os, "O_CLOEXEC", 0)
    descriptor = os.open(path, flags | no_follow | close_on_exec, 0o600)
    os.fchmod(descriptor, 0o600)
    return descriptor


def regular_file_size(path):
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        return 0
    if not stat.S_ISREG(info.st_mode):
        raise RuntimeError("hook event path must be a regular file")
    return info.st_size


def rotate_files():
    oldest = f"{event_file}.{rotation_count}"
    try:
        os.unlink(oldest)
    except FileNotFoundError:
        pass
    for index in range(rotation_count - 1, 0, -1):
        source = f"{event_file}.{index}"
        destination = f"{event_file}.{index + 1}"
        if os.path.lexists(source):
            os.replace(source, destination)
            if stat.S_ISREG(os.lstat(destination).st_mode):
                os.chmod(destination, 0o600)
    if os.path.lexists(event_file):
        if not stat.S_ISREG(os.lstat(event_file).st_mode):
            raise RuntimeError("hook event path must be a regular file")
        os.replace(event_file, f"{event_file}.1")
        os.chmod(f"{event_file}.1", 0o600)


line = encoded_record(record)
directory = os.path.dirname(os.path.abspath(event_file))
directory_existed = os.path.isdir(directory)
os.makedirs(directory, mode=0o700, exist_ok=True)
if not directory_existed or os.path.basename(directory) == "mapofagents":
    os.chmod(directory, 0o700)

lock_descriptor = open_private(event_file + ".lock", os.O_WRONLY | os.O_APPEND | os.O_CREAT)
try:
    fcntl.flock(lock_descriptor, fcntl.LOCK_EX)
    current_size = regular_file_size(event_file)
    if current_size > 0 and current_size + len(line) > event_max_bytes:
        rotate_files()

    event_descriptor = open_private(event_file, os.O_WRONLY | os.O_APPEND | os.O_CREAT)
    try:
        view = memoryview(line)
        while view:
            written = os.write(event_descriptor, view)
            view = view[written:]
    finally:
        os.close(event_descriptor)
finally:
    fcntl.flock(lock_descriptor, fcntl.LOCK_UN)
    os.close(lock_descriptor)
PY
