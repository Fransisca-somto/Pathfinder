// =========================================================
//  PathFinder Vehicle Tracker — Main
//  PathFinder.ino   (Phase 1)
// =========================================================
//  Tab order: PathFinder (this), Config.h, Telemetry, Network, Commands,
//  Battery, GPS, Fingerprint, Alarm, Sensors, SDLogger.
//
//  Design rule for every tab: nothing in loop() may block. Measured MQTT
//  round trip is ~220ms, so a blocking call of even half a second throws
//  away the whole latency budget.
// =========================================================

#include "Config.h"

// ---- Shared state, defined here, declared extern in Config.h ----
String   deviceId;
TinyGPSPlus gps;

bool     engineLocked    = true;   // both relays de-energised
bool     authBypass      = false;  // owner override, restored from NVS at boot
int      currentDriverId = -1;     // -1 = nobody attributable

bool     sirenLatched = false;     // an automatic alarm condition stands
bool     sirenMuted   = false;     // owner silenced it from the app
bool     manualAlarm  = false;     // owner triggered it from the app

unsigned long bootMillis = 0;

// The PC817 pulls this LOW when the ignition circuit is live. It is an
// input-only pin with NO internal pull -- R8 on the PCB holds it high.
bool ignitionIsOn() {
  return digitalRead(ACC_IGNITION_PIN) == LOW;
}

void setup() {
  Serial.begin(115200);
  delay(300);

  // Siren silent from the first instant, before anything else runs.
  setupAlarm();

  Serial.println("\n=== PathFinder Tracker ===");
  Serial.printf("reset reason: %d\n", (int)esp_reset_reason());

  bootMillis = millis();

  // Order matters. The fingerprint handshake goes BEFORE the modem:
  // SoftwareSerial at 57600 is timing-sensitive and modem UART interrupts
  // during setupNetwork() can corrupt every attempt.
  setupSDCard();
  setupFingerprint();
  setupNetwork();
  setupGPS();
  setupBattery();
  setupSensors();

  Serial.println("=== setup complete ===\n");
}

void loop() {
  // --- Communications ---
  loopNetwork();      // modem, MQTT connect/reconnect, SD queue flush
  loopModem();        // SMS queue

  // --- Sensors ---
  loopGPS();          // feed the NMEA parser, track fix freshness
  loopBattery();      // rolling ADC sample, never blocks
  loopSensors();      // accelerometer, temperature, SOS button

  // --- Authorisation ---
  loopFingerprint();  // state machine, scanning, backlight

  // --- Outputs ---
  loopAlarm();        // siren state machine, honours mute

  // --- Publishing ---
  // Runs on its own 5s timer and publishes whether or not there is a fix.
  loopTelemetry();

  // --- Security: movement while immobilised ---
  // Only meaningful with a FRESH fix; a stale reading must never raise this,
  // or a vehicle that lost signal would appear to be driving forever.
  if (engineLocked && !authBypass && gpsIsMoving()) {
    raiseAlarm("theft", "Vehicle moving while immobilised.");
  }

  // --- Sleep ---
  loopSleep();
}

// =========================================================
//  RELAY CONTROL
// =========================================================
//  The ONLY two functions that touch the relays. Both relays move together:
//  neither is wired to vehicle accessories, so there is no accessory
//  circuit to hold up independently.
//
//  Routing every change through here is what stops engineLocked drifting
//  out of step with the hardware, which it did when the writes were
//  scattered across the fingerprint, bypass and boot-restore paths.
// =========================================================
void engineUnlock(int driverId, const char* reason) {
  digitalWrite(ACC_RELAY_PIN, RELAY_ON);
  digitalWrite(FUEL_PUMP_RELAY_PIN, RELAY_ON);
  engineLocked = false;
  currentDriverId = driverId;
  savePersistentState();
  Serial.printf("RELAYS ON (%s), driver %d\n", reason, driverId);
}

void engineLock(const char* reason) {
  digitalWrite(ACC_RELAY_PIN, RELAY_OFF);
  digitalWrite(FUEL_PUMP_RELAY_PIN, RELAY_OFF);
  engineLocked = true;
  currentDriverId = -1;
  savePersistentState();
  Serial.printf("RELAYS OFF (%s)\n", reason);
}

// =========================================================
//  ALARM ENTRY POINT
// =========================================================
//  Rate limited per alert type so a standing condition cannot flood the
//  broker. The siren itself is driven by loopAlarm().
//
//  BUZZER POLICY: security alarms (theft) sound only while the vehicle is
//  LOCKED -- a driver sitting in an authorised vehicle must not set off the
//  siren by moving about. Safety alarms (overheat) and the owner's own
//  app-triggered alarm sound regardless, because an overheating engine
//  happens WHILE DRIVING and a silent warning is no warning.
// =========================================================
void raiseAlarm(const char* type, const String &message) {
  static unsigned long lastRaise[6] = {0};
  static const char* types[6] = {"theft", "crash", "panic", "temperature",
                                 "sensorFault", "system"};
  int slot = 5;
  for (int i = 0; i < 6; i++) if (!strcmp(types[i], type)) { slot = i; break; }

  bool securityAlarm = (strcmp(type, "theft") == 0);
  bool vehicleOpen = (!engineLocked || authBypass);

  if (!securityAlarm || !vehicleOpen) sirenLatched = true;

  if (lastRaise[slot] != 0 && millis() - lastRaise[slot] < ALERT_COOLDOWN_MS) return;
  lastRaise[slot] = millis();
  publishAlert(type, message);
}

// Called when a valid fingerprint, a remote unlock or an app mute clears
// the condition.
void clearAlarm() {
  sirenLatched = false;
  manualAlarm  = false;
}

// =========================================================
//  SLEEP
// =========================================================
//  LIGHT sleep, not deep. Deep sleep would drop the MQTT session, reset
//  millis() and lose RAM; light sleep keeps the connection alive and
//  resumes on the next line, so loop() still runs ~4x a second and the
//  fingerprint sensor keeps being polled.
//
//  Deep sleep with TOUCH_OUT wake is Phase 2.
// =========================================================
void loopSleep() {
  static unsigned long lastActive = 0;
  if (lastActive == 0) lastActive = millis();

  // Any sign of use resets the timer.
  if (ignitionIsOn() || gpsIsMoving() || !engineLocked) lastActive = millis();

  // Never nap while an alarm is up, the vehicle is authorised, or it is
  // moving -- sleeping would abandon the alert and stall telemetry.
  if (sirenLatched || manualAlarm) return;
  if (!engineLocked || authBypass) return;
  if (ignitionIsOn() || gpsIsMoving()) return;
  if (millis() - lastActive < SLEEP_IDLE_MS) return;

  // 250ms naps: loop() still runs ~4x a second, so the fingerprint sensor
  // is polled and telemetry still goes out on schedule.
  esp_sleep_enable_timer_wakeup(250000ULL);
  gpio_wakeup_enable((gpio_num_t)ACC_IGNITION_PIN, GPIO_INTR_LOW_LEVEL);
  gpio_wakeup_enable((gpio_num_t)PANIC_BUTTON_PIN, GPIO_INTR_LOW_LEVEL);
  gpio_wakeup_enable((gpio_num_t)MPU_INT_PIN,      GPIO_INTR_HIGH_LEVEL);
  gpio_wakeup_enable((gpio_num_t)FINGER_TOUCH_PIN, GPIO_INTR_HIGH_LEVEL);
  esp_sleep_enable_gpio_wakeup();
  esp_light_sleep_start();
}