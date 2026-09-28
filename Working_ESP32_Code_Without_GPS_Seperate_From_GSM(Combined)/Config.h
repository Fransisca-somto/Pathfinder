// =========================================================
//  PathFinder Vehicle Tracker — Configuration
//  Config.h   (A7670E build, Phase 1)
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
//  NO separate GPS module on this board. Position comes from the A7670E's
//  built-in GNSS over AT commands on the modem UART. Confirmed on firmware
//  A131B03A7670M6C_M: AT+CGNSSPWR and AT+CGNSSINFO answer OK; the CGPS*
//  family returns ERROR. GPS_RX_PIN / GPS_TX_PIN are deliberately absent --
//  nothing is wired there, and defining them invites someone to open a
//  second UART with no module on the other end.

const int MODEM_RX_PIN = 16, MODEM_TX_PIN = 17;
const uint32_t MODEM_BAUD = 115200;

const int FINGERPRINT_RX = 33, FINGERPRINT_TX = 32;
const uint32_t FINGERPRINT_BAUD = 57600;

// ZW111 TOUCH_OUT. HIGH when a finger is present. Phase 2 wake source.
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
const unsigned long TELEMETRY_INTERVAL_MS = 5000;
const unsigned long SD_LOG_INTERVAL_MS = 15000;
const unsigned long ALERT_COOLDOWN_MS = 10000;
const unsigned long SLEEP_IDLE_MS = 1800000;   // 30 min

// =========================================================
//  AUTHORISATION WINDOWS
// =========================================================
const unsigned long START_WINDOW_MS = 60000;    // time to start the engine
const unsigned long RESTART_GRACE_MS = 120000;  // restart without rescanning

// =========================================================
//  GNSS  (A7670E built-in, AT commands)
// =========================================================
//  Poll cadence. Each AT+CGNSSINFO costs 89-97ms measured on this board,
//  and shares the UART with MQTT -- so poll faster than the telemetry
//  interval but not so fast that the AT queue is crowded.
const unsigned long GNSS_POLL_MS = 2000;

//  8s rather than 5s: the receiver is polled every 2s, so a single missed
//  response must not immediately invalidate an otherwise good position.
const unsigned long GPS_FIX_MAX_AGE_MS = 8000;

//  Cold start measured at 176s on this board; a warm restart fixes on the
//  first poll. Used only for the diagnostic message.
const unsigned long GNSS_COLD_START_MS = 200000;

//  10 km/h, not 0. A stationary receiver reports a few tenths of a knot of
//  jitter continuously, which would mark the vehicle permanently moving.
const float MOVING_THRESHOLD_KMPH = 10.0;

//  Remote lock is refused above this speed.
const float REMOTE_LOCK_MAX_KMPH = 20.0;

// =========================================================
//  MAIN POWER DETECTION
// =========================================================
//  Presence only -- no voltage or percentage, so no per-board calibration.
//  A threshold is still needed because a disconnected feed leaves the
//  divider FLOATING rather than at zero. This is the voltage AT THE PIN
//  corresponding to roughly 6V at the battery.
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
const uint8_t TEMP_RESOLUTION_BITS = 10;
const unsigned long TEMP_READ_INTERVAL_MS = 10000;
const unsigned long TEMP_CONVERSION_MS = 250;
const float OVERHEAT_C = 105.0, OVERHEAT_CLEAR_C = 95.0;
const float TEMP_MIN_VALID_C = -55.0;

// =========================================================
//  SOS  (emergency only)
// =========================================================
const unsigned long PANIC_HOLD_MS = 300;
const unsigned long PANIC_DEBOUNCE_MS = 50;
const unsigned long PANIC_SMS_COOLDOWN_MS = 10000;
#define DEFAULT_EMERGENCY_CONTACT "+2348069971549"

// =========================================================
//  FINGERPRINT
// =========================================================
const unsigned long FINGER_SCAN_INTERVAL_MS = 500;
const unsigned long STRIKE_RESET_MS = 300000;
const int STRIKE_ALARM_THRESHOLD = 5;

//  Hi-Link datasheet states 40 slots, NOT 127. setupFingerprint() prints
//  the module's own reported capacity at boot; trust that if it differs.
const int FINGERPRINT_CAPACITY = 40;

//  Backlight via PS_ControlBLN (instruction 0x3C), verified on hardware.
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
extern bool engineLocked;
extern bool authBypass;
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

// GNSS
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