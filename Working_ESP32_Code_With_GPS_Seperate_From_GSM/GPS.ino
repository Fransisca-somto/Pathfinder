// =========================================================
//  PathFinder Vehicle Tracker — GPS
//  File 7 of 10:  GPS.ino
// =========================================================
//  Feeds the NMEA parser and owns every question about position.
//
//  PIN ORDER: confirmed by test. The ESP32 RECEIVES on 13 and TRANSMITS
//  on 4. The old Hardware.h named these from the MODULE's perspective,
//  so passing GPS_RX_PIN as begin()'s rx argument had the ESP32 listening
//  to its own output -- which is why neither unit ever got a fix.
//
//  This module reports a multi-GNSS solution ($GNGGA, $GNRMC, plus BeiDou
//  $BDGSA/$BDGSV), so it is not a GPS-only NEO-6M. TinyGPSPlus parses GN
//  sentences correctly, so no special handling is needed.
//
//  KEY POINT: isValid() stays true forever once a fix has been seen. Age
//  is the only thing separating "where the vehicle IS" from "where it WAS".
//  Everything below checks age, never isValid() alone.
// =========================================================

#include "Config.h"

HardwareSerial gpsSerial(2);

// Last known good position, kept so telemetry can report where the vehicle
// was even while the fix is stale. Survives signal loss, not a reboot.
static float lastGoodLat = 0.0, lastGoodLng = 0.0;
static bool  everHadFix = false;
static unsigned long lastFixMillis = 0;

static bool wiringWarned = false;
static unsigned long bytesSeen = 0;

void setupGPS() {
  // Enlarge the RX buffer BEFORE begin(). The default is 256 bytes, but a
  // 1 Hz multi-GNSS burst is 400-700 bytes. If any tab blocks for more than
  // ~250ms the buffer overflows, sentences are lost, and every age() check
  // in the rest of the firmware starts rejecting good data.
  gpsSerial.setRxBufferSize(1024);
  gpsSerial.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

  Serial.printf("GPS: rx=%d tx=%d @ %d baud\n", GPS_RX_PIN, GPS_TX_PIN, GPS_BAUD);
}

void loopGPS() {
  // Bounded read, not "while (available())". At 9600 baud a byte lands
  // roughly every millisecond, and if the buffer is already deep an
  // unbounded loop keeps servicing new arrivals and never returns --
  // starving the fingerprint scan, the SOS poll and crash detection.
  // 256 bytes is a quarter of the buffer: enough to keep up with a normal
  // burst while guaranteeing we hand control back.
  int budget = 256;
  while (gpsSerial.available() > 0 && budget-- > 0) {
    char c = gpsSerial.read();
    bytesSeen++;
    gps.encode(c);
  }

  // Capture each fresh fix as it arrives, so last-known survives the loss.
  if (gps.location.isValid() && gps.location.age() < GPS_FIX_MAX_AGE_MS) {
    lastGoodLat = gps.location.lat();
    lastGoodLng = gps.location.lng();
    lastFixMillis = millis();
    everHadFix = true;
  }

  // Wiring warning, latched so it prints once rather than forever.
  if (!wiringWarned && millis() > 10000 && gps.charsProcessed() < 10) {
    Serial.println("GPS: no data received. Check rx/tx order and the antenna.");
    wiringWarned = true;
  }
}

// =========================================================
//  ACCESSORS
// =========================================================

// The single definition of "we know where the vehicle is right now".
bool gpsHasFreshFix() {
  return gps.location.isValid() && gps.location.age() < GPS_FIX_MAX_AGE_MS;
}

float gpsLat() { return gps.location.lat(); }
float gpsLng() { return gps.location.lng(); }

// Speed is only trusted when it is BOTH valid and fresh. A stale speed is
// how a vehicle that lost signal on the motorway appears to keep driving
// at its last known speed indefinitely.
float gpsSpeedKmph() {
  if (!gps.speed.isValid() || gps.speed.age() >= GPS_FIX_MAX_AGE_MS) return 0.0;
  return gps.speed.kmph();
}

// 10 km/h, not 0. A stationary receiver reports 0.1-1.5 km/h of jitter
// continuously, which previously made the vehicle look permanently moving
// and generated hundreds of one-second trips in the backend.
bool gpsIsMoving() {
  if (!gpsHasFreshFix()) return false;
  return gpsSpeedKmph() > MOVING_THRESHOLD_KMPH;
}

int gpsSatellites() {
  if (!gps.satellites.isValid() || gps.satellites.age() >= GPS_FIX_MAX_AGE_MS) return 0;
  int n = gps.satellites.value();
  // Guard against a garbled sentence passing checksum: a receiver tracking
  // 34 satellites is a parser artefact, and the backend rejects any packet
  // claiming more than 32.
  if (n < 0 || n > 32) return 0;
  return n;
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
//  Called from loopSensors(). Tells the backend explicitly when a fix is
//  lost or regained, so it can distinguish "parked here" from "we have
//  lost sight of the vehicle" -- which telemetry alone cannot convey.
// =========================================================
void checkGpsFixLoss() {
  static bool fixLost = false;
  static unsigned long lostSince = 0;

  bool fresh = gpsHasFreshFix();

  if (!fresh && everHadFix) {
    if (lostSince == 0) lostSince = millis();
    // 60 seconds before raising it. Brief dropouts under a bridge or in a
    // car park entrance are normal and not worth an alert.
    if (!fixLost && millis() - lostSince > 60000) {
      fixLost = true;
      publishAlert("sensorFault",
                   "GPS fix lost. Last known position " +
                   String(gpsFixAgeSeconds()) + "s old.");
    }
  } else if (fresh) {
    lostSince = 0;
    if (fixLost) {
      fixLost = false;
      publishAlert("system", "GPS fix reacquired.");
    }
  }
}

// =========================================================
//  DIAGNOSTIC
// =========================================================
//  Printed periodically while there is no fix, so a bench test shows
//  whether bytes are arriving at all. A byte count that stays at zero is a
//  wiring fault; a count that climbs with no fix is cold-start acquisition.
// =========================================================
void gpsPrintStatus() {
  static unsigned long lastPrint = 0;
  if (gpsHasFreshFix()) return;
  if (millis() - lastPrint < 10000) return;
  lastPrint = millis();

  Serial.printf("GPS: no fix | bytes=%lu parsed=%lu sats=%d checksumErr=%lu\n",
                bytesSeen, gps.charsProcessed(),
                gps.satellites.isValid() ? gps.satellites.value() : -1,
                gps.failedChecksum());

  if (bytesSeen == 0)
    Serial.println("GPS: zero bytes -- wrong pin order, or module TX not wired.");
  else if (gps.failedChecksum() > 20)
    Serial.println("GPS: checksum errors -- baud mismatch or a noisy line.");
}