#include "Hardware.h"
#include <TinyGPSPlus.h>
#include <esp_sleep.h>

// --- Global Objects shared across tabs ---
String deviceId;
TinyGPSPlus gps;

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



  // --- Security Logic: Unauthorized Movement ---
  bool isEngineLocked = (digitalRead(ACC_RELAY_PIN) == LOW);
  bool isMoving = (gps.speed.isValid() && gps.speed.kmph() > 5.0);

  if (isEngineLocked && isMoving) {
    digitalWrite(ALARM_SIREN_PIN, HIGH); // Sound alarm if moving while locked
    extern void publishAlert(String, String);
    static unsigned long lastMovingAlert = 0;
    if (millis() - lastMovingAlert > 10000) {
      publishAlert("danger", "UNAUTHORIZED MOVEMENT DETECTED!");
      lastMovingAlert = millis();
    }
  }

  // --- Deep Sleep Logic ---
  bool isAccOff = (digitalRead(ACC_IGNITION_PIN) == HIGH);

  if (isMoving || !isAccOff) {
    lastMovingTime = millis(); // Reset sleep timer
  }

  if (isAccOff && !isMoving && (millis() - lastMovingTime > DEEP_SLEEP_TIMEOUT_MS)) {
    Serial.println("ACC is OFF and vehicle parked for 30 mins.");
    Serial.println("Going to Deep Sleep for 1 hour to save battery...");
    
    // Enable timer wakeup (1 hour = 3600 seconds)
    esp_sleep_enable_timer_wakeup(3600ULL * 1000000ULL);
    
    // Optional: Turn off modem to save power before sleeping
    // modem.poweroff(); 

    esp_deep_sleep_start();
  }
}
