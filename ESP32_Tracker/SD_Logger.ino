#include <SPI.h>
#include <SD.h>
#include <FS.h>
#include <TinyGPSPlus.h>

extern TinyGPSPlus gps;

#include "Hardware.h"

// Helper to get formatted GPS timestamp
String getGPSTimestamp() {
  if (gps.date.isValid() && gps.time.isValid()) {
    char ts[32];
    sprintf(ts, "%04d-%02d-%02dT%02d:%02d:%02dZ",
            gps.date.year(), gps.date.month(), gps.date.day(),
            gps.time.hour(), gps.time.minute(), gps.time.second());
    return String(ts);
  }
  return String(millis()) + "_ms_uptime";
}

void appendFile(const char * path, const char * message) {
  Serial.printf("Appending to file: %s\n", path);

  File file = SD.open(path, FILE_APPEND);
  if(!file){
    Serial.println("Failed to open file for appending");
    return;
  }
  if(file.print(message)){
    // Serial.println("Message appended");
  } else {
    Serial.println("Append failed");
  }
  file.close();
}

void setupSDCard() {
  Serial.println("Initializing SD card...");

  // SD card SPI pins: SCK=18, MISO=19, MOSI=23, CS=5
  if (!SD.begin(SD_CS_PIN)) {
    Serial.println("SD Card Mount Failed! Check wiring.");
    return;
  }
  uint8_t cardType = SD.cardType();

  if (cardType == CARD_NONE) {
    Serial.println("No SD card attached");
    return;
  }

  Serial.print("SD Card Type: ");
  if (cardType == CARD_MMC) {
    Serial.println("MMC");
  } else if (cardType == CARD_SD) {
    Serial.println("SDSC");
  } else if (cardType == CARD_SDHC) {
    Serial.println("SDHC");
  } else {
    Serial.println("UNKNOWN");
  }

  uint64_t cardSize = SD.cardSize() / (1024 * 1024);
  Serial.printf("SD Card Size: %lluMB\n", cardSize);

  // Create directories if they don't exist
  if (!SD.exists("/telemetry")) SD.mkdir("/telemetry");
  if (!SD.exists("/events")) SD.mkdir("/events");
  if (!SD.exists("/system")) SD.mkdir("/system");

  // Create CSV Headers if files don't exist
  if (!SD.exists("/telemetry/gps.csv")) {
    File file = SD.open("/telemetry/gps.csv", FILE_WRITE);
    if(file) {
      file.println("timestamp,latitude,longitude,speed_kmh,satellites,status");
      file.close();
    }
  }

  if (!SD.exists("/events/alerts.csv")) {
    File file = SD.open("/events/alerts.csv", FILE_WRITE);
    if(file) {
      file.println("timestamp,type,message");
      file.close();
    }
  }

  if (!SD.exists("/system/status.csv")) {
    File file = SD.open("/system/status.csv", FILE_WRITE);
    if(file) {
      file.println("timestamp,event_type,details");
      file.close();
    }
  }

  Serial.println("SD Card Initialized successfully!");
}

void logGPSData(float lat, float lng, float speed, int satellites, String status) {
  String ts = getGPSTimestamp();
  String dataString = ts + "," + 
                      String(lat, 6) + "," + 
                      String(lng, 6) + "," + 
                      String(speed) + "," + 
                      String(satellites) + "," + 
                      status + "\n";
  
  appendFile("/telemetry/gps.csv", dataString.c_str());
}

void logEvent(String type, String message) {
  String ts = getGPSTimestamp();
  String logEntry = ts + "," + type + "," + message + "\n";
  
  appendFile("/events/alerts.csv", logEntry.c_str());
}

void logSystemEvent(String eventType, String details) {
  String ts = getGPSTimestamp();
  String logEntry = ts + "," + eventType + "," + details + "\n";
  
  appendFile("/system/status.csv", logEntry.c_str());
}
