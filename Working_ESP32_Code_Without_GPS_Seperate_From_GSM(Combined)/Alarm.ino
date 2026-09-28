// =========================================================
//  PathFinder Vehicle Tracker — Alarm
//  Alarm.ino   (Phase 1)
// =========================================================
//  Sole owner of ALARM_SIREN_PIN. Nothing else writes it.
//
//  An earlier build had two tabs driving this pin: the main loop asserted
//  it while latched, and beep() drove it for feedback. Whichever ran last
//  in loop() won, which is why every beep was stomped microseconds after it
//  started and none were audible. One writer, one state machine.
//
//  Buzzer is ACTIVE-HIGH on this build: SIREN_ON = HIGH.
//
//  Three independent inputs decide whether it sounds:
//    sirenLatched — an automatic alarm condition (theft, overheat, strikes)
//    manualAlarm  — the owner pressed the alarm button in the app
//    sirenMuted   — the owner silenced it, WITHOUT clearing the condition
//
//  Mute deliberately does not clear the condition. The app keeps showing
//  the alert while the vehicle stays quiet, and the history stays intact.
//
//  NOTE: whether a theft condition latches the siren at all is decided in
//  raiseAlarm() (PathFinder.ino), not here. This file only plays what it
//  is told to play.
// =========================================================

#include "Config.h"

// Queued beep pattern. beep() returns immediately; this drives it.
static int  beepsRemaining = 0;
static int  beepDuration = 0;
static bool beepPhaseOn = false;
static unsigned long beepNextToggle = 0;

// Current physical pin state, tracked so we only write on a change.
static bool pinIsOn = false;

void setupAlarm() {
  pinMode(ALARM_SIREN_PIN, OUTPUT);
  digitalWrite(ALARM_SIREN_PIN, SIREN_OFF);
  pinIsOn = false;
}

// Queue a feedback pattern. Returns immediately.
// Suppressed while the siren is sounding: chopping a theft alarm into beeps
// is worse than giving no confirmation at all.
void beep(int times, int durationMs) {
  if (sirenLatched || manualAlarm) return;
  beepsRemaining = times * 2;        // each beep = one ON phase + one gap
  beepDuration = durationMs;
  beepPhaseOn = true;
  beepNextToggle = millis() + durationMs;
}

void setSirenMuted(bool muted) {
  sirenMuted = muted;
  Serial.printf("Siren: %s\n", muted ? "MUTED" : "unmuted");
}

void setManualAlarm(bool on) {
  manualAlarm = on;
  Serial.printf("Siren: manual alarm %s\n", on ? "ON" : "off");
}

void loopAlarm() {
  unsigned long now = millis();

  bool alarmWanted = (sirenLatched || manualAlarm) && !sirenMuted;

  if (alarmWanted) {
    // An alarm takes priority over any queued beep. Abandon the pattern
    // rather than interleaving the two on one pin.
    if (beepsRemaining > 0) { beepsRemaining = 0; beepPhaseOn = false; }

    // Pulsed, not continuous: 400ms on, 300ms off. A pulsing siren carries
    // further and is unmistakably an alarm rather than a stuck buzzer.
    static unsigned long alarmToggle = 0;
    static bool alarmPhase = false;
    if (now >= alarmToggle) {
      alarmPhase = !alarmPhase;
      alarmToggle = now + (alarmPhase ? 400 : 300);
      if (pinIsOn != alarmPhase) {
        digitalWrite(ALARM_SIREN_PIN, alarmPhase ? SIREN_ON : SIREN_OFF);
        pinIsOn = alarmPhase;
      }
    }
    return;
  }

  // No alarm. Drive any queued beep pattern.
  if (beepsRemaining > 0) {
    if (now >= beepNextToggle) {
      beepsRemaining--;
      if (beepsRemaining <= 0) {
        if (pinIsOn) { digitalWrite(ALARM_SIREN_PIN, SIREN_OFF); pinIsOn = false; }
        beepPhaseOn = false;
      } else {
        beepPhaseOn = !beepPhaseOn;
        digitalWrite(ALARM_SIREN_PIN, beepPhaseOn ? SIREN_ON : SIREN_OFF);
        pinIsOn = beepPhaseOn;
        beepNextToggle = now + beepDuration;
      }
    }
    return;
  }

  // Nothing wants the siren. Make sure it is off.
  if (pinIsOn) {
    digitalWrite(ALARM_SIREN_PIN, SIREN_OFF);
    pinIsOn = false;
  }
}