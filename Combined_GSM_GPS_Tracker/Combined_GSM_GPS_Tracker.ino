#include "Hardware.h"
#include <esp_sleep.h>
#include <PubSubClient.h>

// --- Global Objects shared across tabs ---
String deviceId;
float currentVehicleSpeed = 0.0;
extern PubSubClient mqttClient;

// --- Function Declarations from other tabs ---
void setupSDCard();
void setupNetwork();
void loopNetwork();
void loopModem();
void publishTelemetry(float lat, float lng, float speed, int satellites);

void setupGPS();
void loopGPS();

void setupSOS();
void loopSOS();

void setupAccelerometer();
void loopAccelerometer();

void setupFingerprint();
void loopFingerprint();

void setupTemperature();
void loopTemperature();

void setupCameraServer();
void loopCameraServer();

unsigned long lastMovingTime = 0;
const unsigned long DEEP_SLEEP_TIMEOUT_MS = 1800000; // 30 minutes

void setup() {
  Serial.begin(115200);
  
  // If we woke up from deep sleep, we can log it
  esp_sleep_wakeup_cause_t wakeup_reason = esp_sleep_get_wakeup_cause();
  if (wakeup_reason == ESP_SLEEP_WAKEUP_TIMER) {
    Serial.println("Woke up from deep sleep (Hourly Update)");
  }

  // 0. Initialize SD Card Logger
  setupSDCard();
  
  // 1. Initialize Cellular Network & MQTT
  setupNetwork();
  
  // 2. Initialize Hardware Serial for the GPS module
  setupGPS();

  // 3. Initialize SOS Panic Button
  setupSOS();

  // 4. Initialize MPU6050 Accelerometer
  setupAccelerometer();

  // 5. Initialize Fingerprint Scanner
  setupFingerprint();

  // 6. Initialize Temperature Sensor
  setupTemperature();

  // 7. Initialize Camera Wi-Fi SoftAP and HTTP Server
  setupCameraServer();

  lastMovingTime = millis();
}

void loop() {
  // 1. Keep Modem/MQTT alive and check incoming calls/SMS
  loopNetwork();
  loopModem();
  
  // 2. Read GPS data and publish it
  loopGPS();

  // 3. Monitor Panic Button
  loopSOS();

  // 4. Read Accelerometer for crash/theft detection
  loopAccelerometer();

  // 5. Read Fingerprint for authentication
  loopFingerprint();

  // 6. Read Temperature
  loopTemperature();

  // 7. Handle incoming Camera file uploads over Wi-Fi
  loopCameraServer();

  // --- Deep Sleep Logic ---
  bool isAccOff = (digitalRead(ACC_IGNITION_PIN) == LOW);
  bool isMoving = (currentVehicleSpeed > 5.0);

  if (isMoving || !isAccOff) {
    lastMovingTime = millis(); // Reset sleep timer
  }

  if (isAccOff && !isMoving && (millis() - lastMovingTime > DEEP_SLEEP_TIMEOUT_MS)) {
    Serial.println("ACC is OFF and vehicle parked for 30 mins.");
    Serial.println("Going to Deep Sleep for 1 hour to save battery...");
    
    // Notify server we're going offline
    String offlineMsg = "{\"deviceId\":\"" + deviceId + "\",\"status\":\"offline\"}";
    mqttClient.publish("pathfinder/telemetry", offlineMsg.c_str());
    mqttClient.disconnect();
    delay(500);

    // Enable timer wakeup (1 hour = 3600 seconds)
    esp_sleep_enable_timer_wakeup(3600ULL * 1000000ULL);

    esp_deep_sleep_start();
  }
}
