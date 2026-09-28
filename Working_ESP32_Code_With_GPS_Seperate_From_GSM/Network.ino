// =========================================================
//  PathFinder Vehicle Tracker — Network
//  File 4 of 10:  Network.ino
// =========================================================
//  Owns the modem, the MQTT session, and the outbound SMS queue.
//
//  IMPORTANT: nothing outside this file may read SerialAT directly.
//  TinyGsm owns that stream and consumes bytes destructively, so a raw
//  read elsewhere would steal AT responses and break MQTT at random.
//
//  Nothing here may block. Measured round trip is ~220ms; a single
//  blocking call of half a second throws away the whole latency budget.
// =========================================================

#include "Config.h"

HardwareSerial SerialAT(1);
TinyGsm modem(SerialAT);
TinyGsmClient gsmClient(modem);
PubSubClient mqttClient(gsmClient);

static unsigned long lastMqttTry = 0, lastGprsTry = 0, lastNetCheck = 0;
static bool everConnected = false;

// ---- Outbound SMS queue ----
// modem.sendSMS() blocks for 3-10 seconds. Calling it from a crash or panic
// handler would freeze GPS parsing and telemetry for that whole window --
// exactly when it matters most. Callers queue and return immediately.
static const int SMS_QUEUE_SIZE = 5;
static String smsNum[SMS_QUEUE_SIZE], smsTxt[SMS_QUEUE_SIZE];
static int smsCount = 0, smsRetries = 0;
static unsigned long lastSmsSend = 0;
static const unsigned long SMS_MIN_INTERVAL_MS = 15000;

bool mqttIsConnected() { return mqttClient.connected(); }

// Single publish point, so every caller gets the same failure handling.
bool mqttPublishRaw(const char* topic, const char* payload, size_t len) {
  if (!mqttClient.connected()) return false;
  return mqttClient.publish(topic, (const uint8_t*)payload, len, false);
}

static bool publishQueuedAlert(const char* json) {
  if (!mqttClient.connected()) return false;
  return mqttClient.publish(TOPIC_ALERTS, json);
}

// =========================================================
//  SETUP
// =========================================================
void setupNetwork() {
  Serial.println("Modem: starting...");

  // deviceId must exist before anything publishes. Lowercase bare hex --
  // the backend compares this exactly, and a case mismatch silently
  // discards every command.
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char macStr[13];
  snprintf(macStr, sizeof(macStr), "%02x%02x%02x%02x%02x%02x",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  deviceId = String(macStr);
  Serial.printf("Device ID: %s\n", deviceId.c_str());

  // Seed from the MAC. An unseeded random() gives every unit the same
  // client-ID sequence, so two devices reconnecting together collide and
  // kick each other off the broker in a loop.
  randomSeed(((uint32_t)mac[2] << 24) | ((uint32_t)mac[3] << 16) |
             ((uint32_t)mac[4] << 8) | mac[5]);

  SerialAT.begin(MODEM_BAUD, SERIAL_8N1, MODEM_RX_PIN, MODEM_TX_PIN);
  SerialAT.setTimeout(50);   // no accidental read can stall the loop for a second
  delay(3000);               // acceptable in setup only; the modem needs to settle

  if (!modem.restart()) {
    Serial.println("Modem: no AT response. Check PWRKEY and the supply.");
  } else {
    Serial.printf("Modem: %s\n", modem.getModemInfo().c_str());

    // Accept 1 or 3: TinyGsm reports READY as either depending on version.
    int sim = (int)modem.getSimStatus();
    Serial.printf("SIM: %d %s\n", sim, (sim == 1 || sim == 3) ? "ready" : "NOT READY");

    if (modem.waitForNetwork(30000L)) {
      Serial.printf("Network: registered, signal %d\n", modem.getSignalQuality());
      if (modem.gprsConnect(APN, GPRS_USER, GPRS_PASS))
        Serial.printf("GPRS: attached, IP %s\n", modem.getLocalIP().c_str());
      else
        Serial.println("GPRS: failed, will retry in loop");
    } else {
      Serial.println("Network: not registered, will retry in loop");
    }
  }

  mqttClient.setServer(MQTT_HOST, MQTT_PORT);
  mqttClient.setCallback(handleCommand);

  // PubSubClient defaults to a 256-byte packet limit in many versions, and
  // a telemetry payload larger than that fails to publish SILENTLY.
  mqttClient.setBufferSize(1024);
  mqttClient.setKeepAlive(60);
}

// =========================================================
//  RECONNECT
// =========================================================
static void reconnectMQTT() {
  if (mqttClient.connected()) return;
  if (millis() - lastMqttTry < MQTT_RETRY_MS) return;
  lastMqttTry = millis();

  String clientId = "pf-" + deviceId + "-" + String(random(0xffff), HEX);

  // Last Will: retained, QoS 1, on the dedicated status topic. QoS 1 is
  // available here because the LWT is negotiated at connect time --
  // PubSubClient cannot publish at QoS 1 afterwards.
  String will = "{\"deviceId\":\"" + deviceId + "\",\"status\":\"offline\"}";

  Serial.print("MQTT: connecting... ");
  if (!mqttClient.connect(clientId.c_str(), TOPIC_STATUS, 1, true, will.c_str())) {
    Serial.printf("failed rc=%d\n", mqttClient.state());
    logSystemEvent("mqtt_error", "rc=" + String(mqttClient.state()));
    return;
  }
  Serial.println("connected");

  publishStatus("online");
  mqttClient.subscribe(TOPIC_COMMANDS);
  logSystemEvent("mqtt", "connected");

  // First connection of this boot: tell the backend what state the vehicle
  // came up in, so it can reconcile rather than assume.
  if (!everConnected) {
    everConnected = true;
    if (!engineLocked) {
      publishAlert("system", "Device rebooted. Engine unlocked state restored.",
                   currentDriverId);
    } else {
      publishAlert("system", "Device booted. Engine locked.");
    }
  }

  // Send a telemetry packet immediately rather than waiting up to 5s, so
  // the app populates the moment the device appears.
  publishTelemetryNow();
}

// =========================================================
//  LOOP
// =========================================================
void loopNetwork() {
  unsigned long now = millis();

  // Registration check, rate limited. The old build called
  // waitForNetwork(180000L) inline -- three minutes of blocking during which
  // the GPS buffer overflowed and nothing else ran.
  if (now - lastNetCheck > NETWORK_CHECK_MS) {
    lastNetCheck = now;
    if (!modem.isNetworkConnected()) return;
  }

  if (!modem.isGprsConnected()) {
    if (now - lastGprsTry > GPRS_RETRY_MS) {
      lastGprsTry = now;
      Serial.println("GPRS: reconnecting...");
      modem.gprsConnect(APN, GPRS_USER, GPRS_PASS);
    }
    return;
  }

  if (!mqttClient.connected()) { reconnectMQTT(); return; }

  mqttClient.loop();

  // Drain the persistent alert queue. Three per pass so a long backlog
  // cannot stall the loop, and only every 2s so a big flush cannot
  // monopolise the SD bus -- each call rewrites the remainder of the file.
  static unsigned long lastFlush = 0;
  if (now - lastFlush > 2000 && hasPendingAlerts()) {
    lastFlush = now;
    flushPendingAlerts(publishQueuedAlert, 3);
  }
}

// =========================================================
//  PUBLISHING
// =========================================================
void publishStatus(const char* status) {
  if (!mqttClient.connected()) return;
  String msg = "{\"deviceId\":\"" + deviceId + "\",\"status\":\"" + status + "\"}";
  mqttClient.publish(TOPIC_STATUS, msg.c_str(), true);   // retained
  Serial.printf("STATUS: %s\n", status);
}

void publishAlert(const char* type, const String &message) {
  publishAlert(type, message, -1);
}

void publishAlert(const char* type, const String &message, int driverId) {
  StaticJsonDocument<384> doc;
  doc["deviceId"] = deviceId;
  doc["type"] = type;
  doc["message"] = message;
  doc["driverId"] = driverId;

  // uptime is part of the backend's dedup key, so a queued alert replayed
  // later MUST carry the value it was generated with -- not the value at
  // the moment it is finally sent. Captured here, stored with the payload.
  doc["uptime"] = (millis() - bootMillis) / 1000;

  char buf[448];
  serializeJson(doc, buf, sizeof(buf));

  Serial.printf("ALERT: %s | %s\n", type, message.c_str());

  // Permanent record on the card regardless of link state.
  logEvent(type, message);

  // Try the wire; on failure the payload goes to the card, not to RAM.
  // A crash or a cut battery is exactly the event most likely to take the
  // link down AND reboot us, so anything held only in RAM would be lost.
  if (!mqttClient.connected() || !mqttClient.publish(TOPIC_ALERTS, buf)) {
    queueAlertToSD(String(buf));
  }
}

// =========================================================
//  SMS
// =========================================================
static void smsPopHead() {
  for (int i = 1; i < smsCount; i++) {
    smsNum[i - 1] = smsNum[i];
    smsTxt[i - 1] = smsTxt[i];
  }
  smsCount--;
  smsRetries = 0;
}

void sendSMS(const String &number, const String &text) {
  if (smsCount >= SMS_QUEUE_SIZE) {
    Serial.println("SMS: queue full, dropping oldest.");
    smsPopHead();
  }
  smsNum[smsCount] = number;
  smsTxt[smsCount] = text;
  smsCount++;
  Serial.printf("SMS: queued for %s (%d pending)\n", number.c_str(), smsCount);
}

static void drainSmsQueue() {
  if (smsCount == 0) return;
  if (millis() - lastSmsSend < SMS_MIN_INTERVAL_MS) return;
  lastSmsSend = millis();

  // This blocks. Unavoidable with TinyGsm, but it now happens at most once
  // every 15s and never inside a crash or panic handler.
  bool ok = modem.sendSMS(smsNum[0], smsTxt[0]);
  Serial.println(ok ? "SMS: sent" : "SMS: failed");

  if (ok) { smsPopHead(); return; }

  // Cap retries: a wrong number or a rejecting SMSC will never succeed, and
  // retrying forever means the head of the queue blocks everything behind
  // it -- including a later SOS.
  if (++smsRetries >= 5) {
    Serial.println("SMS: failed 5 times, dropping.");
    smsPopHead();
  }
}

void loopModem() {
  // The only thing that should touch SerialAT. Lets TinyGsm drain and
  // dispatch anything unsolicited sitting on the port.
  modem.maintain();
  drainSmsQueue();
}

// =========================================================
//  BACKUP BATTERY
// =========================================================
//  Nothing on the PCB senses the backup cell -- BATTERY_PIN is on the
//  vehicle divider. The A7670E's VBAT pin sits directly on the LiPo, so
//  AT+CBC is the only route to that reading.
//
//  Goes through TinyGsm's sendAT/waitResponse rather than touching SerialAT
//  directly, for the reason at the top of this file.
// =========================================================
int readBackupBatteryMv() {
  modem.sendAT(GF("+CBC"));
  if (modem.waitResponse(2000L, GF("+CBC:")) != 1) return -1;

  String line = modem.stream.readStringUntil('\n');
  modem.waitResponse(1000L);   // consume the trailing OK

  int comma = line.lastIndexOf(',');
  if (comma < 0) return -1;
  String field = line.substring(comma + 1);
  field.trim();
  if (field.length() == 0) return -1;

  float v = field.toFloat();
  if (v <= 0) return -1;
  if (v < 100) v *= 1000.0;   // some firmware reports volts, not millivolts
  return (int)v;
}