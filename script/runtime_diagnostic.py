#!/usr/bin/env python3
import base64
import json
import os
import select
import subprocess
import sys
import time


def websocket_frame(payload: bytes) -> bytes:
    mask = os.urandom(4)
    header = bytearray([0x81])
    length = len(payload)
    if length < 126:
        header.append(0x80 | length)
    elif length <= 0xFFFF:
        header.extend([0x80 | 126, (length >> 8) & 0xFF, length & 0xFF])
    else:
        header.append(0x80 | 127)
        header.extend(length.to_bytes(8, "big"))
    masked = bytes(byte ^ mask[index % 4] for index, byte in enumerate(payload))
    return bytes(header) + mask + masked


def read_frame(stdout, timeout=5):
    ready, _, _ = select.select([stdout], [], [], timeout)
    if not ready:
        raise TimeoutError("timed out waiting for websocket frame")

    first = os.read(stdout.fileno(), 2)
    if len(first) != 2:
        raise RuntimeError("incomplete websocket frame header")

    opcode = first[0] & 0x0F
    length = first[1] & 0x7F
    if length == 126:
        length = int.from_bytes(os.read(stdout.fileno(), 2), "big")
    elif length == 127:
        length = int.from_bytes(os.read(stdout.fileno(), 8), "big")

    payload = os.read(stdout.fileno(), length)
    if opcode != 1:
        return read_frame(stdout, timeout)
    return json.loads(payload.decode("utf-8"))


def request(proc, request_id, method, params=None):
    message = {"id": request_id, "method": method}
    if params is not None:
        message["params"] = params
    proc.stdin.write(websocket_frame(json.dumps(message).encode("utf-8")))
    proc.stdin.flush()

    while True:
        response = read_frame(proc.stdout)
        if response.get("id") == request_id:
            if "error" in response:
                raise RuntimeError(response["error"])
            return response.get("result")


def notify(proc, method, params=None):
    message = {"method": method}
    if params is not None:
        message["params"] = params
    proc.stdin.write(websocket_frame(json.dumps(message).encode("utf-8")))
    proc.stdin.flush()


def main():
    subprocess.run(["codex", "app-server", "daemon", "start"], check=True)

    proc = subprocess.Popen(
        ["codex", "app-server", "proxy"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    key = base64.b64encode(os.urandom(16)).decode("ascii")
    handshake = (
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {key}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    ).encode("ascii")
    proc.stdin.write(handshake)
    proc.stdin.flush()

    deadline = time.time() + 5
    response = b""
    while b"\r\n\r\n" not in response and time.time() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], max(0, deadline - time.time()))
        if ready:
            response += os.read(proc.stdout.fileno(), 4096)

    if b" 101 " not in response.split(b"\r\n", 1)[0]:
        raise RuntimeError(f"websocket handshake failed: {response[:300]!r}")

    initialize = request(
        proc,
        1,
        "initialize",
        {
            "clientInfo": {
                "name": "mapofagents-runtime-diagnostic",
                "title": "mapofagents Runtime Diagnostic",
                "version": "0.1.0",
            },
            "capabilities": {"experimentalApi": True},
        },
    )
    notify(proc, "initialized")
    account = request(proc, 2, "account/read", {"refreshToken": False})
    models = request(proc, 3, "model/list", {"limit": 20, "includeHidden": False})
    threads = request(proc, 4, "thread/list", {"limit": 5, "archived": False})

    proc.terminate()

    print(
        json.dumps(
            {
                "ok": True,
                "transport": "daemon proxy websocket",
                "codexHome": initialize.get("codexHome"),
                "platformOs": initialize.get("platformOs"),
                "account": "authenticated" if account.get("account") else "missing",
                "requiresOpenaiAuth": account.get("requiresOpenaiAuth"),
                "models": [model.get("id") or model.get("model") for model in models.get("data", [])[:5]],
                "threadCountSample": len(threads.get("data", [])),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"runtime diagnostic failed: {exc}", file=sys.stderr)
        sys.exit(1)
