#include <WiFi.h>
#include <WebServer.h>
#include <SD.h>

WebServer cameraServer(80);

// We will use this flag in Phase 3 to trigger the modem upload
String pendingFileUpload = "";

void handleUpload() {
  HTTPUpload& upload = cameraServer.upload();
  static File uploadFile;

  if (upload.status == UPLOAD_FILE_START) {
    String filename = upload.filename;
    if (!filename.startsWith("/")) filename = "/" + filename;
    Serial.print("[Camera Server] Receiving file: ");
    Serial.println(filename);

    if (SD.exists(filename)) {
      SD.remove(filename);
    }
    uploadFile = SD.open(filename, FILE_WRITE);
    if (!uploadFile) {
      Serial.println("[Camera Server] Failed to open file for writing on SD card.");
    }
  } else if (upload.status == UPLOAD_FILE_WRITE) {
    if (uploadFile) {
      uploadFile.write(upload.buf, upload.currentSize);
    }
  } else if (upload.status == UPLOAD_FILE_END) {
    if (uploadFile) {
      uploadFile.close();
      Serial.print("[Camera Server] File saved successfully. Size: ");
      Serial.print(upload.totalSize);
      Serial.println(" bytes.");
      
      // Send response to the ESP32-S3 camera that upload succeeded
      cameraServer.send(200, "text/plain", "Upload success");
      
      // Store the filename to trigger a cellular upload later (Phase 3)
      pendingFileUpload = upload.filename;
    } else {
      cameraServer.send(500, "text/plain", "Failed to save file");
    }
  }
}

void setupCameraServer() {
  Serial.println("[Camera Server] Starting Wi-Fi SoftAP...");
  
  // Set up the Wi-Fi Access Point
  // SSID: Pathfinder_Internal, Password: SecurePass123
  WiFi.softAP("Pathfinder_Internal", "SecurePass123");
  
  IPAddress IP = WiFi.softAPIP();
  Serial.print("[Camera Server] AP IP address: ");
  Serial.println(IP);

  // Setup the HTTP POST endpoint for file uploads
  cameraServer.on("/upload", HTTP_POST, []() {
    // This empty handler is called after handleUpload is finished if handleUpload didn't already send a response
    cameraServer.send(200, "text/plain", "OK");
  }, handleUpload);

  cameraServer.begin();
  Serial.println("[Camera Server] HTTP Server started listening on /upload");
}

void loopCameraServer() {
  cameraServer.handleClient();
}
