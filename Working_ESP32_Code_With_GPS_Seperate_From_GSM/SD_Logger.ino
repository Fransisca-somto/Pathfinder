// =========================================================
//  PathFinder Vehicle Tracker — SD Logger
//  File 11:  SDLogger.ino
// =========================================================
//  Two jobs:
//
//  1. FORENSIC TRAIL — position, power and ignition written every cycle
//     regardless of link state, so the card can be pulled from the tracker
//     and read as a complete history. The online/OFFLINE marker on each row
//     identifies which stretches never reached the backend.
//
//  2. OFFLINE ALERT QUEUE — an alert that fails to publish is written here,
//     not to RAM. A crash in a tunnel or a cut battery is exactly the event
//     most likely to take the link down AND reboot the device, so anything
//     held only in RAM would die with the reboot. The one alert that
//     mattered would be the one lost.
// =========================================================

#include "Config.h"

static bool sdReady = false;
static Preferences sdPrefs;
static uint32_t bootCount = 0;

// =========================================================
//  HELPERS
// =========================================================

// GPS time when it is genuinely current, otherwise a boot-relative stamp.
// age() matters: isValid() stays true forever once a fix has been seen, so
// without it every row logged inside a tunnel carries the timestamp of the
// moment signal was lost -- dozens of identical, unorderable stamps.
static String stamp() {
  char ts[40];
  if (gps.date.isValid() && gps.time.isValid() &&
      gps.time.age() < GPS_FIX_MAX_AGE_MS &&
      gps.date.age() < GPS_FIX_MAX_AGE_MS &&
      gps.date.year() > 2020) {
    snprintf(ts, sizeof(ts), "%04d-%02d-%02dT%02d:%02d:%02dZ",
             gps.date.year(), gps.date.month(), gps.date.day(),
             gps.time.hour(), gps.time.minute(), gps.time.second());
  } else {
    // Boot counter included, otherwise rows from before and after a reboot
    // both start near zero and cannot be ordered.
    snprintf(ts, sizeof(ts), "boot%lu_%lums",
             (unsigned long)bootCount, (unsigned long)millis());
  }
  return String(ts);
}

// Wrap a CSV field so embedded commas cannot shift every column after it.
// Alert messages routinely contain commas.
static String esc(String field) {
  field.replace("\"", "\"\"");
  return "\"" + field + "\"";
}

static void appendFile(const char* path, const String &line) {
  if (!sdReady) return;
  File f = SD.open(path, FILE_APPEND);
  if (!f) return;
  f.print(line);
  f.close();
}

// Rotate a log that has outgrown its cap. Keeps one previous generation.
static void rotateIfLarge(const char* path, const char* oldPath, size_t maxBytes) {
  if (!sdReady) return;
  File f = SD.open(path, FILE_READ);
  if (!f) return;
  size_t sz = f.size();
  f.close();
  if (sz < maxBytes) return;
  if (SD.exists(oldPath)) SD.remove(oldPath);
  SD.rename(path, oldPath);
  Serial.printf("SD: rotated %s (%u bytes)\n", path, (unsigned)sz);
}

static void createCsv(const char* path, const char* header) {
  if (SD.exists(path)) return;
  File f = SD.open(path, FILE_WRITE);
  if (!f) return;
  f.println(header);
  f.close();
}

// =========================================================
//  SETUP
// =========================================================
void setupSDCard() {
  sdPrefs.begin("sdlog", false);
  bootCount = sdPrefs.getUInt("boots", 0) + 1;
  sdPrefs.putUInt("boots", bootCount);
  Serial.printf("SD: boot #%lu\n", (unsigned long)bootCount);

  if (!SD.begin(SD_CS_PIN)) {
    Serial.println("SD: mount FAILED. Logging and offline queue DISABLED.");
    return;
  }
  if (SD.cardType() == CARD_NONE) {
    Serial.println("SD: no card. Logging and offline queue DISABLED.");
    return;
  }

  Serial.printf("SD: %luMB\n", (unsigned long)(SD.cardSize() / 1048576ULL));

  if (!SD.exists("/telemetry")) SD.mkdir("/telemetry");
  if (!SD.exists("/events"))    SD.mkdir("/events");
  if (!SD.exists("/system"))    SD.mkdir("/system");

  createCsv("/telemetry/gps.csv", "timestamp,lat,lng,speed_kmh,satellites,status");
  createCsv("/events/alerts.csv", "timestamp,type,message");
  createCsv("/system/status.csv", "timestamp,event,details");

  sdReady = true;

  rotateIfLarge("/telemetry/gps.csv", "/telemetry/gps.1.csv", GPS_LOG_MAX_BYTES);
  rotateIfLarge("/events/alerts.csv", "/events/alerts.1.csv", EVT_LOG_MAX_BYTES);
  rotateIfLarge("/system/status.csv", "/system/status.1.csv", EVT_LOG_MAX_BYTES);

  Serial.println("SD: ready");
}

// =========================================================
//  LOGGING
// =========================================================
void logGPSData(float lat, float lng, float speed, int sats, const char* status) {
  appendFile("/telemetry/gps.csv",
             stamp() + "," + String(lat, 6) + "," + String(lng, 6) + "," +
             String(speed, 2) + "," + String(sats) + "," + status + "\n");
}

void logEvent(const char* type, const String &message) {
  appendFile("/events/alerts.csv",
             stamp() + "," + esc(type) + "," + esc(message) + "\n");
}

void logSystemEvent(const char* type, const String &details) {
  appendFile("/system/status.csv",
             stamp() + "," + esc(type) + "," + esc(details) + "\n");
}

// =========================================================
//  OFFLINE ALERT QUEUE
// =========================================================
//  One JSON payload per line. Newlines inside a payload would corrupt the
//  format, so they are stripped on the way in.
// =========================================================

void queueAlertToSD(const String &json) {
  if (!sdReady) return;

  // Cap the file so a long outage cannot fill the card and take the
  // forensic trail down with it.
  File check = SD.open(QUEUE_PATH, FILE_READ);
  if (check) {
    size_t sz = check.size();
    check.close();
    if (sz > QUEUE_MAX_BYTES) {
      Serial.println("SD: alert queue full, dropping.");
      return;
    }
  }

  String line = json;
  line.replace("\r", " ");
  line.replace("\n", " ");
  line += "\n";
  appendFile(QUEUE_PATH, line);
}

bool hasPendingAlerts() {
  if (!sdReady || !SD.exists(QUEUE_PATH)) return false;
  File f = SD.open(QUEUE_PATH, FILE_READ);
  if (!f) return false;
  bool any = f.size() > 0;
  f.close();
  return any;
}

// Publish queued alerts through the supplied callback, which returns true on
// success. maxToSend limits work per call so a large backlog cannot stall
// the loop. Anything unsent is written back, so nothing is lost if the link
// drops halfway through a flush.
int flushPendingAlerts(bool (*publishFn)(const char*), int maxToSend) {
  if (!sdReady || !SD.exists(QUEUE_PATH)) return 0;

  File in = SD.open(QUEUE_PATH, FILE_READ);
  if (!in) return 0;

  String remaining = "";
  int sent = 0;
  bool linkDown = false;

  while (in.available()) {
    String line = in.readStringUntil('\n');
    line.trim();
    if (line.length() == 0) continue;

    if (linkDown || sent >= maxToSend) { remaining += line + "\n"; continue; }

    if (publishFn(line.c_str())) sent++;
    else { linkDown = true; remaining += line + "\n"; }
  }
  in.close();

  if (remaining.length() == 0) {
    SD.remove(QUEUE_PATH);
  } else {
    // Stage the rewrite in a TEMP file, then swap. The old code removed the
    // queue and only then reopened it for writing, so a power cut in that
    // window destroyed every pending alert -- and an SD.open() failure did
    // the same silently. Both are exactly the conditions this queue exists
    // to survive.
    const char* tmp = "/events/pending.tmp";
    if (SD.exists(tmp)) SD.remove(tmp);

    File out = SD.open(tmp, FILE_WRITE);
    if (!out) {
      // Could not stage it. Leave the original untouched: the alerts just
      // sent will be sent twice on the next flush, which is far better than
      // losing the ones that were not.
      Serial.println("SD: queue rewrite failed, leaving queue intact.");
      return sent;
    }
    size_t written = out.print(remaining);
    out.close();

    if (written != remaining.length()) {
      Serial.println("SD: queue write incomplete, leaving queue intact.");
      SD.remove(tmp);
      return sent;
    }

    SD.remove(QUEUE_PATH);
    SD.rename(tmp, QUEUE_PATH);
  }

  if (sent > 0) Serial.printf("SD: flushed %d pending alert(s)\n", sent);
  return sent;
}