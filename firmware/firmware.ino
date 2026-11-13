#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

const char* WIFI_SSID    = "Wokwi-GUEST";
const char* WIFI_PASS    = "";
const char* MQTT_BROKER  = "host.wokwi.internal";
const uint16_t MQTT_PORT = 1883;
const char* NODE_ID      = "esp32s3_ferma_piscicola";

WiFiClient espClient;
PubSubClient mqttClient(espClient);
LiquidCrystal_I2C lcd(0x27, 16, 2);

const uint8_t PIN_TEMP_B1    = 1;
const uint8_t PIN_DO_B1      = 2;
const uint8_t PIN_TURB_IN    = 4;
const uint8_t PIN_CALCAR     = 5;
const uint8_t PIN_I2C_SDA    = 8;
const uint8_t PIN_I2C_SCL    = 9;
const uint8_t PIN_BTN_FEED   = 14;
const uint8_t PIN_SW_POMPA   = 15;

const uint8_t PIN_SERVO_B1   = 17;
const uint8_t PIN_POMPA_RAU  = 39;
const uint8_t PIN_FILTRU_BW  = 40;
const uint8_t PIN_OXIG_B1    = 42;
const uint8_t PIN_ANTICALC   = 38;
const uint8_t PIN_BUZZER     = 45;
const uint8_t PIN_ALARMA     = 47;

struct ProfilBazin {
  String categorie;
  float tempMin;
  float tempMax;
  float doMin;
  float phMin;
  float phMax;
  uint8_t debitPompaPct;
};

ProfilBazin bazineCfg[3] = {
  { "puiet",    14.0f, 16.0f, 8.5f, 6.8f, 7.8f, 55 },
  { "adulti",   12.0f, 15.0f, 7.5f, 6.5f, 8.0f, 85 },
  { "gestante", 10.0f, 13.0f, 9.0f, 7.0f, 7.6f, 65 }
};

unsigned long lastTelemetryMs = 0;
unsigned long lastFeedMs = 0;
unsigned long lastLcdMs = 0;
unsigned long lastMqttRetryMs = 0;
bool feederOpen = false;

void setServoAngle(uint8_t angle) {
  uint32_t us = map(angle, 0, 180, 544, 2400);
  uint32_t duty = (us * 16383UL) / 20000UL;
  ledcWrite(PIN_SERVO_B1, duty);
}

void declanseazaHranire(unsigned long now, const char* sursa) {
  lastFeedMs = now;
  if (!feederOpen) {
    feederOpen = true;
    setServoAngle(90);
    Serial.print("[HRANITOR] Deschis 90 deg -> ");
    Serial.println(sursa);
  }
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String t(topic);
  JsonDocument doc;
  if (deserializeJson(doc, payload, length)) return;

  for (int i = 0; i < 3; i++) {
    if (t == "ferma/bazin/" + String(i + 1) + "/config") {
      if (doc["categorie"].is<const char*>()) bazineCfg[i].categorie = doc["categorie"].as<String>();
      if (doc["temp_min"].is<float>()) bazineCfg[i].tempMin = doc["temp_min"];
      if (doc["temp_max"].is<float>()) bazineCfg[i].tempMax = doc["temp_max"];
      if (doc["do_min"].is<float>())   bazineCfg[i].doMin   = doc["do_min"];
      if (doc["debit_pompa_pct"].is<uint8_t>()) bazineCfg[i].debitPompaPct = doc["debit_pompa_pct"];
    } else if (t == "ferma/bazin/" + String(i + 1) + "/comenzi") {
      if (doc["hranire_manuala"] == true && i == 0) {
        declanseazaHranire(millis(), "MQTT");
      }
    }
  }
}

void tryConnectMQTT(unsigned long now) {
  if (mqttClient.connected()) return;
  if (now - lastMqttRetryMs < 3000UL) return;
  lastMqttRetryMs = now;
  Serial.print("[MQTT] Conectare la ");
  Serial.print(MQTT_BROKER);
  Serial.print("... ");
  if (mqttClient.connect(NODE_ID)) {
    Serial.println("CONECTAT!");
    mqttClient.subscribe("ferma/bazin/+/config");
    mqttClient.subscribe("ferma/bazin/+/comenzi");
  } else {
    Serial.print("ESEC rc=");
    Serial.println(mqttClient.state());
  }
}

void setup() {
  Serial.begin(115200);

  pinMode(PIN_BTN_FEED, INPUT_PULLUP);
  pinMode(PIN_SW_POMPA, INPUT);

  pinMode(PIN_OXIG_B1, OUTPUT);
  pinMode(PIN_ANTICALC, OUTPUT);
  pinMode(PIN_FILTRU_BW, OUTPUT);
  pinMode(PIN_POMPA_RAU, OUTPUT);
  pinMode(PIN_ALARMA, OUTPUT);
  pinMode(PIN_BUZZER, OUTPUT);

  ledcAttach(PIN_SERVO_B1, 50, 14);
  setServoAngle(0);

  Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL);
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("Ferma Piscicola");
  lcd.setCursor(0, 1);
  lcd.print("Conectare WiFi..");

  WiFi.begin(WIFI_SSID, WIFI_PASS);
  unsigned long wifiStart = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - wifiStart < 8000UL) {
    delay(250);
  }
  Serial.print("[WIFI] Status=");
  Serial.print(WiFi.status());
  Serial.print(" IP=");
  Serial.println(WiFi.localIP());

  mqttClient.setServer(MQTT_BROKER, MQTT_PORT);
  mqttClient.setBufferSize(1024);
  mqttClient.setCallback(mqttCallback);

  declanseazaHranire(millis(), "PORNIRE");
}

void loop() {
  unsigned long now = millis();

  float tempB1   = 8.0f + (analogRead(PIN_TEMP_B1) / 4095.0f) * 16.0f;
  float doB1     = 4.0f + (analogRead(PIN_DO_B1)   / 4095.0f) * 8.0f;
  float turbIn   = (analogRead(PIN_TURB_IN)        / 4095.0f) * 120.0f;
  float calcar   = 100.0f + (analogRead(PIN_CALCAR)/ 4095.0f) * 350.0f;
  bool pompaRau  = (digitalRead(PIN_SW_POMPA) == HIGH);
  bool btnManual = (digitalRead(PIN_BTN_FEED) == LOW);

  bool alarmaDO     = (doB1 < bazineCfg[0].doMin);
  bool alarmaTempHi = (tempB1 > bazineCfg[0].tempMax);
  bool alarmaTempLo = (tempB1 < bazineCfg[0].tempMin);
  bool alarmaTemp   = alarmaTempHi || alarmaTempLo;
  bool alarmaTurb   = (turbIn > 65.0f);
  bool antiCalc     = (calcar > 220.0f);
  bool alarmaB1     = alarmaDO || alarmaTemp || alarmaTurb || antiCalc;

  digitalWrite(PIN_OXIG_B1,   alarmaDO   ? HIGH : LOW);
  digitalWrite(PIN_ANTICALC,  antiCalc   ? HIGH : LOW);
  digitalWrite(PIN_FILTRU_BW, alarmaTurb ? HIGH : LOW);
  digitalWrite(PIN_POMPA_RAU, pompaRau   ? HIGH : LOW);
  digitalWrite(PIN_ALARMA,    alarmaB1   ? HIGH : LOW);

  if (alarmaB1 && ((now / 400) % 2 == 0)) {
    uint16_t freq = alarmaDO ? 1000 : (alarmaTemp ? 1500 : (antiCalc ? 1800 : 2100));
    tone(PIN_BUZZER, freq);
  } else {
    noTone(PIN_BUZZER);
  }

  if (btnManual) {
    declanseazaHranire(now, "BUTON_MANUAL");
  } else if (!feederOpen && (now - lastFeedMs >= 10000UL)) {
    declanseazaHranire(now, "AUTOMAT_10S");
  } else if (feederOpen && (now - lastFeedMs >= 2500UL)) {
    feederOpen = false;
    setServoAngle(0);
    Serial.println("[HRANITOR] Inchis 0 deg");
  }

  if (now - lastLcdMs >= 350UL) {
    lastLcdMs = now;
    lcd.setCursor(0, 0);
    lcd.printf("Turb:%5.1f NTU  ", turbIn);
    lcd.setCursor(0, 1);
    if (alarmaDO) {
      lcd.printf("ALARMA DO:%4.1f  ", doB1);
    } else if (alarmaTempHi) {
      lcd.printf("T MARE:%4.1fC    ", tempB1);
    } else if (alarmaTempLo) {
      lcd.printf("T MICA:%4.1fC    ", tempB1);
    } else if (antiCalc) {
      lcd.printf("CALCAR:%4.0f ppm ", calcar);
    } else if (alarmaTurb) {
      lcd.print("ALARMA TURB RAU ");
    } else {
      lcd.printf("T:%4.1fC DO:%4.1f ", tempB1, doB1);
    }
  }

  tryConnectMQTT(now);
  if (mqttClient.connected()) {
    mqttClient.loop();
    if (now - lastTelemetryMs >= 3000UL) {
      lastTelemetryMs = now;
      char buf[384];

      const char* statusMsg = "OK";
      if (alarmaDO) statusMsg = "HIPOXIE_DO_SCAZUT";
      else if (alarmaTempHi) statusMsg = "TEMPERATURA_RIDICATA";
      else if (alarmaTempLo) statusMsg = "TEMPERATURA_SCAZUTA";
      else if (antiCalc) statusMsg = "CALCAR_RIDICAT";
      else if (alarmaTurb) statusMsg = "TURBIDITATE_CRITICA";

      for (int i = 0; i < 3; i++) {
        JsonDocument doc;
        doc["id_bazin"]        = i + 1;
        doc["categorie"]       = bazineCfg[i].categorie;
        doc["temperatura_c"]   = (i == 0) ? tempB1 : (i == 1 ? 13.5 : 11.4);
        doc["oxigen_do_mg_l"]  = (i == 0) ? doB1   : (i == 1 ? 8.2  : 9.4);
        doc["ph"]              = 7.3;
        doc["turbiditate_ntu"] = (i == 0) ? (turbIn * 0.1) : 3.2;
        doc["nivel_apa_cm"]    = pompaRau ? 145.0 : 128.0;
        doc["alarma"]          = (i == 0) ? alarmaB1 : false;
        doc["status_alarma"]   = (i == 0) ? statusMsg : "OK";

        size_t n = serializeJson(doc, buf);
        String topic = "ferma/bazin/" + String(i + 1) + "/telemetrie";
        mqttClient.publish(topic.c_str(), buf, n);

        if (i == 0 && alarmaB1) {
          mqttClient.publish("ferma/alarme/bazin/1", buf, n);
        }
      }

      JsonDocument docF;
      docF["turbiditate_dunare_ntu"] = turbIn;
      docF["turbiditate_iesire_ntu"] = turbIn * 0.08f;
      docF["duritate_calcar_ppm"]    = calcar;
      docF["debit_recirculare_l_m"]  = pompaRau ? 320.0f : 0.0f;
      docF["apa_curata_ok"]          = !alarmaTurb;
      docF["dozare_anticalcar"]      = antiCalc;
      docF["oxigenator_activ"]       = alarmaDO;

      size_t nF = serializeJson(docF, buf);
      mqttClient.publish("ferma/filtrare/telemetrie", buf, nF);
      Serial.printf("[TELEMETRIE] B1: T=%.1fC DO=%.1f | Dunare: Turb=%.0f Calcar=%.0fppm | Status=%s\n", tempB1, doB1, turbIn, calcar, statusMsg);
    }
  }
}
