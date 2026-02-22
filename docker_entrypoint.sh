#!/usr/bin/env sh
set -eu

cd /app

# Optional env aliases for docker-compose convenience.
export MQTT_HOST="${MQTT_HOST:-${BATMON_MQTT_HOST:-}}"
export MQTT_PORT="${MQTT_PORT:-${BATMON_MQTT_PORT:-}}"
export MQTT_USER="${MQTT_USER:-${BATMON_MQTT_USER:-}}"
export MQTT_PASSWORD="${MQTT_PASSWORD:-${BATMON_MQTT_PASSWORD:-}}"

if [ "${BATMON_SKIP_PAIRING:-0}" != "1" ]; then
  /app/venv_bleak_pairing/bin/python3 main.py pair-only || true
fi

exec /app/venv/bin/python3 main.py "$@"
