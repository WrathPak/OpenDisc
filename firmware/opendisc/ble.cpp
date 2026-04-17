#include "ble.h"
#include <NimBLEDevice.h>
#include "sensors.h"
#include "analyzer.h"

#define NUS_SERVICE_UUID        "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX_UUID             "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_TX_UUID             "6e400003-b5a3-f393-e0a9-e50e24dcca9e"

// External state from disc_golf_imu.ino
extern const char* stateNames[];
extern int state;  // enum State underlying type is int
extern float liveRpmGyro, liveRpmAccel, liveAccelG, liveHgG;
extern float liveHyzer, liveNose;
extern bool liveClipped;
extern float calRadius, calRx, calRy;
extern uint16_t calCount;
extern float calRpmMin, calRpmMax;
extern bool autoArm;
extern float triggerG;
extern bool hasLastThrow;
extern ThrowMetrics lastMetrics;

// Functions from disc_golf_imu.ino
extern void handleCalStart();
extern void handleCalStop();
extern void saveSettings();
extern void loadSettings();

// Forward declarations for functions we'll call
void bleHandleCommand(const char* json);
void bleSendJson(const char* json);

// Debug log ring buffer
char debugLog[DEBUG_LOG_SIZE][DEBUG_MSG_LEN];
uint8_t debugLogHead = 0;
uint8_t debugLogCount = 0;

void debugMsg(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vsnprintf(debugLog[debugLogHead], DEBUG_MSG_LEN, fmt, args);
  va_end(args);
  Serial.printf("[DBG] %s\n", debugLog[debugLogHead]);
  debugLogHead = (debugLogHead + 1) % DEBUG_LOG_SIZE;
  if (debugLogCount < DEBUG_LOG_SIZE) debugLogCount++;
}

static NimBLEServer* pServer = nullptr;
static NimBLECharacteristic* pTxChar = nullptr;
static NimBLECharacteristic* pRxChar = nullptr;
static bool deviceConnected = false;
static bool liveStreaming = false;
static unsigned long lastStreamMs = 0;
static unsigned long lastCalPushMs = 0;
static uint8_t prevState = 255;

// WiFi power management
static bool wifiDisabledByBle = false;
static unsigned long bleDisconnectMs = 0;
#define WIFI_RESTORE_TIMEOUT_MS  300000  // 5 minutes

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pSvr, NimBLEConnInfo& connInfo) override {
    deviceConnected = true;
    pSvr->updateConnParams(connInfo.getConnHandle(), 12, 24, 0, 200);
    debugMsg("BLE client connected");
  }
  void onDisconnect(NimBLEServer* pSvr, NimBLEConnInfo& connInfo, int reason) override {
    deviceConnected = false;
    liveStreaming = false;
    if (wifiDisabledByBle) bleDisconnectMs = millis();
    debugMsg("BLE client disconnected (reason %d)", reason);
    NimBLEDevice::startAdvertising();
  }
  void onMTUChange(uint16_t mtu, NimBLEConnInfo& connInfo) override {
    Serial.printf("[BLE] MTU changed to %d\n", mtu);
  }
};

class RxCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* pChar, NimBLEConnInfo& connInfo) override {
    std::string val = pChar->getValue();
    debugMsg("BLE RX %d bytes: %.80s", val.length(), val.c_str());
    if (val.length() > 0) {
      bleHandleCommand(val.c_str());
    }
  }
};

void initBLE() {
  NimBLEDevice::init("OpenDisc");
  NimBLEDevice::setMTU(256);

  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // NUS Service
  NimBLEService* pNus = pServer->createService(NUS_SERVICE_UUID);

  pTxChar = pNus->createCharacteristic(
    NUS_TX_UUID,
    NIMBLE_PROPERTY::NOTIFY
  );

  pRxChar = pNus->createCharacteristic(
    NUS_RX_UUID,
    NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
  );
  pRxChar->setCallbacks(new RxCallbacks());

  pNus->start();

  // Device Info Service
  NimBLEService* pDis = pServer->createService("180A");
  pDis->createCharacteristic("2A24", NIMBLE_PROPERTY::READ)->setValue("OpenDisc");
  pDis->createCharacteristic("2A26", NIMBLE_PROPERTY::READ)->setValue("1.0.1");
  pDis->createCharacteristic("2A29", NIMBLE_PROPERTY::READ)->setValue("OpenDisc");
  pDis->start();

  // Advertising
  NimBLEAdvertising* pAdv = NimBLEDevice::getAdvertising();
  pAdv->addServiceUUID(NUS_SERVICE_UUID);
  pAdv->setName("OpenDisc");
  pAdv->enableScanResponse(true);
  pAdv->start();

  Serial.println("[BLE] Advertising as OpenDisc");
}

// Send a notification with the data passed in directly. Avoids the
// setValue() + notify() race where rapid successive setValue calls overwrite
// the stored characteristic value before the BLE task has transmitted the
// previous notification. NimBLE's notify(value, length) overload copies the
// payload into its own mbuf, so each call is independent.
void bleSendJson(const char* json) {
  if (!deviceConnected || !pTxChar) return;
  size_t len = strlen(json);
  pTxChar->notify((const uint8_t*)json, len);
  debugMsg("BLE TX %d bytes", len);
}

// Binary TX on the same characteristic. Client distinguishes binary vs JSON
// by the leading byte (0xFF = binary, 0x7B = JSON '{').
void bleSendBinary(const uint8_t* data, size_t len) {
  if (!deviceConnected || !pTxChar) return;
  pTxChar->notify(data, len);
}

bool bleClientConnected() {
  return deviceConnected;
}

bool bleWifiShouldBeOn() {
  if (!wifiDisabledByBle) return true;
  if (deviceConnected) return false;  // BLE still managing, stay off
  // Auto-restore after timeout
  if (millis() - bleDisconnectMs > WIFI_RESTORE_TIMEOUT_MS) {
    wifiDisabledByBle = false;
    debugMsg("WiFi auto-restored after timeout");
    return true;
  }
  return false;
}

void blePushState(const char* stateName) {
  char buf[64];
  snprintf(buf, sizeof(buf), "{\"type\":\"state\",\"state\":\"%s\"}", stateName);
  bleSendJson(buf);
}

void blePushThrowReady() {
  bleSendJson("{\"type\":\"throw_ready\"}");
}

void bleTick() {
  if (!deviceConnected) return;

  unsigned long now = millis();

  // Push state changes
  if (state != prevState) {
    prevState = state;
    blePushState(stateNames[state]);
  }

  // Live stream at 10 Hz
  if (liveStreaming && (now - lastStreamMs >= 100)) {
    lastStreamMs = now;
    char buf[300];
    snprintf(buf, sizeof(buf),
      "{\"type\":\"live\",\"rpm_gyro\":%.1f,\"rpm_accel\":%.1f,"
      "\"accel_g\":%.2f,\"hg_g\":%.1f,"
      "\"hyzer\":%.1f,\"nose\":%.1f,"
      "\"gyro_clipped\":%s,\"state\":\"%s\"}",
      liveRpmGyro, liveRpmAccel,
      liveAccelG, liveHgG,
      liveHyzer, liveNose,
      liveClipped ? "true" : "false",
      stateNames[state]);
    bleSendJson(buf);
  }

  // Cal progress at 5 Hz during calibration
  if (state == 4 /* CALIBRATING */ && (now - lastCalPushMs >= 200)) {
    lastCalPushMs = now;
    const char* hint = "Spin the disc";
    if (liveClipped) hint = "Too fast - gyro clipping";
    else if (liveRpmGyro < 150) hint = "Spin faster (aim 200-600 RPM)";
    else if (calCount >= 20 && (calRpmMax - calRpmMin) < 100) hint = "Vary the speed - need a wider range";
    else if (calCount >= 200) hint = "Ready - tap Stop";
    else hint = "Good - keep varying the spin";

    char buf[256];
    snprintf(buf, sizeof(buf),
      "{\"type\":\"cal_progress\",\"pts\":%d,\"target\":200,"
      "\"rpm\":%.0f,\"rpm_min\":%.0f,\"rpm_max\":%.0f,\"hint\":\"%s\"}",
      calCount, liveRpmGyro,
      (calCount > 0) ? calRpmMin : 0.0f, calRpmMax, hint);
    bleSendJson(buf);
  }
}

// Simple JSON key extraction (no external JSON library)
static bool jsonGetString(const char* json, const char* key, char* out, int maxLen) {
  char search[64];
  snprintf(search, sizeof(search), "\"%s\":\"", key);
  const char* p = strstr(json, search);
  if (!p) return false;
  p += strlen(search);
  int i = 0;
  while (*p && *p != '"' && i < maxLen - 1) out[i++] = *p++;
  out[i] = 0;
  return true;
}

static bool jsonGetFloat(const char* json, const char* key, float* out) {
  char search[64];
  snprintf(search, sizeof(search), "\"%s\":", key);
  const char* p = strstr(json, search);
  if (!p) return false;
  p += strlen(search);
  while (*p == ' ') p++;
  *out = atof(p);
  return true;
}

static bool jsonGetBool(const char* json, const char* key, bool* out) {
  char search[64];
  snprintf(search, sizeof(search), "\"%s\":", key);
  const char* p = strstr(json, search);
  if (!p) return false;
  p += strlen(search);
  while (*p == ' ') p++;
  *out = (*p == 't' || *p == '1');
  return true;
}

void bleHandleCommand(const char* json) {
  char cmd[32] = {0};
  if (!jsonGetString(json, "cmd", cmd, sizeof(cmd))) return;

  debugMsg("BLE cmd: %s", cmd);

  if (strcmp(cmd, "status") == 0) {
    char buf[256];
    snprintf(buf, sizeof(buf),
      "{\"type\":\"status\",\"state\":\"%s\",\"auto_arm\":%s,"
      "\"radius\":%.6f,\"cal_rx\":%.6f,\"cal_ry\":%.6f,"
      "\"has_throw\":%s,\"fw_version\":\"1.0.0\"}",
      stateNames[state], autoArm ? "true" : "false",
      calRadius, calRx, calRy,
      hasLastThrow ? "true" : "false");
    bleSendJson(buf);

  } else if (strcmp(cmd, "live_start") == 0) {
    liveStreaming = true;
    lastStreamMs = 0;

  } else if (strcmp(cmd, "live_stop") == 0) {
    liveStreaming = false;

  } else if (strcmp(cmd, "arm") == 0) {
    // Reuse the same logic as handleArm
    extern uint16_t ringHead, postCount;
    extern unsigned long lastSampleUs;
    if (state == 4) { // CALIBRATING
      bleSendJson("{\"type\":\"ack\",\"msg\":\"Stop calibration first\"}");
    } else {
      state = 1; // ARMED
      ringHead = 0;
      postCount = 0;
      lastSampleUs = micros();
      hasLastThrow = false;
      bleSendJson("{\"type\":\"ack\",\"msg\":\"Armed! Waiting for throw...\"}");
    }

  } else if (strcmp(cmd, "throw") == 0) {
    if (!hasLastThrow) {
      bleSendJson("{\"type\":\"throw\",\"valid\":false}");
    } else {
      const ThrowMetrics& m = lastMetrics;
      char buf[400];
      snprintf(buf, sizeof(buf),
        "{\"type\":\"throw\",\"valid\":%s,\"rpm\":%.1f,"
        "\"mph\":%.2f,\"peak_g\":%.2f,"
        "\"hyzer\":%.1f,\"nose\":%.1f,\"launch\":%.1f,"
        "\"wobble\":%.1f,\"duration_ms\":%lu,"
        "\"release_idx\":%d,\"motion_start_idx\":%d,\"stationary_end\":%d}",
        m.valid ? "true" : "false",
        m.rpm, m.mph, m.peak_accel_g,
        m.launch_hyzer_deg, m.launch_nose_deg, m.launch_angle_deg, m.wobble_deg,
        (unsigned long)m.duration_ms,
        m.release_index, m.motion_start_index, m.stationary_end);
      bleSendJson(buf);
    }

  } else if (strcmp(cmd, "cal_start") == 0) {
    // Directly set cal state (mirrors handleCalStart logic)
    extern float calRpmMin, calRpmMax;
    extern float calAxyMax;
    extern int16_t calRawAxAbsMax, calRawAyAbsMax, calRawAzAbsMax;
    extern int16_t calRawGxAbsMax, calRawGyAbsMax, calRawGzAbsMax;
    extern unsigned long lastCalSample;
    calCount = 0;
    calRpmMin = 9999; calRpmMax = 0;
    calAxyMax = 0;
    calRawAxAbsMax = calRawAyAbsMax = calRawAzAbsMax = 0;
    calRawGxAbsMax = calRawGyAbsMax = calRawGzAbsMax = 0;
    lastCalSample = 0;
    state = 4; // CALIBRATING
    bleSendJson("{\"type\":\"ack\",\"msg\":\"Calibrating - vary spin 200-500 RPM\"}");

  } else if (strcmp(cmd, "cal_stop") == 0) {
    extern float computeRadius();
    extern void saveCalRadius();
    float newRadius = computeRadius();
    bool accepted = (calCount >= 20 && (calRpmMax - calRpmMin) >= 100 && newRadius > 0);
    if (accepted) {
      calRadius = newRadius;
      saveCalRadius();
    }
    state = 0; // IDLE
    char buf[256];
    snprintf(buf, sizeof(buf),
      "{\"type\":\"cal_result\",\"accepted\":%s,\"radius\":%.6f,"
      "\"rx\":%.6f,\"ry\":%.6f,\"points\":%d,"
      "\"rpm_min\":%.0f,\"rpm_max\":%.0f,"
      "\"msg\":\"%s: %d pts, r=%.1fmm\"}",
      accepted ? "true" : "false",
      calRadius, calRx, calRy, calCount,
      calRpmMin, calRpmMax,
      accepted ? "Calibration saved" : "Rejected",
      calCount, newRadius * 1000.0f);
    bleSendJson(buf);

  } else if (strcmp(cmd, "settings_get") == 0) {
    char buf[100];
    snprintf(buf, sizeof(buf),
      "{\"type\":\"settings\",\"auto_arm\":%s,\"trigger_g\":%.2f}",
      autoArm ? "true" : "false", triggerG);
    bleSendJson(buf);

  } else if (strcmp(cmd, "settings_set") == 0) {
    bool aa;
    if (jsonGetBool(json, "auto_arm", &aa)) autoArm = aa;
    float tg;
    if (jsonGetFloat(json, "trigger_g", &tg) && tg >= 1.0f && tg <= 10.0f) triggerG = tg;
    saveSettings();
    char buf[100];
    snprintf(buf, sizeof(buf),
      "{\"type\":\"settings\",\"auto_arm\":%s,\"trigger_g\":%.2f}",
      autoArm ? "true" : "false", triggerG);
    bleSendJson(buf);

  } else if (strcmp(cmd, "wifi_off") == 0) {
    wifiDisabledByBle = true;
    debugMsg("WiFi disabled by BLE client");
    bleSendJson("{\"type\":\"ack\",\"msg\":\"WiFi off. Restores 5 min after BLE disconnect.\"}");

  } else if (strcmp(cmd, "wifi_on") == 0) {
    wifiDisabledByBle = false;
    debugMsg("WiFi enabled by BLE client");
    bleSendJson("{\"type\":\"ack\",\"msg\":\"WiFi on.\"}");

  } else if (strcmp(cmd, "dump_raw") == 0) {
    // Binary-framed ring dump. iOS receives frames on the same TX characteristic
    // and disambiguates by the leading byte (0xFF = binary dump frame).
    //
    // Each frame is 6-byte header + up to 8 samples × 20 bytes = 166 bytes max,
    // which fits under the default 185-byte BLE notification MTU.
    //
    // Frame header:
    //   byte 0    : 0xFF           magic
    //   byte 1    : 0x01           protocol version
    //   bytes 2-3 : seq (uint16 LE) — frame index, 0..N-1
    //   byte 4    : count          — number of samples in this frame
    //   byte 5    : reserved (0)
    // Followed by `count` samples, each 10×int16 LE in order:
    //   i, ax, ay, az, gx, gy, gz, hx, hy, hz
    extern RawSample ring[];
    extern uint16_t triggerIndex;
    #define EXT_PRE_TRIGGER 960
    #define EXT_POST_TRIGGER 960
    #define EXT_RING_SIZE (EXT_PRE_TRIGGER + EXT_POST_TRIGGER)
    constexpr uint16_t SAMPLES_PER_FRAME = 8;

    if (!hasLastThrow) {
      bleSendJson("{\"type\":\"dump\",\"status\":\"no_throw\"}");
    } else {
      const uint16_t totalSamples = EXT_RING_SIZE;
      const uint16_t totalFrames = (totalSamples + SAMPLES_PER_FRAME - 1) / SAMPLES_PER_FRAME;
      const uint16_t ringStart = (triggerIndex + totalSamples - EXT_PRE_TRIGGER) % totalSamples;
      debugMsg("dump_raw: %u samples in %u frames (binary)", totalSamples, totalFrames);

      char startMsg[160];
      snprintf(startMsg, sizeof(startMsg),
        "{\"type\":\"dump\",\"status\":\"start\",\"samples\":%u,\"frames\":%u,\"spf\":%u,\"fmt\":\"bin1\"}",
        totalSamples, totalFrames, SAMPLES_PER_FRAME);
      bleSendJson(startMsg);
      delay(30);  // let iOS process `start` before the binary stream begins

      uint8_t buf[6 + SAMPLES_PER_FRAME * 20];
      for (uint16_t frame = 0; frame < totalFrames; frame++) {
        const uint16_t frameStart = frame * SAMPLES_PER_FRAME;
        const uint16_t samplesInFrame =
          (uint16_t)((totalSamples - frameStart) < SAMPLES_PER_FRAME
                     ? (totalSamples - frameStart) : SAMPLES_PER_FRAME);

        buf[0] = 0xFF;
        buf[1] = 0x01;
        buf[2] = (uint8_t)(frame & 0xFF);
        buf[3] = (uint8_t)((frame >> 8) & 0xFF);
        buf[4] = (uint8_t)samplesInFrame;
        buf[5] = 0;

        size_t off = 6;
        auto writeI16LE = [&](int16_t v) {
          buf[off++] = (uint8_t)(v & 0xFF);
          buf[off++] = (uint8_t)((v >> 8) & 0xFF);
        };

        for (uint16_t k = 0; k < samplesInFrame; k++) {
          const uint16_t sampleIdx = frameStart + k;
          const uint16_t ringIdx = (ringStart + sampleIdx) % totalSamples;
          const RawSample& s = ring[ringIdx];
          const int16_t sampleI = (int16_t)((int)sampleIdx - (int)EXT_PRE_TRIGGER);
          writeI16LE(sampleI);
          writeI16LE(s.ax); writeI16LE(s.ay); writeI16LE(s.az);
          writeI16LE(s.gx); writeI16LE(s.gy); writeI16LE(s.gz);
          writeI16LE(s.hx); writeI16LE(s.hy); writeI16LE(s.hz);
        }

        bleSendBinary(buf, off);
        // Pacing: one frame per ~25ms comfortably below iOS's 15-30ms
        // connection interval so the NimBLE TX queue never backs up.
        // 240 frames × 25ms ≈ 6s total — acceptable.
        delay(25);
      }
      // Small trailing buffer before the `done` marker so the last binary
      // frame has time to actually leave the TX queue.
      delay(50);
      bleSendJson("{\"type\":\"dump\",\"status\":\"done\"}");
      debugMsg("dump_raw: complete");
    }

  } else if (strcmp(cmd, "imudiag") == 0) {
    ImuDiag d = readImuDiag();
    char buf[300];
    snprintf(buf, sizeof(buf),
      "{\"type\":\"imudiag\",\"whoami\":\"0x%02X\","
      "\"ctrl1\":\"0x%02X\",\"ctrl2\":\"0x%02X\","
      "\"ctrl6\":\"0x%02X\",\"ctrl8\":\"0x%02X\","
      "\"ctrl9\":\"0x%02X\",\"ctrl1_xl_hg\":\"0x%02X\","
      "\"fs_g\":\"%s\",\"fs_xl\":\"%s\"}",
      d.whoami, d.ctrl1, d.ctrl2, d.ctrl6, d.ctrl8, d.ctrl9, d.ctrl1_xl_hg,
      (d.ctrl6 & 0x07) == 4 ? "2000 dps" : "other",
      (d.ctrl8 & 0x03) == 3 ? "16 g" : "other");
    bleSendJson(buf);
  }
}
