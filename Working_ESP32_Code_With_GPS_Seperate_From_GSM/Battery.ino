// =========================================================
//  PathFinder Vehicle Tracker — Main power detection
//  Battery.ino   (Phase 1: presence only, no voltage reporting)
// =========================================================
//  The vehicle's 12V feed is sensed through the divider on GPIO35, but the
//  firmware no longer reports a voltage or a percentage -- only whether the
//  feed is PRESENT.
//
//  A threshold is still needed: a disconnected feed leaves the divider
//  FLOATING rather than sitting at zero, and a floating ESP32 input drifts
//  a few hundred millivolts. That drift is what produced the frozen 2.37V
//  reading seen earlier. The threshold sits well above any float voltage
//  and well below a flat battery, so neither end can be mistaken.
//
//  Because nothing is calibrated any more, CAL_SLOPE and CAL_OFFSET are
//  gone and a second board needs no per-unit calibration.
// =========================================================

#include "Config.h"

// Raw divider voltage at the pin, smoothed. Never published.
static float pinVolts = 0.0;
static unsigned long lastSample = 0;

// Sampling is spread across loop passes. Reading 50 samples back to back
// with delay(2) -- as the bench sketch does -- blocks for 100ms, which is
// long enough to overflow the GPS UART buffer.
static const int BATCH_SIZE = 50;
static const int SAMPLES_PER_PASS = 5;
static const unsigned long SAMPLE_INTERVAL_MS = 4;
static float batchTotal = 0;
static int   batchCount = 0;

void setupBattery() {
  analogReadResolution(12);
  analogSetPinAttenuation(BATTERY_PIN, ADC_11db);   // reach the ~1.1-1.3V the divider gives

  // Seed with a full blocking batch. This is setup, so blocking is fine,
  // and it means the first telemetry packet reports real presence rather
  // than tripping a false power-cut alert before loopBattery() has run.
  float total = 0;
  for (int i = 0; i < BATCH_SIZE; i++) { total += analogReadMilliVolts(BATTERY_PIN); delay(2); }
  pinVolts = (total / BATCH_SIZE) / 1000.0;

  Serial.printf("Main power: %s (pin %.3fV)\n",
                mainPowerPresent() ? "PRESENT" : "ABSENT", pinVolts);
}

void loopBattery() {
  if (millis() - lastSample < SAMPLE_INTERVAL_MS) return;
  lastSample = millis();

  for (int i = 0; i < SAMPLES_PER_PASS; i++) batchTotal += analogReadMilliVolts(BATTERY_PIN);
  batchCount += SAMPLES_PER_PASS;

  if (batchCount < BATCH_SIZE) return;

  float reading = (batchTotal / batchCount) / 1000.0;
  batchTotal = 0;
  batchCount = 0;

  // Light smoothing so a single noisy batch cannot flip the presence flag.
  pinVolts = (0.7 * pinVolts) + (0.3 * reading);
}

// The pin sees the DIVIDED voltage, so the threshold is scaled by the same
// ratio the divider applies: ~0.56V at the pin is roughly 6V at the battery.
bool mainPowerPresent() {
  return pinVolts >= MAIN_POWER_PIN_THRESHOLD_V;
}

// True when the feed has been severed -- a strong theft signal.
//
// Guarded: a vehicle cannot be running without its own supply, so a reading
// this low while the ignition is ON is far more likely to be a sensing fault
// than a cut battery. Reporting a fault as theft would wake the owner at 3am
// over a loose divider wire.
bool batteryPowerCut() {
  if (mainPowerPresent()) return false;
  if (ignitionIsOn()) return false;
  return true;
}

// =========================================================
//  POWER-CUT WATCH
// =========================================================
//  Fires once on the transition, not every cycle, and requires the
//  condition to persist. A starter motor pulls the rail down hard for a
//  second or so during cranking, and without this every engine start would
//  look like a severed battery.
// =========================================================
void checkPowerCut() {
  static bool cutActive = false;
  static unsigned long cutSince = 0;

  bool cut = batteryPowerCut();

  if (cut && !cutActive) {
    if (cutSince == 0) cutSince = millis();
    if (millis() - cutSince > 3000) {
      cutActive = true;
      raiseAlarm("theft", "Main vehicle power disconnected. Running on backup.");
    }
  } else if (!cut) {
    cutSince = 0;
    if (cutActive) {
      cutActive = false;
      publishAlert("system", "Main vehicle power restored.");
    }
  }
}