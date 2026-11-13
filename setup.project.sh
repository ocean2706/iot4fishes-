#!/usr/bin/env bash
set -euo pipefail
# Generic installation & bootstrap script for the Sturion / Pastrav Fish Farm IoT MQTT Module
# Works from any target directory (defaults to current working directory or $1)
PROJECT_DIR="${1:-$(pwd)/ferma-piscicola-iot}"
echo "[1/5] Creating project structure in: ${PROJECT_DIR}"
mkdir -p
"${PROJECT_DIR}"/{firmware/build,backend,database,mosquitto/config,mosquitto/data,mosquit
to/log}
echo "[2/5] Writing Mosquitto MQTT broker configuration..."
cat << 'EOF' > "${PROJECT_DIR}/mosquitto/config/mosquitto.conf"
listener 1883 0.0.0.0
allow_anonymous true
persistence true
persistence_location /mosquitto/data/
log_dest file /mosquitto/log/mosquitto.log
log_dest stdout
EOF
echo "[3/5] Writing PostgreSQL DDL schema (database/schema_baza_date.sql)..."
cat << 'EOF' > "${PROJECT_DIR}/database/schema_baza_date.sql"
CREATE TABLE IF NOT EXISTS categorii_varsta (
id_categorie SERIAL PRIMARY KEY,
nume_categorie VARCHAR(32) UNIQUE NOT NULL,
specie VARCHAR(64) NOT NULL,
temp_min NUMERIC(4,2) NOT NULL,
temp_max NUMERIC(4,2) NOT NULL,
do_min_mg_l NUMERIC(4,2) NOT NULL,
ph_min NUMERIC(4,2) NOT NULL,
ph_max NUMERIC(4,2) NOT NULL,
debit_pompa_procent INT NOT NULL
);
CREATE TABLE IF NOT EXISTS bazine (
id_bazin SERIAL PRIMARY KEY,
id_categorie INT REFERENCES categorii_varsta(id_categorie),
nume_bazin VARCHAR(64) NOT NULL,
volum_m3 NUMERIC(8,2) NOT NULL,
stare_activa BOOLEAN DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS masuratori_bazine (
id_masuratoare BIGSERIAL PRIMARY KEY,
id_bazin INT REFERENCES bazine(id_bazin),
timestamp TIMESTAMPTZ DEFAULT NOW(),
temperatura_c NUMERIC(5,2),
oxigen_do_mg_l NUMERIC(5,2),
ph NUMERIC(4,2),
turbiditate_ntu NUMERIC(6,2),
nivel_apa_cm NUMERIC(6,2)
);
CREATE TABLE IF NOT EXISTS statie_filtrare_dunare (
id_log_filtrare BIGSERIAL PRIMARY KEY,
timestamp TIMESTAMPTZ DEFAULT NOW(),
turbiditate_dunare_ntu NUMERIC(6,2),
turbiditate_iesire_ntu NUMERIC(6,2),
duritate_calcar_ppm NUMERIC(6,2),
debit_recirculare_l_m NUMERIC(6,2),
apa_curata_ok BOOLEAN,
dozare_anticalcar BOOLEAN,
oxigenator_activ BOOLEAN
);
CREATE TABLE IF NOT EXISTS evenimente_alarme (
id_alarma BIGSERIAL PRIMARY KEY,
id_bazin INT REFERENCES bazine(id_bazin),
timestamp TIMESTAMPTZ DEFAULT NOW(),
sursa_subsistem VARCHAR(64),
tip_alarma VARCHAR(64),
valoare_masurata NUMERIC(6,2),
severitate VARCHAR(16) DEFAULT 'CRITICAL',
rezolvata BOOLEAN DEFAULT FALSE
);
INSERT INTO categorii_varsta (nume_categorie, specie, temp_min, temp_max, do_min_mg_l,
ph_min, ph_max, debit_pompa_procent)
VALUES
('puiet', 'Pastrav / Sturion', 14.0, 16.0, 8.5, 6.8, 7.8, 55),
('adulti', 'Pastrav / Sturion', 12.0, 15.0, 7.5, 6.5, 8.0, 85),
('gestante', 'Pastrav / Sturion', 10.0, 13.0, 9.0, 7.0, 7.6, 65)
ON CONFLICT (nume_categorie) DO NOTHING;

INSERT INTO bazine (id_bazin, id_categorie, nume_bazin, volum_m3)
VALUES
(1, 1, 'Bazin 1 - Puiet', 25.0),
(2, 2, 'Bazin 2 - Adulti', 80.0),
(3, 3, 'Bazin 3 - Gestante', 50.0)
ON CONFLICT (id_bazin) DO NOTHING;
EOF
echo "[4/5] Writing Docker Compose & Python MQTT ingestion worker..."
cat << 'EOF' > "${PROJECT_DIR}/docker-compose.yml"
services:
mosquitto:
image: eclipse-mosquitto:2
container_name: ferma_mosquitto
restart: unless-stopped
ports:
- "1883:1883"
volumes:
- ./mosquitto/config:/mosquitto/config
- ./mosquitto/data:/mosquitto/data
- ./mosquitto/log:/mosquitto/log
postgres:
image: postgres:16-alpine
container_name: ferma_postgres
restart: unless-stopped
environment:
POSTGRES_USER: postgres
POSTGRES_PASSWORD: ferma_password
POSTGRES_DB: ferma_piscicola
ports:
- "5432:5432"
volumes:
- ./database/schema_baza_date.sql:/docker-entrypoint-initdb.d/01_schema.sql
EOF
cat << 'EOF' > "${PROJECT_DIR}/backend/requirements.txt"
paho-mqtt>=2.1.0
psycopg2-binary>=2.9.9
EOF
cat << 'EOF' > "${PROJECT_DIR}/backend/backend_mqtt_db.py"
import json

import os
import time
import psycopg2
import paho.mqtt.client as mqtt
MQTT_HOST = os.getenv("MQTT_HOST", "127.0.0.1")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
DB_DSN = os.getenv("DB_DSN", "dbname=ferma_piscicola user=postgres
password=ferma_password host=127.0.0.1 port=5432")
def get_db():
while True:
try:
return psycopg2.connect(DB_DSN)
except Exception as exc:
print(f"[DB] Waiting for PostgreSQL: {exc}")
time.sleep(2)
conn = get_db()
conn.autocommit = True
def on_connect(client, userdata, flags, reason_code, properties=None):
print(f"[MQTT] Connected (rc={reason_code}), subscribing to ferma/#")
client.subscribe("ferma/#")
def on_message(client, userdata, msg):
try:
data = json.loads(msg.payload.decode("utf-8"))
with conn.cursor() as cur:
if msg.topic.startswith("ferma/bazin/") and msg.topic.endswith("/telemetrie"):
cur.execute(
"""INSERT INTO masuratori_bazine (id_bazin, temperatura_c, oxigen_do_mg_l,

ph, turbiditate_ntu, nivel_apa_cm)

VALUES (%s, %s, %s, %s, %s, %s)""",
(data["id_bazin"], data["temperatura_c"], data["oxigen_do_mg_l"], data["ph"],

data["turbiditate_ntu"], data["nivel_apa_cm"])
)
elif msg.topic == "ferma/filtrare/telemetrie":
cur.execute(
"""INSERT INTO statie_filtrare_dunare
(turbiditate_dunare_ntu, turbiditate_iesire_ntu, duritate_calcar_ppm,
debit_recirculare_l_m, apa_curata_ok, dozare_anticalcar, oxigenator_activ)

VALUES (%s, %s, %s, %s, %s, %s, %s)""",

(data["turbiditate_dunare_ntu"], data["turbiditate_iesire_ntu"],

data["duritate_calcar_ppm"],

data["debit_recirculare_l_m"], data["apa_curata_ok"], data["dozare_anticalcar"],

data["oxigenator_activ"])
)
elif msg.topic.startswith("ferma/alarme/bazin/"):
cur.execute(
"""INSERT INTO evenimente_alarme (id_bazin, sursa_subsistem, tip_alarma,

valoare_masurata, severitate)

VALUES (%s, %s, %s, %s, %s)""",
(data["id_bazin"], "BAZIN_IOT", data.get("status_alarma", "ALARMA"),

data.get("oxigen_do_mg_l", 0.0), "CRITICAL")
)
except Exception as exc:
print(f"[ERR] Failed processing {msg.topic}: {exc}")
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
client.on_connect = on_connect
client.on_message = on_message
client.connect(MQTT_HOST, MQTT_PORT, 60)
client.loop_forever()
EOF
echo "[5/5] Installing Arduino CLI libraries and Python virtual environment..."
if command -v arduino-cli >/dev/null 2>&1; then
arduino-cli core update-index
arduino-cli core install esp32:esp32
arduino-cli lib install "PubSubClient" "ArduinoJson" "LiquidCrystal I2C"
fi
python3 -m venv "${PROJECT_DIR}/backend/.venv"
"${PROJECT_DIR}/backend/.venv/bin/pip" install --upgrade pip
"${PROJECT_DIR}/backend/.venv/bin/pip" install -r
"${PROJECT_DIR}/backend/requirements.txt"
if command -v docker >/dev/null 2>&1; then
(cd "${PROJECT_DIR}" && docker compose up -d)
fi
echo "Setup complete in ${PROJECT_DIR}."
echo "Next: place firmware.ino, diagram.json, and wokwi.toml into ${PROJECT_DIR}/firmware
and compile with:"
echo " arduino-cli compile --fqbn esp32:esp32:esp32s3 --output-dir

${PROJECT_DIR}/firmware/build ${PROJECT_DIR}/firmware/firmware.ino"
