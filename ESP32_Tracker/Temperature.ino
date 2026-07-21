#include <OneWire.h>
#include <DallasTemperature.h>
#include "Hardware.h"

OneWire oneWire(TEMP_SENSOR_PIN);
DallasTemperature sensors(&oneWire);

float currentTemp = 0.0;
unsigned long lastTempReadTime = 0;
const unsigned long TEMP_READ_INTERVAL = 10000; // 10 seconds

extern void publishAlert(String type, String message);

void setupTemperature() {
  Serial.println("Initializing DS18B20 Temperature Sensor...");
  sensors.begin();
  
  // Check if sensor is found
  if (sensors.getDeviceCount() > 0) {
    Serial.print("Found ");
    Serial.print(sensors.getDeviceCount());
    Serial.println(" DS18B20 sensor(s).");
  } else {
    Serial.println("No DS18B20 temperature sensors found. Check wiring.");
  }
}

void loopTemperature() {
  if (millis() - lastTempReadTime >= TEMP_READ_INTERVAL) {
    lastTempReadTime = millis();
    
    sensors.requestTemperatures(); 
    currentTemp = sensors.getTempCByIndex(0);
    
    if (currentTemp != DEVICE_DISCONNECTED_C) {
      // Serial.print("Current Engine Temp: ");
      // Serial.print(currentTemp);
      // Serial.println(" °C");
      
      // If temperature is dangerously high, send an alert!
      if (currentTemp > 105.0) { // e.g., > 105C is overheating
        Serial.println("⚠️ OVERHEAT WARNING! Temp > 105°C");
        publishAlert("temperature", "Engine Overheat Alert! Current Temp: " + String(currentTemp) + "C");
      }
    } else {
      // Serial.println("Error reading temperature!");
    }
  }
}

// Function to allow Network.ino to grab the temp for telemetry
float getVehicleTemperature() {
  return currentTemp;
}
