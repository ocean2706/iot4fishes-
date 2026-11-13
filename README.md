# Industrial IoT Automation Module for Sturgeon & Trout Aquaculture (MQTT \+ ESP32-S3)

**Author:** George-Razvan Bungarzescu  
**Institution:** Universitatea Politehnica Timisoara — Facultatea de Automatica si Calculatoare (Anul II, 2025–2026)  
**Course:** Proiect Sincretic — Sisteme cu microcontrolere si IoT industriale

---

## 1\. Project Scope

This repository implements an end-to-end industrial IoT monitoring and closed-loop control module for intensive **Sturgeon (*Acipenseridae*) and Trout (*Salmonidae*)** aquaculture farms. Designed for autonomous operation along the upper Danube basin, the system eliminates dependence on variable natural river flow by combining forced-recirculation river simulation, multi-stage raw water treatment, and age-differentiated biological tank profiles over an **MQTT Publish/Subscribe** architecture.

### Biological & Process Profiles (3 Differentiated Tanks)

| Tank ID | Biological Stage | Temperature Range | Dissolved Oxygen (DO) | pH Range | River Flow Pump |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Bazin 1** | **Puiet** (Juveniles / Fry) | `14.0°C – 16.0°C` | `> 8.5 mg/L` | `6.8 – 7.8` | `55%` |
| **Bazin 2** | **Adulti** (Grow-out Adults) | `12.0°C – 15.0°C` | `> 7.5 mg/L` | `6.5 – 8.0` | `85%` |
| **Bazin 3** | **Gestante** (Broodstock / Gravid) | `10.0°C – 13.0°C` | `> 9.0 mg/L` | `7.0 – 7.6` | `65%` |

### Key Subsystems

1. **Edge Control Node (`ESP32-S3-DevKitC-1`):**  
   - Acquires analog/digital telemetry for Tank 1 temperature, dissolved oxygen (`DO`), Danube intake turbidity (`NTU`), and water hardness/scale (`CaCO3` ppm).  
   - Executes fail-safe local control loops: micro-bubble oxygenator (`Blue LED`), anti-scale dosing (`Yellow LED`), coarse/fine filter backwash (`Green LED`), river-current recirculation pump (`Cyan LED`), automated/manual servo feeder (`90°` dosing), local `16x2 I2C LCD` readout, and multi-tone piezo audio/visual critical alarms (`Red LED` \+ `Buzzer`).  
2. **MQTT Message Broker (`Eclipse Mosquitto`):**  
   - Decouples embedded field nodes from backend storage and operator HMIs over TCP/IP port `1883`.  
   - Topics: `ferma/bazin/{1..3}/telemetrie`, `ferma/filtrare/telemetrie`, `ferma/alarme/bazin/{id}`, `ferma/bazin/{id}/config`, and `ferma/bazin/{id}/comenzi`.  
3. **Persistence & Analytics Backend (`Python` \+ `PostgreSQL`):**  
   - Subscribes to `ferma/#`, validates JSON telemetry packets, logs time-series measurements (`masuratori_bazine`, `statie_filtrare_dunare`), and records critical alarm events (`evenimente_alarme`) for veterinary traceability.

---

## 2\. Repository Structure

```
ferma-piscicola-iot/
├── setup.project.sh               # Path-independent bootstrap & dependency installer
├── docker-compose.yml             # Eclipse Mosquitto + PostgreSQL 16 stack
├── mosquitto/config/mosquitto.conf# Broker listener & persistence config
├── database/schema_baza_date.sql  # Relational DDL & biological seed profiles
├── backend/
│   ├── backend_mqtt_db.py         # MQTT-to-PostgreSQL ingestion service
│   └── requirements.txt           # Python dependencies (paho-mqtt, psycopg2-binary)
└── firmware/
    ├── firmware.ino               # ESP32-S3 C++ firmware (Wi-Fi, MQTT, LEDC Servo, LCD, Alarms)
    ├── diagram.json               # Wokwi hardware simulation schematic
    └── wokwi.toml                 # Wokwi simulator binary mapping
```

---

## 3\. Quick Start 

1. **Run the generic installer** from any directory (optionally passing a target folder):

```sh
chmod +x setup.project.sh
./setup.project.sh /path/to/your/workspace/ferma-piscicola-iot
```

2. **Compile the ESP32-S3 firmware:**

```sh
cd /path/to/your/workspace/ferma-piscicola-iot/firmware
arduino-cli compile --fqbn esp32:esp32:esp32s3 --output-dir ./build firmware.ino
```

3. **Start the backend ingestion worker:**

```sh
../backend/.venv/bin/python ../backend/backend_mqtt_db.py
```

4. **Launch the Wokwi simulation** in VS Code by opening `firmware/diagram.json` and clicking **Start Simulation**.
   
## 4\. System & Software Requirements

The project can be deployed and simulated on **Linux** (recommended) or **Windows 10/11** (via WSL2):

### 1. Container Runtime (Linux or Windows)
* **Linux:** Docker Engine + Docker Compose v2 (`docker compose`) or Podman (`podman-compose`) to run the **Eclipse Mosquitto** MQTT broker (`port 1883`) and **PostgreSQL 16** database (`port 5432`)[cite: 16, 17].
* **Windows:** **Docker Desktop for Windows** (with the WSL2 backend enabled) or **Podman Desktop** — `host.wokwi.internal` resolves automatically to the Windows/WSL2 host on port `1883`.

### 2. Development & Compilation Toolchain
* **Visual Studio Code (VS Code)** (Linux or Windows).
* **Wokwi Simulator Extension for VS Code** (`wokwi.wokwi-vscode` — installed from the VS Code Extensions Marketplace) to emulate the **ESP32-S3-DevKitC-1**, I2C `LCD1602`, potentiometers, servo feeder, LEDs, and piezo buzzer[cite: 13, 15, 17].
* **Arduino CLI (`arduino-cli`)** with the `esp32:esp32` board core and libraries (`PubSubClient`, `ArduinoJson`, `LiquidCrystal I2C`)[cite: 15, 16].
* **Python 3.10+** with `paho-mqtt` and `psycopg2-binary` (automatically provisioned inside `.venv` by `setup.project.sh`)[cite: 16, 17].
