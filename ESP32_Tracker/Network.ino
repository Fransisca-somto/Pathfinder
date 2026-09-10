#include "Hardware.h"
#include <esp_mac.h>

#define TINY_GSM_MODEM_SIM7600
#include <TinyGsmClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <SD.h>



// --- APN Configuration ---
const char apn[]      = "YOUR_APN";
const char gprsUser[] = "";
const char gprsPass[] = "";

// --- MQTT Configuration ---
const char* mqtt_server = "broker.hivemq.com";
const int mqtt_port = 1883;
const char* mqtt_topic_telemetry = "pathfinder/telemetry";

HardwareSerial SerialAT(1);
TinyGsm modem(SerialAT);
TinyGsmClient gsmClient(modem);
PubSubClient mqttClient(gsmClient);

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
    
    // Create the Last Will and Testament (LWT) payload
    String willMessage = "{\"deviceId\":\"" + deviceId + "\",\"status\":\"offline\"}";
    
    // Connect with LWT: connect(clientId, willTopic, willQos, willRetain, willMessage)
    if (mqttClient.connect(clientId.c_str(), mqtt_topic_telemetry, 1, false, willMessage.c_str())) {
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
  snprintf(macStr, sizeof(macStr), "%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
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

  mqttClient.setServer(mqtt_server, mqtt_port);
  mqttClient.setCallback(mqttCallback);
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


}

extern float getVehicleTemperature();

float getCarBatteryVoltage() {
  int rawADC = analogRead(BATTERY_PIN);
  float voltageAtPin = (rawADC / 4095.0) * 3.3; // ESP32 ADC max is 3.3V
  
  // For R1=100k, R2=27k -> Ratio = 4.703
  float ratio = 4.703; 
  return voltageAtPin * ratio;
}

int getCarBatteryPercentage() {
  float voltage = getCarBatteryVoltage();
  if (voltage < 5.0) return 0; // Main battery disconnected/stolen
  if (voltage >= 12.6) return 100;
  if (voltage <= 11.9) return 0;
  
  float percentage = ((voltage - 11.9) / (12.6 - 11.9)) * 100.0;
  return (int)percentage;
}

void publishTelemetry(float lat, float lng, float speed, int satellites) {
  if (!mqttClient.connected()) return;

  StaticJsonDocument<200> doc;
  doc["deviceId"] = deviceId;
  doc["lat"] = lat;
  doc["lng"] = lng;
  doc["speed"] = speed;
  doc["satellites"] = satellites;
  doc["acc"] = (digitalRead(ACC_IGNITION_PIN) == LOW);
  doc["status"] = (speed > 5) ? "moving" : "parked";
  doc["temperature"] = getVehicleTemperature();
  doc["battery"] = getCarBatteryPercentage();
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


