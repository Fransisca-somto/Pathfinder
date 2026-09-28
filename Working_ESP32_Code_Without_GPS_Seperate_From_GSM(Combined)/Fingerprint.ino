// =========================================================
//  PathFinder Vehicle Tracker — Fingerprint & Authorisation
//  Fingerprint.ino   (Phase 1)
// =========================================================
//  Owns the ZW111 sensor, its backlight, and the authorisation state
//  machine that drives both relays.
//
//  AUTHORISATION STATES
//    ARMED       blue backlight, scanning, relays OFF. Engine cannot start.
//    AUTHORISED  valid finger. Green 2s then backlight OFF, scanning stops,
//                relays ON, 60s to get the engine running.
//    RUNNING     ignition detected. Stays authorised while it runs.
//    GRACE       engine stopped. Relays stay ON for 120s so the driver can
//                restart without rescanning. Restart cancels it; a remote
//                lock cancels it immediately; expiry returns to ARMED.
//
//  Both relays move together: neither is wired to vehicle accessories, so
//  there is no accessory circuit to keep alive independently.
//
//  SoftwareSerial at 57600 is timing-marginal on ESP32 -- bench testing
//  gave 0/10 handshakes on one boot and 10/10 on the next with identical
//  wiring. Hence the 20-attempt retry here and the 30s re-probe in loop().
// =========================================================

#include "Config.h"

SoftwareSerial fingerSerial(FINGERPRINT_RX, FINGERPRINT_TX);
Adafruit_Fingerprint finger = Adafruit_Fingerprint(&fingerSerial);
Preferences prefs;

static bool sensorFound = false;
static bool enrollMode = false;
static int  enrollId = -1;

// Latch: a finger resting on the sensor must be LIFTED before another match
// is accepted. Without this the same finger re-matches every 500ms and
// republishes authSuccess forever.
static bool fingerPresent = false;

static unsigned long lastScan = 0;
static int failedAttempts = 0;
static unsigned long lastFailTime = 0;

// ---- Authorisation state ----
enum AuthState { AUTH_ARMED, AUTH_AUTHORISED, AUTH_RUNNING, AUTH_GRACE };
static AuthState authState = AUTH_ARMED;
static unsigned long authStateSince = 0;

// ---- Backlight state ----
static unsigned long ledUntil = 0;
static bool ledTimed = false;

bool fingerprintSensorOk() { return sensorFound; }

const char* authStateName() {
  switch (authState) {
    case AUTH_ARMED:      return "armed";
    case AUTH_AUTHORISED: return "authorised";
    case AUTH_RUNNING:    return "running";
    case AUTH_GRACE:      return "grace";
  }
  return "unknown";
}

void savePersistentState() {
  prefs.putBool("unlocked", !engineLocked);
  prefs.putInt("driver", currentDriverId);
  prefs.putBool("bypass", authBypass);
}

static bool driverIsSuspended(int id) {
  return prefs.getBool(String(id).c_str(), false);
}

// =========================================================
//  BACKLIGHT — PS_ControlBLN, instruction 0x3C
// =========================================================
//  The Adafruit library's LEDcontrol() sends instruction 0x35 (the R503
//  aura command), which this module does NOT implement -- every call was
//  silently ignored. Verified on hardware: 0x3C returns confirmation 00,
//  the colours match the bitmask, and OFF stays off through a capture.
//
//  Packet: EF01 | FFFFFFFF | 01 | 0007 | 3C | func | start | end | cycles | sum
//
//  Colour is a BITMASK: bit0 blue, bit1 green, bit2 red. 0x00 = all off.
//  Function: 1 breathing, 2 flashing, 3 steady on, 4 steady off,
//            5 gradual on, 6 gradual off.
//  Start and end colour differ only for breathing; otherwise set both.
// =========================================================
#define BLN_ON     0x03
#define BLN_OFF    0x04
#define BLN_BLUE   0x01
#define BLN_GREEN  0x02
#define BLN_RED    0x04
#define BLN_DARK   0x00

static void blnControl(uint8_t func, uint8_t startCol, uint8_t endCol) {
  if (!sensorFound) return;

  uint8_t pkt[16];
  int i = 0;
  pkt[i++] = 0xEF; pkt[i++] = 0x01;                 // header
  pkt[i++] = 0xFF; pkt[i++] = 0xFF;
  pkt[i++] = 0xFF; pkt[i++] = 0xFF;                 // address
  pkt[i++] = 0x01;                                  // PID = command
  pkt[i++] = 0x00; pkt[i++] = 0x07;                 // length = 5 body + checksum

  uint8_t body[5] = {0x3C, func, startCol, endCol, 0x00};
  uint16_t sum = 0x01 + 0x00 + 0x07;
  for (int k = 0; k < 5; k++) { pkt[i++] = body[k]; sum += body[k]; }
  pkt[i++] = sum >> 8; pkt[i++] = sum & 0xFF;

  while (fingerSerial.available()) fingerSerial.read();
  fingerSerial.write(pkt, i);

  // Drain the reply, or it will be mistaken for a scan response later.
  unsigned long t = millis();
  while (millis() - t < 150) {
    if (fingerSerial.available()) { fingerSerial.read(); t = millis(); }
  }
}

void fingerLedIdle() {
  blnControl(BLN_ON, BLN_BLUE, BLN_BLUE);
  ledTimed = false;
}

void fingerLedOff() {
  blnControl(BLN_OFF, BLN_DARK, BLN_DARK);
  ledTimed = false;
}

// Green while the vehicle is being authorised, then dark. The driver has
// their confirmation; a permanently lit sensor in a parked car is a beacon.
void fingerLedSuccess() {
  blnControl(BLN_ON, BLN_GREEN, BLN_GREEN);
  ledUntil = millis() + FINGER_LED_SUCCESS_MS;
  ledTimed = true;
}

// Red briefly, then back to blue and ready for the next attempt.
void fingerLedFail() {
  blnControl(BLN_ON, BLN_RED, BLN_RED);
  ledUntil = millis() + FINGER_LED_FAIL_MS;
  ledTimed = true;
}

static void updateLed() {
  if (!ledTimed || millis() < ledUntil) return;
  ledTimed = false;
  // Where the backlight goes next depends on whether we are still scanning.
  if (authState == AUTH_ARMED && !authBypass) fingerLedIdle();
  else                                        fingerLedOff();
}

// =========================================================
//  STATE TRANSITIONS
// =========================================================
static void enterArmed(const char* reason) {
  authState = AUTH_ARMED;
  authStateSince = millis();
  fingerPresent = false;
  engineLock(reason);          // drops BOTH relays
  fingerLedIdle();
  Serial.printf("AUTH: armed (%s)\n", reason);
}

static void enterAuthorised(int driverId) {
  authState = AUTH_AUTHORISED;
  authStateSince = millis();
  engineUnlock(driverId, "fingerprint");
  fingerLedSuccess();          // green 2s, then updateLed() turns it off
  Serial.printf("AUTH: authorised, driver %d, %lus to start\n",
                driverId, START_WINDOW_MS / 1000);
}

static void enterRunning() {
  authState = AUTH_RUNNING;
  authStateSince = millis();
  fingerLedOff();
  Serial.println("AUTH: engine running");
  publishAlert("system", "Engine started.", currentDriverId);
  publishTelemetryNow();
}

static void enterGrace() {
  authState = AUTH_GRACE;
  authStateSince = millis();
  Serial.printf("AUTH: engine stopped, %lus grace to restart\n",
                RESTART_GRACE_MS / 1000);
  publishAlert("system", "Engine stopped.", currentDriverId);
  publishTelemetryNow();
}

// Called by Commands.ino when the owner locks remotely. Cancels the grace
// window at once -- the owner should not have to wait out a timer.
void cancelGraceForRemoteLock() {
  if (authState == AUTH_GRACE || authState == AUTH_AUTHORISED)
    Serial.println("AUTH: grace cancelled by remote lock");
  enterArmed("remote lock");
}

// =========================================================
//  SETUP
// =========================================================
void setupFingerprint() {
  prefs.begin("pathfinder", false);

  pinMode(ACC_RELAY_PIN, OUTPUT);
  pinMode(FUEL_PUMP_RELAY_PIN, OUTPUT);
  pinMode(FINGER_TOUCH_PIN, INPUT);       // TOUCH_OUT, used in Phase 2

  fingerSerial.begin(FINGERPRINT_BAUD);
  finger.begin(FINGERPRINT_BAUD);

  // Retry hard: bench testing gave 0/10 on one boot and 10/10 on the next
  // with identical wiring. The count is the diagnostic -- 0/20 means
  // unreachable, anything in between means SoftwareSerial bit timing.
  int passes = 0;
  for (int i = 0; i < 20; i++) {
    if (finger.verifyPassword()) passes++;
    delay(100);
  }
  sensorFound = (passes > 0);
  Serial.printf("Fingerprint: verifyPassword %d/20\n", passes);

  if (sensorFound) {
    finger.getTemplateCount();
    Serial.printf("Fingerprint: %d of %d templates stored\n",
                  finger.templateCount, FINGERPRINT_CAPACITY);
  } else {
    Serial.println("Fingerprint: NOT DETECTED. Check 32/33 and the 3V3 feed.");
  }

  // Bypass persists across reboots, so a brownout mid-journey does not
  // force a fresh scan. The app shows the current state in its quick view,
  // so the owner can always see whether the vehicle is bypassed.
  authBypass = prefs.getBool("bypass", false);

  bool wasUnlocked = prefs.getBool("unlocked", false);
  bool ignitionOn  = ignitionIsOn();

  if (wasUnlocked || ignitionOn || authBypass) {
    int driver = prefs.getInt("driver", -1);

    // A driver suspended while the device was off must not come back
    // authorised. Bypass overrides this: it is the owner's own override.
    if (!authBypass && driver > 0 && driverIsSuspended(driver)) {
      Serial.printf("Boot: driver %d suspended, locking.\n", driver);
      enterArmed("suspended driver on boot");
      return;
    }

    digitalWrite(ACC_RELAY_PIN, RELAY_ON);
    digitalWrite(FUEL_PUMP_RELAY_PIN, RELAY_ON);
    engineLocked = false;
    currentDriverId = driver;

    // Restore into the state that matches reality. Under bypass the vehicle
    // stays authorised indefinitely, so AUTH_AUTHORISED would be wrong --
    // its 60s start window would expire and drop the relays.
    if (ignitionOn)      authState = AUTH_RUNNING;
    else if (authBypass) authState = AUTH_RUNNING;
    else                 authState = AUTH_GRACE;

    authStateSince = millis();
    fingerLedOff();
    Serial.printf("Boot: restored %s, driver %d, bypass %d\n",
                  authStateName(), driver, authBypass);
  } else {
    digitalWrite(ACC_RELAY_PIN, RELAY_OFF);
    digitalWrite(FUEL_PUMP_RELAY_PIN, RELAY_OFF);
    engineLocked = true;
    currentDriverId = -1;
    authState = AUTH_ARMED;
    authStateSince = millis();
    fingerLedIdle();
    Serial.println("Boot: armed, awaiting fingerprint.");
  }
}

// =========================================================
//  REMOTE COMMANDS
// =========================================================
void triggerEnrollment(int id) {
  enrollMode = true;
  enrollId = id;
  fingerPresent = false;
  Serial.printf("Enrolment: armed for slot %d\n", id);
}

void triggerDeleteFingerprint(int id) {
  uint8_t p = finger.deleteModel(id);
  if (p != FINGERPRINT_OK) {
    Serial.printf("Delete: failed slot %d, code 0x%02X\n", id, p);
    publishAlert("system", "Failed to delete fingerprint for ID " + String(id), id);
    return;
  }
  prefs.remove(String(id).c_str());

  // A deleted driver must not keep the vehicle authorised.
  if (currentDriverId == id && !authBypass) enterArmed("authorised driver deleted");

  publishAlert("system", "Fingerprint deleted for ID " + String(id), id);
}

void setDriverStatus(int id, bool isActive) {
  prefs.putBool(String(id).c_str(), !isActive);   // stores the SUSPENDED state
  Serial.printf("Driver %d %s\n", id, isActive ? "ACTIVATED" : "SUSPENDED");
}

void setAuthBypass(bool state) {
  authBypass = state;
  if (state) {
    clearAlarm();
    failedAttempts = 0;
    // No finger was scanned, so there is no driver to credit this to.
    // RUNNING rather than AUTHORISED: bypass has no start window to expire.
    authState = AUTH_RUNNING;
    authStateSince = millis();
    engineUnlock(-1, "remote bypass");
    fingerLedOff();
    publishAlert("system", "Authentication bypassed. Engine unlocked.", -1);
  } else {
    enterArmed("remote bypass disabled");
    publishAlert("system", "Authentication enabled. Engine locked.", -1);
  }
  savePersistentState();
}

// =========================================================
//  ENROLMENT STATE MACHINE
// =========================================================
//  One sensor operation per loop pass, never blocking. An earlier version
//  sat in while loops for up to 60s per stage, during which there was no
//  MQTT keepalive -- so the broker fired the Last Will and the app showed
//  the vehicle OFFLINE mid-enrolment.
// =========================================================
static void runEnrollment() {
  static int stage = 0;
  static unsigned long stageStart = 0, lastPoll = 0;

  unsigned long now = millis();

  if (stage == 0 && stageStart == 0) {
    stageStart = now;
    fingerLedIdle();
    publishAlert("enrollProgress", "Place finger on the sensor.", enrollId);
  }

  if (now - lastPoll < 100) return;
  lastPoll = now;

  #define ENROLL_FAIL(msg) {                          \
      publishAlert("enrollFailed", msg, enrollId);    \
      fingerLedFail(); beep(2, 150);                  \
      stage = 0; stageStart = 0;                      \
      enrollMode = false; enrollId = -1;              \
      fingerPresent = true;                           \
      return; }

  switch (stage) {
    case 0:
      if (now - stageStart > 60000) ENROLL_FAIL("Enrolment timed out.")
      if (finger.getImage() != FINGERPRINT_OK) return;
      if (finger.image2Tz(1) != FINGERPRINT_OK)
        ENROLL_FAIL("Could not read the first scan. Try again.")
      publishAlert("enrollProgress", "First scan captured. Remove your finger.", enrollId);
      stage = 1; stageStart = now;
      return;

    case 1:   // settle pause, replaces delay(2000)
      if (now - stageStart >= 2000) { stage = 2; stageStart = now; }
      return;

    case 2:
      if (now - stageStart > 20000) ENROLL_FAIL("Finger was not removed.")
      if (finger.getImage() != FINGERPRINT_NOFINGER) return;
      publishAlert("enrollProgress", "Place the same finger again.", enrollId);
      stage = 3; stageStart = now;
      return;

    case 3:
      if (now - stageStart > 60000) ENROLL_FAIL("Enrolment timed out.")
      if (finger.getImage() != FINGERPRINT_OK) return;
      if (finger.image2Tz(2) != FINGERPRINT_OK)
        ENROLL_FAIL("Could not read the second scan. Try again.")
      publishAlert("enrollProgress", "Second scan captured. Saving...", enrollId);
      stage = 4; stageStart = now;
      return;

    case 4:   // build and store, ~200ms, the only blocking stage
      if (finger.createModel() != FINGERPRINT_OK)
        ENROLL_FAIL("The two scans did not match. Try again.")
      if (finger.storeModel(enrollId) != FINGERPRINT_OK)
        ENROLL_FAIL("Could not save the fingerprint.")

      Serial.printf("Enrolment: stored as slot %d\n", enrollId);
      publishAlert("enrollSuccess", "Fingerprint enrollment successful.", enrollId);
      prefs.putBool(String(enrollId).c_str(), false);   // new drivers start active
      fingerLedSuccess();
      beep(1, 300);

      stage = 0; stageStart = 0;
      enrollMode = false; enrollId = -1;
      fingerPresent = true;
      return;
  }
  #undef ENROLL_FAIL
}

// =========================================================
//  AUTHENTICATION RESULTS
// =========================================================
static void authSuccess(int id) {
  failedAttempts = 0;

  // A valid finger silences a standing alarm at ANY time -- this is the
  // owner's fastest way to stop a false theft siren, and it must work even
  // when the vehicle is already authorised or running under bypass.
  clearAlarm();

  if (authBypass) {
    // Already authorised remotely. Record who is present and clear the
    // alarm, but leave the relays and the state machine alone.
    currentDriverId = id;
    savePersistentState();
    publishAlert("authSuccess", "Driver identified. Alarm cleared.", id);
    fingerLedSuccess();
    beep(1, 300);
    publishTelemetryNow();
    return;
  }

  if (authState == AUTH_RUNNING || authState == AUTH_GRACE) {
    // Engine running or inside the restart grace. Nothing to unlock.
    currentDriverId = id;
    savePersistentState();
    publishAlert("authSuccess", "Driver re-authenticated.", id);
    fingerLedSuccess();
    beep(1, 300);
    publishTelemetryNow();
    return;
  }

  enterAuthorised(id);
  publishAlert("authSuccess", "Engine authorised. Start within " +
               String(START_WINDOW_MS / 1000) + "s.", id);
  beep(1, 300);
  publishTelemetryNow();
}

static void authFailure() {
  failedAttempts++;
  lastFailTime = millis();
  fingerLedFail();
  beep(1, 120);          // short beep, then back to blue and ready again

  // No driverId: no template matched, so there is nobody to attribute it to.
  if (failedAttempts >= STRIKE_ALARM_THRESHOLD) {
    publishAlert("authFailure",
                 "CRITICAL: " + String(failedAttempts) + " failed attempts.");
    // Only raise the siren when the vehicle is actually locked.
    if (engineLocked && !authBypass)
      raiseAlarm("theft", "Repeated unauthorised fingerprint attempts.");
  } else {
    publishAlert("authSilent",
                 String(failedAttempts) + " failed fingerprint attempt(s).");
  }
}

static void authDenied(int id) {
  failedAttempts++;
  lastFailTime = millis();
  fingerLedFail();
  beep(1, 120);
  publishAlert("authDenied", "Access denied: this driver is deactivated.", id);

  if (failedAttempts >= STRIKE_ALARM_THRESHOLD && engineLocked && !authBypass)
    raiseAlarm("theft", "Repeated attempts by a deactivated driver.");
}

// =========================================================
//  LOOP
// =========================================================
void loopFingerprint() {
  updateLed();

  if (enrollMode && enrollId >= 0) { runEnrollment(); return; }

  // ---- Authorisation state machine ----
  // Bypass suspends it entirely: the owner has taken manual control and the
  // start window and grace timers must not drop the relays underneath them.
  bool ignitionOn = ignitionIsOn();
  unsigned long inState = millis() - authStateSince;

  if (!authBypass) {
    switch (authState) {
      case AUTH_AUTHORISED:
        if (ignitionOn) { enterRunning(); break; }
        // Engine never started. Drop the relays and go back to waiting.
        if (inState > START_WINDOW_MS) {
          publishAlert("system", "Engine not started in time. Re-armed.",
                       currentDriverId);
          enterArmed("start window expired");
          publishTelemetryNow();
        }
        break;

      case AUTH_RUNNING:
        if (!ignitionOn) enterGrace();
        break;

      case AUTH_GRACE:
        if (ignitionOn) {           // restarted inside the window
          authState = AUTH_RUNNING;
          authStateSince = millis();
          Serial.println("AUTH: restarted within grace");
          break;
        }
        if (inState > RESTART_GRACE_MS) {
          publishAlert("system", "Grace expired. Fingerprint required.",
                       currentDriverId);
          enterArmed("grace expired");
          publishTelemetryNow();
        }
        break;

      case AUTH_ARMED:
        break;
    }
  }

  // ---- Scanning ----
  if (!sensorFound) {
    static unsigned long lastProbe = 0;
    if (millis() - lastProbe > 30000) {
      lastProbe = millis();
      if (finger.verifyPassword()) {
        sensorFound = true;
        Serial.println("Fingerprint: sensor recovered.");
        publishAlert("system", "Fingerprint sensor recovered.");
        if (authState == AUTH_ARMED && !authBypass) fingerLedIdle();
      }
    }
    return;
  }

  if (failedAttempts > 0 && millis() - lastFailTime > STRIKE_RESET_MS) {
    Serial.println("Fingerprint: strike counter reset.");
    failedAttempts = 0;
  }

  // Scanning STOPS once authorised: the vehicle is already released and a
  // second finger has nothing to add. It resumes on re-arming.
  //
  // The exception is a standing alarm -- a valid finger must always be able
  // to silence it, so keep scanning while the siren is up whatever the state.
  bool wantScan = (authState == AUTH_ARMED && !authBypass) || sirenLatched;
  if (!wantScan) return;

  if (millis() - lastScan < FINGER_SCAN_INTERVAL_MS) return;
  lastScan = millis();

  uint8_t p = finger.getImage();
  if (p != FINGERPRINT_OK) {
    if (p == FINGERPRINT_NOFINGER) fingerPresent = false;   // arm for next press
    return;
  }

  if (fingerPresent) return;   // same finger still down, already judged
  fingerPresent = true;

  if (finger.image2Tz() != FINGERPRINT_OK) return;

  p = finger.fingerSearch();
  if (p == FINGERPRINT_OK) {
    int id = finger.fingerID;
    if (driverIsSuspended(id)) authDenied(id);
    else                       authSuccess(id);
  } else if (p == FINGERPRINT_NOTFOUND) {
    authFailure();
  }
}