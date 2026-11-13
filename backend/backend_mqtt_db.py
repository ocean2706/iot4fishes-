import os
import json
import time
import logging
from datetime import datetime, timezone
import psycopg2
from psycopg2.extras import RealDictCursor
import paho.mqtt.client as mqtt

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

MQTT_BROKER = os.getenv("MQTT_BROKER", "mosquitto")
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "$$$postgres"),
    "port": int(os.getenv("DB_PORT", "5432")),
    "dbname": os.getenv("DB_NAME", "$$$ferma_piscicola"),
    "user": os.getenv("DB_USER", "$$$postgres"),
    "password": os.getenv("DB_PASSWORD", "$$$$postgres_password")
}

def get_db_connection():
    return psycopg2.connect(**DB_CONFIG)

def sincronizeaza_configuratii_bazine(client: mqtt.Client):
    query = """
        SELECT b.id_bazin, c.nume_categorie, c.temp_min, c.temp_max,
               c.do_min_mg_l, c.ph_min, c.ph_max, c.debit_pompa_procent
        FROM bazine b
        JOIN categorii_varsta c ON b.id_categorie = c.id_categorie
        WHERE b.stare_activa = TRUE;
    """
    with get_db_connection() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(query)
        for row in cur.fetchall():
            payload = {
                "categorie": row["nume_categorie"],
                "temp_min": float(row["temp_min"]),
                "temp_max": float(row["temp_max"]),
                "do_min": float(row["do_min_mg_l"]),
                "ph_min": float(row["ph_min"]),
                "ph_max": float(row["ph_max"]),
                "debit_pompa_pct": int(row["debit_pompa_procent"])
            }
            topic = f"ferma/bazin/{row['id_bazin']}/config"
            client.publish(topic, json.dumps(payload), qos=1, retain=True)
            logging.info("Configuratie sincronizata pe %s: %s", topic, payload)

def salveaza_telemetrie_bazin(data: dict):
    sql = """
        INSERT INTO masuratori_bazine
            (id_bazin, timestamp, temperatura_c, oxigen_do_mg_l, ph, turbiditate_ntu, nivel_apa_cm)
        VALUES (%s, %s, %s, %s, %s, %s, %s);
    """
    with get_db_connection() as conn, conn.cursor() as cur:
        cur.execute(sql, (
            data["id_bazin"], datetime.now(timezone.utc),
            float(data["temperatura_c"]), float(data["oxigen_do_mg_l"]),
            float(data["ph"]), float(data["turbiditate_ntu"]), float(data["nivel_apa_cm"])
        ))
    logging.info("Telemetrie salvata in DB pentru Bazin %s (%s)", data["id_bazin"], data.get("categorie"))

def salveaza_telemetrie_filtrare(data: dict):
    sql = """
        INSERT INTO statie_filtrare_dunare
            (timestamp, turbiditate_dunare_ntu, turbiditate_iesire_ntu, duritate_calcar_ppm,
             debit_recirculare_l_m, filtru_impuritati_ok, dozare_anticalcar_act, oxigenator_activ)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s);
    """
    with get_db_connection() as conn, conn.cursor() as cur:
        cur.execute(sql, (
            datetime.now(timezone.utc),
            float(data["turbiditate_dunare_ntu"]), float(data["turbiditate_iesire_ntu"]),
            float(data["duritate_calcar_ppm"]), float(data["debit_recirculare_l_m"]),
            bool(data["apa_curata_ok"]), bool(data["dozare_anticalcar"]), bool(data["oxigenator_activ"])
        ))

def inregistreaza_alarma(data: dict):
    sql = """
        INSERT INTO evenimente_alarme
            (id_bazin, timestamp, sursa_subsistem, tip_alarma, valoare_masurata, severitate, rezolvata)
        VALUES (%s, %s, %s, %s, %s, %s, FALSE);
    """
    severitate = "CRITICAL" if data.get("categorie") == "gestante" or "HIPOXIE" in data.get("status_alarma", "") else "WARNING"
    with get_db_connection() as conn, conn.cursor() as cur:
        cur.execute(sql, (
            data.get("id_bazin"), datetime.now(timezone.utc),
            f"BAZIN_{data.get('id_bazin')}", data.get("status_alarma", "ALARMA_GENERALA"),
            float(data.get("oxigen_do_mg_l", 0.0)), severitate
        ))
    logging.warning("ALARMA [%s] Bazin %s: %s", severitate, data.get("id_bazin"), data.get("status_alarma"))

def on_connect(client, userdata, flags, reason_code, properties=None):
    logging.info("Conectat la Broker MQTT (%s:%s)", MQTT_BROKER, MQTT_PORT)
    client.subscribe("ferma/bazin/+/telemetrie")
    client.subscribe("ferma/filtrare/telemetrie")
    client.subscribe("ferma/alarme/#")
    sincronizeaza_configuratii_bazine(client)

def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode("utf-8"))
        if msg.topic.endswith("/telemetrie") and "ferma/bazin/" in msg.topic:
            salveaza_telemetrie_bazin(payload)
        elif msg.topic == "ferma/filtrare/telemetrie":
            salveaza_telemetrie_filtrare(payload)
        elif msg.topic.startswith("ferma/alarme/"):
            inregistreaza_alarma(payload)
    except Exception as exc:
        logging.error("Eroare procesare mesaj pe %s: %s", msg.topic, exc)

def main():
    while True:
        try:
            with get_db_connection() as conn:
                logging.info("Conexiune PostgreSQL verificata cu succes.")
                break
        except Exception:
            logging.info("Astept pornirea PostgreSQL...")
            time.sleep(2)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="backend_ferma_piscicola")
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
    client.loop_forever()

if __name__ == "__main__":
    main()
