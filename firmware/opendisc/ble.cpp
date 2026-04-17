#include "ble.h"
#include <NimBLEDevice.h>
#include "sensors.h"
#include "analyzer.h"

// ─── Raw-dump session state ────────────────────────────────────────────
// The dump handler can NOT run inside onWrite: NimBLE's RX callback executes
// on the BLE host task, which is the same task that drains notifications to
// the radio. Calling notify() + delay() from inside onWrite queues TX data
// onto the one task that's now blocked, so almost nothing ships. Everything
// below is driven from bleTick() on the Arduino loop task instead.
// 8 samples per frame (166-byte notification) + PRN batch of 4. Mac-side
// BLE testing confirmed firmware transmits full-size frames reliably —
// the size isn't the issue. The iOS app's @Observable/SwiftUI churn was
// the actual cause of dropped notifications; fixed on the client side.
static constexpr uint16_t DUMP_SAMPLES_PER_FRAME = 8;
static constexpr uint16_t DUMP_FRAMES_PER_BATCH  = 4;
static constexpr uint16_t DUMP_PRE_TRIGGER = 960;
static constexpr uint16_t DUMP_RING_SIZE   = 1920;

// Written by onWrite (BLE task), consumed by bleTick (Arduino task). 1-byte
// aligned writes on ESP32 are atomic — no locking needed for a plain flag.
static volatile bool     dumpStartRequested = false;
static volatile bool     dumpNextRequested  = false;
// PRN acknowledgement from iOS. Written by onWrite when the app sends
// `{"cmd":"dump_ack","last":N}`; consumed by the dump loop on the Arduino
// task. The `last` value lets the firmware confirm iOS received up through
// at least that frame seq.
static volatile bool     dumpAckReceived    = false;
static volatile uint16_t dumpAckLastSeq     = 0;

// Dump session state — only touched by bleTick / helpers, so no races.
static bool     dumpActive      = false;
static uint16_t dumpTotalFrames = 0;
static uint16_t dumpNextFrame   = 0;
static uint16_t dumpRingStart   = 0;

#define NUS_SERVICE_UUID        "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_RX_UUID             "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define NUS_TX_UUID             "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
// Dump characteristic — INDICATE only. Every binary dump frame gets an
// ATT-layer ACK before the next is sent, so the TX queue can't back up.
// iOS subscribes to this separately from the NOTIFY TX channel.
#define NUS_DUMP_UUID           "6e400004-b5a3-f393-e0a9-e50e24dcca9e"

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
static NimBLECharacteristic* pDumpChar = nullptr;
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

  // INDICATE-only binary dump channel. Each call to pDumpChar->indicate()
  // blocks in NimBLE until the ATT-level confirmation comes back from the
  // client — guaranteed in-order delivery, no TX-queue overflow possible.
  pDumpChar = pNus->createCharacteristic(
    NUS_DUMP_UUID,
    NIMBLE_PROPERTY::INDICATE
  );

  pNus->start();

  // Device Info Service
  NimBLEService* pDis = pServer->createService("180A");
  pDis->createCharacteristic("2A24", NIMBLE_PROPERTY::READ)->setValue("OpenDisc");
  pDis->createCharacteristic("2A26", NIMBLE_PROPERTY::READ)->setValue("1.1.3");
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

// Binary TX via ATT-level INDICATE on the dedicated dump characteristic.
// indicate(data, len) should block until the client ACKs, but diagnostic
// log output here + the return value tell us whether NimBLE-Arduino 2.5
// actually waits or fire-and-forgets.
// Send a binary dump frame. We now route through the TX notify characteristic
// (same channel as JSON status) rather than a dedicated indicate characteristic —
// iOS's CoreBluetooth caches the GATT service table per-peripheral and a
// freshly-added characteristic may not be visible to an iOS app that connected
// to this device at any point prior. JSON status messages prove the TX channel
// is subscribed and delivering; the 0xFF magic byte at offset 0 of every binary
// frame is the discriminator the iOS client already handles.
void bleSendBinary(const uint8_t* data, size_t len) {
  if (!deviceConnected || !pTxChar) return;
  unsigned long t0 = millis();
  bool ok = pTxChar->notify(data, len);
  unsigned long dt = millis() - t0;
  Serial.printf("[BIN] len=%u ok=%d dt=%lums\n", (unsigned)len, (int)ok, dt);
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

// Build one binary dump frame for `frame` into `buf`. Returns bytes written.
static size_t buildDumpFrame(uint16_t frame, uint8_t* buf) {
  extern RawSample ring[];
  const uint16_t frameStart = frame * DUMP_SAMPLES_PER_FRAME;
  const uint16_t samplesInFrame =
    (uint16_t)((DUMP_RING_SIZE - frameStart) < DUMP_SAMPLES_PER_FRAME
               ? (DUMP_RING_SIZE - frameStart) : DUMP_SAMPLES_PER_FRAME);
  buf[0] = 0xFF;
  buf[1] = 0x01;
  buf[2] = (uint8_t)(frame & 0xFF);
  buf[3] = (uint8_t)((frame >> 8) & 0xFF);
  buf[4] = (uint8_t)samplesInFrame;
  buf[5] = 0;
  size_t off = 6;
  for (uint16_t k = 0; k < samplesInFrame; k++) {
    const uint16_t sampleIdx = frameStart + k;
    const uint16_t ringIdx   = (dumpRingStart + sampleIdx) % DUMP_RING_SIZE;
    const RawSample& s = ring[ringIdx];
    const int16_t sampleI = (int16_t)((int)sampleIdx - (int)DUMP_PRE_TRIGGER);
    int16_t fields[10] = {sampleI, s.ax, s.ay, s.az, s.gx, s.gy, s.gz, s.hx, s.hy, s.hz};
    for (int f = 0; f < 10; f++) {
      buf[off++] = (uint8_t)(fields[f] & 0xFF);
      buf[off++] = (uint8_t)((fields[f] >> 8) & 0xFF);
    }
  }
  return off;
}

// Nordic-DFU-style Packet Receipt Notification flow control.
//
// notify() on NimBLE-Arduino does not block on wire delivery — it only
// enqueues an mbuf. Under sustained burst (240 × 166 B) the TX queue
// silently drops frames that don't fit. See NimBLE-Arduino#728.
//
// Fix: send N frames, then wait for iOS to write
//   {"cmd":"dump_ack","last":<lastSeqReceived>}
// before sending the next N. iOS paces the transfer by only ACKing after
// it has actually received and decoded the frames. This is the same
// pattern Nordic DFU uses to ship tens of MB of firmware over BLE.
static void handleDumpStart() {
  extern uint16_t triggerIndex;
  if (!hasLastThrow) {
    bleSendJson("{\"type\":\"dump\",\"status\":\"no_throw\"}");
    dumpActive = false;
    return;
  }
  const uint16_t totalFrames = (DUMP_RING_SIZE + DUMP_SAMPLES_PER_FRAME - 1) / DUMP_SAMPLES_PER_FRAME;
  dumpRingStart      = (triggerIndex + DUMP_RING_SIZE - DUMP_PRE_TRIGGER) % DUMP_RING_SIZE;
  dumpActive         = true;
  dumpAckReceived    = false;
  dumpAckLastSeq     = 0;

  char startMsg[220];
  snprintf(startMsg, sizeof(startMsg),
    "{\"type\":\"dump\",\"status\":\"start\",\"samples\":%u,\"frames\":%u,"
    "\"spf\":%u,\"batch\":%u,\"fmt\":\"bin1\",\"mode\":\"prn\"}",
    DUMP_RING_SIZE, totalFrames,
    DUMP_SAMPLES_PER_FRAME, DUMP_FRAMES_PER_BATCH);
  bleSendJson(startMsg);
  debugMsg("dump start: %u frames, batch=%u, waiting for ACK",
           totalFrames, DUMP_FRAMES_PER_BATCH);

  delay(50);  // let `start` drain before the binary burst begins

  uint8_t buf[6 + DUMP_SAMPLES_PER_FRAME * 20];
  uint16_t nextFrame = 0;
  constexpr uint8_t MAX_BATCH_RETRIES = 4;
  while (nextFrame < totalFrames && deviceConnected) {
    const uint16_t batchEnd =
      (nextFrame + DUMP_FRAMES_PER_BATCH < totalFrames)
        ? nextFrame + DUMP_FRAMES_PER_BATCH
        : totalFrames;

    // Retry the whole batch up to MAX_BATCH_RETRIES times on ACK timeout.
    // CoreBluetooth sporadically drops notifications; iOS's dedup means
    // replaying already-received frames is free (they're ignored). Only a
    // frame iOS never received drives the ACK forward, so retries
    // eventually get every frame through.
    bool batchAcked = false;
    for (uint8_t attempt = 0; attempt < MAX_BATCH_RETRIES && !batchAcked && deviceConnected; attempt++) {
      for (uint16_t f = nextFrame; f < batchEnd; f++) {
        size_t len = buildDumpFrame(f, buf);
        bleSendBinary(buf, len);
        delay(15);  // intra-batch pacing so rapid notifies can drain
      }

      // Wait for iOS to ACK. 1.5s per attempt is plenty — a healthy batch
      // is ACK'd within ~50ms.
      dumpAckReceived = false;
      const uint16_t waitMs = 1500;
      uint16_t waited = 0;
      while (!dumpAckReceived && waited < waitMs && deviceConnected) {
        delay(5);
        waited += 5;
      }
      batchAcked = dumpAckReceived;
      if (!batchAcked && attempt + 1 < MAX_BATCH_RETRIES) {
        debugMsg("batch [%u..%u) retry %u",
                 nextFrame, batchEnd, attempt + 1);
      }
    }
    if (!batchAcked) {
      debugMsg("dump ACK timeout at frame %u after %u retries — aborting",
               batchEnd, MAX_BATCH_RETRIES);
      break;
    }

    // Resume from one past the highest seq iOS confirmed. If iOS lost a
    // frame inside the batch, dumpAckLastSeq will be lower than batchEnd-1
    // and we'll re-send from the gap on the next iteration.
    if (dumpAckLastSeq + 1 >= batchEnd) {
      nextFrame = batchEnd;
    } else {
      nextFrame = dumpAckLastSeq + 1;
      debugMsg("dump resending from %u (ACK said last=%u)",
               nextFrame, dumpAckLastSeq);
    }
  }

  delay(50);
  bleSendJson("{\"type\":\"dump\",\"status\":\"done\"}");
  dumpActive = false;
  debugMsg("dump complete (reached frame %u of %u)", nextFrame, totalFrames);
}

// Legacy no-op — kept for wire-compat with any iOS build that still
// speaks the old pull protocol. New firmware drives everything via PRN
// ACKs instead, so any stray dump_next writes just get an idle reply.
static void handleDumpNext() {
  bleSendJson("{\"type\":\"dump\",\"status\":\"idle\"}");
}

void bleTick() {
  if (!deviceConnected) return;

  // Service dump requests flagged by onWrite. Do this first so a pending
  // dump doesn't get starved by live-stream chatter below.
  if (dumpStartRequested) {
    dumpStartRequested = false;
    handleDumpStart();
  }
  if (dumpNextRequested) {
    dumpNextRequested = false;
    handleDumpNext();
  }

  unsigned long now = millis();

  // Push state changes
  if (state != prevState) {
    prevState = state;
    blePushState(stateNames[state]);
  }

  // Live stream at 10 Hz — suppressed while a raw-dump is in progress so
  // the 10Hz JSON chatter doesn't compete with dump frames on the same
  // TX queue and push the queue into overflow.
  if (liveStreaming && !dumpActive && (now - lastStreamMs >= 100)) {
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
    // DO NOT do dump work here — we're on the NimBLE RX task and calling
    // notify() from here would queue TX onto this same task before we
    // return. Just flag it and bleTick() on the Arduino loop task picks
    // it up.
    Serial.println("[BLE RX] dump_raw");
    dumpStartRequested = true;

  } else if (strcmp(cmd, "dump_next") == 0) {
    Serial.println("[BLE RX] dump_next");
    dumpNextRequested = true;

  } else if (strcmp(cmd, "dump_ack") == 0) {
    // PRN ACK from iOS: Nordic-style packet receipt notification. iOS
    // writes this every DUMP_FRAMES_PER_BATCH frames it has decoded; we
    // use it as a credit to send the next batch.
    float lastF = 0;
    if (jsonGetFloat(json, "last", &lastF)) {
      dumpAckLastSeq = (uint16_t)lastF;
    }
    dumpAckReceived = true;

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
