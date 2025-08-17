#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "DHT.h"


const char* WIFI_SSID = "Wanna give some Ransom!?";
const char* WIFI_PASS = "#meow@meow#";
const char* DB_BASE   = "https://pond-monitor-ss-default-rtdb.asia-southeast1.firebasedatabase.app";

String NODE_ID = "pond_node_01";

#define DHTPIN   16
#define DHTTYPE  DHT22
#define ONE_WIRE_BUS 4
#define PH_ADC   34

DHT dht(DHTPIN, DHTTYPE);
OneWire oneWire(ONE_WIRE_BUS);
DallasTemperature ds18b20(&oneWire);

const float PH_M = -5.55f; // placeholder slope
const float PH_B = 20.38f; // placeholder offset


float readPoVoltage() {
  const int N = 40;
  uint32_t sum = 0;
  for (int i=0;i<N;i++){ sum += analogRead(PH_ADC); delay(5); }
  float avg   = sum / float(N);           // 0..4095
  float v_adc = (avg / 4095.0f) * 3.3f;   // ADC voltage
  float v_po  = v_adc / 0.6f;             // divider back-calc (10k top / 15k bottom)
  return v_po;
}
float voltageToPH(float v_po){ return PH_M * v_po + PH_B; }

bool firebasePUT(const String& path, const String& json) {
  String url = String(DB_BASE) + "/" + path + ".json";
  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type","application/json");
  int code = http.PUT((uint8_t*)json.c_str(), json.length());
  http.end();
  return (code == 200 || code == 204);
}
bool firebasePOST(const String& path, const String& json) {
  String url = String(DB_BASE) + "/" + path + ".json";
  HTTPClient http;
  http.begin(url);
  http.addHeader("Content-Type","application/json");
  int code = http.POST((uint8_t*)json.c_str(), json.length());
  http.end();
  return (code == 200);
}

void setup() {
  Serial.begin(115200);
  analogReadResolution(12);
  analogSetPinAttenuation(PH_ADC, ADC_11db); 

  dht.begin();
  ds18b20.begin();

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  Serial.print("Connecting WiFi");
  uint8_t tries=0;
  while (WiFi.status()!=WL_CONNECTED && tries<50){ delay(200); Serial.print("."); tries++; }
  Serial.println(WiFi.status()==WL_CONNECTED ? "\nWiFi OK" : "\nWiFi FAIL");
}

uint32_t lastHistory = 0;

void loop() {
  float airT = dht.readTemperature();
  float hum  = dht.readHumidity();

  ds18b20.requestTemperatures();
  float waterT = ds18b20.getTempCByIndex(0);

  float v_po  = readPoVoltage();
  float ph    = voltageToPH(v_po);

  // Build JSON
  StaticJsonDocument<256> doc;
  doc["node_id"] = NODE_ID;
  doc["ts"] = (uint32_t)(millis()/1000);
  if (isnan(airT)) doc["air_temp_c"] = nullptr; else doc["air_temp_c"] = airT;
  if (isnan(hum))  doc["humidity"]   = nullptr; else doc["humidity"]   = hum;
  doc["water_temp_c"] = waterT;
  doc["ph"] = ph;
  doc["ph_vpo"] = v_po;

  String payload; serializeJson(doc, payload);
  Serial.println(payload);

  if (WiFi.status()==WL_CONNECTED) {
    // Live overwrite
    firebasePUT("live/" + NODE_ID, payload);

    // History every 60s
    if (millis() - lastHistory > 60000) {
      firebasePOST("history/" + NODE_ID, payload);
      lastHistory = millis();
    }
  } else {
    Serial.println("No WiFi, skipping upload.");
  }

  delay(5000);
}
