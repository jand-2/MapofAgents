#!/usr/bin/env python3
"""Fail on high-confidence secrets, private machine identifiers, or oversized media."""

from __future__ import annotations

import argparse
import ipaddress
import os
import pathlib
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable, List, Optional


SAFE_USERNAMES = {
    "default",
    "example",
    "local",
    "public",
    "runner",
    "runneradmin",
    "shared",
    "test",
    "user",
}
SAFE_TEST_USERNAMES = {
    # Canonical OS-managed profiles used by path-hardening fixtures. Keep these
    # exceptions test-only so the public source and documentation scan remains
    # strict for the same names.
    "all",
    "defaultuser0",
    "guest",
}
SAFE_TEST_ADDRESSES = {
    "10.0.0.4",
    "100.64.0.10",
    "100.64.0.11",
    "100.64.0.12",
    "192.168.1.25",
    "192.168.1.42",
}
SAFE_TEST_IPV6_ADDRESSES = {
    "fd7a:115c:a1e0::10",
}
SENSITIVE_SUFFIXES = {
    ".key",
    ".mobileprovision",
    ".p12",
    ".pem",
    ".token",
}
MEDIA_SUFFIXES = {
    ".gif",
    ".heic",
    ".jpeg",
    ".jpg",
    ".mov",
    ".mp4",
    ".png",
    ".webm",
}


@dataclass(frozen=True)
class Finding:
    path: pathlib.Path
    reason: str
    line: Optional[int] = None

    def render(self, root: pathlib.Path) -> str:
        relative = self.path.relative_to(root)
        location = f"{relative}:{self.line}" if self.line is not None else str(relative)
        return f"{location}: {self.reason}"


def repository_files(root: pathlib.Path) -> List[pathlib.Path]:
    process = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cwd=str(root),
        check=True,
        stdout=subprocess.PIPE,
    )
    paths = [root / item.decode("utf-8") for item in process.stdout.split(b"\0") if item]
    return [path for path in paths if path.is_file()]


def is_test_fixture(path: pathlib.Path, root: pathlib.Path) -> bool:
    relative = path.relative_to(root)
    parts = {part.lower() for part in relative.parts}
    return bool(parts & {"tests", "fixtures"})


def high_confidence_secret_reason(line: str) -> Optional[str]:
    patterns = (
        (r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----", "private key material"),
        (r"\bgithub_pat_[A-Za-z0-9_]{20,}\b", "GitHub personal access token"),
        (r"\bgh[pousr]_[A-Za-z0-9]{20,}\b", "GitHub token"),
        (r"\bsk-[A-Za-z0-9_-]{20,}\b", "OpenAI-style API key"),
        (r"\bAKIA[0-9A-Z]{16}\b", "AWS access key"),
        (r"\bssh-(?:rsa|ed25519)\s+[A-Za-z0-9+/]{40,}={0,3}", "SSH public key"),
    )
    for pattern, reason in patterns:
        if re.search(pattern, line):
            return reason

    bearer = re.search(r"(?i)\bBearer\s+([A-Za-z0-9._~-]{20,})\b", line)
    if bearer and bearer.group(1).lower() != "abcdefghijklmnopqrstuvwxyz":
        return "literal bearer credential"

    assignment = re.search(
        r"(?i)\b(?:api[_-]?key|password|secret|token)\s*[:=]\s*['\"]([A-Za-z0-9._~+/=-]{16,})['\"]",
        line,
    )
    if assignment:
        normalized = assignment.group(1).lower()
        placeholders = ("example", "placeholder", "redacted", "changeme", "not-a-real", "test-only")
        if not any(value in normalized for value in placeholders):
            return "literal credential assignment"
    return None


def text_findings(path: pathlib.Path, root: pathlib.Path, text: str) -> Iterable[Finding]:
    for line_number, line in enumerate(text.splitlines(), start=1):
        secret_reason = high_confidence_secret_reason(line)
        if secret_reason:
            yield Finding(path, secret_reason, line_number)

        for match in re.finditer(r"/Users/([A-Za-z0-9][A-Za-z0-9._-]*)(?:/|\b)", line):
            username = match.group(1).lower()
            if username not in SAFE_USERNAMES and not (
                is_test_fixture(path, root) and username in SAFE_TEST_USERNAMES
            ):
                yield Finding(path, f"personal macOS home path for user {match.group(1)!r}", line_number)

        for match in re.finditer(
            r"(?i)\b[A-Z]:[\\/]Users[\\/]([A-Za-z0-9][A-Za-z0-9._-]*)(?:[\\/]|\b)", line
        ):
            username = match.group(1).lower()
            if username not in SAFE_USERNAMES and not (
                is_test_fixture(path, root) and username in SAFE_TEST_USERNAMES
            ):
                yield Finding(path, f"personal Windows home path for user {match.group(1)!r}", line_number)

        if re.search(r"/Volumes/[A-Za-z0-9._ -]+(?:/|\b)", line):
            yield Finding(path, "machine-specific mounted-volume path", line_number)

        for match in re.finditer(r"(?<![A-Za-z0-9])(?:\d{1,3}\.){3}\d{1,3}(?![A-Za-z0-9])", line):
            address_text = match.group(0)
            try:
                address = ipaddress.ip_address(address_text)
            except ValueError:
                continue
            private_networks = (
                ipaddress.ip_network("10.0.0.0/8"),
                ipaddress.ip_network("172.16.0.0/12"),
                ipaddress.ip_network("192.168.0.0/16"),
            )
            is_private = any(address in network for network in private_networks)
            is_tailnet = address in ipaddress.ip_network("100.64.0.0/10")
            if address.is_loopback:
                continue
            if is_private or is_tailnet:
                if is_test_fixture(path, root) and address_text in SAFE_TEST_ADDRESSES:
                    continue
                yield Finding(path, f"private or tailnet IPv4 address {address_text}", line_number)

        ipv6_pattern = r"(?<![A-Za-z0-9])(?:[0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}(?![A-Za-z0-9])"
        for match in re.finditer(ipv6_pattern, line):
            address_text = match.group(0)
            try:
                address = ipaddress.ip_address(address_text)
            except ValueError:
                continue
            is_private = (
                address in ipaddress.ip_network("fc00::/7")
                or address in ipaddress.ip_network("fe80::/10")
            )
            if address.is_loopback or not is_private:
                continue
            if is_test_fixture(path, root) and address_text.lower() in SAFE_TEST_IPV6_ADDRESSES:
                continue
            yield Finding(path, f"private or tailnet IPv6 address {address_text}", line_number)


def scan(root: pathlib.Path, max_media_bytes: int) -> List[Finding]:
    findings: List[Finding] = []
    for path in repository_files(root):
        if path.resolve() == pathlib.Path(__file__).resolve():
            continue
        relative = path.relative_to(root)
        lowered_parts = {part.lower() for part in relative.parts}
        suffix = path.suffix.lower()

        if ".codex" in lowered_parts:
            findings.append(Finding(path, "tracked local Codex state"))
        if path.name.startswith(".env") or suffix in SENSITIVE_SUFFIXES:
            findings.append(Finding(path, "tracked sensitive credential/configuration filename"))
        oversized_media = suffix in MEDIA_SUFFIXES and path.stat().st_size > max_media_bytes
        if oversized_media:
            findings.append(
                Finding(
                    path,
                    f"media is {path.stat().st_size} bytes; public media limit is {max_media_bytes} bytes",
                )
            )
            continue

        try:
            data = path.read_bytes()
        except OSError as error:
            findings.append(Finding(path, f"could not read tracked file: {error}"))
            continue
        text = data.decode("utf-8", errors="ignore")
        findings.extend(text_findings(path, root, text))
    return findings


def self_test(root: pathlib.Path) -> None:
    safe = "Paths: /Users/example/project and C:\\Users\\User\\Desktop; ws://127.0.0.1:9"
    if list(text_findings(root / "Tests" / "fixture.txt", root, safe)):
        raise AssertionError("safe fixture values produced a finding")
    reserved_fixture = "/Users/Guest/project C:\\Users\\defaultuser0\\Desktop"
    if list(text_findings(root / "Tests" / "fixture.txt", root, reserved_fixture)):
        raise AssertionError("canonical reserved-profile test fixtures produced a finding")
    if not list(text_findings(root / "README.txt", root, reserved_fixture)):
        raise AssertionError("reserved-profile exceptions escaped their test-only scope")
    unsafe = "/Users/private-user/project github_pat_abcdefghijklmnopqrstuvwxyz123456 fd00::1234"
    reasons = [item.reason for item in text_findings(root / "README.txt", root, unsafe)]
    expected_fragments = ("home path", "GitHub", "IPv6")
    if any(not any(fragment in reason for reason in reasons) for fragment in expected_fragments):
        raise AssertionError("private path/token self-test was not detected")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=pathlib.Path,
        default=pathlib.Path(__file__).resolve().parent.parent,
        help="repository root",
    )
    parser.add_argument(
        "--max-media-bytes",
        type=int,
        default=int(os.environ.get("MAPOFAGENTS_MAX_PUBLIC_MEDIA_BYTES", 12 * 1024 * 1024)),
    )
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    if arguments.self_test:
        self_test(root)
    findings = scan(root, arguments.max_media_bytes)
    if findings:
        print("Sensitive/public-safety scan failed:", file=sys.stderr)
        for finding in findings:
            print(f"  {finding.render(root)}", file=sys.stderr)
        return 1
    print(f"Sensitive/public-safety scan passed ({len(repository_files(root))} files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
