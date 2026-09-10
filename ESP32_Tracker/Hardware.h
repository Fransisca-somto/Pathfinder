#ifndef HARDWARE_H
#define HARDWARE_H

#include <Arduino.h>

// ==========================================================
//  HARDWARE PIN MAP — PathFinder Vehicle Tracker (ESP32)
// ==========================================================
//  Serial Ports:
//    Serial0 (GPIO 1, 3):   USB Debug Monitor
//    Serial1 (GPIO 16, 17): A7670E LTE Modem
//    Serial2 (GPIO 4, 13):  NEO-6M GPS Module
//    SoftwareSerial (GPIO 32, 33): ZW111 Fingerprint Sensor
// ==========================================================

// --- GPS Module (NEO-6M) --- Hardware Serial2
const int GPS_RX_PIN = 4;
const int GPS_TX_PIN = 13;
const int GPS_BAUD = 9600;

// --- A7670E Modem (LTE) --- Hardware Serial1
const int MODEM_RX_PIN = 16;
const int MODEM_TX_PIN = 17;
const int MODEM_BAUD = 115200;

// --- Fingerprint Sensor (ZW111) --- SoftwareSerial
const int FINGERPRINT_RX = 32;
const int FINGERPRINT_TX = 33;

// --- Relays (Engine Immobilization) ---
const int ACC_RELAY_PIN = 26;       // ACC authorization relay
const int FUEL_PUMP_RELAY_PIN = 27; // Fuel cutoff relay

// --- Inputs ---
const int PANIC_BUTTON_PIN = 39; // SOS Button (Sensor VN, input only)
const int ACC_IGNITION_PIN = 34; // PC817 optocoupler ACC detection (input only)
const int BATTERY_PIN = 35; // Voltage divider for 12V car battery (input only)

// --- Temperature Sensor (DS18B20 / LM35) ---
const int TEMP_SENSOR_PIN = 25;

// --- SD Card (SPI) ---
const int SD_CS_PIN = 5;
// MOSI = 23, MISO = 19, SCK = 18

// --- Accelerometer (MPU6050) ---
// SDA = 21, SCL = 22
const int MPU_INT_PIN = 36; // Interrupt pin (Sensor VP, input only)

// --- User Feedback ---
const int ALARM_SIREN_PIN = 14; // High decibel buzzer (alarm)
const int LED_RED = 2;          // Red status LED
const int LED_GREEN = 15;       // Green status LED

#endif
