// =========================================================
//  PathFinder Vehicle Tracker — GNSS (A7670E built-in)
//  GPS.ino   (A7670E build)
// =========================================================
//  Position comes from the modem over AT commands on the SAME UART that
//  carries MQTT. There is no second serial port and no NMEA parsing.
//
//  Measured on this board: a poll costs 89-97ms, consistently. Cold start
//  to first fix was 176s; a warm restart fixed on the first poll.
//
//  Response format (A7670E-MASA, firmware A131B03A7670M6C_M):
//    +CGNSSINFO: <mode>,<GPS>,<GLONASS>,<BEIDOU>,<GALILEO>,
//                <lat>,<N/S>,<lng>,<E/W>,<date>,<UTC>,
//                <alt>,<speed_knots>,<course>,<PDOP>,<HDOP>,<VDOP>,...
//  Example:
//    3,11,,05,00,6.2477107,N,7.1128087,E,140926,225439.00,75.0,0.337,,4.21,2.40,3.46,06
//
//  Coordinates are DECIMAL DEGREES here, unlike AT+CGPSINFO which returns
//  degrees-minutes. No conversion needed. Speed is in KNOTS.
//  An unfixed receiver returns a line of bare commas: ",,,,,,,,".
// =========================================================

#include "Config.h"

extern TinyGsm modem;      // owned by Network.ino

// ---- Cached fix state ----
static bool  fixValid = false;
static float fixLat = 0.0, fixLng = 0.0;
static float fixSpeedKmph = 0.0;
static int   fixSats = 0;
static unsigned long lastFixMillis = 0;

// Last known position, kept across signal loss so telemetry can still
// report where the vehicle was. Survives loss, not a reboot.
static float lastGoodLat = 0.0, lastGoodLng = 0.0;
static bool  everHadFix = false;

static bool gnssPowered = false;
static unsigned long lastPoll = 0;
static unsigned long gnssOnAt = 0;

// =========================================================
//  SETUP
// =========================================================
//  Called AFTER setupNetwork(): the modem must be awake before it will
//  accept AT+CGNSSPWR. Power-on is retried from loopGPS() if it fails.
// =========================================================
void setupGPS() {
  Serial.println("GNSS: powering receiver...");
  modem.sendAT(GF("+CGNSSPWR=1"));
  if (modem.waitResponse(10000L) == 1) {
    gnssPowered = true;
    gnssOnAt = millis();
    Serial.println("GNSS: powered. Cold start may take 2-3 minutes.");
  } else {
    Serial.println("GNSS: power-on failed, will retry in loop.");
  }
}

// =========================================================
//  PARSER
// =========================================================
//  Field positions shift between firmware revisions, so rather than
//  trusting an index we locate the N/S hemisphere marker: latitude is
//  always the field immediately before it, longitude two after.
// =========================================================
static bool parseCGNSSINFO(const String &line) {
  if (line.length() < 12) return false;      // unfixed = bare commas

  String f[20];
  int n = 0, start = 0;
  for (int i = 0; i <= (int)line.length() && n < 20; i++) {
    if (i == (int)line.length() || line[i] == ',') {
      f[n++] = line.substring(start, i);
      start = i + 1;
    }
  }
  if (n < 10) return false;

  int ns = -1;
  for (int i = 1; i < n; i++) {
    f[i].trim();
    if (f[i] == "N" || f[i] == "S") { ns = i; break; }
  }
  if (ns < 1 || ns + 3 >= n) return false;

  String latS = f[ns - 1]; latS.trim();
  String lngS = f[ns + 1]; lngS.trim();
  String ewS  = f[ns + 2]; ewS.trim();
  if (latS.length() == 0 || lngS.length() == 0) return false;

  float lat = latS.toFloat();
  float lng = lngS.toFloat();
  if (lat == 0.0 && lng == 0.0) return false;
  if (f[ns] == "S") lat = -lat;
  if (ewS == "W")   lng = -lng;

  // Sanity: a parse artefact must never reach the backend.
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;

  fixLat = lat;
  fixLng = lng;

  // Satellites: sum the numeric counts before the latitude field.
  int sats = 0;
  for (int i = 1; i < ns - 1; i++) {
    f[i].trim();
    if (f[i].length()) sats += f[i].toInt();
  }
  fixSats = (sats > 0 && sats <= 32) ? sats : 0;

  // Speed sits past E/W, date, UTC and altitude, and is in KNOTS.
  int speedIdx = ns + 6;
  if (speedIdx < n) {
    f[speedIdx].trim();
    fixSpeedKmph = f[speedIdx].length() ? f[speedIdx].toFloat() * 1.852 : 0.0;
  } else fixSpeedKmph = 0.0;

  return true;
}

// =========================================================
//  LOOP
// =========================================================
void loopGPS() {
  if (millis() - lastPoll < GNSS_POLL_MS) return;
  lastPoll = millis();

  if (!gnssPowered) {
    static unsigned long lastRetry = 0;
    if (millis() - lastRetry < 30000) return;
    lastRetry = millis();
    modem.sendAT(GF("+CGNSSPWR=1"));
    if (modem.waitResponse(10000L) == 1) {
      gnssPowered = true;
      gnssOnAt = millis();
      Serial.println("GNSS: powered on retry.");
    }
    return;
  }

  modem.sendAT(GF("+CGNSSINFO"));
  if (modem.waitResponse(3000L, GF("+CGNSSINFO:")) != 1) {
    modem.waitResponse(500L);
    return;
  }

  String line = modem.stream.readStringUntil('\n');
  modem.waitResponse(1000L);     // consume the trailing OK
  line.trim();

  if (parseCGNSSINFO(line)) {
    fixValid = true;
    lastFixMillis = millis();
    lastGoodLat = fixLat;
    lastGoodLng = fixLng;
    everHadFix = true;
  }
  // No else: a failed parse leaves the cached fix in place and lets it age
  // out through gpsHasFreshFix(). One dropped poll must not discard a
  // perfectly good position.
}

// =========================================================
//  ACCESSORS
// =========================================================
//  Identical signatures to the separate-module version, so telemetry,
//  commands, alarm and SD logging need no changes at all.
// =========================================================
bool gpsHasFreshFix() {
  if (!fixValid) return false;
  return (millis() - lastFixMillis) < GPS_FIX_MAX_AGE_MS;
}

float gpsLat() { return fixLat; }
float gpsLng() { return fixLng; }

float gpsSpeedKmph() {
  if (!gpsHasFreshFix()) return 0.0;
  return fixSpeedKmph;
}

bool gpsIsMoving() {
  if (!gpsHasFreshFix()) return false;
  return fixSpeedKmph > MOVING_THRESHOLD_KMPH;
}

int gpsSatellites() {
  if (!gpsHasFreshFix()) return 0;
  return fixSats;
}

unsigned long gpsFixAgeSeconds() {
  if (!everHadFix) return 0;
  return (millis() - lastFixMillis) / 1000;
}

bool  gpsEverHadFix() { return everHadFix; }
float gpsLastLat()    { return lastGoodLat; }
float gpsLastLng()    { return lastGoodLng; }

// =========================================================
//  FIX-LOSS WATCH
// =========================================================
void checkGpsFixLoss() {
  static bool fixLost = false;
  static unsigned long lostSince = 0;

  bool fresh = gpsHasFreshFix();

  if (!fresh && everHadFix) {
    if (lostSince == 0) lostSince = millis();
    // 60 seconds before raising it: brief dropouts under a bridge or in a
    // car park entrance are normal and not worth an alert.
    if (!fixLost && millis() - lostSince > 60000) {
      fixLost = true;
      publishAlert("sensorFault",
                   "GNSS fix lost. Last position " +
                   String(gpsFixAgeSeconds()) + "s old.");
    }
  } else if (fresh) {
    lostSince = 0;
    if (fixLost) {
      fixLost = false;
      publishAlert("system", "GNSS fix reacquired.");
    }
  }
}

// =========================================================
//  DIAGNOSTIC
// =========================================================
void gpsPrintStatus() {
  static unsigned long lastPrint = 0;
  if (gpsHasFreshFix()) return;
  if (millis() - lastPrint < 15000) return;
  lastPrint = millis();

  Serial.printf("GNSS: no fix | powered=%d elapsed=%lus everHadFix=%d\n",
                gnssPowered, gnssOnAt ? (millis() - gnssOnAt) / 1000 : 0,
                everHadFix);
  if (gnssPowered && gnssOnAt && millis() - gnssOnAt < GNSS_COLD_START_MS)
    Serial.println("GNSS: still in cold start, this took 176s on the bench.");
}