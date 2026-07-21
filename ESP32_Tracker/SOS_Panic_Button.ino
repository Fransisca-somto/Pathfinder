// Match Sw1 / SENSOR_VN on schematic
#include "Hardware.h"

// Variables for debounce logic
int buttonState;             
int lastButtonState = HIGH;   
unsigned long lastDebounceTime = 0;  
unsigned long debounceDelay = 50;    

extern String deviceId;
extern void publishAlert(String type, String message);
extern void logEvent(String type, String message);

void setupSOS() {
  Serial.println("Initializing SOS Panic Button...");
  // The schematic has an external 10K pull-up resistor for Pin 39.
  // The pin will read HIGH normally, and LOW when the button is pressed.
  pinMode(PANIC_BUTTON_PIN, INPUT);
}

void loopSOS() {
  int reading = digitalRead(PANIC_BUTTON_PIN);

  // If the switch changed, due to noise or pressing
  if (reading != lastButtonState) {
    lastDebounceTime = millis();
  }

  if ((millis() - lastDebounceTime) > debounceDelay) {
    // if the button state has changed:
    if (reading != buttonState) {
      buttonState = reading;

      // Only trigger the alert if the new button state is LOW (pressed)
      if (buttonState == LOW) {
        Serial.println("🚨 PANIC BUTTON PRESSED!");
        
        // 1. Log to SD Card permanently
        logEvent("panic", "Emergency SOS Triggered! Driver needs immediate assistance.");
        
        // 2. Publish to cloud
        publishAlert("panic", "Emergency SOS Triggered! Driver needs immediate assistance.");
      }
    }
  }

  lastButtonState = reading;
}
