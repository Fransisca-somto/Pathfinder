// =========================================================
//  PathFinder Vehicle Tracker — Commands
//  Commands.ino   (Phase 1)
// =========================================================
//  Everything arriving on pathfinder/commands lands here.
//
//  RULE: every recognised command publishes commandAck BEFORE acting. The
//  app cancels its UI timeout on that ack, so it must go out first -- an
//  ack sent after a slow operation leaves the button spinning.
//
//  RULE: nothing here may block. This runs inside mqttClient.loop(), so a
//  blocking call here stalls the MQTT session itself. Commands that take
//  time (enrolment) set a flag and return; the owning tab does the work.
// =========================================================

#include "Config.h"

// Acknowledge receipt. Sent before the command is carried out, so the app
// can distinguish "device never heard me" from "device heard me and failed".
static void ack(const char* command, bool accepted, const String &reason) {
  StaticJsonDocument<256> doc;
  doc["deviceId"] = deviceId;
  doc["type"] = "commandAck";
  doc["message"] = String("Received command ") + command;
  doc["command"] = command;
  doc["accepted"] = accepted;
  if (reason.length()) doc["reason"] = reason;
  doc["driverId"] = -1;
  doc["uptime"] = (millis() - bootMillis) / 1000;

  char buf[320];
  serializeJson(doc, buf, sizeof(buf));

  // Acks are not queued to SD on failure. They are only meaningful to a UI
  // waiting right now; replaying one twenty minutes later would resolve a
  // timeout that has long since expired.
  if (mqttIsConnected()) mqttPublishRaw(TOPIC_ALERTS, buf, strlen(buf));
  Serial.printf("ACK: %s %s%s\n", command, accepted ? "accepted" : "REJECTED",
                reason.length() ? (" - " + reason).c_str() : "");
}

// ArduinoJson's | operator returns the fallback for a MISSING key, and the
// fallback for a missing bool is false. A malformed setAuthBypass would
// therefore silently LOCK THE ENGINE. Every field is checked for presence.
static bool readBool(JsonDocument &d, const char* key, bool &out) {
  if (d["payload"][key].is<bool>()) { out = d["payload"][key].as<bool>(); return true; }
  if (d[key].is<bool>())            { out = d[key].as<bool>();            return true; }
  return false;
}

static bool readInt(JsonDocument &d, const char* key, int &out) {
  if (d["payload"][key].is<int>()) { out = d["payload"][key].as<int>(); return true; }
  if (d[key].is<int>())            { out = d[key].as<int>();            return true; }
  return false;
}

void handleCommand(char* topic, byte* payload, unsigned int len) {
  if (strcmp(topic, TOPIC_COMMANDS) != 0) return;

  StaticJsonDocument<512> doc;
  DeserializationError err = deserializeJson(doc, payload, len);
  if (err) {
    Serial.printf("CMD: JSON parse failed: %s\n", err.c_str());
    return;
  }

  // Addressing. The backend sends lowercase; deviceId is built lowercase.
  // A case mismatch here is silent and discards every command, which is
  // exactly what happened before -- so compare case-insensitively and let a
  // future backend change not break us again.
  const char* target = doc["deviceId"] | "";
  if (!deviceId.equalsIgnoreCase(target)) return;

  const char* cmd = doc["command"] | "";
  if (!cmd[0]) return;

  Serial.printf("CMD: %s\n", cmd);

  // ---------------------------------------------------------
  //  Engine lock / unlock  (single toggle, both directions)
  // ---------------------------------------------------------
  //  state true  -> bypass ON,  engine released without a fingerprint
  //  state false -> bypass OFF, engine immobilised, fingerprint required
  if (!strcmp(cmd, "setAuthBypass") || !strcmp(cmd, "setEngineLock")) {
    bool state;
    if (!readBool(doc, "state", state)) {
      ack(cmd, false, "missing or invalid 'state' field");
      return;
    }

    // setEngineLock is the inverse: lock=true means bypass=false.
    if (!strcmp(cmd, "setEngineLock")) state = !state;

    // Refuse to immobilise a MOVING vehicle. Two independent ways to be
    // sure it is safe: the ignition is off, so the engine cannot be
    // running; or GPS confirms the vehicle is slow. Either is enough.
    //
    // Requiring a fresh fix ALONE was too strict -- indoors or in a garage
    // there is never a fix, so every lock command was rejected with
    // "vehicle speed unknown" even on a car that was plainly parked.
    if (!state) {
      bool ignitionOff = !ignitionIsOn();
      bool gpsSaysSlow = gpsHasFreshFix() && gpsSpeedKmph() < REMOTE_LOCK_MAX_KMPH;

      if (gpsHasFreshFix() && gpsSpeedKmph() >= REMOTE_LOCK_MAX_KMPH) {
        ack(cmd, false, "vehicle moving above " +
            String((int)REMOTE_LOCK_MAX_KMPH) + " km/h");
        publishAlert("system", "Remote lock rejected: vehicle in motion.");
        return;
      }
      // The one genuinely ambiguous case: ignition live and no fix, so the
      // vehicle could be moving. Fail safe and refuse.
      if (!ignitionOff && !gpsSaysSlow) {
        ack(cmd, false, "ignition on and no GPS speed, cannot confirm vehicle is stopped");
        publishAlert("system", "Remote lock rejected: vehicle state unknown.");
        return;
      }
    }

    ack(cmd, true, "");

    if (!state) {
      // Cancel any restart grace at once. The owner should not have to wait
      // out a 120s timer to immobilise their own vehicle.
      cancelGraceForRemoteLock();
    }
    setAuthBypass(state);
    publishTelemetryNow();       // push the new state immediately
    return;
  }

  // ---------------------------------------------------------
  //  Siren  (manual trigger, and mute)
  // ---------------------------------------------------------
  //  soundAlarm true  -> siren on
  //  soundAlarm false -> siren off AND mute any standing alarm, so the owner
  //                      can silence a theft alert without clearing the
  //                      underlying condition. The app flips its button to
  //                      "unmute" on the siren_muted telemetry field.
  //
  //  Exempt from the lock-state buzzer policy: it is the owner's explicit
  //  instruction, so it sounds whatever the vehicle state.
  if (!strcmp(cmd, "soundAlarm") || !strcmp(cmd, "muteAlarm")) {
    bool state;
    if (!readBool(doc, "state", state)) {
      ack(cmd, false, "missing or invalid 'state' field");
      return;
    }
    if (!strcmp(cmd, "muteAlarm")) state = !state;   // mute=true means siren off

    ack(cmd, true, "");

    if (state) {
      setSirenMuted(false);      // unmute first, or turning it on does nothing
      setManualAlarm(true);
      publishAlert("system", "Alarm activated from app.");
    } else {
      setManualAlarm(false);
      setSirenMuted(true);       // silences a standing theft alarm too
      publishAlert("system", "Alarm silenced from app.");
    }
    publishTelemetryNow();
    return;
  }

  // ---------------------------------------------------------
  //  Fingerprint enrolment
  // ---------------------------------------------------------
  //  Capacity is 40, per the Hi-Link datasheet -- NOT 127. Slots above that
  //  fail at storeModel() with a confusing error, so reject early with a
  //  reason the app can display.
  if (!strcmp(cmd, "enrollFingerprint")) {
    int id;
    if (!readInt(doc, "driverId", id)) { ack(cmd, false, "missing driverId"); return; }
    if (id < 1 || id > FINGERPRINT_CAPACITY) {
      ack(cmd, false, "driverId out of range 1-" + String(FINGERPRINT_CAPACITY));
      return;
    }
    if (!fingerprintSensorOk()) { ack(cmd, false, "fingerprint sensor not responding"); return; }

    ack(cmd, true, "");
    triggerEnrollment(id);   // sets a flag; the state machine does the work
    return;
  }

  if (!strcmp(cmd, "deleteFingerprint")) {
    int id;
    if (!readInt(doc, "driverId", id)) { ack(cmd, false, "missing driverId"); return; }
    if (id < 1 || id > FINGERPRINT_CAPACITY) {
      ack(cmd, false, "driverId out of range 1-" + String(FINGERPRINT_CAPACITY));
      return;
    }
    if (!fingerprintSensorOk()) { ack(cmd, false, "fingerprint sensor not responding"); return; }

    ack(cmd, true, "");
    triggerDeleteFingerprint(id);
    return;
  }

  // ---------------------------------------------------------
  //  Driver suspension
  // ---------------------------------------------------------
  //  The template stays on the sensor, but a scan is refused. If the
  //  suspended driver is the one currently authorised, the vehicle is
  //  immobilised at once -- otherwise revoking access would have no effect
  //  until the next restart.
  if (!strcmp(cmd, "setDriverStatus")) {
    int id; bool active;
    if (!readInt(doc, "driverId", id))      { ack(cmd, false, "missing driverId"); return; }
    if (!readBool(doc, "isActive", active)) { ack(cmd, false, "missing isActive"); return; }
    if (id < 1 || id > FINGERPRINT_CAPACITY) {
      ack(cmd, false, "driverId out of range 1-" + String(FINGERPRINT_CAPACITY));
      return;
    }

    ack(cmd, true, "");
    setDriverStatus(id, active);

    if (!active && currentDriverId == id && !authBypass) {
      engineLock("driver deactivated while authorised");
      publishAlert("authDenied", "Driver deactivated. Engine locked.", id);
    }
    publishTelemetryNow();
    return;
  }

  // ---------------------------------------------------------
  //  Emergency contact
  // ---------------------------------------------------------
  //  International format required: sendSMS() hands the string straight to
  //  the modem, and a local-format number is rejected or misrouted by the
  //  SMSC at the moment it is needed most.
  if (!strcmp(cmd, "setEmergencyContact")) {
    const char* n = doc["payload"]["number"] | doc["number"] | "";
    size_t L = strlen(n);
    bool ok = (L >= 8 && L <= 20 && n[0] == '+');
    for (size_t i = 1; ok && i < L; i++) if (n[i] < '0' || n[i] > '9') ok = false;

    if (!ok) { ack(cmd, false, "use international format, e.g. +234..."); return; }

    ack(cmd, true, "");
    setEmergencyContact(String(n));
    // Do NOT echo the number back: this broker is public, and a phone number
    // alongside live GPS is personal data.
    publishAlert("system", "Emergency contact updated.");
    return;
  }

  // ---------------------------------------------------------
  //  Diagnostics
  // ---------------------------------------------------------
  //  Lets the app force a fresh snapshot without waiting for the next 5s
  //  cycle -- useful for a pull-to-refresh gesture.
  if (!strcmp(cmd, "requestTelemetry")) {
    ack(cmd, true, "");
    publishTelemetryNow();
    return;
  }

  if (!strcmp(cmd, "reboot")) {
    ack(cmd, true, "");
    publishAlert("system", "Reboot requested from app.");
    delay(500);              // let the publish leave before the radio dies
    ESP.restart();
    return;
  }

  ack(cmd, false, "unknown command");
}