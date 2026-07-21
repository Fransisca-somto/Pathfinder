#include <Adafruit_Fingerprint.h>
#include <Preferences.h>
#include <SoftwareSerial.h>
#include "Hardware.h"

SoftwareSerial fingerSerial(FINGERPRINT_RX, FINGERPRINT_TX);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&fingerSerial);
Preferences preferences;

#ifndef FINGERPRINT_TIMEOUT
#define FINGERPRINT_TIMEOUT 0x0A
#endif

// State management
bool enrollMode = false;
int enrollId = -1;
unsigned long lastScanTime = 0;
bool authBypass = false;

// 5-strike system
int failedAttempts = 0;

extern void publishAlert(String type, String message);

void beep(int times, int durationMs) {
  for (int i = 0; i < times; i++) {
    digitalWrite(BUZZER_PIN, HIGH);
    delay(durationMs);
    digitalWrite(BUZZER_PIN, LOW);
    if (i < times - 1) delay(durationMs);
  }
}

void blinkLED(int pin, int durationMs) {
  digitalWrite(pin, HIGH);
  delay(durationMs);
  digitalWrite(pin, LOW);
}

void setupFingerprint() {
  Serial.println("Initializing ZW111 Fingerprint Sensor...");
  
  preferences.begin("pathfinder", false);
  
  pinMode(ACC_RELAY_PIN, OUTPUT);
  pinMode(FUEL_PUMP_RELAY_PIN, OUTPUT);
  digitalWrite(ACC_RELAY_PIN, LOW);       // LOW = Locked
  digitalWrite(FUEL_PUMP_RELAY_PIN, LOW); // LOW = Locked
  
  pinMode(LED_GREEN, OUTPUT);
  pinMode(LED_RED, OUTPUT);
  pinMode(BUZZER_PIN, OUTPUT);
  pinMode(ALARM_SIREN_PIN, OUTPUT);
  
  digitalWrite(LED_GREEN, LOW);
  digitalWrite(LED_RED, LOW);
  digitalWrite(BUZZER_PIN, LOW);
  digitalWrite(ALARM_SIREN_PIN, LOW);

  fingerSerial.begin(57600);
  finger.begin(57600);
  
  if (finger.verifyPassword()) {
    Serial.println("ZW111 Fingerprint Sensor Found!");
  } else {
    Serial.println("Did not find fingerprint sensor :(");
  }
}

void triggerEnrollment(int id) {
  enrollMode = true;
  enrollId = id;
  Serial.print("Entered Enrollment Mode for ID: ");
  Serial.println(id);
}

void setDriverStatus(int id, bool isActive) {
  preferences.begin("pathfinder", false);
  preferences.putBool(String(id).c_str(), !isActive);
  Serial.print("Driver ID "); Serial.print(id); 
  Serial.println(isActive ? " activated" : " deactivated");
}

void triggerDeleteFingerprint(int id) {
  uint8_t p = finger.deleteModel(id);
  if (p == FINGERPRINT_OK) {
    Serial.println("Deleted fingerprint successfully");
    publishAlert("system", "Fingerprint deleted for ID " + String(id));
  } else {
    Serial.print("Failed to delete fingerprint. Error: ");
    Serial.println(p);
  }
}

extern TinyGPSPlus gps;

void setAuthBypass(bool state) {
  // Remote immobilization logic
  if (!state) { // Trying to lock the engine
    if (gps.speed.isValid() && gps.speed.kmph() >= 20.0) {
      Serial.println("Cannot remotely immobilize: Speed is >= 20 km/h!");
      publishAlert("system", "Remote immobilization rejected. Vehicle speed > 20km/h.");
      return;
    }
  }

  authBypass = state;
  if (authBypass) {
    digitalWrite(ACC_RELAY_PIN, HIGH);
    digitalWrite(FUEL_PUMP_RELAY_PIN, HIGH);
    Serial.println("Auth Bypass ENABLED: Engine unlocked.");
    publishAlert("system", "Authentication bypassed, engine unlocked.");
  } else {
    digitalWrite(ACC_RELAY_PIN, LOW);
    digitalWrite(FUEL_PUMP_RELAY_PIN, LOW);
    Serial.println("Auth Bypass DISABLED: Engine locked.");
    publishAlert("system", "Authentication enabled, engine locked.");
  }
}

uint8_t getFingerprintEnroll() {
  int p = -1;
  Serial.print("Waiting for valid finger to enroll as ID "); Serial.println(enrollId);
  unsigned long startMillis = millis();
  
  while (p != FINGERPRINT_OK) {
    if (millis() - startMillis > 60000) {
      publishAlert("system", "Fingerprint enrollment timeout");
      return FINGERPRINT_TIMEOUT;
    }
    p = finger.getImage();
    switch (p) {
      case FINGERPRINT_OK: break;
      case FINGERPRINT_NOFINGER: break;
      case FINGERPRINT_PACKETRECIEVEERR: break;
      case FINGERPRINT_IMAGEFAIL: break;
      default: break;
    }
    delay(100);
  }

  p = finger.image2Tz(1);
  if (p != FINGERPRINT_OK) return p;
  
  Serial.println("Remove finger");
  delay(2000);
  p = 0;
  while (p != FINGERPRINT_NOFINGER) {
    p = finger.getImage();
  }
  
  Serial.println("Place same finger again");
  startMillis = millis();
  while (p != FINGERPRINT_OK) {
    if (millis() - startMillis > 60000) {
      publishAlert("system", "Fingerprint enrollment timeout");
      return FINGERPRINT_TIMEOUT;
    }
    p = finger.getImage();
    delay(100);
  }

  p = finger.image2Tz(2);
  if (p != FINGERPRINT_OK) return p;
  
  p = finger.createModel();
  if (p != FINGERPRINT_OK) return p;
  
  p = finger.storeModel(enrollId);
  if (p == FINGERPRINT_OK) {
    publishAlert("system", "Fingerprint enrollment successful");
    beep(1, 500);
    blinkLED(LED_GREEN, 1000);
  } else {
    publishAlert("system", "Failed to store fingerprint model");
    beep(2, 200);
    blinkLED(LED_RED, 1000);
  }
  return p;
}

void handleAuthSuccess(int id) {
  failedAttempts = 0;
  digitalWrite(ALARM_SIREN_PIN, LOW); // Turn off alarm if it was on
  
  digitalWrite(ACC_RELAY_PIN, HIGH);
  digitalWrite(FUEL_PUMP_RELAY_PIN, HIGH);
  
  publishAlert("authSuccess", "Engine Unlocked by Driver ID " + String(id));
  
  blinkLED(LED_GREEN, 1000);
  beep(1, 1000);
}

void handleAuthFailure() {
  failedAttempts++;
  Serial.print("Failed attempts: "); Serial.println(failedAttempts);
  
  blinkLED(LED_RED, 1000);
  beep(2, 200);
  
  if (failedAttempts == 3) {
    publishAlert("authFailure", "3 failed attempts. Capturing silent image...");
    // Future: trigger ESP-NOW to camera
  } else if (failedAttempts == 4) {
    publishAlert("authFailure", "4 failed attempts. Warning!");
  } else if (failedAttempts >= 5) {
    publishAlert("authFailure", "CRITICAL: 5 failed attempts! Alarm activated!");
    digitalWrite(ALARM_SIREN_PIN, HIGH); // Main alarm ON
  } else {
    publishAlert("authFailure", "Unauthorized ignition attempt detected!");
  }
}

void loopFingerprint() {
  if (enrollMode && enrollId >= 0) {
    getFingerprintEnroll();
    enrollMode = false;
    return;
  }

  if (authBypass) return;

  if (millis() - lastScanTime < 500) return;
  lastScanTime = millis();

  uint8_t p = finger.getImage();
  if (p != FINGERPRINT_OK) return; 

  p = finger.image2Tz();
  if (p != FINGERPRINT_OK) return;

  p = finger.fingerSearch();
  if (p == FINGERPRINT_OK) {
    bool isDisabled = preferences.getBool(String(finger.fingerID).c_str(), false);
    if (isDisabled) {
      publishAlert("authFailure", "Access denied: Driver ID " + String(finger.fingerID) + " is deactivated.");
      handleAuthFailure();
      return;
    }
    handleAuthSuccess(finger.fingerID);
  } else if (p == FINGERPRINT_NOTFOUND) {
    handleAuthFailure();
  }
}
