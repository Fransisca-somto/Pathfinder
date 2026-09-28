// =========================================================
//  PathFinder Vehicle Tracker — Telemetry
//  Telemetry.ino   (Phase 1)
// =========================================================
//  Two independent jobs, deliberately decoupled:
//
//  1. SD TRAIL — written every cycle whether or not there is a link, and
//     whether or not there is a fix. This is the forensic record read off
//     the card afterwards. It must never depend on the modem.
//
//  2. MQTT PUBLISH — every 5 seconds whenever the link is up, INDEPENDENT
//     of GPS. An earlier build only published inside the fresh-fix branch,
//     so a device with no satellite lock sent nothing at all and the
//     backend, waiting on telemetry to confirm liveness, showed it
//     permanently offline. Telemetry is a snapshot of NOW, so it is never
//     replayed from the card: a stale position carrying a fresh timestamp
//     is worse than a gap.
// =========================================================

#include "Config.h"

static unsigned long lastTelemetry = 0;
static uint32_t telemetrySeq = 0;

static void logTelemetryToSD();

void loopTelemetry() {
  if (millis() - lastTelemetry < TELEMETRY_INTERVAL_MS) return;
  lastTelemetry = millis();
  publishTelemetryNow();
}

void publishTelemetryNow() {
  // Card first, always. If the vehicle was in a basement or the link was
  // jammed, this is the only record of where it went.
  logTelemetryToSD();

  if (!mqttIsConnected()) return;

  StaticJsonDocument<640> doc;
  doc["deviceId"] = deviceId;

  bool fresh = gpsHasFreshFix();
  doc["gps_fix"] = fresh;

  if (fresh) {
    doc["lat"] = gpsLat();
    doc["lng"] = gpsLng();
    doc["speed"] = gpsSpeedKmph();
    doc["satellites"] = gpsSatellites();
    doc["fix_age_s"] = 0;
  } else {
    // (char*)NULL is the ArduinoJson idiom for a real JSON null. Assigning
    // nullptr or 0 would serialise as the NUMBER zero, which would then
    // trip the backend's Null Island filter and get the packet dropped.
    doc["lat"] = (char*)NULL;
    doc["lng"] = (char*)NULL;
    doc["speed"] = 0;
    doc["satellites"] = gpsSatellites();
    doc["fix_age_s"] = gpsFixAgeSeconds();

    if (gpsEverHadFix()) {
      doc["last_lat"] = gpsLastLat();
      doc["last_lng"] = gpsLastLng();
    }
  }

  // Movement is judged on a FRESH fix only. A stale reading must never
  // report movement, or a vehicle that lost signal on the motorway would
  // appear to be driving at its last known speed indefinitely.
  bool moving = gpsIsMoving();
  doc["status"] = moving ? "moving" : "parked";

  // --- Vehicle state ---
  doc["acc"] = ignitionIsOn();
  doc["engine_locked"] = engineLocked;
  doc["auth_bypass"] = authBypass;
  doc["driverId"] = currentDriverId;

  // Where the vehicle sits in the authorisation cycle: armed (waiting for a
  // finger), authorised (relays live, waiting for the engine), running, or
  // grace (engine stopped, restart still allowed). Lets the app show why
  // the vehicle will or will not start.
  doc["auth_state"] = authStateName();

  // --- Power ---
  // Presence only. No voltage or percentage is reported: nothing downstream
  // needs the number, and dropping it removes per-board ADC calibration.
  doc["power_cut"] = batteryPowerCut();

  // --- Temperature ---
  // NAN serialises as null, so the backend can tell a dead probe from a real
  // reading instead of receiving a stale value dressed up as live.
  if (temperatureValid()) doc["temperature"] = roundf(vehicleTemperature() * 100) / 100.0;
  else                    doc["temperature"] = (char*)NULL;

  // --- Alarm state, so the app's mute button reflects reality ---
  doc["siren_active"] = (sirenLatched || manualAlarm) && !sirenMuted;
  doc["siren_muted"] = sirenMuted;

  // --- Diagnostics ---
  // Lets the app show which peripherals are alive without a separate probe,
  // and distinguishes "sensor dead" from "command never arrived".
  JsonObject sensors = doc.createNestedObject("sensors");
  sensors["gps"] = gpsEverHadFix();
  sensors["fingerprint"] = fingerprintSensorOk();
  sensors["accelerometer"] = accelerometerOk();
  sensors["temperature"] = temperatureValid();

  doc["uptime"] = (millis() - bootMillis) / 1000;
  doc["seq"] = ++telemetrySeq;

  char buf[768];
  size_t n = serializeJson(doc, buf, sizeof(buf));

  if (n >= sizeof(buf) - 1) {
    Serial.println("TELEMETRY: payload truncated, fields dropped.");
    return;
  }

  if (!mqttPublishRaw(TOPIC_TELEMETRY, buf, n)) {
    Serial.println("TELEMETRY: publish failed.");
    return;
  }

  // One compact serial line, not a block. Readable during a bench test while
  // still showing every field that matters.
  Serial.printf("TX #%lu %s ", (unsigned long)telemetrySeq, fresh ? "FIX  " : "NOFIX");
  if (fresh) Serial.printf("%.6f,%.6f %.1fkm/h %dsat ",
                           gpsLat(), gpsLng(), gpsSpeedKmph(), gpsSatellites());
  else       Serial.printf("(age %lus) ", gpsFixAgeSeconds());
  Serial.printf("| pwr=%s | ign=%d %s drv=%d | %sC\n",
                mainPowerPresent() ? "ok" : "CUT",
                ignitionIsOn(), authStateName(), currentDriverId,
                temperatureValid() ? String(vehicleTemperature(), 1).c_str() : "NA");
}

// =========================================================
//  SD TRAIL
// =========================================================
//  Rows carry a fix flag, so a gap in position alongside a continuing power
//  and ignition record shows the GPS lost lock rather than the device dying.
//  The online/OFFLINE marker identifies which stretches of a journey never
//  reached the backend -- otherwise impossible to reconstruct afterwards.
// =========================================================
static void logTelemetryToSD() {
  static unsigned long lastLog = 0;
  if (millis() - lastLog < SD_LOG_INTERVAL_MS) return;
  lastLog = millis();

  if (gpsHasFreshFix()) {
    logGPSData(gpsLat(), gpsLng(), gpsSpeedKmph(), gpsSatellites(),
               gpsIsMoving() ? "moving" : "parked");
  } else if (gpsEverHadFix()) {
    logGPSData(gpsLastLat(), gpsLastLng(), 0.0, gpsSatellites(), "nofix");
  } else {
    logGPSData(0.0, 0.0, 0.0, gpsSatellites(), "nofix");
  }

  // Power, ignition and authorisation go to their own file, so the trail
  // survives even when there has never been a fix. This is what proves the
  // device was alive and what state the vehicle was in.
  logSystemEvent("state",
    String(mainPowerPresent() ? "pwr_ok," : "PWR_CUT,") +
    (ignitionIsOn() ? "ign_on," : "ign_off,") +
    String(authStateName()) + "," +
    (engineLocked ? "locked," : "unlocked,") +
    "drv" + String(currentDriverId) + "," +
    (temperatureValid() ? String(vehicleTemperature(), 1) : "NA") + "C," +
    (mqttIsConnected() ? "online" : "OFFLINE"));
}