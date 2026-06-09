#!/usr/bin/env python3
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path


IGNORED_FOLDER_NAMES = {
    ".build",
    ".codex",
    ".git",
    ".swiftpm",
    "__pycache__",
    "build",
    "deriveddata",
    "dist",
    "node_modules",
    "tmp",
}


def main():
    payload = read_stdin_json()
    if not command_succeeded(payload):
        return 0

    command = first_string(
        payload,
        "cmd",
        "command",
        "shellCommand",
        "shell_command",
        "script",
    )
    if not command:
        return 0

    cwd = first_string(payload, "cwd", "workdir", "workingDirectory", "working_directory") or os.getcwd()
    source_host_id = first_string(payload, "sourceHostID", "sourceHostId", "source_host_id", "hostID", "hostId", "host_id")
    source_thread_id = first_string(
        payload,
        "sourceThreadID",
        "sourceThreadId",
        "source_thread_id",
        "threadID",
        "threadId",
        "thread_id",
        "sessionID",
        "sessionId",
        "session_id",
    )
    source_turn_id = first_string(payload, "sourceTurnID", "sourceTurnId", "source_turn_id", "turnID", "turnId", "turn_id")

    for folder_path in created_folder_roots(command, cwd):
        env = os.environ.copy()
        if source_host_id:
            env["MAPOFAGENTS_SOURCE_HOST_ID"] = source_host_id
            env["MAPOFAGENTS_CHILD_HOST_ID"] = source_host_id
        if source_thread_id:
            env["MAPOFAGENTS_SOURCE_THREAD_ID"] = source_thread_id
        if source_turn_id:
            env["MAPOFAGENTS_SOURCE_TURN_ID"] = source_turn_id
        env["MAPOFAGENTS_CHILD_FOLDER_PATH"] = folder_path
        env["MAPOFAGENTS_CHILD_TITLE"] = folder_title(folder_path)

        helper = Path(__file__).resolve().with_name("mapofagents-hook-event.sh")
        subprocess.run(
            [str(helper), "folder.created"],
            input=json.dumps(payload),
            text=True,
            env=env,
            check=False,
        )

    return 0


def read_stdin_json():
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        value = json.loads(raw)
    except Exception:
        return {"stdin": raw}
    return value if isinstance(value, dict) else {"payload": value}


def command_succeeded(value):
    if is_post_tool_use_command_payload(value) and has_key(value, "tool_response"):
        return True

    success = first_bool(value, "success", "succeeded", "ok")
    if success is not None:
        return success

    exit_code = first_int(
        value,
        "exitCode",
        "exit_code",
        "statusCode",
        "status_code",
        "returnCode",
        "return_code",
        "code",
    )
    if exit_code is not None:
        return exit_code == 0

    status = first_string(value, "status", "state", "result")
    if status:
        lowered = status.lower()
        if lowered in {"success", "succeeded", "completed", "complete", "ok"}:
            return True
        if lowered in {"failure", "failed", "error", "cancelled", "canceled"}:
            return False

    text = json.dumps(value, separators=(",", ":")).lower()
    if re.search(r"(process )?exited with code 0\b", text) or re.search(r"exit code[:= ]+0\b", text):
        return True
    if re.search(r"(process )?exited with code [1-9]\d*\b", text) or re.search(r"exit code[:= ]+[1-9]\d*\b", text):
        return False

    return False


def is_post_tool_use_command_payload(value):
    event_name = first_string(value, "hook_event_name", "hookEventName")
    return event_name == "PostToolUse"


def has_key(value, key):
    if isinstance(value, dict):
        if key in value:
            return True
        return any(has_key(child, key) for child in value.values())
    if isinstance(value, list):
        return any(has_key(child, key) for child in value)
    return False


def created_folder_roots(command, cwd):
    paths = mkdir_paths(command) + powershell_new_item_paths(command)
    result = []
    seen = set()
    for path in paths:
        normalized = normalized_path(path)
        if not normalized or normalized in seen:
            continue
        if path_inside_or_equal(normalized, normalized_path(cwd)):
            continue
        if folder_title(path).lower() in IGNORED_FOLDER_NAMES:
            continue
        seen.add(normalized)
        result.append(path)
    return result


def mkdir_paths(command):
    paths = []
    for segment in command_segments(command, "mkdir"):
        tokens = shell_tokens(segment)
        for token in tokens:
            if not token or token == "--" or token.startswith("-"):
                continue
            if is_absolute_path(token):
                paths.append(trim_path_token(token))
    return paths


def powershell_new_item_paths(command):
    paths = []
    for segment in command_segments(command, "New-Item"):
        tokens = shell_tokens(segment)
        lowered = [token.lower() for token in tokens]
        if "directory" not in lowered:
            continue
        for index, token in enumerate(tokens):
            lower = token.lower()
            if lower in {"-path", "-literalpath"} and index + 1 < len(tokens):
                candidate = trim_path_token(tokens[index + 1])
                if is_absolute_path(candidate):
                    paths.append(candidate)
            elif is_absolute_path(token):
                paths.append(trim_path_token(token))
    return paths


def command_segments(command, executable_name):
    pattern = re.compile(rf"(?i)(?:^|[^A-Za-z0-9_-]){re.escape(executable_name)}(?P<segment>[^\n;&|]*)")
    return [match.group("segment") for match in pattern.finditer(command)]


def shell_tokens(segment):
    try:
        return shlex.split(segment, posix=True)
    except ValueError:
        return segment.split()


def trim_path_token(value):
    trimmed = value.strip().strip("`'\"")
    return trimmed.rstrip(".,;:)]}")


def is_absolute_path(path):
    return path.startswith("/") or re.match(r"^[A-Za-z]:[\\/]", path) is not None


def normalized_path(path):
    if not path:
        return ""
    slash_path = path.replace("\\", "/").rstrip("/")
    if re.match(r"^[A-Za-z]:", slash_path):
        return slash_path.lower()
    return os.path.normpath(slash_path)


def path_inside_or_equal(path, root):
    if not path or not root:
        return False
    if path == root:
        return True
    root_with_slash = root if root.endswith("/") else root + "/"
    return path.startswith(root_with_slash)


def folder_title(path):
    slash_path = path.replace("\\", "/").rstrip("/")
    title = slash_path.rsplit("/", 1)[-1]
    return title or "folder"


def first_string(value, *keys):
    key_set = set(keys)
    if isinstance(value, dict):
        for key in keys:
            child = value.get(key)
            if isinstance(child, (str, int, float)) and str(child):
                return str(child)
        for key, child in value.items():
            if key in key_set and isinstance(child, (str, int, float)) and str(child):
                return str(child)
            found = first_string(child, *keys)
            if found:
                return found
    elif isinstance(value, list):
        for child in value:
            found = first_string(child, *keys)
            if found:
                return found
    elif isinstance(value, str):
        stripped = value.strip()
        if stripped.startswith("{") and stripped.endswith("}"):
            try:
                return first_string(json.loads(stripped), *keys)
            except Exception:
                return None
    return None


def first_bool(value, *keys):
    if isinstance(value, dict):
        for key in keys:
            child = value.get(key)
            if isinstance(child, bool):
                return child
        for child in value.values():
            found = first_bool(child, *keys)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = first_bool(child, *keys)
            if found is not None:
                return found
    return None


def first_int(value, *keys):
    if isinstance(value, dict):
        for key in keys:
            child = value.get(key)
            parsed = parse_int(child)
            if parsed is not None:
                return parsed
        for child in value.values():
            found = first_int(child, *keys)
            if found is not None:
                return found
    elif isinstance(value, list):
        for child in value:
            found = first_int(child, *keys)
            if found is not None:
                return found
    return None


def parse_int(value):
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return None
    return None


if __name__ == "__main__":
    raise SystemExit(main())
