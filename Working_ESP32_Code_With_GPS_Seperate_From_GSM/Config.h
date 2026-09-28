// =========================================================
//  PathFinder Vehicle Tracker — Configuration
//  Config.h   (Phase 1)
// =========================================================
#ifndef CONFIG_H
#define CONFIG_H

#define TINY_GSM_MODEM_SIM7600

#include <Arduino.h>
#include <Wire.h>
#include <SPI.h>
#include <SD.h>
#include <math.h>
#include <Preferences.h>
#include <SoftwareSerial.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <TinyGPSPlus.h>
#include <TinyGsmClient.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_Fingerprint.h>
#include <esp_mac.h>
#include <esp_system.h>
#include <esp_sleep.h>
#include <driver/gpio.h>

// =========================================================
//  PIN MAP
// =========================================================
//  GPS pin order confirmed by test: the ESP32 RECEIVES on 13 and TRANSMITS
//  on 4. The old Hardware.h named these from the MODULE's perspective, so
//  passing them the other way round had the ESP32 listening to its own
//  output -- which is why neither unit ever got a fix.
const int GPS_RX_PIN  = 13;   // ESP32 RX  <- module TXD
const int GPS_TX_PIN  = 4;    // ESP32 TX  -> module RXD
const int GPS_BAUD    = 9600;

const int MODEM_RX_PIN = 16, MODEM_TX_PIN = 17;
const uint32_t MODEM_BAUD = 115200;

const int FINGERPRINT_RX = 33, FINGERPRINT_TX = 32;
const uint32_t FINGERPRINT_BAUD = 57600;

// ZW111 TOUCH_OUT, wired on this board revision. HIGH when a finger is
// present. Unused in Phase 1; becomes a deep-sleep wake source in Phase 2.
const int FINGER_TOUCH_PIN = 2;

// Relays. HIGH = coil energised. NEITHER is wired to vehicle accessories --
// both sit in the ignition and fuel circuits, so they always move together.
const int ACC_RELAY_PIN = 26, FUEL_PUMP_RELAY_PIN = 27;
const int RELAY_ON = HIGH, RELAY_OFF = LOW;

// Input-only pins. NO internal pull resistors exist on 34/35/36/39 --
// every level comes from an external component on the PCB.
const int PANIC_BUTTON_PIN = 39;   // external 10k pull-up, LOW = pressed
const int ACC_IGNITION_PIN = 34;   // PC817 + R8, LOW = ignition ON
const int BATTERY_PIN      = 35;   // 12V divider, presence sensing only
const int MPU_INT_PIN      = 36;   // no external pull fitted

const int TEMP_SENSOR_PIN = 25;
const int SD_CS_PIN = 5;           // MOSI 23, MISO 19, SCK 18

// Buzzer is ACTIVE-HIGH on this build.
const int ALARM_SIREN_PIN = 14;
const int SIREN_ON = HIGH, SIREN_OFF = LOW;

// NOTE: no external LEDs are fitted. Driver feedback comes from the ZW111's
// own backlight (blue idle / green accepted / red rejected) and the buzzer.

// =========================================================
//  NETWORK
// =========================================================
#define APN           "web.gprs.mtnnigeria.net"
#define GPRS_USER     ""
#define GPRS_PASS     ""
#define MQTT_HOST     "broker.hivemq.com"
#define MQTT_PORT     1883

#define TOPIC_TELEMETRY "pathfinder/telemetry"
#define TOPIC_STATUS    "pathfinder/status"
#define TOPIC_ALERTS    "pathfinder/alerts"
#define TOPIC_COMMANDS  "pathfinder/commands"

const unsigned long MQTT_RETRY_MS    = 5000;
const unsigned long GPRS_RETRY_MS    = 15000;
const unsigned long NETWORK_CHECK_MS = 10000;

// =========================================================
//  TIMING
// =========================================================
//  Telemetry publishes on this interval whenever the link is up, whether or
//  not there is a GPS fix. Measured MQTT round trip is ~220ms.
const unsigned long TELEMETRY_INTERVAL_MS = 5000;

//  SD trail cadence. Slower than the publish interval: a row every 15s is a
//  usable history without filling the card while parked.
const unsigned long SD_LOG_INTERVAL_MS = 15000;

const unsigned long ALERT_COOLDOWN_MS = 10000;   // per alert type

//  30 minutes with the vehicle locked and stationary before the device naps.
const unsigned long SLEEP_IDLE_MS = 1800000;

// =========================================================
//  AUTHORISATION WINDOWS
// =========================================================
//  After a valid fingerprint the relays energise and the driver has this
//  long to get the engine running. If it does not start, the relays drop
//  and a fresh scan is required -- an authorised vehicle left unattended
//  must not stay startable indefinitely.
const unsigned long START_WINDOW_MS = 60000;

//  When the engine stops, the relays stay energised this long so the driver
//  can restart without rescanning: a stall at a junction or a two-minute
//  stop at a shop should not demand a fresh finger. A remote lock cancels
//  this immediately.
const unsigned long RESTART_GRACE_MS = 120000;

// =========================================================
//  GPS
// =========================================================
//  isValid() stays true forever once a fix has been seen, so age() is the
//  only thing separating "where the vehicle IS" from "where it WAS".
const unsigned long GPS_FIX_MAX_AGE_MS = 5000;

//  10 km/h, not 0. A stationary receiver reports 0.1-1.5 km/h of jitter
//  continuously, which previously made the vehicle look permanently moving
//  and generated hundreds of one-second trips in the backend.
const float MOVING_THRESHOLD_KMPH = 10.0;

//  Remote lock is refused above this speed.
const float REMOTE_LOCK_MAX_KMPH = 20.0;

// =========================================================
//  MAIN POWER DETECTION
// =========================================================
//  Presence only -- no voltage or percentage is reported, so no per-board
//  calibration is needed. A threshold is still required because a
//  disconnected feed leaves the divider FLOATING rather than at zero, and a
//  floating ESP32 input drifts a few hundred millivolts. This is the
//  voltage AT THE PIN corresponding to roughly 6V at the battery.
const float MAIN_POWER_PIN_THRESHOLD_V = 0.56;

// =========================================================
//  ACCELEROMETER
// =========================================================
const float G_MS2 = 9.80665;
const float CRASH_THRESHOLD_MS2 = 3.5 * G_MS2;
const float THEFT_THRESHOLD_MS2 = 0.5 * G_MS2;
const int   CRASH_CONFIRM_SAMPLES = 2;
const int   THEFT_CONFIRM_SAMPLES = 3;

// =========================================================
//  TEMPERATURE
// =========================================================
const uint8_t TEMP_RESOLUTION_BITS = 10;   // ~187ms conversion, not 750ms
const unsigned long TEMP_READ_INTERVAL_MS = 10000;
const unsigned long TEMP_CONVERSION_MS = 250;
const float OVERHEAT_C = 105.0, OVERHEAT_CLEAR_C = 95.0;
const float TEMP_MIN_VALID_C = -55.0;

// =========================================================
//  SOS  (emergency only -- single function)
// =========================================================
//  300ms: testing showed 11 of 13 deliberate presses were discarded at a 2s
//  threshold, which is unacceptable for an emergency control. 300ms still
//  rejects a knock or a brush against the button.
const unsigned long PANIC_HOLD_MS = 300;
const unsigned long PANIC_DEBOUNCE_MS = 50;

//  The MQTT alert fires on EVERY press -- it costs nothing, and a driver
//  pressing repeatedly must not be met with silence. Only the SMS is rate
//  limited, because that costs credit and blocks the modem for seconds.
const unsigned long PANIC_SMS_COOLDOWN_MS = 10000;

#define DEFAULT_EMERGENCY_CONTACT "+2348069971549"

// =========================================================
//  FINGERPRINT
// =========================================================
const unsigned long FINGER_SCAN_INTERVAL_MS = 500;
const unsigned long STRIKE_RESET_MS = 300000;   // 5 min of calm clears strikes
const int STRIKE_ALARM_THRESHOLD = 5;

//  Template slots. The Hi-Link datasheet states 40, NOT the 127 the old
//  firmware accepted -- slots above the real limit fail at storeModel()
//  with a confusing error. setupFingerprint() prints the module's OWN
//  reported capacity at boot; if it differs, trust that and change this.
const int FINGERPRINT_CAPACITY = 40;

//  Backlight: blue while waiting, green for 2s on a match then OFF, red
//  plus a short beep on a reject then back to blue. Driven by PS_ControlBLN
//  (instruction 0x3C), verified on hardware.
const unsigned long FINGER_LED_SUCCESS_MS = 2000;
const unsigned long FINGER_LED_FAIL_MS = 800;

// =========================================================
//  SD CARD
// =========================================================
//  NOT named PENDING: the ESP32 core defines that as an enum in ets_sys.h.
#define QUEUE_PATH "/events/pending.csv"
const size_t QUEUE_MAX_BYTES   = 32768;
const size_t GPS_LOG_MAX_BYTES = 5242880UL;
const size_t EVT_LOG_MAX_BYTES = 1048576UL;

// =========================================================
//  SHARED STATE  (defined in PathFinder.ino)
// =========================================================
extern String deviceId;
extern TinyGPSPlus gps;
extern bool engineLocked;     // both relays de-energised, vehicle immobilised
extern bool authBypass;       // owner override, restored from NVS at boot
extern int  currentDriverId;
extern bool sirenLatched;
extern bool sirenMuted;
extern bool manualAlarm;
extern unsigned long bootMillis;

// =========================================================
//  CROSS-TAB FUNCTION DECLARATIONS
// =========================================================
// Main
void engineUnlock(int driverId, const char* reason);
void engineLock(const char* reason);
bool ignitionIsOn();
void raiseAlarm(const char* type, const String &message);
void clearAlarm();
void loopSleep();

// Telemetry
void loopTelemetry();
void publishTelemetryNow();

// Network
void setupNetwork();
void loopNetwork();
void loopModem();
bool mqttPublishRaw(const char* topic, const char* payload, size_t len);
void publishAlert(const char* type, const String &message);
void publishAlert(const char* type, const String &message, int driverId);
void publishStatus(const char* status);
bool mqttIsConnected();
void sendSMS(const String &number, const String &text);
int  readBackupBatteryMv();

// Commands
void handleCommand(char* topic, byte* payload, unsigned int len);

// Main power
void setupBattery();
void loopBattery();
bool mainPowerPresent();
bool batteryPowerCut();
void checkPowerCut();

// GPS
void setupGPS();
void loopGPS();
bool  gpsHasFreshFix();
bool  gpsIsMoving();
float gpsSpeedKmph();
float gpsLat();
float gpsLng();
int   gpsSatellites();
unsigned long gpsFixAgeSeconds();
bool  gpsEverHadFix();
float gpsLastLat();
float gpsLastLng();
void  checkGpsFixLoss();
void  gpsPrintStatus();

// Fingerprint & authorisation
void setupFingerprint();
void loopFingerprint();
void triggerEnrollment(int id);
void triggerDeleteFingerprint(int id);
void setDriverStatus(int id, bool isActive);
void setAuthBypass(bool state);
bool fingerprintSensorOk();
void savePersistentState();
const char* authStateName();
void cancelGraceForRemoteLock();
void fingerLedIdle();
void fingerLedSuccess();
void fingerLedFail();
void fingerLedOff();

// Alarm
void setupAlarm();
void loopAlarm();
void beep(int times, int durationMs);
void setSirenMuted(bool muted);
void setManualAlarm(bool on);

// Sensors
void setupSensors();
void loopSensors();
float vehicleTemperature();
bool  temperatureValid();
bool  accelerometerOk();
void  setEmergencyContact(const String &number);

// SD logger
void setupSDCard();
void logGPSData(float lat, float lng, float speed, int sats, const char* status);
void logEvent(const char* type, const String &message);
void logSystemEvent(const char* type, const String &details);
void queueAlertToSD(const String &json);
bool hasPendingAlerts();
int  flushPendingAlerts(bool (*fn)(const char*), int maxToSend);

#endif