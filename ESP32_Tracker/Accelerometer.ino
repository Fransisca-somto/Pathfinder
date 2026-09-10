#include <Wire.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include "Hardware.h"

Adafruit_MPU6050 mpu;
bool mpuInitialized = false;

// --- Thresholds & Timers ---
const float CRASH_THRESHOLD_G = 3.5; 
const float THEFT_THRESHOLD_G = 1.5; 
const float G_TO_MS2 = 9.80665; 
const float CRASH_THRESHOLD_MS2 = CRASH_THRESHOLD_G * G_TO_MS2; 
const float THEFT_THRESHOLD_MS2 = THEFT_THRESHOLD_G * G_TO_MS2; 

unsigned long lastCrashAlertTime = 0;
unsigned long lastTheftAlertTime = 0;
const unsigned long ALERT_COOLDOWN_MS = 10000; 

extern void publishAlert(String type, String message);
extern void sendSMS(String phoneNumber, String text);

void setupAccelerometer() {
  Serial.println("Initializing MPU-6050 Accelerometer...");
  
  pinMode(ACC_IGNITION_PIN, INPUT);

  Wire.begin();
  
  if (!mpu.begin()) {
    Serial.println("Failed to find MPU6050 chip!");
    mpuInitialized = false;
    return;
  }
  
  mpu.setAccelerometerRange(MPU6050_RANGE_16_G);
  mpu.setGyroRange(MPU6050_RANGE_500_DEG);
  mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  
  mpuInitialized = true;
}

void loopAccelerometer() {
  if (!mpuInitialized) return;

  sensors_event_t a, g, temp;
  mpu.getEvent(&a, &g, &temp);

  float totalAccel = sqrt(pow(a.acceleration.x, 2) + 
                          pow(a.acceleration.y, 2) + 
                          pow(a.acceleration.z, 2));

  unsigned long now = millis();

  // 1. Crash Detection
  if (totalAccel > CRASH_THRESHOLD_MS2) {
    if (now - lastCrashAlertTime > ALERT_COOLDOWN_MS) {
      Serial.println("⚠️ CRASH DETECTED! High G-Force!");
      publishAlert("crash", "Vehicle crash detected! High impact force recorded.");
      // Optional: sendSMS("+1234567890", "CRASH DETECTED on PathFinder!");
      lastCrashAlertTime = now;
    }
  }

  // 2. Theft Detection (If ACC is OFF and parked)
  bool isAccOff = (digitalRead(ACC_IGNITION_PIN) == HIGH);
  
  if (isAccOff && totalAccel > THEFT_THRESHOLD_MS2) {
    if (now - lastTheftAlertTime > ALERT_COOLDOWN_MS) {
      Serial.println("⚠️ THEFT DETECTED! Vehicle moved while parked!");
      publishAlert("theft", "Theft alert: Vehicle shaken or moved while parked!");
      lastTheftAlertTime = now;
    }
  }
}
