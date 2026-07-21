#ifndef HARDWARE_H
#define HARDWARE_H

#include <Arduino.h>

// --- Serial Ports ---
// Serial0 (Pins 1, 3): Debugging
// Serial1 (Pins 16, 17): A7670E Modem
// Serial2 (Pins 4, 13): Neo-6M GPS (Custom pins used in GPS.ino)

// --- GPS Module (NEO-6M) ---
const int GPS_RX_PIN = 4;
const int GPS_TX_PIN = 13;
const int GPS_BAUD   = 9600;

// --- A7670E Modem (LTE) ---
const int MODEM_RX_PIN = 16;
const int MODEM_TX_PIN = 17;
const int MODEM_BAUD   = 115200;

// --- Fingerprint Sensor ---
const int FINGERPRINT_RX = 25;
const int FINGERPRINT_TX = 27;

// --- Relays ---
const int ACC_RELAY_PIN       = 26;
const int FUEL_PUMP_RELAY_PIN = 15;

// --- Inputs ---
const int PANIC_BUTTON_PIN = 39; // Input only, requires external pull-up
const int ACC_IGNITION_PIN = 34; // Input only, 12V -> Optocoupler -> 3.3V

// --- Temperature Sensor ---
const int TEMP_SENSOR_PIN = 32;

// --- SD Card (SPI) ---
const int SD_CS_PIN = 5;
// MOSI = 23, MISO = 19, SCK = 18

// --- Accelerometer (MPU6500) ---
// SDA = 21, SCL = 22

// --- User Feedback ---
const int LED_GREEN       = 12;
const int LED_RED         = 14;
const int BUZZER_PIN      = 2; // Also LED_BUILTIN on some boards
const int ALARM_SIREN_PIN = 33;

#endif
