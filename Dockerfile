FROM python:3.12-alpine

WORKDIR /app

RUN apk add --no-cache \
    bluez \
    dbus \
    git \
    bash

COPY requirements.txt ./

# main runtime venv
RUN python3 -m venv /app/venv \
    && /app/venv/bin/pip install --no-cache-dir --upgrade pip \
    && /app/venv/bin/pip install --no-cache-dir -r requirements.txt \
    && /app/venv/bin/pip install --no-cache-dir influxdb \
    && /app/venv/bin/pip install --no-cache-dir 'git+https://github.com/patman15/aiobmsble'

# separate venv for pairing agent capable bleak build
RUN python3 -m venv /app/venv_bleak_pairing \
    && /app/venv_bleak_pairing/bin/pip install --no-cache-dir --upgrade pip \
    && /app/venv_bleak_pairing/bin/pip install --no-cache-dir -r requirements.txt \
    && /app/venv_bleak_pairing/bin/pip install --no-cache-dir 'git+https://github.com/jpeters-ml/bleak@feature/windowsPairing' || true

COPY . .
RUN chmod +x /app/docker_entrypoint.sh

ENTRYPOINT ["/app/docker_entrypoint.sh"]
