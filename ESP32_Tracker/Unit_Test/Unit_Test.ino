// ==========================================================
//  PathFinder Hardware Unit Test Suite
// ==========================================================
//  Upload this sketch to test each component individually.
//  Open Serial Monitor at 115200 baud, then type a number
//  from the menu to test that component.
// ==========================================================

#include <Arduino.h>
#include <Wire.h>
Filter your search... Type :

    All Topic :

    All 12345678910111213141516
// Match Sw1 / SENSOR_VN on schematic
#include "Hardware.h"

    // Variables for debounce logic
    int buttonState;
int lastButtonState = HIGH;
unsigned long lastDebounceTime = 0;
unsigned long debounceDelay = 50;

extern String deviceId;

#include <Adafruit_Fingerprint.h>
#include <SD.h>
#include <SPI.h>
#include <SoftwareSerial.h>
#include <TinyGPSPlus.h>
#include <esp_mac.h>

// ---- Pin Definitions (matching Hardware.h) ----
// GPS
#define GPS_RX 4
#define GPS_TX 13
#define GPS_BAUD 9600

// Modem
#define MODEM_RX 16
#define MODEM_TX 17
#define MODEM_BAUD 115200

// Fingerprint
#define FP_RX 32
#define FP_TX 33

// Relays
#define ACC_RELAY 26
#define FUEL_RELAY 27

// Inputs
#define SOS_BTN 39
#define ACC_DETECT 34
#define MPU_INT 36

// Temperature
#define TEMP_PIN 25

// SD Card
#define SD_CS 5

// Feedback
#define BUZZER 12
#define ALARM 14
#define LED_R 2
#define LED_G 15

// ---- Objects ----
HardwareSerial gpsSerial(2);
HardwareSerial modemSerial(1);
SoftwareSerial fpSerial(FP_RX, FP_TX);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&fpSerial);
TinyGPSPlus gps;

// =========================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println();
  Serial.println("=============================================");
  Serial.println("   PATHFINDER — HARDWARE UNIT TEST SUITE");
  Serial.println("=============================================");
  Serial.println();

  // Get Device ID
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X", mac[0],
           mac[1], mac[2], mac[3], mac[4], mac[5]);
  Serial.print("Device MAC: ");
  Serial.println(macStr);
  Serial.println();

  // Configure all output pins
  pinMode(ACC_RELAY, OUTPUT);
  pinMode(FUEL_RELAY, OUTPUT);
  pinMode(BUZZER, OUTPUT);
  pinMode(ALARM, OUTPUT);
  pinMode(LED_R, OUTPUT);
  pinMode(LED_G, OUTPUT);

  // All outputs OFF
  digitalWrite(ACC_RELAY, LOW);
  digitalWrite(FUEL_RELAY, LOW);
  digitalWrite(BUZZER, LOW);
  digitalWrite(ALARM, LOW);
  digitalWrite(LED_R, LOW);
  digitalWrite(LED_G, LOW);

  // Configure input pins
  pinMode(SOS_BTN, INPUT);
  pinMode(ACC_DETECT, INPUT);
  pinMode(MPU_INT, INPUT);

  printMenu();
}

void loop() {
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    int choice = input.toInt();

    Serial.println();
    Serial.println("---------------------------------------------");

    switch (choice) {
    case 1:
      testGPS();
      break;
    case 2:
      testFingerprint();
      break;
    case 3:
      testModem();
      break;
    case 4:
      testMPU6050();
      break;
    case 5:
      testTemperature();
      break;
    case 6:
      testSDCard();
      break;
    case 7:
      testRelays();
      break;
    case 8:
      testBuzzers();
      break;
    case 9:
      testLEDs();
      break;
    case 10:
      testSOSButton();
      break;
    case 11:
      testACCDetection();
      break;
    case 12:
      testAllOutputs();
      break;
    default:
      Serial.println("Invalid choice. Type a number 1-12.");
      break;
    }

    Serial.println("---------------------------------------------");
    Serial.println();
    printMenu();
  }
}

// =========================================================
void printMenu() {
  Serial.println("=== SELECT A COMPONENT TO TEST ===");
  Serial.println("  1.  GPS Module (NEO-6M)");
  Serial.println("  2.  Fingerprint Sensor (ZW111)");
  Serial.println("  3.  Cellular Modem (A7670E)");
  Serial.println("  4.  Accelerometer (MPU6050)");
  Serial.println("  5.  Temperature Sensor");
  Serial.println("  6.  SD Card");
  Serial.println("  7.  Relays (ACC + Fuel)");
  Serial.println("  8.  Buzzers (Piezo + Alarm)");
  Serial.println("  9.  LEDs (Red + Green)");
  Serial.println("  10. SOS Panic Button");
  Serial.println("  11. ACC Ignition Detection");
  Serial.println("  12. ALL Outputs Quick Test");
  Serial.println("==================================");
  Serial.println("Type a number and press Enter:");
}

// =========================================================
//  TEST 1: GPS MODULE
// =========================================================
void testGPS() {
  Serial.println("[TEST] GPS Module (NEO-6M) on Serial2");
  Serial.println("Listening for 15 seconds...");
  Serial.println("(Place antenna near a window for satellite fix)");

  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX, GPS_TX);
  delay(100);

  unsigned long start = millis();
  int charsReceived = 0;

  while (millis() - start < 15000) {
    while (gpsSerial.available()) {
      char c = gpsSerial.read();
      gps.encode(c);
      charsReceived++;
    }
  }

  Serial.print("  Characters received: ");
  Serial.println(charsReceived);

  if (charsReceived < 10) {
    Serial.println("  RESULT: FAIL — No data from GPS.");
    Serial.println("  Check: RX/TX wiring may be swapped.");
  } else {
    Serial.println("  RESULT: PASS — GPS is communicating.");

    if (gps.location.isValid()) {
      Serial.print("  Latitude:   ");
      Serial.println(gps.location.lat(), 6);
      Serial.print("  Longitude:  ");
      Serial.println(gps.location.lng(), 6);
    } else {
      Serial.println("  Location:   Not yet fixed (needs clear sky).");
    }

    if (gps.satellites.isValid()) {
      Serial.print("  Satellites: ");
      Serial.println(gps.satellites.value());
    }
  }

  gpsSerial.end();
}

// =========================================================
//  TEST 2: FINGERPRINT SENSOR
// =========================================================
void testFingerprint() {
  Serial.println("[TEST] Fingerprint Sensor (ZW111) on SoftwareSerial");

  fpSerial.begin(57600);
  finger.begin(57600);
  delay(200);

  if (finger.verifyPassword()) {
    Serial.println("  RESULT: PASS — Sensor detected!");

    finger.getTemplateCount();
    Serial.print("  Stored fingerprints: ");
    Serial.println(finger.templateCount);

    Serial.println("  Place a finger on the sensor within 10 seconds...");

    unsigned long start = millis();
    bool scanned = false;

    while (millis() - start < 10000) {
      uint8_t p = finger.getImage();
      if (p == FINGERPRINT_OK) {
        p = finger.image2Tz();
        if (p == FINGERPRINT_OK) {
          p = finger.fingerSearch();
          if (p == FINGERPRINT_OK) {
            Serial.print("  MATCH FOUND! ID #");
            Serial.print(finger.fingerID);
            Serial.print(" (Confidence: ");
            Serial.print(finger.confidence);
            Serial.println(")");
          } else {
            Serial.println("  Finger scanned but NO MATCH in database.");
          }
          scanned = true;
          break;
        }
      }
      delay(100);
    }

    if (!scanned) {
      Serial.println("  No finger detected (timeout). Sensor still OK.");
    }
  } else {
    Serial.println("  RESULT: FAIL — Sensor not found.");
    Serial.println("  Check: Wiring on GPIO 32 (RX) and GPIO 33 (TX).");
  }

  fpSerial.end();
}

// =========================================================
//  TEST 3: CELLULAR MODEM
// =========================================================
void testModem() {
  Serial.println("[TEST] Cellular Modem (A7670E) on Serial1");
  Serial.println("Sending AT command...");

  modemSerial.begin(MODEM_BAUD, SERIAL_8N1, MODEM_RX, MODEM_TX);
  delay(1000);

  // Send basic AT command
  modemSerial.println("AT");
  delay(1000);

  String response = "";
  while (modemSerial.available()) {
    response += (char)modemSerial.read();
  }

  if (response.indexOf("OK") >= 0) {
    Serial.println("  AT Response: OK");
    Serial.println("  RESULT: PASS — Modem is responding.");

    // Check SIM card
    modemSerial.println("AT+CPIN?");
    delay(1000);
    response = "";
    while (modemSerial.available()) {
      response += (char)modemSerial.read();
    }
    Serial.print("  SIM Status: ");
    if (response.indexOf("READY") >= 0) {
      Serial.println("SIM card detected and ready.");
    } else {
      Serial.println("SIM card issue or not inserted.");
    }
    Serial.print("  Raw: ");
    Serial.println(response);

    // Check signal strength
    modemSerial.println("AT+CSQ");
    delay(1000);
    response = "";
    while (modemSerial.available()) {
      response += (char)modemSerial.read();
    }
    Serial.print("  Signal: ");
    Serial.println(response);

  } else {
    Serial.println("  RESULT: FAIL — No response from modem.");
    Serial.println("  Check: Power supply, RX/TX wiring, baud rate.");
    Serial.print("  Raw response: '");
    Serial.print(response);
    Serial.println("'");
  }

  modemSerial.end();
}

// =========================================================
//  TEST 4: ACCELEROMETER (MPU6050)
// =========================================================
void testMPU6050() {
  Serial.println("[TEST] Accelerometer (MPU6050) on I2C");

  Wire.begin(21, 22); // SDA=21, SCL=22
  delay(100);

  // Wake up MPU6050
  Wire.beginTransmission(0x68);
  Wire.write(0x6B); // PWR_MGMT_1 register
  Wire.write(0x00); // Wake up
  uint8_t error = Wire.endTransmission();

  if (error == 0) {
    Serial.println("  RESULT: PASS — MPU6050 detected at address 0x68.");

    // Read WHO_AM_I register
    Wire.beginTransmission(0x68);
    Wire.write(0x75);
    Wire.endTransmission(false);
    Wire.requestFrom(0x68, 1);
    if (Wire.available()) {
      uint8_t whoAmI = Wire.read();
      Serial.print("  WHO_AM_I: 0x");
      Serial.println(whoAmI, HEX);
    }

    // Read accelerometer data 5 times
    Serial.println("  Reading acceleration (5 samples):");
    for (int i = 0; i < 5; i++) {
      Wire.beginTransmission(0x68);
      Wire.write(0x3B); // ACCEL_XOUT_H
      Wire.endTransmission(false);
      Wire.requestFrom(0x68, 6);

      if (Wire.available() == 6) {
        int16_t ax = Wire.read() << 8 | Wire.read();
        int16_t ay = Wire.read() << 8 | Wire.read();
        int16_t az = Wire.read() << 8 | Wire.read();

        Serial.print("    X=");
        Serial.print(ax / 16384.0, 2);
        Serial.print("g  Y=");
        Serial.print(ay / 16384.0, 2);
        Serial.print("g  Z=");
        Serial.print(az / 16384.0, 2);
        Serial.println("g");
      }
      delay(500);
    }

    // Check interrupt pin
    Serial.print("  INT pin (GPIO 36) state: ");
    Serial.println(digitalRead(MPU_INT) ? "HIGH" : "LOW");

  } else {
    Serial.println("  RESULT: FAIL — MPU6050 not found.");
    Serial.println("  Check: SDA (GPIO 21), SCL (GPIO 22), power.");

    // I2C Scanner
    Serial.println("  Scanning I2C bus...");
    int found = 0;
    for (uint8_t addr = 1; addr < 127; addr++) {
      Wire.beginTransmission(addr);
      if (Wire.endTransmission() == 0) {
        Serial.print("    Found device at 0x");
        Serial.println(addr, HEX);
        found++;
      }
    }
    if (found == 0) {
      Serial.println("    No I2C devices found at all.");
    }
  }
}

// =========================================================
//  TEST 5: TEMPERATURE SENSOR
// =========================================================
void testTemperature() {
  Serial.println("[TEST] Temperature Sensor on GPIO 25");
  Serial.println("Reading analog value 5 times...");
  Serial.println(
      "(If using LM35: Voltage = reading * 3.3/4095, Temp = V * 100)");
  Serial.println("(If using DS18B20: This raw analog test won't work — use "
                 "OneWire library)");

  for (int i = 0; i < 5; i++) {
    int raw = analogRead(TEMP_PIN);
    float voltage = raw * (3.3 / 4095.0);
    float tempC = voltage * 100.0; // LM35 formula

    Serial.print("  Sample ");
    Serial.print(i + 1);
    Serial.print(": Raw=");
    Serial.print(raw);
    Serial.print("  Voltage=");
    Serial.print(voltage, 3);
    Serial.print("V  Temp(LM35)=");
    Serial.print(tempC, 1);
    Serial.println("C");

    delay(1000);
  }

  if (analogRead(TEMP_PIN) > 0) {
    Serial.println("  RESULT: PASS — Sensor is providing readings.");
  } else {
    Serial.println("  RESULT: FAIL — No reading. Check wiring.");
  }
}

// =========================================================
//  TEST 6: SD CARD
// =========================================================
void testSDCard() {
  Serial.println("[TEST] SD Card on SPI (CS = GPIO 5)");

  if (SD.begin(SD_CS)) {
    Serial.println("  RESULT: PASS — SD card detected!");

    uint8_t cardType = SD.cardType();
    Serial.print("  Card Type: ");
    switch (cardType) {
    case CARD_MMC:
      Serial.println("MMC");
      break;
    case CARD_SD:
      Serial.println("SD");
      break;
    case CARD_SDHC:
      Serial.println("SDHC");
      break;
    default:
      Serial.println("Unknown");
      break;
    }

    uint64_t cardSize = SD.cardSize() / (1024 * 1024);
    Serial.print("  Card Size: ");
    Serial.print((uint32_t)cardSize);
    Serial.println(" MB");

    // Try writing a test file
    File testFile = SD.open("/pathfinder_test.txt", FILE_WRITE);
    if (testFile) {
      testFile.println("PathFinder Unit Test - SD Write OK");
      testFile.close();
      Serial.println("  Write Test: PASS");

      // Read it back
      testFile = SD.open("/pathfinder_test.txt");
      if (testFile) {
        Serial.print("  Read Test:  '");
        while (testFile.available()) {
          Serial.write(testFile.read());
        }
        Serial.println("'");
        testFile.close();
      }

      // Clean up
      SD.remove("/pathfinder_test.txt");
    } else {
      Serial.println("  Write Test: FAIL");
    }

    SD.end();
  } else {
    Serial.println("  RESULT: FAIL — SD card not detected.");
    Serial.println("  Check: CS (GPIO 5), MOSI (23), MISO (19), SCK (18).");
  }
}

// =========================================================
//  TEST 7: RELAYS
// =========================================================
void testRelays() {
  Serial.println("[TEST] Relays (ACC + Fuel Cutoff)");
  Serial.println("  You should hear a click sound from each relay.");

  Serial.println("  ACC Relay ON...");
  digitalWrite(ACC_RELAY, HIGH);
  delay(1500);
  Serial.println("  ACC Relay OFF.");
  digitalWrite(ACC_RELAY, LOW);
  delay(500);

  Serial.println("  Fuel Relay ON...");
  digitalWrite(FUEL_RELAY, HIGH);
  delay(1500);
  Serial.println("  Fuel Relay OFF.");
  digitalWrite(FUEL_RELAY, LOW);
  delay(500);

  Serial.println("  Both Relays ON...");
  digitalWrite(ACC_RELAY, HIGH);
  digitalWrite(FUEL_RELAY, HIGH);
  delay(1500);
  Serial.println("  Both Relays OFF.");
  digitalWrite(ACC_RELAY, LOW);
  digitalWrite(FUEL_RELAY, LOW);

  Serial.println("  RESULT: PASS (if you heard clicks).");
}

// =========================================================
//  TEST 8: BUZZERS
// =========================================================
void testBuzzers() {
  Serial.println("[TEST] Buzzers (Piezo + High Decibel Alarm)");

  Serial.println("  Piezo Buzzer (GPIO 12) — 3 short beeps...");
  for (int i = 0; i < 3; i++) {
    digitalWrite(BUZZER, HIGH);
    delay(200);
    digitalWrite(BUZZER, LOW);
    delay(200);
  }
  delay(500);

  Serial.println("  High Decibel Alarm (GPIO 14) — 1 short burst...");
  Serial.println("  WARNING: This will be LOUD!");
  delay(1000);
  digitalWrite(ALARM, HIGH);
  delay(500);
  digitalWrite(ALARM, LOW);

  Serial.println("  RESULT: PASS (if you heard sounds).");
}

// =========================================================
//  TEST 9: LEDs
// =========================================================
void testLEDs() {
  Serial.println("[TEST] LEDs (Red + Green)");

  Serial.println("  Red LED ON (GPIO 2)...");
  digitalWrite(LED_R, HIGH);
  delay(1500);
  digitalWrite(LED_R, LOW);
  Serial.println("  Red LED OFF.");
  delay(300);

  Serial.println("  Green LED ON (GPIO 15)...");
  digitalWrite(LED_G, HIGH);
  delay(1500);
  digitalWrite(LED_G, LOW);
  Serial.println("  Green LED OFF.");
  delay(300);

  Serial.println("  Alternating 5 times...");
  for (int i = 0; i < 5; i++) {
    digitalWrite(LED_R, HIGH);
    digitalWrite(LED_G, LOW);
    delay(300);
    digitalWrite(LED_R, LOW);
    digitalWrite(LED_G, HIGH);
    delay(300);
  }
  digitalWrite(LED_G, LOW);

  Serial.println("  RESULT: PASS (if you saw them blink).");
}

// =========================================================
//  TEST 10: SOS PANIC BUTTON
// =========================================================
void testSOSButton() {
  Serial.println("[TEST] SOS Panic Button (GPIO 39 / Sensor VN)");
  Serial.println("  Press the SOS button within 10 seconds...");
  Serial.println("  (Monitoring pin state. Press button NOW)");

  unsigned long start = millis();
  bool pressed = false;
  int lastState = digitalRead(SOS_BTN);

  while (millis() - start < 10000) {
    int state = digitalRead(SOS_BTN);
    if (state != lastState) {
      Serial.print("  Button state changed: ");
      Serial.println(state ? "HIGH" : "LOW");
      pressed = true;
      lastState = state;
    }
    delay(50);
  }

  if (pressed) {
    Serial.println("  RESULT: PASS — Button press detected!");
  } else {
    Serial.println("  RESULT: FAIL — No button press detected.");
    Serial.println("  Check: Wiring, pull-up resistor, GPIO 39.");
    Serial.print("  Current pin state: ");
    Serial.println(digitalRead(SOS_BTN) ? "HIGH" : "LOW");
  }
}

// =========================================================
//  TEST 11: ACC IGNITION DETECTION
// =========================================================
void testACCDetection() {
  Serial.println("[TEST] ACC Ignition Detection (GPIO 34 via PC817)");
  Serial.println("  Reading for 10 seconds...");
  Serial.println("  Turn the vehicle ignition key ON/OFF to see changes.");

  unsigned long start = millis();
  int lastState = -1;

  while (millis() - start < 10000) {
    int state = digitalRead(ACC_DETECT);
    if (state != lastState) {
      Serial.print("  ACC state: ");
      Serial.print(state ? "HIGH" : "LOW");
      Serial.println(state ? " (Ignition ON)" : " (Ignition OFF)");
      lastState = state;
    }
    delay(100);
  }

  int finalState = digitalRead(ACC_DETECT);
  Serial.print("  Final state: ");
  Serial.println(finalState ? "HIGH (Ignition ON)" : "LOW (Ignition OFF)");
  Serial.println("  RESULT: PASS (if readings matched ignition state).");
}

// =========================================================
//  TEST 12: ALL OUTPUTS QUICK TEST
// =========================================================
void testAllOutputs() {
  Serial.println("[TEST] ALL OUTPUTS — Quick sequential test");
  Serial.println("  This will briefly activate every output one by one.");
  delay(500);

  Serial.println("  1/6  Red LED...");
  digitalWrite(LED_R, HIGH);
  delay(500);
  digitalWrite(LED_R, LOW);
  delay(200);

  Serial.println("  2/6  Green LED...");
  digitalWrite(LED_G, HIGH);
  delay(500);
  digitalWrite(LED_G, LOW);
  delay(200);

  Serial.println("  3/6  Piezo Buzzer...");
  digitalWrite(BUZZER, HIGH);
  delay(300);
  digitalWrite(BUZZER, LOW);
  delay(200);

  Serial.println("  4/6  Alarm Siren (brief)...");
  digitalWrite(ALARM, HIGH);
  delay(200);
  digitalWrite(ALARM, LOW);
  delay(200);

  Serial.println("  5/6  ACC Relay...");
  digitalWrite(ACC_RELAY, HIGH);
  delay(500);
  digitalWrite(ACC_RELAY, LOW);
  delay(200);

  Serial.println("  6/6  Fuel Relay...");
  digitalWrite(FUEL_RELAY, HIGH);
  delay(500);
  digitalWrite(FUEL_RELAY, LOW);
  delay(200);

  Serial.println("  ALL OUTPUTS TESTED.");
  Serial.println("  RESULT: PASS (if each component activated).");
}
