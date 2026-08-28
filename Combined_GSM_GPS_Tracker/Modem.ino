#include "Hardware.h"

#define TINY_GSM_MODEM_SIM7600
#include <TinyGsmClient.h>

extern TinyGsm modem;
extern HardwareSerial SerialAT;

void sendSMS(String phoneNumber, String text) {
  Serial.print("Sending SMS to ");
  Serial.print(phoneNumber);
  Serial.println("...");
  
  if (modem.sendSMS(phoneNumber, text)) {
    Serial.println("SMS sent successfully!");
  } else {
    Serial.println("SMS failed to send.");
  }
}

void makePhoneCall(String phoneNumber) {
  Serial.print("Calling ");
  Serial.println(phoneNumber);
  
  if (modem.callNumber(phoneNumber)) {
    Serial.println("Call initiated.");
  } else {
    Serial.println("Call failed.");
  }
}

void answerCall() {
  Serial.println("Answering incoming call...");
  modem.callAnswer();
}

void hangupCall() {
  Serial.println("Hanging up call...");
  modem.callHangup();
}

// Basic function to check if the modem receives a "RING"
void loopModem() {
  if (SerialAT.available()) {
    String response = SerialAT.readStringUntil('\n');
    response.trim();
    if (response.length() > 0) {
      if (response == "RING") {
        Serial.println("Incoming call detected!");
        // We can automatically answer for Live Audio (Stage 6) later,
        // or just send an alert.
      } else if (response.startsWith("+CMTI:")) {
        Serial.println("New SMS received!");
        // SMS reading logic goes here if needed.
      }
    }
  }
}
