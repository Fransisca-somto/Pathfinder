#include <HardwareSerial.h>

HardwareSerial gpsSerial(2); // We will use Hardware Serial port 2

#include "Hardware.h"

// --- Variables ---

const uint32_t GPS_BAUD = 9600; // Default baud rate for NEO-6M and NEO-8M

// --- Timing ---
unsigned long lastPublish = 0;
const unsigned long PUBLISH_INTERVAL = 5000; // Publish every 5 seconds

// Declarations for functions in other tabs
extern void logGPSData(float lat, float lng, float speed, int satellites, String status);

void setupGPS() {
  Serial.println("Initializing GPS Module...");
  
  // Begin Serial2 with our custom pins
  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
  
  Serial.println("GPS Module initialized on Pins 4 (RX) and 5 (TX).");
}

void loopGPS() {
  // 1. Continuously feed incoming data from the GPS module to TinyGPSPlus
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }

  // 2. Every 5 seconds, check if we have a valid location and publish it
  unsigned long now = millis();
  if (now - lastPublish > PUBLISH_INTERVAL) {
    lastPublish = now;

    if (gps.location.isValid()) {
      float currentLat = gps.location.lat();
      float currentLng = gps.location.lng();
      float currentSpeed = gps.speed.isValid() ? gps.speed.kmph() : 0.0;
      int satellites = gps.satellites.isValid() ? gps.satellites.value() : 0;

      Serial.print("GPS Fix Acquired! Satellites: ");
      Serial.print(satellites);
      Serial.print(" | Lat: ");
      Serial.print(currentLat, 6);
      Serial.print(" | Lng: ");
      Serial.println(currentLng, 6);

      String currentStatus = (currentSpeed > 0.0) ? "moving" : "parked";

      // 1. Log to SD Card
      logGPSData(currentLat, currentLng, currentSpeed, satellites, currentStatus);

      // 2. Send to Server via MQTT
      publishTelemetry(currentLat, currentLng, currentSpeed, satellites);
      
    } else {
      // We are receiving data, but the GPS doesn't know where it is yet
      Serial.print("Waiting for GPS satellite fix... ");
      if (gps.satellites.isValid()) {
        Serial.print("(Currently seeing ");
        Serial.print(gps.satellites.value());
        Serial.println(" satellites)");
      } else {
        Serial.println("(Please place antenna near a window)");
      }
    }
    
    // Warning if wiring is wrong
    if (millis() > 5000 && gps.charsProcessed() < 10) {
      Serial.println(F("WARNING: No GPS data received. Check your wiring (RX/TX might be swapped)."));
    }
  }
}
