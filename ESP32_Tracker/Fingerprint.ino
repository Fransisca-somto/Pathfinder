// =========================================================
//  Fingerprint.ino — ZW111 Fingerprint Authentication Module
// =========================================================
//  Uses Hardware Serial2 (no SoftwareSerial needed on ESP32).
//  Uses Preferences (NVS flash storage) to remember which
//  driver IDs have been deactivated by the owner, even after
//  a power cycle or reboot.
// =========================================================

#include <SoftwareSerial.h>
#include <Adafruit_Fingerprint.h>
#include <Preferences.h>
#include "Hardware.h"

// Use SoftwareSerial for fingerprint so Serial2 is free for GPS module
SoftwareSerial fingerSerial(FINGERPRINT_RX, FINGERPRINT_TX);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&fingerSerial);

// --- NVS (Non-Volatile Storage) via Preferences ---
// Preferences stores key-value pairs in the ESP32's flash memory.
// We use it to persistently track which driver slot IDs are
// disabled/deactivated. This data survives reboots and power loss.
// Example: preferences.putBool("3", true) means driver slot 3 is disabled.
Preferences preferences;

// Enrollment timeout (in case sensor never receives a finger)
#ifndef FINGERPRINT_TIMEOUT
#define FINGERPRINT_TIMEOUT 0x0A
#endif

// --- State Variables ---
bool enrollMode = false;   // True when the owner triggers remote enrollment
int enrollId = -1;         // The slot ID to enroll a new fingerprint into
unsigned long lastScanTime = 0; // Throttle: prevents scanning too rapidly
bool authBypass = false;   // True when the owner remotely bypasses fingerprint auth

// --- 5-Strike Security System ---
int failedAttempts = 0;
// Strike 1-2: Beep + Red LED warning
// Strike 3:   Silent camera capture alert sent to owner
// Strike 4:   Escalated warning alert
// Strike 5+:  Full alarm siren activated

// External function from Network.ino to send alerts to the backend
extern void publishAlert(String type, String message);

// External GPS object from ESP32_Tracker.ino for speed-based safety checks
extern TinyGPSPlus gps;


// =========================
//  UTILITY FUNCTIONS
// =========================

// Beep the buzzer a specified number of times
void beep(int times, int durationMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(durationMs);
    digitalWrite(BUZZER_PIN, LOW);
    if (i < times - 1) delay(durationMs);
  }
}

// Flash an LED once for a given duration
void blinkLED(int pin, int durationMs) {
  digitalWrite(pin, HIGH);
  delay(durationMs);
  digitalWrite(pin, LOW);
}


// =========================
//  SETUP
// =========================

void setupFingerprint() {
  Serial.println("Initializing ZW111 Fingerprint Sensor...");

  // Open the "pathfinder" namespace in NVS for reading/writing
  preferences.begin("pathfinder", false);

  // Configure relay pins (engine immobilization)
  pinMode(ACC_RELAY_PIN, OUTPUT);
  pinMode(FUEL_PUMP_RELAY_PIN, OUTPUT);
  digitalWrite(ACC_RELAY_PIN, LOW);       // LOW = Engine Locked
  digitalWrite(FUEL_PUMP_RELAY_PIN, LOW); // LOW = Fuel Pump Off

  // Configure feedback pins
  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_RED, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(ALARM_SIREN_PIN, OUTPUT);

  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_RED, LOW);
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(ALARM_SIREN_PIN, LOW);

  // Initialize SoftwareSerial for the fingerprint sensor
  fingerSerial.begin(57600);
  finger.begin(57600);

  if (finger.verifyPassword()) {
    Serial.println("ZW111 Fingerprint Sensor Found!");
  } else {
    Serial.println("ERROR: Fingerprint sensor not detected. Check wiring.");
  }
}


// ======================================
//  REMOTE COMMANDS (called from MQTT)
// ======================================

// Called when the owner taps "Enroll New Driver" in the app
void triggerEnrollment(int id) {
  enrollMode = true;
  enrollId = id;
  Serial.print("Enrollment mode activated for slot ID: ");
  Serial.println(id);
}

// Called when the owner taps "Activate/Deactivate Driver" in the app.
// Uses Preferences (NVS) to persist the state across reboots.
void setDriverStatus(int id, bool isActive) {
  // Store the DISABLED state: true = disabled, false = enabled
  preferences.putBool(String(id).c_str(), !isActive);
  Serial.print("Driver ID ");
  Serial.print(id);
  Serial.println(isActive ? " ACTIVATED" : " DEACTIVATED");
}

// Called when the owner taps "Delete Fingerprint" in the app
void triggerDeleteFingerprint(int id) {
  uint8_t p = finger.deleteModel(id);
  if (p == FINGERPRINT_OK) {
    Serial.println("Fingerprint deleted successfully.");
    // Also clear the NVS entry for this slot
    preferences.remove(String(id).c_str());
    publishAlert("system", "Fingerprint deleted for ID " + String(id));
  } else {
    Serial.print("Failed to delete fingerprint. Error code: ");
    Serial.println(p);
  }
}

// Called when the owner taps "Lock/Unlock Engine" in the app.
// Includes a safety check: cannot remotely lock at high speed.
void setAuthBypass(bool state) {
  if (!state) {
    // Trying to LOCK the engine remotely
    if (gps.speed.isValid() && gps.speed.kmph() >= 20.0) {
      Serial.println("SAFETY: Cannot lock engine at >= 20 km/h!");
      publishAlert("system", "Remote lock rejected. Vehicle speed > 20km/h.");
      return;
    }
  }

  authBypass = state;

  if (authBypass) {
    // Bypass ON: unlock engine without fingerprint
    digitalWrite(ACC_RELAY_PIN, HIGH);
    digitalWrite(FUEL_PUMP_RELAY_PIN, HIGH);
    Serial.println("Auth Bypass ENABLED: Engine unlocked remotely.");
    publishAlert("system", "Authentication bypassed, engine unlocked.");
  } else {
    // Bypass OFF: re-enable fingerprint requirement, lock engine
    digitalWrite(ACC_RELAY_PIN, LOW);
    digitalWrite(FUEL_PUMP_RELAY_PIN, LOW);
    Serial.println("Auth Bypass DISABLED: Engine locked.");
    publishAlert("system", "Authentication enabled, engine locked.");
  }
}


// ======================================
//  FINGERPRINT ENROLLMENT PROCESS
// ======================================

uint8_t getFingerprintEnroll() {
  int p = -1;
  Serial.print("Waiting for finger to enroll as ID ");
  Serial.println(enrollId);

  unsigned long startMillis = millis();

  // Step 1: Capture first image (with 60-second timeout)
  while (p != FINGERPRINT_OK) {
    if (millis() - startMillis > 60000) {
      publishAlert("system", "Fingerprint enrollment timeout.");
      return FINGERPRINT_TIMEOUT;
    }
    p = finger.getImage();
    delay(100);
  }

  p = finger.image2Tz(1);
  if (p != FINGERPRINT_OK) return p;

  // Step 2: Ask user to remove finger
  Serial.println("Image 1 captured. Remove finger...");
  delay(2000);
  p = 0;
  while (p != FINGERPRINT_NOFINGER) {
    p = finger.getImage();
  }

  // Step 3: Capture second image of the same finger
  Serial.println("Place the SAME finger again...");
  startMillis = millis();
  p = -1;
  while (p != FINGERPRINT_OK) {
    if (millis() - startMillis > 60000) {
      publishAlert("system", "Fingerprint enrollment timeout.");
      return FINGERPRINT_TIMEOUT;
    }
    p = finger.getImage();
    delay(100);
  }

  p = finger.image2Tz(2);
  if (p != FINGERPRINT_OK) return p;

  // Step 4: Create and store the model
  Serial.println("Creating fingerprint model...");
  p = finger.createModel();
  if (p != FINGERPRINT_OK) return p;

  p = finger.storeModel(enrollId);
  if (p == FINGERPRINT_OK) {
    Serial.print("SUCCESS: Fingerprint stored as ID #");
    Serial.println(enrollId);
    publishAlert("system", "Fingerprint enrollment successful.");
    beep(1, 500);
    blinkLED(LED_GREEN, 1000);
  } else {
    Serial.println("ERROR: Failed to store fingerprint model.");
    publishAlert("system", "Failed to store fingerprint model.");
    beep(2, 200);
    blinkLED(LED_RED, 1000);
  }
  return p;
}


// ======================================
//  AUTHENTICATION RESULT HANDLERS
// ======================================

void handleAuthSuccess(int id) {
  failedAttempts = 0;
  digitalWrite(ALARM_SIREN_PIN, LOW); // Silence alarm if it was triggered

  // Unlock the engine
  digitalWrite(ACC_RELAY_PIN, HIGH);
  digitalWrite(FUEL_PUMP_RELAY_PIN, HIGH);

  publishAlert("authSuccess", "Engine Unlocked by Driver ID " + String(id));
  blinkLED(LED_GREEN, 1000);
  beep(1, 1000);
}

void handleAuthFailure() {
  failedAttempts++;
  Serial.print("Failed attempts: ");
  Serial.println(failedAttempts);

  blinkLED(LED_RED, 1000);
  beep(2, 200);

  // Escalating security response based on strike count
  if (failedAttempts == 3) {
    publishAlert("authSilent", "3 failed attempts. Capturing silent image...");
  } else if (failedAttempts == 4) {
    publishAlert("authSilent", "4 failed attempts. Warning!");
  } else if (failedAttempts >= 5) {
    publishAlert("authFailure", "CRITICAL: 5 failed attempts! Alarm activated!");
    digitalWrite(ALARM_SIREN_PIN, HIGH); // Full alarm siren ON
  } else {
    publishAlert("authSilent", "Silent: Unauthorized fingerprint scan attempt.");
  }
}


// ======================================
//  MAIN LOOP (called every cycle)
// ======================================

void loopFingerprint() {
  // If enrollment was triggered remotely, handle it first
  if (enrollMode && enrollId >= 0) {
    getFingerprintEnroll();
    enrollMode = false;
    return;
  }

  // If the owner has remotely bypassed authentication, skip scanning
  if (authBypass) return;

  // Throttle: only scan every 500ms to avoid flooding the sensor
  if (millis() - lastScanTime < 500) return;
  lastScanTime = millis();

  // Try to capture a fingerprint image
  uint8_t p = finger.getImage();
  if (p != FINGERPRINT_OK) return; // No finger on sensor, skip

  // Convert the image to a template
  p = finger.image2Tz();
  if (p != FINGERPRINT_OK) return;

  // Search the sensor's internal database for a match
  p = finger.fingerSearch();

  if (p == FINGERPRINT_OK) {
    // Match found! But check if this driver is deactivated via Preferences (NVS)
    bool isDisabled = preferences.getBool(String(finger.fingerID).c_str(), false);
    if (isDisabled) {
      publishAlert("authFailure", "Access denied: Driver ID " + String(finger.fingerID) + " is deactivated.");
      handleAuthFailure();
      return;
    }
    // Driver is active, unlock the engine
    handleAuthSuccess(finger.fingerID);
  } else if (p == FINGERPRINT_NOTFOUND) {
    // No match in the database
    handleAuthFailure();
  }
}
