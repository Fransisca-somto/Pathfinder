// =========================================================
//  PathFinder Vehicle Tracker — Sensors
//  Sensors.ino   (Phase 1)
// =========================================================
//  MPU6050 (crash/theft), DS18B20 (overheat), SOS panic button.
//  Also drives the periodic watches owned by other tabs: power cut,
//  GPS fix loss, backup battery.
// =========================================================

#include "Config.h"

// ---- Accelerometer ----
Adafruit_MPU6050 mpu;
static bool mpuOk = false;
static int crashCount = 0, theftCount = 0;
static unsigned long lastCrashAlert = 0, lastTheftAlert = 0;

// ---- Temperature ----
OneWire oneWire(TEMP_SENSOR_PIN);
DallasTemperature tempSensors(&oneWire);
static float currentTemp = NAN;
static bool tempFound = false, tempFaulted = false, overheatActive = false;
static bool conversionPending = false;
static unsigned long lastTempRead = 0, conversionStart = 0, lastEnumerate = 0;

// ---- SOS ----
Preferences sosPrefs;
static String emergencyContact;
static int btnState = HIGH, lastBtn = HIGH;
static unsigned long lastDebounce = 0, pressedAt = 0, lastPanicSms = 0;
static bool panicArmed = false, panicFired = false;

bool  accelerometerOk()    { return mpuOk; }
float vehicleTemperature() { return currentTemp; }
bool  temperatureValid()   { return !isnan(currentTemp); }

// =========================================================
//  SETUP
// =========================================================
void setupSensors() {
  // Input-only pins. NO internal pulls exist here -- INPUT_PULLUP compiles
  // and is silently ignored. Every level comes from the PCB.
  pinMode(ACC_IGNITION_PIN, INPUT);
  pinMode(PANIC_BUTTON_PIN, INPUT);
  pinMode(MPU_INT_PIN, INPUT);

  // ---- MPU6050 ----
  Wire.begin();
  mpuOk = mpu.begin();
  if (mpuOk) {
    mpu.setAccelerometerRange(MPU6050_RANGE_16_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    // 44 Hz, not 21: the lower bandwidth flattens the short spike of a real
    // impact and a genuine crash reads as a bump.
    mpu.setFilterBandwidth(MPU6050_BAND_44_HZ);
    Serial.println("MPU6050: OK");
  } else {
    // Also fails if an MPU6500 was fitted: the library checks WHO_AM_I for
    // 0x68 and the 6500 answers 0x70.
    Serial.println("MPU6050: not found (check SDA=21/SCL=22, or an MPU6500)");
  }

  // Backdate the cooldowns so the first event after boot is not swallowed.
  lastCrashAlert = millis() - ALERT_COOLDOWN_MS - 1;
  lastTheftAlert = lastCrashAlert;

  // ---- DS18B20 ----
  tempSensors.begin();
  tempSensors.setWaitForConversion(false);   // we time the conversion ourselves
  tempSensors.setResolution(TEMP_RESOLUTION_BITS);
  tempFound = (tempSensors.getDeviceCount() > 0);
  Serial.printf("DS18B20: %s\n", tempFound ? "OK" : "not found");

  // ---- SOS ----
  sosPrefs.begin("sos", false);
  emergencyContact = sosPrefs.getString("sos_number", DEFAULT_EMERGENCY_CONTACT);
  Serial.printf("Emergency contact: %s\n", emergencyContact.c_str());

  // Sample repeatedly rather than once. A floating pin (missing pull-up)
  // reads erratically, and treating that as a press would fire a real SOS
  // at every boot -- which is exactly what happened before.
  int lows = 0;
  for (int i = 0; i < 10; i++) { if (digitalRead(PANIC_BUTTON_PIN) == LOW) lows++; delay(5); }
  btnState = (lows >= 8) ? LOW : HIGH;
  lastBtn = btnState;
  lastDebounce = millis();

  if (lows > 0 && lows < 8)
    Serial.println("SOS: GPIO39 UNSTABLE -- check the external 10k pull-up.");

  // A genuine press can straddle a boot: this pin is a light-sleep wake
  // source, so the button going LOW is what woke us.
  if (btnState == LOW) {
    pressedAt = millis();
    panicArmed = true;
    panicFired = false;
    Serial.println("SOS: button held at startup, arming.");
  }
}

void setEmergencyContact(const String &number) {
  emergencyContact = number;
  sosPrefs.putString("sos_number", number);
  Serial.printf("Emergency contact set: %s\n", number.c_str());
}

// =========================================================
//  ACCELEROMETER
// =========================================================
static void loopAccelerometer() {
  if (!mpuOk) return;

  sensors_event_t a, g, t;
  mpu.getEvent(&a, &g, &t);
  unsigned long now = millis();

  // Track the gravity VECTOR, not just its magnitude. Subtracting 9.81 from
  // the total only works for impacts along the gravity axis: a 3.5G lateral
  // hit gives |a| = sqrt(34.3^2 + 9.81^2) = 35.7, so scalar maths reports
  // 2.64G and misses it. Most real crashes are lateral.
  static float gx = 0, gy = 0, gz = G_MS2;
  static unsigned long lastUpdate = 0;
  static bool seeded = false;

  if (!seeded) {
    gx = a.acceleration.x; gy = a.acceleration.y; gz = a.acceleration.z;
    lastUpdate = now; seeded = true;
    return;
  }

  // Time constant derived from REAL elapsed time, not a fixed alpha. The
  // loop rate varies enormously -- a few hundred Hz while driving, ~4 Hz
  // while light-sleep napping -- and a fixed alpha would track real
  // accelerations and cancel them out in the fast case.
  float dt = (now - lastUpdate) / 1000.0;
  lastUpdate = now;
  float k = exp(-dt / 2.0);          // 2 second time constant
  gx = k * gx + (1 - k) * a.acceleration.x;
  gy = k * gy + (1 - k) * a.acceleration.y;
  gz = k * gz + (1 - k) * a.acceleration.z;

  float dx = a.acceleration.x - gx;
  float dy = a.acceleration.y - gy;
  float dz = a.acceleration.z - gz;
  float net = sqrt(dx * dx + dy * dy + dz * dz);

  // ---- Crash ----
  // Publishes an alert and sends SMS, but deliberately does NOT sound the
  // siren: a crash happens while driving, and a blaring buzzer helps nobody
  // in the seconds after an impact.
  crashCount = (net > CRASH_THRESHOLD_MS2) ? crashCount + 1 : 0;
  if (crashCount >= CRASH_CONFIRM_SAMPLES) {
    crashCount = 0;
    if (now - lastCrashAlert > ALERT_COOLDOWN_MS) {
      lastCrashAlert = now;
      Serial.printf("CRASH: %.2f m/s2 (%.2fG)\n", net, net / G_MS2);
      publishAlert("crash", "Vehicle crash detected. Impact " +
                            String(net / G_MS2, 1) + "G.");
      if (emergencyContact.length() > 7 && emergencyContact.startsWith("+")) {
        String loc = gpsHasFreshFix()
          ? "https://maps.google.com/?q=" + String(gpsLat(), 6) + "," + String(gpsLng(), 6)
          : "Location unavailable.";
        sendSMS(emergencyContact, "PathFinder: CRASH DETECTED. " + loc);
      }
    }
  }

  // ---- Theft: movement while secured ----
  // Gated on LOCKED, not on ignition. A driver sitting in an authorised
  // vehicle with the engine off -- during the restart grace, say -- must not
  // generate theft alerts by shifting in their seat. raiseAlarm() would
  // suppress the SIREN in that state, but the alert would still reach the
  // app, so the gate belongs here too.
  bool vehicleSecured = engineLocked && !authBypass;
  theftCount = (vehicleSecured && net > THEFT_THRESHOLD_MS2) ? theftCount + 1 : 0;
  if (theftCount >= THEFT_CONFIRM_SAMPLES) {
    theftCount = 0;
    if (now - lastTheftAlert > ALERT_COOLDOWN_MS) {
      lastTheftAlert = now;
      raiseAlarm("theft", "Vehicle moved or shaken while immobilised.");
    }
  }
}

// =========================================================
//  TEMPERATURE
// =========================================================
static void handleTempReading(float t) {
  bool valid = (!isnan(t) && t > TEMP_MIN_VALID_C);

  if (!valid) {
    // A dead sensor used to keep its last value forever and publish it as
    // live telemetry, so the dashboard showed a plausible but fictional
    // engine temperature and a real overheat would never be detected.
    currentTemp = NAN;

    // Clear any standing overheat. NAN compares false against everything,
    // so without this the alert could never re-arm and the next genuine
    // overheat after recovery would be silent.
    overheatActive = false;

    if (!tempFaulted) {
      tempFaulted = true;
      tempFound = false;
      publishAlert("sensorFault", "Temperature sensor disconnected or faulty.");
    }
    return;
  }

  if (tempFaulted) {
    tempFaulted = false;
    publishAlert("system", "Temperature sensor recovered.");
  }

  currentTemp = t;

  // Hysteresis: fire once on crossing, re-arm only after it comes back down.
  // Without it a reading hovering at the threshold flaps, and a genuinely
  // overheating engine fires an alert every 10 seconds for minutes.
  //
  // Overheat DOES sound the siren regardless of lock state -- it happens
  // while driving, and a silent warning the driver may never see is no
  // warning at all.
  if (!overheatActive && t > OVERHEAT_C) {
    overheatActive = true;
    raiseAlarm("temperature", "Engine overheat: " + String(t, 1) + "C");
  } else if (overheatActive && t < OVERHEAT_CLEAR_C) {
    overheatActive = false;
    publishAlert("temperature", "Engine temperature normal: " + String(t, 1) + "C");
  }
}

static void loopTemperature() {
  unsigned long now = millis();

  // Collect a conversion started on an earlier pass. requestTemperatures()
  // would block for 750ms at 12-bit; at 10-bit with setWaitForConversion
  // false it returns immediately and we collect ~250ms later.
  if (conversionPending) {
    if (now - conversionStart >= TEMP_CONVERSION_MS) {
      conversionPending = false;
      handleTempReading(tempSensors.getTempCByIndex(0));
    }
    return;
  }

  // Periodically re-enumerate: a loose DS18B20 in a vehicle can reconnect,
  // and the old code polled a nonexistent sensor forever after a failed boot.
  if (!tempFound) {
    if (now - lastEnumerate > 60000) {
      lastEnumerate = now;
      tempSensors.begin();
      tempSensors.setWaitForConversion(false);
      tempSensors.setResolution(TEMP_RESOLUTION_BITS);
      if (tempSensors.getDeviceCount() > 0) {
        tempFound = true;
        Serial.println("DS18B20: detected on retry.");
      }
    }
    return;
  }

  if (now - lastTempRead >= TEMP_READ_INTERVAL_MS) {
    lastTempRead = now;
    tempSensors.requestTemperatures();
    conversionStart = now;
    conversionPending = true;
  }
}

// =========================================================
//  SOS PANIC BUTTON  (emergency only)
// =========================================================
static String panicLocation() {
  char buf[128];
  if (gpsHasFreshFix()) {
    snprintf(buf, sizeof(buf), "https://maps.google.com/?q=%.6f,%.6f",
             gpsLat(), gpsLng());
    return String(buf);
  }
  if (gpsEverHadFix()) {
    snprintf(buf, sizeof(buf), "Last known (%lus ago): https://maps.google.com/?q=%.6f,%.6f",
             gpsFixAgeSeconds(), gpsLastLat(), gpsLastLng());
    return String(buf);
  }
  return String("Location unavailable.");
}

static void firePanic() {
  String loc = panicLocation();
  String msg = "Emergency SOS triggered. Driver needs assistance. " + loc;

  Serial.println("*** SOS FIRED ***");

  // The MQTT alert goes out on EVERY press. It costs nothing, and a driver
  // pressing repeatedly must not be met with silence. Only the SMS is rate
  // limited, because that costs credit and blocks the modem for seconds.
  publishAlert("panic", msg);

  if (lastPanicSms == 0 || millis() - lastPanicSms > PANIC_SMS_COOLDOWN_MS) {
    lastPanicSms = millis();
    if (emergencyContact.length() > 7 && emergencyContact.startsWith("+"))
      sendSMS(emergencyContact, "PathFinder SOS: " + msg);
    else
      publishAlert("system", "SOS raised but no valid emergency contact is set.");
  }

  beep(3, 120);
}

static void loopSOS() {
  int reading = digitalRead(PANIC_BUTTON_PIN);
  if (reading != lastBtn) lastDebounce = millis();

  if (millis() - lastDebounce > PANIC_DEBOUNCE_MS && reading != btnState) {
    btnState = reading;
    if (btnState == LOW) {
      pressedAt = millis();
      panicArmed = true;
      panicFired = false;
    } else {
      panicArmed = false;
      panicFired = false;
    }
  }

  // Fires on the hold, without waiting for release -- a driver should not
  // have to let go to get help. 300ms is short enough that a deliberate
  // press always registers, long enough to reject a knock.
  if (panicArmed && !panicFired && btnState == LOW &&
      millis() - pressedAt >= PANIC_HOLD_MS) {
    panicFired = true;
    firePanic();
  }

  lastBtn = reading;
}

// =========================================================
//  MASTER LOOP
// =========================================================
void loopSensors() {
  loopAccelerometer();
  loopTemperature();
  loopSOS();

  // Watches owned by other tabs, driven from here so each has one caller.
  checkPowerCut();
  checkGpsFixLoss();
  gpsPrintStatus();

  // Backup cell, read through the modem. Polled once a minute because the
  // AT round trip blocks.
  static unsigned long lastVbat = 0;
  static int vbatMv = 4200;
  if (millis() - lastVbat > 60000) {
    lastVbat = millis();
    int v = readBackupBatteryMv();
    if (v > 0) {
      vbatMv = v;
      static bool lowWarned = false;
      if (vbatMv < 3500 && !lowWarned) {
        lowWarned = true;
        publishAlert("system", "Backup battery low: " + String(vbatMv) + "mV");
      } else if (vbatMv > 3700) lowWarned = false;
    }
  }
}