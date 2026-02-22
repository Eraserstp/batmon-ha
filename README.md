# BatMon for Home Assistant (Docker / Compose)

BatMon считывает данные BMS по Bluetooth (BLE), публикует их в MQTT и автоматически создает сущности в Home Assistant через MQTT Discovery.

Этот репозиторий теперь ориентирован на запуск как **обычный Docker-образ** (не только HA add-on), чтобы его можно было добавить в Docker Compose установку вместе с Home Assistant, Zigbee2MQTT и Mosquitto.

## Что умеет BatMon

- BLE-опрос BMS (напряжение, ток, мощность, SoC, ячейки, температуры).
- Параллельный опрос нескольких батарей.
- MQTT Discovery для Home Assistant.
- Расчет энергометров (charge/discharge/total/cycles).
- Поддержка batmon-коннекторов и aiobmsble-коннекторов.

Подробности по поддерживаемым BMS: [doc/BMSes.md](doc/BMSes.md)

---

## 1) Сборка Docker-образа

Из корня репозитория:

```bash
docker build -t batmon-ha:latest .
```

Образ включает:

- Python runtime,
- BlueZ/DBus зависимости для BLE,
- две virtualenv:
  - `/app/venv` — основной рантайм,
  - `/app/venv_bleak_pairing` — отдельная среда для `pair-only` режима.

---

## 2) Файлы конфигурации

BatMon читает конфиг в таком порядке:

1. `/data/options.json`
2. `./options.json` (fallback)

Для Docker Compose рекомендуется монтировать файл как `/data/options.json`.

Пример `./batmon/options.json`:

```json
{
  "devices": [
    {
      "address": "AA:BB:CC:DD:EE:FF",
      "type": "jbd",
      "alias": "jbd_battery"
    }
  ],
  "mqtt_broker": "mosquitto",
  "mqtt_port": 1883,
  "mqtt_user": "homeassistant",
  "mqtt_password": "change_me",
  "keep_alive": true,
  "sample_period": 1.0,
  "publish_period": 1.0,
  "expire_values_after": 20,
  "verbose_log": false,
  "watchdog": false
}
```

---

## 3) Docker Compose (HA + Mosquitto + Zigbee2MQTT + BatMon)

Ниже рабочий шаблон для `docker-compose.yml`.

> Важно: для BLE внутри контейнера BatMon нужен доступ к bluetooth стэку хоста. На практике обычно требуется `network_mode: host`, `privileged: true` и монтирование `/run/dbus`.

```yaml
services:
  homeassistant:
    image: ghcr.io/home-assistant/home-assistant:stable
    container_name: homeassistant
    network_mode: host
    restart: unless-stopped
    volumes:
      - ./homeassistant:/config
      - /etc/localtime:/etc/localtime:ro

  mosquitto:
    image: eclipse-mosquitto:2
    container_name: mosquitto
    restart: unless-stopped
    ports:
      - "1883:1883"
      - "9001:9001"
    volumes:
      - ./mosquitto/config:/mosquitto/config
      - ./mosquitto/data:/mosquitto/data
      - ./mosquitto/log:/mosquitto/log

  zigbee2mqtt:
    image: koenkk/zigbee2mqtt:latest
    container_name: zigbee2mqtt
    restart: unless-stopped
    depends_on:
      - mosquitto
    ports:
      - "8080:8080"
    volumes:
      - ./zigbee2mqtt/data:/app/data
      - /run/udev:/run/udev:ro
    devices:
      - /dev/ttyACM0:/dev/ttyACM0

  batmon:
    build:
      context: .
      dockerfile: Dockerfile
    image: batmon-ha:latest
    container_name: batmon
    restart: unless-stopped
    network_mode: host
    privileged: true
    depends_on:
      - mosquitto
    volumes:
      - ./batmon/options.json:/data/options.json:ro
      - ./batmon/data:/data
      - /run/dbus:/run/dbus:ro
    environment:
      TZ: Europe/Moscow
```

Запуск:

```bash
docker compose up -d --build
```

Проверка логов:

```bash
docker compose logs -f batmon
```

---

## 4) Настройка MQTT в Home Assistant

1. В Home Assistant откройте **Settings → Devices & Services → Add Integration → MQTT**.
2. Укажите broker `mosquitto` (или IP/hostname сервера) и учетные данные.
3. После подключения BatMon опубликует discovery-топики, и сущности батареи появятся автоматически.

---

## 5) Конфигурация для JBD DP04S007

Для JBD DP04S007 используйте сначала штатный драйвер `jbd`.

Пример устройства в `options.json`:

```json
{
  "devices": [
    {
      "address": "AA:BB:CC:DD:EE:FF",
      "type": "jbd",
      "alias": "dp04s007",
      "adapter": "hci0",
      "debug": false
    }
  ],
  "mqtt_broker": "mosquitto",
  "mqtt_port": 1883,
  "mqtt_user": "homeassistant",
  "mqtt_password": "change_me",
  "keep_alive": true,
  "sample_period": 1.0,
  "publish_period": 1.0,
  "expire_values_after": 20
}
```

### Как узнать MAC-адрес DP04S007

- Запустите BatMon и посмотрите список найденных BLE устройств в логах.
- Либо просканируйте BLE любым инструментом (например `bluetoothctl`).

### Если устройство нестабильно подключается

1. Увеличьте `publish_period` до `2-5` секунд.
2. Оставьте `keep_alive: true`.
3. Проверьте помехи (инверторы, Wi‑Fi рядом с BLE адаптером).
4. Попробуйте альтернативный тип `jbd_ble` (через aiobmsble).

---

## 6) Полезные команды

Остановить/запустить BatMon:

```bash
docker compose restart batmon
```

Проверить доступность bluetooth адаптера на хосте:

```bash
hciconfig -a
```

Проверить активность DBus на хосте:

```bash
systemctl status dbus
```

---

## 7) Отладка

- Если BatMon не видит BLE-устройства, проверьте права контейнера (`privileged`) и монтирование `/run/dbus`.
- Если нет сущностей в HA, сначала проверьте, что BatMon подключился к MQTT (это видно в логах BatMon).
- Если есть MQTT, но нет auto-discovery, убедитесь что MQTT integration в HA подключена к тому же брокеру.

---

## Дополнительно

- Standalone запуск без Docker: [doc/Standalone.md](doc/Standalone.md)
- Energy Dashboard: [doc/HA Energy Dashboard.md](doc/HA%20Energy%20Dashboard.md)
- Алгоритмы: [doc/Algorithms.md](doc/Algorithms.md)
