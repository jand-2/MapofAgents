#!/usr/bin/env python3
"""Run dependency-free syntax checks over every tracked repository artifact."""

from __future__ import annotations

import argparse
import ast
import json
import pathlib
import plistlib
import shutil
import subprocess
import sys
from typing import Any, Dict, Iterable, List


class RepositoryValidationError(Exception):
    pass


def tracked_files(root: pathlib.Path) -> List[pathlib.Path]:
    process = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=str(root),
        check=True,
        stdout=subprocess.PIPE,
    )
    paths = [root / item.decode("utf-8") for item in process.stdout.split(b"\0") if item]
    return [path for path in paths if path.is_file()]


def validate_json(path: pathlib.Path) -> None:
    def reject_duplicates(pairs: Iterable[Any]) -> Dict[str, Any]:
        result: Dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise RepositoryValidationError(f"{path}: duplicate JSON key {key!r}")
            result[key] = value
        return result

    try:
        with path.open("r", encoding="utf-8") as handle:
            json.load(handle, object_pairs_hook=reject_duplicates)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise RepositoryValidationError(f"{path}: invalid JSON: {error}") from error


def validate_plist(path: pathlib.Path) -> None:
    try:
        with path.open("rb") as handle:
            plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        raise RepositoryValidationError(f"{path}: invalid property list: {error}") from error


def validate_python(path: pathlib.Path) -> None:
    try:
        source = path.read_text(encoding="utf-8")
        ast.parse(source, filename=str(path))
    except (OSError, UnicodeError, SyntaxError) as error:
        raise RepositoryValidationError(f"{path}: invalid Python: {error}") from error


def validate_shell(paths: List[pathlib.Path], root: pathlib.Path) -> None:
    for path in paths:
        process = subprocess.run(
            ["bash", "-n", str(path)],
            cwd=str(root),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if process.returncode != 0:
            detail = process.stderr.strip() or process.stdout.strip()
            raise RepositoryValidationError(f"{path}: invalid shell syntax: {detail}")


def validate_yaml(paths: List[pathlib.Path], root: pathlib.Path) -> None:
    ruby = shutil.which("ruby")
    if ruby is None:
        raise RepositoryValidationError("Ruby is required for dependency-free YAML syntax validation")
    process = subprocess.run(
        [ruby, "-e", "require 'yaml'; ARGV.each { |path| YAML.parse_file(path) }"]
        + [str(path) for path in paths],
        cwd=str(root),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise RepositoryValidationError(f"invalid YAML: {detail}")


def run(root: pathlib.Path) -> None:
    files = tracked_files(root)
    groups = {
        "JSON": [path for path in files if path.suffix.lower() == ".json"],
        "plist": [path for path in files if path.suffix.lower() in {".plist", ".entitlements"}],
        "Python": [path for path in files if path.suffix.lower() == ".py"],
        "shell": [path for path in files if path.suffix.lower() == ".sh"],
        "YAML": [path for path in files if path.suffix.lower() in {".yml", ".yaml"}],
    }

    for path in groups["JSON"]:
        validate_json(path)
    for path in groups["plist"]:
        validate_plist(path)
    for path in groups["Python"]:
        validate_python(path)
    validate_shell(groups["shell"], root)
    validate_yaml(groups["YAML"], root)

    executable_scripts = [
        path
        for path in groups["Python"] + groups["shell"]
        if path.parent == root / "script" and path.read_bytes().startswith(b"#!")
    ]
    non_executable = [path for path in executable_scripts if not (path.stat().st_mode & 0o111)]
    if non_executable:
        joined = ", ".join(str(path.relative_to(root)) for path in non_executable)
        raise RepositoryValidationError(f"script entry points are not executable: {joined}")

    summary = ", ".join(f"{name}={len(paths)}" for name, paths in groups.items())
    print(f"Repository syntax validation passed: {summary}.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent.parent,
        help="repository root",
    )
    arguments = parser.parse_args()
    try:
        run(arguments.root.resolve())
    except (RepositoryValidationError, subprocess.CalledProcessError) as error:
        print(f"repository validation failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
