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

class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* pSvr, NimBLEConnInfo& connInfo) override {
    deviceConnected = true;
    pSvr->updateConnParams(connInfo.getConnHandle(), 12, 24, 0, 200);
    debugMsg("BLE client connected");
  }
  void onDisconnect(NimBLEServer* pSvr, NimBLEConnInfo& connInfo, int reason) override {
    deviceConnected = false;
    liveStreaming = false;
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
  pDis->createCharacteristic("2A26", NIMBLE_PROPERTY::READ)->setValue("1.0.0");
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

void bleSendJson(const char* json) {
  if (!deviceConnected || !pTxChar) return;
  pTxChar->setValue((const uint8_t*)json, strlen(json));
  pTxChar->notify();
}

bool bleClientConnected() {
  return deviceConnected;
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
        "{\"type\":\"throw\",\"valid\":%s,\"peak_rpm\":%.1f,\"release_rpm\":%.1f,"
        "\"release_mph\":%.2f,\"peak_g\":%.2f,"
        "\"launch_hyzer\":%.1f,\"launch_nose\":%.1f,"
        "\"wobble\":%.1f,\"duration_ms\":%lu,"
        "\"release_idx\":%d,\"motion_start_idx\":%d,\"stationary_end\":%d}",
        m.valid ? "true" : "false",
        m.peak_rpm, m.release_rpm, m.release_mph, m.peak_accel_g,
        m.launch_hyzer_deg, m.launch_nose_deg, m.wobble_deg,
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
