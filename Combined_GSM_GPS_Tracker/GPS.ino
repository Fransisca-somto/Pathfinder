#include "Hardware.h"
#define TINY_GSM_MODEM_SIM7600
#include <TinyGsmClient.h>

extern TinyGsm modem;
extern float currentVehicleSpeed;
extern void publishTelemetry(float lat, float lng, float speed, int satellites);
extern void logGPSData(float lat, float lng, float speed, int satellites, String status);

// --- Timing ---
unsigned long lastPublish = 0;
const unsigned long PUBLISH_INTERVAL = 5000; // Publish every 5 seconds

void setupGPS() {
  Serial.println("Initializing Cellular GPS (GNSS)...");
  
  // Turn on VAUX (Power supply for the Active GPS Antenna)
  Serial.println("Turning on power for Active GPS Antenna...");
  modem.sendAT(GF("+CVAUX=1"));
  modem.waitResponse();

  // Power on the GPS engine inside the modem
  if (modem.enableGPS()) {
    Serial.println("GPS Module enabled successfully.");
  } else {
    Serial.println("Failed to enable GPS Module (it might already be on).");
  }
}

void loopGPS() {
  unsigned long now = millis();
  if (now - lastPublish > PUBLISH_INTERVAL) {
    lastPublish = now;

    float lat = 0.0, lon = 0.0, speed = 0.0, alt = 0.0;
    int vsat = 0, usat = 0;
    float accuracy = 0.0;

    // Ask the modem for the current location
    if (modem.getGPS(&lat, &lon, &speed, &alt, &vsat, &usat, &accuracy)) {
      
      // Update our global speed variable
      currentVehicleSpeed = speed;

      Serial.print("GPS Fix Acquired! Satellites (Usable): ");
      Serial.print(usat);
      Serial.print(" | Lat: ");
      Serial.print(lat, 6);
      Serial.print(" | Lng: ");
      Serial.println(lon, 6);

      String currentStatus = (currentVehicleSpeed > 0.0) ? "moving" : "parked";

      // 1. Log to SD Card
      logGPSData(lat, lon, currentVehicleSpeed, usat, currentStatus);

      // 2. Send to Server via MQTT
      publishTelemetry(lat, lon, currentVehicleSpeed, usat);
      
    } else {
      // The modem couldn't get a valid fix
      currentVehicleSpeed = 0.0;
      Serial.println("Waiting for Cellular GPS satellite fix... (Please place antenna near a window)");
      // DEBUG: Directly ask the modem for GPS info and print everything it replies
      extern HardwareSerial SerialAT;
      Serial.print("Raw GPS Data: ");
      SerialAT.println("AT+CGPSINFO");
      
      unsigned long startTime = millis();
      while (millis() - startTime < 1000) {
        while (SerialAT.available()) {
          Serial.write(SerialAT.read());
        }
      }
      Serial.println();
    }
  }
}
