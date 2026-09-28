// =========================================================
//  PathFinder Vehicle Tracker — Main
//  PathFinder.ino   (A7670E build, Phase 1)
// =========================================================
//  This board has NO separate GPS module -- position comes from the
//  A7670E's built-in GNSS over AT commands, so there is no TinyGPSPlus
//  object here.
//
//  Design rule for every tab: nothing in loop() may block. Measured MQTT
//  round trip is ~220ms and a GNSS poll costs ~90ms, so a blocking call of
//  even half a second throws away the whole latency budget.
// =========================================================

#include "Config.h"

// ---- Shared state, defined here, declared extern in Config.h ----
String deviceId;

bool engineLocked    = true;   // both relays de-energised
bool authBypass      = false;  // owner override, restored from NVS at boot
int  currentDriverId = -1;     // -1 = nobody attributable

bool sirenLatched = false;     // an automatic alarm condition stands
bool sirenMuted   = false;     // owner silenced it from the app
bool manualAlarm  = false;     // owner triggered it from the app

unsigned long bootMillis = 0;

// =========================================================
//  IGNITION SENSING
// =========================================================
//  The PC817 optocoupler pulls GPIO34 LOW when the vehicle's ignition
//  circuit is live. GPIO34 is input-only with NO internal pull resistor --
//  R8 on the PCB is the only thing holding it high, so an UNCONNECTED
//  optocoupler leaves this reading HIGH forever, i.e. "ignition off".
//
//  If the app shows the engine permanently off, verify the pin ACTUALLY
//  MOVES before inverting this: with a meter, GPIO34 to ground should read
//  ~3.3V with the ignition off and near 0V with it on. Inverting a pin
//  that never moves gives "permanently running" instead, which is worse --
//  the authorisation state machine would never re-arm.
// =========================================================
bool ignitionIsOn() {
  return digitalRead(ACC_IGNITION_PIN) == LOW;
}

void setup() {
  Serial.begin(115200);
  delay(300);

  // Siren silent from the first instant, before anything else runs.
  setupAlarm();

  Serial.println("\n=== PathFinder Tracker (A7670E GNSS) ===");
  Serial.printf("reset reason: %d\n", (int)esp_reset_reason());

  bootMillis = millis();

  // Order matters twice over. The fingerprint handshake goes BEFORE the
  // modem: SoftwareSerial at 57600 is timing-sensitive and modem UART
  // interrupts during setupNetwork() can corrupt every attempt. And
  // setupGPS() goes AFTER it, because AT+CGNSSPWR needs a live modem.
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
  loopGPS();          // poll AT+CGNSSINFO, cache the fix
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
  // Only meaningful with a FRESH fix; a stale reading must never raise
  // this, or a vehicle that lost signal would appear to drive forever.
  if (engineLocked && !authBypass && gpsIsMoving()) {
    raiseAlarm("theft", "Vehicle moving while immobilised.");
  }

  // --- Ignition transition logging ---
  // Prints every change on GPIO34 to serial. If this line never appears
  // while you turn the key, the optocoupler is not driving the pin and
  // the state machine will never leave its start window.
  static int lastIgn = -1;
  int ign = ignitionIsOn() ? 1 : 0;
  if (ign != lastIgn) {
    Serial.printf("IGNITION -> %s (GPIO34 reads %s)\n",
                  ign ? "ON" : "OFF",
                  digitalRead(ACC_IGNITION_PIN) ? "HIGH" : "LOW");
    lastIgn = ign;
  }

  // --- Sleep ---
  loopSleep();
}

// =========================================================
//  RELAY CONTROL
// =========================================================
//  The ONLY two functions that touch the relays. Both relays move
//  together: neither is wired to vehicle accessories, so there is no
//  accessory circuit to hold up independently.
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
//  LOCKED -- a driver sitting in an authorised vehicle must not set off
//  the siren by moving about. Safety alarms (overheat) and the owner's own
//  app-triggered alarm sound regardless, because an overheating engine
//  happens WHILE DRIVING and a silent warning is no warning.
//
//  Crash deliberately does not reach here: it publishes an alert and sends
//  SMS from Sensors.ino without sounding the siren.
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
//  millis() and lose RAM, and would cold-start the GNSS -- which took 176s
//  on this board. Light sleep keeps the connection alive and resumes on
//  the next line, so loop() still runs ~4x a second.
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
  // is polled, the GNSS keeps being read and telemetry goes out on time.
  esp_sleep_enable_timer_wakeup(250000ULL);
  gpio_wakeup_enable((gpio_num_t)ACC_IGNITION_PIN, GPIO_INTR_LOW_LEVEL);
  gpio_wakeup_enable((gpio_num_t)PANIC_BUTTON_PIN, GPIO_INTR_LOW_LEVEL);
  gpio_wakeup_enable((gpio_num_t)MPU_INT_PIN,      GPIO_INTR_HIGH_LEVEL);
  gpio_wakeup_enable((gpio_num_t)FINGER_TOUCH_PIN, GPIO_INTR_HIGH_LEVEL);
  esp_sleep_enable_gpio_wakeup();
  esp_light_sleep_start();
}