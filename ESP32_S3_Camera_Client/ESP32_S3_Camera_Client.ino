#include "esp_camera.h"

// =========================================================
// ESP32-S3 WROOM CAM PINOUT (Freenove / Generic S3 N16R8)
// =========================================================
#define PWDN_GPIO_NUM  -1
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM  15
#define SIOD_GPIO_NUM  4
#define SIOC_GPIO_NUM  5
#define Y9_GPIO_NUM    16
#define Y8_GPIO_NUM    17
#define Y7_GPIO_NUM    18
#define Y6_GPIO_NUM    12
#define Y5_GPIO_NUM    10
#define Y4_GPIO_NUM    8
#define Y3_GPIO_NUM    9
#define Y2_GPIO_NUM    11
#define VSYNC_GPIO_NUM 6
#define HREF_GPIO_NUM  7
#define PCLK_GPIO_NUM  13

void setup() {
  Serial.begin(115200);
  
  // Wait up to 5 seconds for the Native USB to connect to Windows
  unsigned long startWait = millis();
  while (!Serial && millis() - startWait < 5000) {
    delay(10);
  }
  
  Serial.println("\n\n=================================");
  Serial.println("--- ESP32-S3 Camera Hardware Test ---");
  Serial.println("=================================");
  delay(1000);

  Serial.println("1. Setting up camera configuration...");
  delay(1000);

  // 1. Configure the Camera
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sccb_sda = SIOD_GPIO_NUM;
  config.pin_sccb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  
  // Use internal RAM (DRAM) instead of PSRAM to completely bypass any PSRAM errors!
  config.xclk_freq_hz = 10000000; 
  config.frame_size = FRAMESIZE_QVGA; // 320x240 fits easily in internal RAM
  config.pixel_format = PIXFORMAT_JPEG; 
  config.grab_mode = CAMERA_GRAB_WHEN_EMPTY;
  config.fb_location = CAMERA_FB_IN_DRAM; // <--- This is the key change!
  config.jpeg_quality = 12;
  config.fb_count = 1;

  Serial.println("2. Calling esp_camera_init()...");
  Serial.println("(If the serial monitor freezes exactly here, your PSRAM settings in Arduino IDE are wrong and the chip crashed!)");
  delay(1000);

  // 2. Initialize the Camera
  esp_err_t err = esp_camera_init(&config);
  
  if (err != ESP_OK) {
    Serial.printf("CRITICAL FAIL: Camera init failed with error 0x%x\n", err);
    Serial.println("Check if you selected the right PSRAM settings in Arduino IDE!");
    return;
  }
  
  Serial.println("SUCCESS: Camera initialized perfectly!");
  Serial.println("-------------------------------------");
}

void loop() {
  Serial.println("Attempting to capture a frame...");
  
  // 3. Take a picture
  camera_fb_t * fb = esp_camera_fb_get();  
  
  if (!fb) {
    Serial.println("FAIL: Camera capture failed!");
  } else {
    Serial.println("PASS: Picture taken successfully!");
    Serial.printf("      Image Size: %zu bytes\n", fb->len);
    Serial.printf("      Resolution: %d x %d\n", fb->width, fb->height);
    
    // Return the frame buffer back to the driver
    esp_camera_fb_return(fb); 
  }

  Serial.println("-------------------------------------");
  
  // Wait 5 seconds before capturing again
  delay(5000);
}
