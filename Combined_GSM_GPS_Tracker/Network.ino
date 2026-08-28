#include "Hardware.h"
#include <esp_mac.h>

#define TINY_GSM_MODEM_SIM7600
#include <TinyGsmClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <SD.h>

extern String pendingFileUpload;

// --- APN Configuration (MTN Nigeria) ---
const char apn[]      = "web.gprs.mtnnigeria.net";
const char gprsUser[] = "";
const char gprsPass[] = "";

// --- MQTT Configuration ---
const char* mqtt_server = "broker.hivemq.com";
const int mqtt_port = 1883;
const char* mqtt_topic_telemetry = "pathfinder/telemetry";

HardwareSerial SerialAT(1);
TinyGsm modem(SerialAT);
TinyGsmClient mqttGsmClient(modem, 0);      // MUX 0 for MQTT (Keep-alive)
TinyGsmClient gsmClient(modem, 1);          // MUX 1 for HTTP Uploads
PubSubClient mqttClient(mqttGsmClient);

extern String deviceId;
extern void logSystemEvent(String eventType, String details);
extern void triggerEnrollment(int id);
extern void triggerDeleteFingerprint(int id);
extern void setAuthBypass(bool state);
extern void setDriverStatus(int id, bool isActive);

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message;
  for (int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  Serial.print("Command received: ");
  Serial.println(message);

  if (String(topic) == "pathfinder/commands") {
    StaticJsonDocument<200> doc;
    if (!deserializeJson(doc, message)) {
      String targetDevice = doc["deviceId"];
      if (targetDevice == deviceId) {
        String command = doc["command"];
        if (command == "enrollFingerprint") {
          int driverId = doc["payload"]["driverId"] | doc["driverId"] | 1;
          triggerEnrollment(driverId);
        } else if (command == "deleteFingerprint") {
          int driverId = doc["payload"]["driverId"] | doc["driverId"] | 1;
          triggerDeleteFingerprint(driverId);
        } else if (command == "setAuthBypass") {
          bool state = doc["payload"]["state"] | doc["state"];
          setAuthBypass(state);
        } else if (command == "setDriverStatus") {
          int driverId = doc["payload"]["driverId"];
          bool isActive = doc["payload"]["isActive"];
          setDriverStatus(driverId, isActive);
        }
      }
    }
  }
}

void reconnectMQTT() {
  while (!mqttClient.connected()) {
    Serial.print("Attempting MQTT connection...");
    String clientId = "Pathfinder-" + deviceId + "-" + String(random(0xffff), HEX);
    
    // Try connecting without the LWT (Last Will and Testament) first, 
    // since the minimal test proved that a simple connect works perfectly.
    if (mqttClient.connect(clientId.c_str())) {
      Serial.println("connected");
      logSystemEvent("MQTT", "Connected to broker");
      
      // We just came online! Let the server know immediately
      String onlineMsg = "{\"deviceId\":\"" + deviceId + "\",\"status\":\"online\"}";
      mqttClient.publish(mqtt_topic_telemetry, onlineMsg.c_str());
      
      // Subscribe to commands topic
      mqttClient.subscribe("pathfinder/commands");
      
    } else {
      Serial.print("failed, rc=");
      Serial.print(mqttClient.state());
      Serial.println(" try again in 5 seconds");
      logSystemEvent("MQTT_ERROR", "Failed to connect. rc=" + String(mqttClient.state()));
      delay(5000);
    }
  }
}

void setupNetwork() {
  Serial.println("Initializing A7670E Modem...");
  
  // Get MAC Address for deviceId
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  deviceId = String(macStr);
  Serial.print("Unique Device ID: ");
  Serial.println(deviceId);

  SerialAT.begin(MODEM_BAUD, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);
  delay(3000);

  Serial.println("Restarting modem...");
  modem.restart();
  
  Serial.print("Waiting for network...");
  if (!modem.waitForNetwork()) {
    Serial.println(" fail");
    delay(10000);
    return;
  }
  Serial.println(" success");

  if (modem.isNetworkConnected()) {
    Serial.println("Network connected");
  }

  Serial.print("Connecting to APN: ");
  Serial.print(apn);
  if (!modem.gprsConnect(apn, gprsUser, gprsPass)) {
    Serial.println(" fail");
    delay(10000);
    return;
  }
  Serial.println(" success");

  if (modem.isGprsConnected()) {
    Serial.println("GPRS connected");
    logSystemEvent("Network", "Connected to Cellular Data");
  }

  // Set ADC attenuation for battery voltage reading
  analogSetPinAttenuation(BATTERY_PIN, ADC_11db);

  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
  
  // Increase timeouts for cellular networks (default is often too short for GPRS)
  mqttClient.setKeepAlive(60);
  mqttClient.setSocketTimeout(30);
}

void loopNetwork() {
  if (!modem.isNetworkConnected()) {
    Serial.println("Network disconnected");
    if (!modem.waitForNetwork(180000L, true)) {
      Serial.println(" fail");
      delay(10000);
      return;
    }
    if (modem.isNetworkConnected()) {
      Serial.println("Network re-connected");
    }
  }

  if (!modem.isGprsConnected()) {
    Serial.println("GPRS disconnected!");
    Serial.print("Connecting to APN: ");
    Serial.print(apn);
    if (!modem.gprsConnect(apn, gprsUser, gprsPass)) {
      Serial.println(" fail");
      delay(10000);
      return;
    }
    if (modem.isGprsConnected()) {
      Serial.println("GPRS reconnected");
    }
  }

  if (!mqttClient.connected()) {
    reconnectMQTT();
  }
  mqttClient.loop();

  // Check if there's a file waiting to be uploaded from the SD card
  extern void processPendingUploads();
  processPendingUploads();
}

extern float getVehicleTemperature();

float getCarBatteryVoltage() {
  // Average 32 ADC reads for stability
  long adcSum = 0;
  for (int i = 0; i < 32; i++) {
    adcSum += analogRead(BATTERY_PIN);
    delayMicroseconds(100);
  }
  float voltageAtPin = (adcSum / 32.0 / 4095.0) * 3.3;
  // Calibrated from real measurement: 13.72V battery = 1.003V at ADC
  float calibrationFactor = 13.68;
  return voltageAtPin * calibrationFactor;
}

void publishTelemetry(float lat, float lng, float speed, int satellites) {
  if (!mqttClient.connected()) return;

  StaticJsonDocument<200> doc;
  doc["deviceId"] = deviceId;
  doc["lat"] = lat;
  doc["lng"] = lng;
  doc["speed"] = speed;
  doc["satellites"] = satellites;
  doc["status"] = (speed > 5) ? "moving" : "parked";
  doc["temperature"] = getVehicleTemperature();
  doc["battery_voltage"] = getCarBatteryVoltage();

  char jsonBuffer[512];
  serializeJson(doc, jsonBuffer);

  Serial.print("Publishing telemetry: ");
  Serial.println(jsonBuffer);
  
  mqttClient.publish(mqtt_topic_telemetry, jsonBuffer);
}

void publishAlert(String type, String message) {
  if (!mqttClient.connected()) return;

  StaticJsonDocument<200> doc;
  doc["deviceId"] = deviceId;
  doc["type"] = type;
  doc["message"] = message;

  char jsonBuffer[256];
  serializeJson(doc, jsonBuffer);

  Serial.print("Publishing alert: ");
  Serial.println(jsonBuffer);
  
  mqttClient.publish("pathfinder/alerts", jsonBuffer);
}

void processPendingUploads() {
  if (pendingFileUpload == "") return;
  
  if (!modem.isGprsConnected()) {
    Serial.println("[Network] Cannot upload, GPRS disconnected.");
    return;
  }

  String filePath = pendingFileUpload;
  pendingFileUpload = ""; // Clear flag

  Serial.print("[Network] Uploading file to server: ");
  Serial.println(filePath);

  File file = SD.open(filePath, FILE_READ);
  if (!file) {
    Serial.println("[Network] Failed to open file for reading!");
    return;
  }

  String server = "pathfinder-unizk.up.railway.app";
  int port = 80;

  Serial.print("[Network] Connecting to ");
  Serial.println(server);

  if (!gsmClient.connect(server.c_str(), port)) {
    Serial.println("[Network] Connection failed! Will try again later.");
    pendingFileUpload = filePath; // Restore flag to retry
    file.close();
    return;
  }

  // Construct HTTP POST multipart/form-data payload
  String boundary = "----PathfinderBoundary123456";
  String contentType = filePath.endsWith(".wav") ? "audio/wav" : "image/jpeg";
  
  String head = "--" + boundary + "\r\n";
  head += "Content-Disposition: form-data; name=\"file\"; filename=\"" + filePath.substring(1) + "\"\r\n";
  head += "Content-Type: " + contentType + "\r\n\r\n";
  
  String tail = "\r\n--" + boundary + "--\r\n";
  
  uint32_t contentLength = head.length() + file.size() + tail.length();

  Serial.println("[Network] Sending HTTP POST request...");
  
  gsmClient.print(String("POST /api/upload HTTP/1.1\r\n"));
  gsmClient.print(String("Host: ") + server + "\r\n");
  gsmClient.print(String("Content-Length: ") + String(contentLength) + "\r\n");
  gsmClient.print(String("Content-Type: multipart/form-data; boundary=") + boundary + "\r\n");
  gsmClient.print(String("X-Device-ID: ") + deviceId + "\r\n"); // Identifying the tracker
  gsmClient.print("\r\n");
  
  // Send body header
  gsmClient.print(head);

  // Send file chunks
  const int chunk_size = 512;
  uint8_t buffer[chunk_size];
  while (file.available()) {
    int bytesRead = file.read(buffer, chunk_size);
    gsmClient.write(buffer, bytesRead);
  }
  file.close();
  
  // Send body tail
  gsmClient.print(tail);

  Serial.println("[Network] Upload complete, waiting for response...");
  
  unsigned long timeout = millis();
  while (gsmClient.connected() && millis() - timeout < 10000) {
    while (gsmClient.available()) {
      char c = gsmClient.read();
      Serial.print(c);
      timeout = millis();
    }
  }
  Serial.println("\n[Network] --- Upload Finished ---");
  gsmClient.stop();
  
  // Clean up the file so we don't fill the SD card
  SD.remove(filePath);
}
