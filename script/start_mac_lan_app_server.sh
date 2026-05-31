#!/usr/bin/env bash
set -euo pipefail

PORT="${MAPOFAGENTS_MAC_LAN_PORT:-18945}"
HOST="${MAPOFAGENTS_MAC_LAN_HOST:-127.0.0.1}"
ALLOW_INSECURE_LAN="${MAPOFAGENTS_ALLOW_INSECURE_LAN:-0}"
SUPPORT_DIR="${HOME}/Library/Application Support/mapofagents"
TOKEN_FILE="${MAPOFAGENTS_MAC_LAN_TOKEN_FILE:-${SUPPORT_DIR}/mac-lan-app-server.token}"
LOG_FILE="${MAPOFAGENTS_MAC_LAN_LOG_FILE:-${SUPPORT_DIR}/mac-lan-app-server.log}"

mkdir -p "${SUPPORT_DIR}"

case "${HOST}" in
  127.0.0.1|localhost|::1|"[::1]")
    ;;
  *)
    if [[ "${ALLOW_INSECURE_LAN}" != "1" ]]; then
      echo "Refusing to expose a bearer-token Codex App Server over cleartext ws://${HOST}:${PORT}." >&2
      echo "Use the Mac app pairing flow, a wss:// endpoint, or set MAPOFAGENTS_ALLOW_INSECURE_LAN=1 for a temporary development override." >&2
      exit 64
    fi
    echo "Warning: starting a cleartext non-loopback App Server because MAPOFAGENTS_ALLOW_INSECURE_LAN=1." >&2
    ;;
esac

if /usr/sbin/lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port ${PORT} is already listening; refusing to reuse an existing listener with an unknown token policy." >&2
  exit 64
fi

umask 077
/usr/bin/openssl rand -hex 32 > "${TOKEN_FILE}"

echo "Starting Codex App Server on ws://${HOST}:${PORT}"
echo "Token file: ${TOKEN_FILE}"
echo "Log file: ${LOG_FILE}"

nohup codex app-server \
  --listen "ws://${HOST}:${PORT}" \
  --ws-auth capability-token \
  --ws-token-file "${TOKEN_FILE}" \
  > "${LOG_FILE}" 2>&1 < /dev/null &

echo $! > "${SUPPORT_DIR}/mac-lan-app-server.pid"
sleep 1

if ! /usr/sbin/lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Codex App Server did not start. Recent log:"
  tail -40 "${LOG_FILE}" || true
  exit 1
fi

echo "Ready: ws://${HOST}:${PORT}"
echo "Token file: ${TOKEN_FILE}"
