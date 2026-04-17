/*
 * OpenDisc — Web Interface
 * =========================
 * ESP32-C6 + BerryIMU 320G
 * Serves a web UI for live readings, burst capture, and radius calibration.
 *
 * Wiring:  GPIO6=SDA  GPIO7=SCL  3.3V=VCC  GND=GND
 * Board:   ESP32C6 Dev Module, Partition: Minimal SPIFFS
 *          (1.9MB APP with OTA / 128KB SPIFFS — sketch has outgrown the 1.2MB default).
 */

#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Wire.h>
#include <Preferences.h>
#include <math.h>
#include "sensors.h"
#include "analyzer.h"
#include "ble.h"
#include "page.h"

// ─── Forward declarations ───────────────────────────────────
// Arduino IDE auto-generates these from ctags output, but arduino-cli 1.4+
// doesn't, so declare them explicitly to stay toolchain-portable.
void loadSettings();
void saveSettings();
void saveCalRadius();
void updateLiveMetrics();
void burstSample();
float computeRadius();
void handleRoot();
void handleArm();
void handleStatus();
void handleDump();
void handleThrow();
void handleCalDump();
void handleDebugLog();
void handleImuDiag();
void handleSettings();
void handleEisTest();
void handleSetFsG();
void handleCalStart();
void handleCalStop();
void handleLive();

// ─── WiFi ───────────────────────────────────────────────────
const char* WIFI_SSID = "Dino-Main";
const char* WIFI_PASS = "goodlife123";

// ─── Pins ───────────────────────────────────────────────────
#define SDA_PIN 6
#define SCL_PIN 7

// ─── Burst capture config ───────────────────────────────────
#define SAMPLE_HZ      960
#define SAMPLE_US      (1000000UL / SAMPLE_HZ)
#define PRE_TRIGGER    960
#define POST_TRIGGER   960
#define RING_SIZE      (PRE_TRIGGER + POST_TRIGGER)
#define TRIGGER_G_DEFAULT  3.0f

// ─── State ──────────────────────────────────────────────────
enum State { IDLE, ARMED, CAPTURING, DONE, CALIBRATING };
const char* stateNames[] = {"IDLE","ARMED","CAPTURING","DONE","CALIBRATING"};

State state = IDLE;
RawSample ring[RING_SIZE];
uint16_t ringHead = 0;
uint16_t triggerIndex = 0;
uint16_t postCount = 0;
int32_t triggerRaw = (int32_t)(TRIGGER_G_DEFAULT / ACCEL_SENS);

// Current live reading (updated every loop)
RawSample live;
float liveRpmGyro = 0;
float liveRpmAccel = -1;  // -1 = not calibrated
float liveAccelG = 0;
float liveHgG = 0;
float liveHyzer = 0;
float liveNose = 0;
bool liveClipped = false;

// Calibration
#define CAL_MAX_PTS 2000
float calOmega2[CAL_MAX_PTS];  // (rad/s)^2
float calAccel[CAL_MAX_PTS];    // m/s^2 centripetal (magnitude, for backward compat)
float calAx[CAL_MAX_PTS];       // m/s^2 body x (for vectorial fit)
float calAy[CAL_MAX_PTS];       // m/s^2 body y
int16_t calRawAx[CAL_MAX_PTS];
int16_t calRawAy[CAL_MAX_PTS];
int16_t calRawAz[CAL_MAX_PTS];
int16_t calRawGx[CAL_MAX_PTS];
int16_t calRawGy[CAL_MAX_PTS];
int16_t calRawGz[CAL_MAX_PTS];
uint32_t calTimeMs[CAL_MAX_PTS];
uint16_t calCount = 0;
float calRadius = 0;  // meters (|r_xy|)
float calRx = 0, calRy = 0;  // meters, body-frame chip position
float calRpmMin = 9999, calRpmMax = 0;
int16_t calRawAxAbsMax = 0, calRawAyAbsMax = 0, calRawAzAbsMax = 0;
int16_t calRawGxAbsMax = 0, calRawGyAbsMax = 0, calRawGzAbsMax = 0;
float calAxyMax = 0;
unsigned long lastCalSample = 0;

// Timing
unsigned long lastSampleUs = 0;
unsigned long doneAtMs = 0;

// Settings (persisted)
Preferences prefs;
bool autoArm = true;
float triggerG = 3.0f;

// Last throw
ThrowMetrics lastMetrics = {};
bool hasLastThrow = false;

// Monotonic throw sequence counter, persisted to NVS. Incremented each time a
// new throw is analyzed. Exposed in throw_ready / throw / status responses so
// iOS can dedupe across BT drops and detect missed throws on reconnect.
uint32_t throwSeq = 0;

// Auto-arm debounce
uint8_t autoArmRun = 0;

// Web server
WebServer server(80);


// ─── Setup ──────────────────────────────────────────────────

void loadSettings() {
  prefs.begin("opendisc", true);
  autoArm = prefs.getBool("autoArm", true);
  triggerG = prefs.getFloat("triggerG", TRIGGER_G_DEFAULT);
  calRadius = prefs.getFloat("calRadius", 0.0f);
  calRx = prefs.getFloat("calRx", 0.0f);
  calRy = prefs.getFloat("calRy", 0.0f);
  throwSeq = prefs.getUInt("throwSeq", 0);
  prefs.end();
  triggerRaw = (int32_t)(triggerG / ACCEL_SENS);
}

void saveSettings() {
  prefs.begin("opendisc", false);
  prefs.putBool("autoArm", autoArm);
  prefs.putFloat("triggerG", triggerG);
  prefs.end();
  triggerRaw = (int32_t)(triggerG / ACCEL_SENS);
}

void saveCalRadius() {
  prefs.begin("opendisc", false);
  prefs.putFloat("calRadius", calRadius);
  prefs.putFloat("calRx", calRx);
  prefs.putFloat("calRy", calRy);
  prefs.end();
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== OpenDisc Web ===\n");

  loadSettings();
  Serial.printf("[CFG] autoArm=%d triggerG=%.2f\n", autoArm, triggerG);

  // I2C + sensors
  Wire.begin(SDA_PIN, SCL_PIN, 400000);
  delay(100);
  if (!scanAndVerify()) {
    Serial.println("[FATAL] Sensor fail");
    while (1) delay(1000);
  }
  initIMU();
  initMag();
  Serial.println("[OK] Sensors ready");

  // WiFi
  Serial.printf("[WIFI] Connecting to %s", WIFI_SSID);
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.printf("\n[WIFI] Connected! IP: %s\n", WiFi.localIP().toString().c_str());

  // mDNS: http://opendisc.local/
  if (MDNS.begin("opendisc")) {
    MDNS.addService("http", "tcp", 80);
    Serial.println("[MDNS] http://opendisc.local/");
  } else {
    Serial.println("[MDNS] Failed to start");
  }

  // Web routes
  server.on("/", handleRoot);
  server.on("/api/live", handleLive);
  server.on("/api/arm", handleArm);
  server.on("/api/dump", handleDump);
  server.on("/api/status", handleStatus);
  server.on("/api/throw", handleThrow);
  server.on("/api/settings", handleSettings);
  server.on("/api/imudiag", handleImuDiag);
  server.on("/api/debuglog", handleDebugLog);
  server.on("/api/caldump", handleCalDump);
  server.on("/api/setfsg", handleSetFsG);
  server.on("/api/eis_test", handleEisTest);
  server.on("/api/cal/start", handleCalStart);
  server.on("/api/cal/stop", handleCalStop);
  server.begin();

  Serial.printf("[WEB] Server at http://%s/ (or http://opendisc.local/)\n\n", WiFi.localIP().toString().c_str());

  // BLE
  initBLE();
}


// ─── Main loop ──────────────────────────────────────────────

void loop() {
  unsigned long nowUs = micros();

  // High-rate sensor read when armed/capturing
  if (state == ARMED || state == CAPTURING) {
    if (nowUs - lastSampleUs >= SAMPLE_US) {
      lastSampleUs = nowUs;
      burstSample();
    }
  }

  // Continuous sensor read for live display + calibration
  static unsigned long lastLiveUs = 0;
  if (nowUs - lastLiveUs >= 5000) {  // ~200Hz for live
    lastLiveUs = nowUs;
    readSample(&live);
    updateLiveMetrics();

    // Auto-arm: gate on motion while IDLE
    if (state == IDLE && autoArm) {
      float gx = live.gx * GYRO_SENS;
      float gy = live.gy * GYRO_SENS;
      float gz = live.gz * GYRO_SENS;
      float omega = sqrtf(gx*gx + gy*gy + gz*gz);
      if (omega > 200.0f) {
        autoArmRun++;
        if (autoArmRun >= 3) {
          state = ARMED;
          ringHead = 0;
          postCount = 0;
          lastSampleUs = micros();
          autoArmRun = 0;
          hasLastThrow = false;
          Serial.println("[AUTO] Armed");
        }
      } else {
        autoArmRun = 0;
      }
    }

    // Calibration data collection
    static float lastCalRpm = 0;
    if (state == CALIBRATING && calCount < CAL_MAX_PTS) {
      // Only collect if spinning 150-650 RPM and not clipping
      // Also reject implausible dRPM/sample jumps (gyro noise spikes)
      bool rateSane = (fabsf(liveRpmGyro - lastCalRpm) < 60.0f) || (calCount == 0);
      if (liveRpmGyro > 150 && liveRpmGyro < 650 && !liveClipped && rateSane) {
        if (nowUs - lastCalSample > 20000) {  // 50Hz cal rate
          lastCalSample = nowUs;
          lastCalRpm = liveRpmGyro;
          float gz_dps = fabsf(live.gz * GYRO_SENS);
          float omega = gz_dps * M_PI / 180.0f;  // rad/s

          // XY accel magnitude (centripetal is in the disc plane)
          float ax = live.ax * ACCEL_SENS * 9.81f;  // m/s^2
          float ay = live.ay * ACCEL_SENS * 9.81f;
          float axy = sqrtf(ax*ax + ay*ay);

          calOmega2[calCount] = omega * omega;
          calAccel[calCount] = axy;
          calAx[calCount] = ax;
          calAy[calCount] = ay;
          calRawAx[calCount] = live.ax;
          calRawAy[calCount] = live.ay;
          calRawAz[calCount] = live.az;
          calRawGx[calCount] = live.gx;
          calRawGy[calCount] = live.gy;
          calRawGz[calCount] = live.gz;
          calTimeMs[calCount] = millis();
          calCount++;
          if (liveRpmGyro < calRpmMin) calRpmMin = liveRpmGyro;
          if (liveRpmGyro > calRpmMax) calRpmMax = liveRpmGyro;
          if (axy > calAxyMax) calAxyMax = axy;
          int16_t aax = abs(live.ax); if (aax > calRawAxAbsMax) calRawAxAbsMax = aax;
          int16_t aay = abs(live.ay); if (aay > calRawAyAbsMax) calRawAyAbsMax = aay;
          int16_t aaz = abs(live.az); if (aaz > calRawAzAbsMax) calRawAzAbsMax = aaz;
          int16_t agx = abs(live.gx); if (agx > calRawGxAbsMax) calRawGxAbsMax = agx;
          int16_t agy = abs(live.gy); if (agy > calRawGyAbsMax) calRawGyAbsMax = agy;
          int16_t agz = abs(live.gz); if (agz > calRawGzAbsMax) calRawGzAbsMax = agz;
        }
      }
    }
  }

  // Analyze capture as soon as it finishes, then auto-return to IDLE
  if (state == DONE && !hasLastThrow) {
    CalVector cv = {calRx, calRy, calRadius};
    lastMetrics = analyzeThrow(ring, RING_SIZE, triggerIndex, PRE_TRIGGER, cv);
    hasLastThrow = true;
    throwSeq++;
    prefs.begin("opendisc", false);
    prefs.putUInt("throwSeq", throwSeq);
    prefs.end();
    doneAtMs = millis();
    Serial.printf("[THROW] seq=%u rpm=%.0f mph=%.1f peakG=%.1f rel=%d\n",
      (unsigned)throwSeq, lastMetrics.rpm, lastMetrics.mph,
      lastMetrics.peak_accel_g, lastMetrics.release_index);
    if (bleClientConnected()) blePushThrowReady();
  }
  if (state == DONE && autoArm && (millis() - doneAtMs > 2000)) {
    state = IDLE;
  }

  server.handleClient();
  bleTick();

  // WiFi power management: BLE client can disable WiFi for battery savings
  static bool wifiRunning = true;
  static unsigned long lastWifiCheck = 0;
  if (millis() - lastWifiCheck > 2000) {
    lastWifiCheck = millis();
    bool shouldBeOn = bleWifiShouldBeOn();
    if (wifiRunning && !shouldBeOn) {
      server.stop();
      WiFi.disconnect(true);
      WiFi.mode(WIFI_OFF);
      wifiRunning = false;
      debugMsg("WiFi stopped for power saving");
    } else if (!wifiRunning && shouldBeOn) {
      WiFi.mode(WIFI_STA);
      WiFi.begin(WIFI_SSID, WIFI_PASS);
      unsigned long t = millis();
      while (WiFi.status() != WL_CONNECTED && millis() - t < 10000) delay(100);
      if (WiFi.status() == WL_CONNECTED) {
        MDNS.begin("opendisc");
        server.begin();
        wifiRunning = true;
        debugMsg("WiFi restored: %s", WiFi.localIP().toString().c_str());
      }
    }
  }
}


// ─── Live metrics ───────────────────────────────────────────

void updateLiveMetrics() {
  float gx_dps = live.gx * GYRO_SENS;
  float gy_dps = live.gy * GYRO_SENS;
  float gz_dps = live.gz * GYRO_SENS;
  float omega_dps = sqrtf(gx_dps*gx_dps + gy_dps*gy_dps + gz_dps*gz_dps);
  liveRpmGyro = omega_dps / 6.0f;
  liveClipped = (abs(live.gz) > 28000 || abs(live.gx) > 28000 || abs(live.gy) > 28000);

  float ax = live.ax * ACCEL_SENS;  // g
  float ay = live.ay * ACCEL_SENS;
  float az = live.az * ACCEL_SENS;
  liveAccelG = sqrtf(ax*ax + ay*ay + az*az);

  float hx = live.hx * HG_SENS;
  float hy = live.hy * HG_SENS;
  float hz = live.hz * HG_SENS;
  liveHgG = sqrtf(hx*hx + hy*hy + hz*hz);

  // Subtract centripetal from ax/ay for clean hyzer/nose during spin
  float ax_corr = ax, ay_corr = ay;
  if (calRadius > 0.001f) {
    float omega_rad = omega_dps * (float)M_PI / 180.0f;
    float w2 = omega_rad * omega_rad;
    ax_corr = ax - w2 * calRx / 9.81f;
    ay_corr = ay - w2 * calRy / 9.81f;
  }
  // EMA-smoothed angles (tau ~0.15s at 200Hz = alpha ~0.03)
  float rawHyzer = atan2f(ay_corr, az) * 180.0f / M_PI;
  float rawNose = atan2f(-ax_corr, sqrtf(ay_corr*ay_corr + az*az)) * 180.0f / M_PI;
  const float alpha = 0.03f;
  liveHyzer += alpha * (rawHyzer - liveHyzer);
  liveNose += alpha * (rawNose - liveNose);

  // Accel-derived RPM (if calibrated)
  if (calRadius > 0.001f) {
    float axy_ms2 = sqrtf((ax*9.81f)*(ax*9.81f) + (ay*9.81f)*(ay*9.81f));
    float omega = sqrtf(axy_ms2 / calRadius);
    liveRpmAccel = omega * 60.0f / (2.0f * M_PI);
    // Suppress ghost RPM when not spinning
    if (liveRpmGyro < 20) liveRpmAccel = 0;
  } else {
    liveRpmAccel = -1;
  }
}


// ─── Burst capture ──────────────────────────────────────────

void burstSample() {
  RawSample* s = &ring[ringHead];
  readSample(s);

  if (state == ARMED) {
    int32_t mag2 = (int32_t)s->ax * s->ax
                 + (int32_t)s->ay * s->ay
                 + (int32_t)s->az * s->az;
    int32_t thr2 = triggerRaw * triggerRaw;
    if (mag2 > thr2) {
      state = CAPTURING;
      triggerIndex = ringHead;
      postCount = 0;
    }
  }

  if (state == CAPTURING) {
    postCount++;
    if (postCount >= POST_TRIGGER) {
      state = DONE;
    }
  }

  ringHead = (ringHead + 1) % RING_SIZE;
}


// ─── Calibration math ───────────────────────────────────────

float computeRadius() {
  if (calCount < 10) return 0;

  // Vectorial OLS: fit ax = cx*ω² + bx and ay = cy*ω² + by separately.
  // The slopes cx, cy give the chip's body-frame position vector. Taking
  // magnitude gives |r|. Intercepts absorb gravity tilt leakage.
  // This is MORE robust than fitting |xy| because it uses each axis's sign
  // information and doesn't suffer from sqrt-of-sum-of-squares bias.
  double sumW=0, sumW2=0;
  double sumAx=0, sumAy=0;
  double sumWAx=0, sumWAy=0;
  uint16_t n_used = 0;
  for (uint16_t i = 0; i < calCount; i++) {
    double w2 = calOmega2[i];
    if (w2 > 4800.0) continue;  // reject above ~660 RPM (gyro noise region)
    double ax = calAx[i];
    double ay = calAy[i];
    sumW   += w2;
    sumW2  += w2 * w2;
    sumAx  += ax;
    sumAy  += ay;
    sumWAx += w2 * ax;
    sumWAy += w2 * ay;
    n_used++;
  }
  if (n_used < 10) return 0;
  double n = n_used;
  double denom = n * sumW2 - sumW * sumW;
  if (fabs(denom) < 1e-10) return 0;
  double cx = (n * sumWAx - sumW * sumAx) / denom;
  double cy = (n * sumWAy - sumW * sumAy) / denom;
  calRx = (float)cx;
  calRy = (float)cy;
  return (float)sqrt(cx*cx + cy*cy);  // |r_xy|
}


// ─── Web handlers ───────────────────────────────────────────

void handleRoot() {
  server.send(200, "text/html", PAGE_HTML);
}

void handleArm() {
  if (state == CALIBRATING) {
    server.send(200, "application/json", "{\"msg\":\"Stop calibration first\"}");
    return;
  }
  state = ARMED;
  ringHead = 0;
  postCount = 0;
  lastSampleUs = micros();
  hasLastThrow = false;
  server.send(200, "application/json", "{\"msg\":\"Armed! Waiting for throw...\"}");
}

void handleStatus() {
  char buf[200];
  snprintf(buf, sizeof(buf),
    "{\"state\":\"%s\",\"samples\":%d,\"calPts\":%d,\"radius\":%.6f}",
    stateNames[state], RING_SIZE, calCount, calRadius);
  server.send(200, "application/json", buf);
}

void handleDump() {
  if (state != DONE) {
    server.send(400, "text/plain", "No capture ready");
    return;
  }

  // Build CSV
  String csv = "sample,time_us,gx_dps,gy_dps,gz_dps,"
               "ax_g,ay_g,az_g,hx_g,hy_g,hz_g,"
               "mx,my,mz,rpm_gyro,accel_mag_g,hg_mag_g,gyro_clipped\n";

  uint16_t start = (triggerIndex + RING_SIZE - PRE_TRIGGER) % RING_SIZE;

  for (int i = 0; i < RING_SIZE; i++) {
    uint16_t idx = (start + i) % RING_SIZE;
    RawSample* s = &ring[idx];

    float gx = s->gx * GYRO_SENS;
    float gy = s->gy * GYRO_SENS;
    float gz = s->gz * GYRO_SENS;
    float ax = s->ax * ACCEL_SENS;
    float ay = s->ay * ACCEL_SENS;
    float az = s->az * ACCEL_SENS;
    float hx = s->hx * HG_SENS;
    float hy = s->hy * HG_SENS;
    float hz = s->hz * HG_SENS;
    float mx = s->mx * MAG_SENS;
    float my = s->my * MAG_SENS;
    float mz = s->mz * MAG_SENS;
    float rpm = fabsf(gz) / 6.0f;
    float amag = sqrtf(ax*ax + ay*ay + az*az);
    float hmag = sqrtf(hx*hx + hy*hy + hz*hz);
    int clipped = (abs(s->gz) > 32000) ? 1 : 0;
    int sn = i - PRE_TRIGGER;

    char line[256];
    snprintf(line, sizeof(line),
      "%d,%lu,%.1f,%.1f,%.1f,%.4f,%.4f,%.4f,%.1f,%.1f,%.1f,%.4f,%.4f,%.4f,%.1f,%.2f,%.1f,%d\n",
      sn, s->timestamp_us,
      gx, gy, gz, ax, ay, az, hx, hy, hz, mx, my, mz,
      rpm, amag, hmag, clipped);
    csv += line;
  }

  server.sendHeader("Content-Disposition", "attachment; filename=throw.csv");
  server.send(200, "text/csv", csv);
}

void handleThrow() {
  if (!hasLastThrow) {
    server.send(200, "application/json", "{\"valid\":false}");
    return;
  }
  const ThrowMetrics& m = lastMetrics;
  char buf[512];
  snprintf(buf, sizeof(buf),
    "{\"valid\":%s,\"rpm\":%.1f,"
    "\"mph\":%.2f,\"peak_g\":%.2f,"
    "\"launch_hyzer\":%.1f,\"launch_nose\":%.1f,"
    "\"wobble\":%.1f,\"duration_ms\":%lu,"
    "\"release_idx\":%d,\"motion_start_idx\":%d,\"stationary_end\":%d,"
    "\"ts\":%lu}",
    m.valid ? "true" : "false",
    m.rpm, m.mph, m.peak_accel_g,
    m.launch_hyzer_deg, m.launch_nose_deg, m.wobble_deg,
    (unsigned long)m.duration_ms,
    m.release_index, m.motion_start_index, m.stationary_end,
    (unsigned long)millis());
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", buf);
}

void handleCalDump() {
  // Stream every raw sample as CSV. Chunked so we don't build a giant String.
  server.sendHeader("Content-Disposition", "attachment; filename=cal.csv");
  server.setContentLength(CONTENT_LENGTH_UNKNOWN);
  server.send(200, "text/csv", "");
  server.sendContent(
    "idx,time_ms,raw_ax,raw_ay,raw_az,raw_gx,raw_gy,raw_gz,"
    "ax_g,ay_g,az_g,gz_dps,omega2,axy_ms2,rpm_gyro,r_implied_mm\n");

  char line[192];
  for (uint16_t i = 0; i < calCount; i++) {
    float ax_g = calRawAx[i] * ACCEL_SENS;
    float ay_g = calRawAy[i] * ACCEL_SENS;
    float az_g = calRawAz[i] * ACCEL_SENS;
    float gz_dps = calRawGz[i] * GYRO_SENS;
    float o2 = calOmega2[i];
    float axy = calAccel[i];
    float rpm = sqrtf(o2) * 60.0f / (2.0f * M_PI);
    float r_mm = (o2 > 1e-6f) ? (axy / o2 * 1000.0f) : 0.0f;
    snprintf(line, sizeof(line),
      "%u,%lu,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.1f,%.3f,%.3f,%.1f,%.2f\n",
      i, (unsigned long)calTimeMs[i],
      calRawAx[i], calRawAy[i], calRawAz[i],
      calRawGx[i], calRawGy[i], calRawGz[i],
      ax_g, ay_g, az_g, gz_dps,
      o2, axy, rpm, r_mm);
    server.sendContent(line);
  }

  // Footer with both regressions
  double sumX_lin=0, sumY_lin=0, sumXY_lin=0, sumX2_lin=0;
  double sumX_sq=0, sumY_sq=0, sumXY_sq=0, sumX2_sq=0;
  for (uint16_t i = 0; i < calCount; i++) {
    double o2 = calOmega2[i];
    double a  = calAccel[i];
    sumX_lin  += o2;
    sumY_lin  += a;
    sumXY_lin += o2 * a;
    sumX2_lin += o2 * o2;
    double o4 = o2 * o2;
    double a2 = a * a;
    sumX_sq  += o4;
    sumY_sq  += a2;
    sumXY_sq += o4 * a2;
    sumX2_sq += o4 * o4;
  }
  double n = calCount;
  double lin_slope = 0, sq_slope_r2 = 0, sq_r = 0;
  if (n > 1) {
    double d = n * sumX2_lin - sumX_lin * sumX_lin;
    if (fabs(d) > 1e-12) lin_slope = (n * sumXY_lin - sumX_lin * sumY_lin) / d;
    double d2 = n * sumX2_sq - sumX_sq * sumX_sq;
    if (fabs(d2) > 1e-12) sq_slope_r2 = (n * sumXY_sq - sumX_sq * sumY_sq) / d2;
    if (sq_slope_r2 > 0) sq_r = sqrt(sq_slope_r2);
  }
  snprintf(line, sizeof(line),
    "# n=%u lin_slope_m=%.6f sq_slope_m=%.6f\n",
    calCount, lin_slope, sq_r);
  server.sendContent(line);
  server.sendContent("");  // end chunked
}

void handleDebugLog() {
  String out = "[";
  for (uint8_t i = 0; i < debugLogCount; i++) {
    uint8_t idx = (debugLogHead - debugLogCount + i + DEBUG_LOG_SIZE) % DEBUG_LOG_SIZE;
    if (i > 0) out += ",";
    out += "\"";
    // Escape quotes in message
    for (int j = 0; debugLog[idx][j] && j < DEBUG_MSG_LEN; j++) {
      if (debugLog[idx][j] == '"') out += "\\\"";
      else out += debugLog[idx][j];
    }
    out += "\"";
  }
  out += "]";
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", out);
}

void handleImuDiag() {
  ImuDiag d = readImuDiag();
  const char* fsgName = "?";
  switch (d.ctrl6 & 0x0F) {
    case 0x0: fsgName = "125 dps"; break;
    case 0x1: fsgName = "250 dps"; break;
    case 0x2: fsgName = "500 dps"; break;
    case 0x3: fsgName = "1000 dps"; break;
    case 0x4: fsgName = "2000 dps"; break;
    case 0x5: fsgName = "4000 dps"; break;
  }
  const char* fsxlName = "?";
  switch (d.ctrl8 & 0x03) {
    case 0x0: fsxlName = "2 g"; break;
    case 0x1: fsxlName = "4 g"; break;
    case 0x2: fsxlName = "8 g"; break;
    case 0x3: fsxlName = "16 g"; break;
  }
  char buf[900];
  snprintf(buf, sizeof(buf),
    "{\"whoami\":\"0x%02X\",\"expected\":\"0x73\","
    "\"ctrl1\":\"0x%02X\",\"ctrl2\":\"0x%02X\",\"ctrl3\":\"0x%02X\","
    "\"ctrl4\":\"0x%02X\",\"ctrl5\":\"0x%02X\","
    "\"ctrl6\":\"0x%02X\",\"ctrl8\":\"0x%02X\","
    "\"ctrl9\":\"0x%02X\",\"ctrl10\":\"0x%02X\","
    "\"ctrl1_xl_hg\":\"0x%02X\","
    "\"odr_xl\":\"0x%X\",\"op_xl\":%d,"
    "\"odr_g\":\"0x%X\",\"op_g\":%d,"
    "\"fs_g\":\"%s\",\"fs_xl\":\"%s\","
    "\"cal_raw_ax_max\":%d,\"cal_raw_ay_max\":%d,\"cal_raw_az_max\":%d,"
    "\"cal_raw_gx_max\":%d,\"cal_raw_gy_max\":%d,\"cal_raw_gz_max\":%d,"
    "\"cal_axy_max\":%.2f,\"cal_rpm_max\":%.1f}",
    d.whoami, d.ctrl1, d.ctrl2, d.ctrl3, d.ctrl4, d.ctrl5,
    d.ctrl6, d.ctrl8, d.ctrl9, d.ctrl10, d.ctrl1_xl_hg,
    d.ctrl1 & 0x0F, (d.ctrl1 >> 4) & 0x07,
    d.ctrl2 & 0x0F, (d.ctrl2 >> 4) & 0x07,
    fsgName, fsxlName,
    calRawAxAbsMax, calRawAyAbsMax, calRawAzAbsMax,
    calRawGxAbsMax, calRawGyAbsMax, calRawGzAbsMax,
    calAxyMax, calRpmMax);
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", buf);
}

void handleSettings() {
  if (server.method() == HTTP_POST) {
    if (server.hasArg("auto_arm")) {
      String v = server.arg("auto_arm");
      autoArm = (v == "1" || v == "true");
    }
    if (server.hasArg("trigger_g")) {
      float v = server.arg("trigger_g").toFloat();
      if (v >= 1.0f && v <= 10.0f) triggerG = v;
    }
    saveSettings();
  }
  char buf[128];
  snprintf(buf, sizeof(buf),
    "{\"auto_arm\":%s,\"trigger_g\":%.2f}",
    autoArm ? "true" : "false", triggerG);
  server.send(200, "application/json", buf);
}

void handleEisTest() {
  // Enable EIS gyro at 4000 dps, route to OIS output registers
  // CTRL_EIS (0x6B):
  //   [2:0] fs_g_eis = 5 (4000 dps per enum)
  //   [3]   g_eis_on_g_ois_out_reg = 1 (route EIS to OIS output regs)
  //   [4]   lpf_g_eis_bw = 0
  //   [5]   reserved = 0
  //   [7:6] odr_g_eis = 10 (960 Hz)
  #define CTRL_EIS 0x6B
  #define OUTX_L_G_OIS_EIS 0x2E

  // Also set main UI FS to 5 (required per ST docs for EIS 4000)
  writeReg(IMU_ADDR, CTRL2, 0x00); delay(10);
  writeReg(IMU_ADDR, CTRL6, 0x05); delay(10);
  writeReg(IMU_ADDR, CTRL2, 0x09); delay(10);

  // Enable EIS: fs_g_eis=5, route_to_ois=1, odr=960Hz
  // 10_0_0_1_101 = 0x8D
  writeReg(IMU_ADDR, CTRL_EIS, 0x8D);
  delay(50);

  uint8_t eis_reg = readReg(IMU_ADDR, CTRL_EIS);

  // Read main gyro (0x22) and EIS gyro (0x2E) simultaneously
  uint8_t main_buf[6], eis_buf[6];
  readRegs(IMU_ADDR, OUTX_L_G, main_buf, 6);
  readRegs(IMU_ADDR, OUTX_L_G_OIS_EIS, eis_buf, 6);

  int16_t main_gz = (int16_t)(main_buf[5] << 8 | main_buf[4]);
  int16_t eis_gz = (int16_t)(eis_buf[5] << 8 | eis_buf[4]);
  int16_t main_gx = (int16_t)(main_buf[1] << 8 | main_buf[0]);
  int16_t eis_gx = (int16_t)(eis_buf[1] << 8 | eis_buf[0]);

  char buf[300];
  snprintf(buf, sizeof(buf),
    "{\"eis_ctrl\":\"0x%02X\",\"main_gz\":%d,\"eis_gz\":%d,"
    "\"main_gx\":%d,\"eis_gx\":%d,"
    "\"main_gz_dps\":%.1f,\"eis_gz_dps_at2000\":%.1f,\"eis_gz_dps_at4000\":%.1f,"
    "\"ratio\":%.3f}",
    eis_reg, main_gz, eis_gz, main_gx, eis_gx,
    main_gz * 0.070f, eis_gz * 0.070f, eis_gz * 0.140f,
    (main_gz != 0) ? (float)eis_gz / main_gz : 0.0f);
  debugMsg("EIS test: main_gz=%d eis_gz=%d ratio=%.3f", main_gz, eis_gz,
    (main_gz != 0) ? (float)eis_gz / main_gz : 0.0f);
  server.send(200, "application/json", buf);
}

void handleSetFsG() {
  if (!server.hasArg("v")) {
    server.send(400, "application/json", "{\"error\":\"need ?v=0-7\"}");
    return;
  }
  int rawVal = server.arg("v").toInt();

  if (rawVal == 99) {
    // Special: write 0x4C directly to CTRL2 (datasheet method)
    // This puts FS_G bits in CTRL2 like the older LSM6DSL layout
    writeReg(IMU_ADDR, CTRL2, 0x00); delay(10);  // power down
    writeReg(IMU_ADDR, CTRL2, 0x4C); delay(10);  // 0x4C per datasheet
    uint8_t rb2 = readReg(IMU_ADDR, CTRL2);
    uint8_t rb6 = readReg(IMU_ADDR, CTRL6);
    char buf[150];
    snprintf(buf, sizeof(buf),
      "{\"method\":\"ctrl2_direct\",\"ctrl2\":\"0x%02X\",\"ctrl6\":\"0x%02X\"}", rb2, rb6);
    debugMsg("CTRL2 direct write 0x4C, readback CTRL2=0x%02X CTRL6=0x%02X", rb2, rb6);
    server.send(200, "application/json", buf);
    return;
  }

  uint8_t val = rawVal & 0x0F;
  // Power down gyro, write FS to CTRL6, power back up
  writeReg(IMU_ADDR, CTRL2, 0x00);
  delay(10);
  writeReg(IMU_ADDR, CTRL6, val);
  delay(10);
  writeReg(IMU_ADDR, CTRL2, 0x09);
  delay(10);
  uint8_t readback = readReg(IMU_ADDR, CTRL6);
  char buf[100];
  snprintf(buf, sizeof(buf),
    "{\"wrote\":\"0x%02X\",\"ctrl6\":\"0x%02X\",\"fs_g\":%d}",
    val, readback, readback & 0x0F);
  debugMsg("FS_G set to %d, readback 0x%02X", val, readback);
  server.send(200, "application/json", buf);
}

void handleCalStart() {
  calCount = 0;
  calRpmMin = 9999;
  calRpmMax = 0;
  calAxyMax = 0;
  calRawAxAbsMax = calRawAyAbsMax = calRawAzAbsMax = 0;
  calRawGxAbsMax = calRawGyAbsMax = calRawGzAbsMax = 0;
  lastCalSample = 0;
  state = CALIBRATING;
  server.send(200, "application/json",
    "{\"msg\":\"Calibrating \\u2014 vary spin 200\\u2013600 RPM for best fit\"}");
}

void handleCalStop() {
  float newRadius = computeRadius();
  bool accepted = (calCount >= 20 && (calRpmMax - calRpmMin) >= 100 && newRadius > 0);
  if (accepted) {
    calRadius = newRadius;
    saveCalRadius();
  }
  state = IDLE;
  char buf[256];
  snprintf(buf, sizeof(buf),
    "{\"msg\":\"%s: %d pts, %.0f\\u2013%.0f RPM (span %.0f), r=%.1f mm\","
    "\"radius\":%.6f,\"points\":%d,\"rpm_min\":%.0f,\"rpm_max\":%.0f,\"accepted\":%s}",
    accepted ? "Calibration saved" : "Rejected (need 20+ pts & 100 RPM span)",
    calCount, calRpmMin, calRpmMax, calRpmMax - calRpmMin, newRadius * 1000.0f,
    calRadius, calCount, calRpmMin, calRpmMax,
    accepted ? "true" : "false");
  server.send(200, "application/json", buf);
  Serial.printf("[CAL] %d pts %.0f-%.0f RPM r=%.2f mm %s\n",
    calCount, calRpmMin, calRpmMax, newRadius * 1000.0f,
    accepted ? "SAVED" : "REJECTED");
}

// ─── Live polling endpoint ──────────────────────────────────

void handleLive() {
  char buf[700];
  float rpmMin = (calCount > 0) ? calRpmMin : 0;
  float ax_g = live.ax * ACCEL_SENS;
  float ay_g = live.ay * ACCEL_SENS;
  float az_g = live.az * ACCEL_SENS;
  float gx_dps = live.gx * GYRO_SENS;
  float gy_dps = live.gy * GYRO_SENS;
  float gz_dps = live.gz * GYRO_SENS;
  snprintf(buf, sizeof(buf),
    "{\"rpm_gyro\":%.1f,\"rpm_accel\":%.1f,"
    "\"accel_g\":%.2f,\"hg_g\":%.1f,"
    "\"hyzer\":%.1f,\"nose\":%.1f,"
    "\"gyro_clipped\":%s,"
    "\"state\":\"%s\",\"samples\":%d,"
    "\"calPts\":%d,\"calTarget\":200,"
    "\"calRpmMin\":%.0f,\"calRpmMax\":%.0f,"
    "\"radius\":%.6f,"
    "\"raw_ax\":%d,\"raw_ay\":%d,\"raw_az\":%d,"
    "\"raw_gx\":%d,\"raw_gy\":%d,\"raw_gz\":%d,"
    "\"raw_hx\":%d,\"raw_hy\":%d,\"raw_hz\":%d,"
    "\"ax_g\":%.3f,\"ay_g\":%.3f,\"az_g\":%.3f,"
    "\"gx_dps\":%.1f,\"gy_dps\":%.1f,\"gz_dps\":%.1f}",
    liveRpmGyro, liveRpmAccel,
    liveAccelG, liveHgG,
    liveHyzer, liveNose,
    liveClipped ? "true" : "false",
    stateNames[state], RING_SIZE,
    calCount, rpmMin, calRpmMax,
    calRadius,
    live.ax, live.ay, live.az, live.gx, live.gy, live.gz,
    live.hx, live.hy, live.hz,
    ax_g, ay_g, az_g, gx_dps, gy_dps, gz_dps);
  server.sendHeader("Cache-Control", "no-store");
  server.send(200, "application/json", buf);
}
