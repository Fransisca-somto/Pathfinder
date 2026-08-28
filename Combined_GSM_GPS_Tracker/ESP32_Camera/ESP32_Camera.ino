#include "esp_camera.h"
#include <WiFi.h>
#include <HTTPClient.h>
#include <driver/i2s.h>

// ==========================================
// Audio Pin Configuration (INMP441 I2S Mic)
// ==========================================
#define I2S_WS 42
#define I2S_SD 2
#define I2S_SCK 41
#define I2S_PORT I2S_NUM_0

// ==========================================
// Network Configuration
// ==========================================
// These must match the SoftAP credentials set in the Main Tracker
const char* ssid = "Pathfinder_Internal";
const char* password = "SecurePass123";
const char* serverUrl = "http://192.168.4.1/upload";

// ==========================================
// Camera Pin Configuration (ESP32-S3 OV5640)
// ==========================================
#define PWDN_GPIO_NUM     -1
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM     10
#define SIOD_GPIO_NUM     40
#define SIOC_GPIO_NUM     39

#define Y9_GPIO_NUM       48
#define Y8_GPIO_NUM       11
#define Y7_GPIO_NUM       12
#define Y6_GPIO_NUM       14
#define Y5_GPIO_NUM       16
#define Y4_GPIO_NUM       18
#define Y3_GPIO_NUM       17
#define Y2_GPIO_NUM       15
#define VSYNC_GPIO_NUM    38
#define HREF_GPIO_NUM     47
#define PCLK_GPIO_NUM     13

void setupCamera() {
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
  config.xclk_freq_hz = 20000000;
  
  // Use JPEG format for compression
  config.pixel_format = PIXFORMAT_JPEG;
  
  // High specs for S3 N16R8 (PSRAM available)
  if(psramFound()){
    config.frame_size = FRAMESIZE_UXGA; // 1600x1200
    config.jpeg_quality = 10;           // Lower means higher quality (0-63)
    config.fb_count = 2;
  } else {
    config.frame_size = FRAMESIZE_SVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x\n", err);
    return;
  }
  Serial.println("Camera initialized successfully.");
}

// Generates a standard WAV header
void generateWavHeader(uint8_t* header, uint32_t wavSize, uint32_t sampleRate, uint16_t channels, uint16_t bitDepth) {
  uint32_t byteRate = sampleRate * channels * (bitDepth / 8);
  uint16_t blockAlign = channels * (bitDepth / 8);

  header[0] = 'R'; header[1] = 'I'; header[2] = 'F'; header[3] = 'F';
  uint32_t chunkSize = wavSize + 36;
  memcpy(header + 4, &chunkSize, 4);
  header[8] = 'W'; header[9] = 'A'; header[10] = 'V'; header[11] = 'E';
  header[12] = 'f'; header[13] = 'm'; header[14] = 't'; header[15] = ' ';
  uint32_t subchunk1Size = 16;
  memcpy(header + 16, &subchunk1Size, 4);
  uint16_t audioFormat = 1;
  memcpy(header + 20, &audioFormat, 2);
  memcpy(header + 22, &channels, 2);
  memcpy(header + 24, &sampleRate, 4);
  memcpy(header + 28, &byteRate, 4);
  memcpy(header + 32, &blockAlign, 2);
  memcpy(header + 34, &bitDepth, 2);
  header[36] = 'd'; header[37] = 'a'; header[38] = 't'; header[39] = 'a';
  memcpy(header + 40, &wavSize, 4);
}

void setupAudio() {
  i2s_config_t i2s_config = {
    .mode = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate = 16000,
    .bits_per_sample = I2S_BITS_PER_SAMPLE_16BIT,
    .channel_format = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = i2s_comm_format_t(I2S_COMM_FORMAT_STAND_I2S),
    .intr_alloc_flags = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count = 8,
    .dma_buf_len = 1024,
    .use_apll = false,
    .tx_desc_auto_clear = false,
    .fixed_mclk = 0
  };

  i2s_pin_config_t pin_config = {
    .bck_io_num = I2S_SCK,
    .ws_io_num = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num = I2S_SD
  };

  i2s_driver_install(I2S_PORT, &i2s_config, 0, NULL);
  i2s_set_pin(I2S_PORT, &pin_config);
  Serial.println("I2S Audio initialized.");
}

void recordAndSendAudio() {
  const int duration_seconds = 5;
  const int sample_rate = 16000;
  const int bytes_per_sample = 2; // 16-bit
  const int wav_data_size = duration_seconds * sample_rate * bytes_per_sample;
  const int total_buffer_size = 44 + wav_data_size; // 44 byte header

  Serial.println("Allocating PSRAM for Audio recording...");
  uint8_t* audioBuffer = (uint8_t*)ps_malloc(total_buffer_size);
  
  if(audioBuffer == NULL) {
    Serial.println("Failed to allocate PSRAM for audio");
    return;
  }

  // Generate WAV header
  generateWavHeader(audioBuffer, wav_data_size, sample_rate, 1, 16);

  Serial.println("Recording audio for 5 seconds...");
  size_t bytesRead = 0;
  size_t totalRead = 0;
  uint8_t* pData = audioBuffer + 44; // Start writing after the 44 byte header

  while(totalRead < wav_data_size) {
    size_t toRead = wav_data_size - totalRead;
    if(toRead > 1024) toRead = 1024;
    i2s_read(I2S_PORT, (void*)pData, toRead, &bytesRead, portMAX_DELAY);
    pData += bytesRead;
    totalRead += bytesRead;
  }
  Serial.println("Audio recording complete.");

  if(WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(serverUrl);
    http.addHeader("Content-Type", "audio/wav");
    http.addHeader("X-File-Name", "alert.wav");

    Serial.println("Uploading audio to Main Tracker...");
    int httpResponseCode = http.POST(audioBuffer, total_buffer_size);
    
    if (httpResponseCode > 0) {
      Serial.printf("HTTP Response code: %d\n", httpResponseCode);
    } else {
      Serial.printf("Upload failed, error code: %d\n", httpResponseCode);
    }
    http.end();
  }

  free(audioBuffer);
}

void setup() {
  Serial.begin(115200);
  Serial.println("Initializing ESP32-S3 Camera Module...");

  setupCamera();
  setupAudio();

  // Connect to the Main Tracker's Wi-Fi Hotspot
  Serial.print("Connecting to Wi-Fi SoftAP: ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);
  
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nConnected to Tracker Wi-Fi!");
  Serial.print("Camera IP Address: ");
  Serial.println(WiFi.localIP());
}

void captureAndSend() {
  camera_fb_t * fb = esp_camera_fb_get();  
  if(!fb) {
    Serial.println("Camera capture failed");
    return;
  }
  Serial.printf("Picture taken! Size: %zu bytes\n", fb->len);

  if(WiFi.status() == WL_CONNECTED) {
    HTTPClient http;
    http.begin(serverUrl);
    http.addHeader("Content-Type", "image/jpeg");
    
    // We send the filename as a custom header so the Main Tracker knows how to save it
    http.addHeader("X-File-Name", "alert.jpg");

    Serial.println("Uploading image to Main Tracker...");
    int httpResponseCode = http.POST(fb->buf, fb->len);
    
    if (httpResponseCode > 0) {
      Serial.print("HTTP Response code: ");
      Serial.println(httpResponseCode);
    } else {
      Serial.print("Upload failed, error code: ");
      Serial.println(httpResponseCode);
    }
    http.end();
  } else {
    Serial.println("Error: Not connected to Wi-Fi");
  }
  
  // Return the frame buffer back to the driver for reuse
  esp_camera_fb_return(fb); 
}

void loop() {
  // --- TEST MODE ---
  // Take a picture and send it to the tracker every 15 seconds.
  // Once we verify the connection works, we will change this to be triggered
  // by the Main Tracker sending a command.
  
  captureAndSend();
  delay(2000); // short delay between image and audio
  recordAndSendAudio();
  delay(15000);
}
