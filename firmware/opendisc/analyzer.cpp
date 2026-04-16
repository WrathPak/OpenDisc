#include "analyzer.h"
#include <Arduino.h>
#include <math.h>

struct Vec3 { float x, y, z; };
struct Quat { float w, x, y, z; };

static inline Quat qMul(const Quat& a, const Quat& b) {
  return {
    a.w*b.w - a.x*b.x - a.y*b.y - a.z*b.z,
    a.w*b.x + a.x*b.w + a.y*b.z - a.z*b.y,
    a.w*b.y - a.x*b.z + a.y*b.w + a.z*b.x,
    a.w*b.z + a.x*b.y - a.y*b.x + a.z*b.w
  };
}

static inline void qNormalize(Quat& q) {
  float n = sqrtf(q.w*q.w + q.x*q.x + q.y*q.y + q.z*q.z);
  if (n > 1e-9f) { q.w/=n; q.x/=n; q.y/=n; q.z/=n; }
}

static inline Vec3 qRotate(const Quat& q, const Vec3& v) {
  float ww = q.w*q.w, xx = q.x*q.x, yy = q.y*q.y, zz = q.z*q.z;
  float wx = q.w*q.x, wy = q.w*q.y, wz = q.w*q.z;
  float xy = q.x*q.y, xz = q.x*q.z, yz = q.y*q.z;
  return {
    v.x*(ww+xx-yy-zz) + 2.0f*(v.y*(xy-wz) + v.z*(xz+wy)),
    v.y*(ww-xx+yy-zz) + 2.0f*(v.x*(xy+wz) + v.z*(yz-wx)),
    v.z*(ww-xx-yy+zz) + 2.0f*(v.x*(xz-wy) + v.y*(yz+wx))
  };
}

static Quat qFromGravity(float bx, float by, float bz) {
  float n = sqrtf(bx*bx + by*by + bz*bz);
  if (n < 1e-6f) return {1,0,0,0};
  bx/=n; by/=n; bz/=n;
  float dot = bz;
  if (dot > 0.9999f) return {1,0,0,0};
  if (dot < -0.9999f) return {0,1,0,0};
  float ax = by, ay = -bx;
  float an = sqrtf(ax*ax + ay*ay);
  if (an < 1e-9f) return {1,0,0,0};
  ax/=an; ay/=an;
  float angle = acosf(dot);
  float s = sinf(angle*0.5f);
  return { cosf(angle*0.5f), ax*s, ay*s, 0.0f };
}

// Best accel: use main ±16g unless clipped, then HG ±320g
static Vec3 getAccelMs2(const RawSample& s, bool* clipped) {
  bool clip = (abs(s.ax) >= MAIN_ACCEL_CLIP_RAW ||
               abs(s.ay) >= MAIN_ACCEL_CLIP_RAW ||
               abs(s.az) >= MAIN_ACCEL_CLIP_RAW);
  if (clipped) *clipped = clip;
  if (clip) {
    return { s.hx * HG_SENS * GRAVITY_MS2,
             s.hy * HG_SENS * GRAVITY_MS2,
             s.hz * HG_SENS * GRAVITY_MS2 };
  }
  return { s.ax * ACCEL_SENS * GRAVITY_MS2,
           s.ay * ACCEL_SENS * GRAVITY_MS2,
           s.az * ACCEL_SENS * GRAVITY_MS2 };
}

// Gyro in rad/s from raw, with bias subtracted
static Vec3 getGyroRads(const RawSample& s, const Vec3& bias) {
  float dps2rad = (float)M_PI / 180.0f;
  return {
    (s.gx * GYRO_SENS - bias.x) * dps2rad,
    (s.gy * GYRO_SENS - bias.y) * dps2rad,
    (s.gz * GYRO_SENS - bias.z) * dps2rad
  };
}

// Total angular rate magnitude in dps
static float omegaMagDps(const RawSample& s) {
  float gx = s.gx * GYRO_SENS;
  float gy = s.gy * GYRO_SENS;
  float gz = s.gz * GYRO_SENS;
  return sqrtf(gx*gx + gy*gy + gz*gz);
}

static float accelMagG(const RawSample& s) {
  bool clip;
  Vec3 a = getAccelMs2(s, &clip);
  return sqrtf(a.x*a.x + a.y*a.y + a.z*a.z) / GRAVITY_MS2;
}

// Compute RPM from sample, using gyro when valid, accel fallback when clipped
static float sampleRpm(const RawSample& s, const CalVector& cal) {
  // Use total angular rate (all 3 axes) for best accuracy with slight chip misalignment
  float gx = s.gx * GYRO_SENS;
  float gy = s.gy * GYRO_SENS;
  float gz = s.gz * GYRO_SENS;
  float omega_dps = sqrtf(gx*gx + gy*gy + gz*gz);
  bool gyroClip = (abs(s.gx) > GYRO_CLIP_RAW ||
                   abs(s.gy) > GYRO_CLIP_RAW ||
                   abs(s.gz) > GYRO_CLIP_RAW);

  if (!gyroClip) {
    return omega_dps / 6.0f;
  }

  // Gyro clipped — fall back to accel-derived RPM
  if (cal.radius < 0.001f) return omega_dps / 6.0f;  // no cal, can't fall back
  bool clip;
  Vec3 a = getAccelMs2(s, &clip);
  float axy = sqrtf(a.x*a.x + a.y*a.y);
  float omega_rad = sqrtf(axy / cal.radius);
  return omega_rad * 60.0f / (2.0f * (float)M_PI);
}

ThrowMetrics analyzeThrow(const RawSample* ring,
                          uint16_t ringSize,
                          uint16_t triggerIndex,
                          uint16_t preTrigger,
                          const CalVector& cal) {
  ThrowMetrics m = {};
  m.release_mph = -1;
  m.release_index = -1;
  m.motion_start_index = -1;
  m.stationary_end = -1;
  m.valid = false;

  uint16_t start = (uint16_t)((triggerIndex + ringSize - preTrigger) % ringSize);
  auto at = [&](uint16_t i) -> const RawSample& {
    return ring[(start + i) % ringSize];
  };
  const uint16_t triggerLin = preTrigger;

  // ── Pass 1: peaks, stationary window, motion start, gyro bias ──
  float peakRpm = 0;
  float peakG = 0;
  int stationaryEnd = -1;
  int motionStart = -1;
  int run = 0;

  // Gyro bias: average gx/gy/gz over stationary window
  Vec3 gyroBias = {0, 0, 0};
  int biasCount = 0;

  for (uint16_t i = 0; i < ringSize; i++) {
    const RawSample& s = at(i);

    // Peak RPM (gyro or accel fallback)
    float rpm = sampleRpm(s, cal);
    if (rpm > peakRpm) peakRpm = rpm;

    // Peak accel
    float g = accelMagG(s);
    if (g > peakG) peakG = g;

    // Stationary window detection
    if (stationaryEnd < 0) {
      float w = omegaMagDps(s);
      bool still = (w < STATIONARY_OMEGA_DPS) &&
                   (g >= STATIONARY_G_MIN) && (g <= STATIONARY_G_MAX);
      if (still) {
        run++;
        // Accumulate gyro bias during stationary
        gyroBias.x += s.gx * GYRO_SENS;
        gyroBias.y += s.gy * GYRO_SENS;
        gyroBias.z += s.gz * GYRO_SENS;
        biasCount++;
        if (run >= STATIONARY_WINDOW) stationaryEnd = i;
      } else {
        run = 0;
        gyroBias = {0,0,0};
        biasCount = 0;
      }
    } else if (motionStart < 0) {
      if (omegaMagDps(s) > MOTION_START_DPS) motionStart = i;
    }
  }

  m.peak_rpm = peakRpm;
  m.peak_accel_g = peakG;
  m.stationary_end = stationaryEnd;
  m.motion_start_index = motionStart;

  // Finalize gyro bias (dps)
  if (biasCount > 0) {
    gyroBias.x /= biasCount;
    gyroBias.y /= biasCount;
    gyroBias.z /= biasCount;
  }

  // ── Pass 2: release detection (forward from trigger) ──
  // After release, arm centripetal disappears but disc-spin centripetal remains.
  // Subtract known disc-spin centripetal from |a_xy| before checking threshold.
  int release = -1;
  int belowRun = 0;
  for (int i = triggerLin; i < ringSize; i++) {
    const RawSample& s = at(i);
    bool clip;
    Vec3 a = getAccelMs2(s, &clip);

    // Subtract disc-spin centripetal from xy plane
    float wx = s.gx * GYRO_SENS * (float)M_PI / 180.0f;
    float wy = s.gy * GYRO_SENS * (float)M_PI / 180.0f;
    float wz = s.gz * GYRO_SENS * (float)M_PI / 180.0f;
    float w2 = wx*wx + wy*wy + wz*wz;
    float ax_corr = a.x - w2 * cal.rx;
    float ay_corr = a.y - w2 * cal.ry;
    float g_corr = sqrtf(ax_corr*ax_corr + ay_corr*ay_corr + a.z*a.z) / GRAVITY_MS2;

    float gz_dps = fabsf(s.gz * GYRO_SENS);
    if (g_corr < RELEASE_G_THRESHOLD && gz_dps > RELEASE_MIN_SPIN_DPS) {
      belowRun++;
      if (belowRun >= RELEASE_HOLD_SAMPLES) {
        release = i - RELEASE_HOLD_SAMPLES + 1;
        break;
      }
    } else {
      belowRun = 0;
    }
  }
  m.release_index = release;

  // Release-point metrics
  if (release >= 0) {
    const RawSample& rs = at(release);
    m.release_rpm = sampleRpm(rs, cal);

    // Launch angles computed from quaternion in Pass 3 (see below).
    // Placeholder values overwritten if strapdown succeeds.
    m.launch_hyzer_deg = 0;
    m.launch_nose_deg = 0;

    // Wobble: RMS of gx,gy over 100 ms (96 samples) after release
    double wob2 = 0;
    int n = 0;
    for (int i = release + 1; i < release + 97 && i < ringSize; i++) {
      const RawSample& s = at(i);
      float gx = s.gx * GYRO_SENS - gyroBias.x;
      float gy = s.gy * GYRO_SENS - gyroBias.y;
      wob2 += gx*gx + gy*gy;
      n++;
    }
    m.wobble_deg = (n > 0) ? sqrtf(wob2 / n) : 0;
  }

  // Duration
  if (motionStart >= 0 && release >= 0 && release > motionStart) {
    m.duration_ms = (uint32_t)((release - motionStart) * 1000.0f / 960.0f);
  }

  // ── Pass 3: strapdown integration for MPH ──
  // Computes disc CENTER-OF-MASS velocity by subtracting the chip's
  // centripetal acceleration from the measured body-frame accel before
  // rotating to world frame and integrating.
  if (stationaryEnd >= 0 && release >= 0 && release > stationaryEnd) {
    // Average gravity in body frame over stationary window
    float gbx = 0, gby = 0, gbz = 0;
    int n0 = 0;
    for (int i = stationaryEnd - STATIONARY_WINDOW + 1; i <= stationaryEnd; i++) {
      if (i < 0) continue;
      bool clip;
      Vec3 a = getAccelMs2(at(i), &clip);
      gbx += a.x; gby += a.y; gbz += a.z;
      n0++;
    }
    if (n0 > 0) { gbx/=n0; gby/=n0; gbz/=n0; }

    Quat q = qFromGravity(gbx, gby, gbz);

    float vx = 0, vy = 0, vz = 0;
    float prev_wz = 0;  // for angular accel estimation

    for (int i = stationaryEnd + 1; i <= release; i++) {
      const RawSample& s = at(i);

      // Bias-corrected gyro in rad/s
      Vec3 w = getGyroRads(s, gyroBias);
      float wn = sqrtf(w.x*w.x + w.y*w.y + w.z*w.z);

      // Propagate orientation quaternion
      Quat dq;
      if (wn * SAMPLE_DT_S < 1e-6f) {
        dq = {1, 0.5f*w.x*SAMPLE_DT_S, 0.5f*w.y*SAMPLE_DT_S, 0.5f*w.z*SAMPLE_DT_S};
      } else {
        float theta = wn * SAMPLE_DT_S * 0.5f;
        float sOverW = sinf(theta) / wn;
        dq = { cosf(theta), w.x*sOverW, w.y*sOverW, w.z*sOverW };
      }
      q = qMul(q, dq);
      qNormalize(q);

      // Best body-frame acceleration (main or HG fallback)
      bool clip;
      Vec3 aBody = getAccelMs2(s, &clip);

      // Subtract chip's non-CM acceleration in body frame:
      //   a_chip = a_cm + centripetal + tangential
      //   centripetal_body = -ω² × r_body (pointing from chip toward CM)
      //   tangential_body = α × r_perp (angular accel × tangential direction)
      if (cal.radius > 0.001f) {
        // ω² using total angular rate for accuracy
        float w2 = w.x*w.x + w.y*w.y + w.z*w.z;  // (rad/s)²

        // Centripetal correction: subtract ω²·r pointing outward from CM
        // (chip measures extra accel in the radial direction)
        aBody.x -= w2 * cal.rx;
        aBody.y -= w2 * cal.ry;

        // Tangential correction: α × r_perp where α = dω/dt
        // r_perp (tangential to radial) = (-ry, rx) / |r| × |r| = (-ry, rx)
        float alpha_z = (w.z - prev_wz) / SAMPLE_DT_S;  // angular accel (z component)
        aBody.x -= alpha_z * (-cal.ry);
        aBody.y -= alpha_z * (cal.rx);
      }
      prev_wz = w.z;

      // Rotate corrected body accel to world frame and subtract gravity
      Vec3 aWorld = qRotate(q, aBody);
      aWorld.z -= GRAVITY_MS2;

      // Integrate velocity
      vx += aWorld.x * SAMPLE_DT_S;
      vy += aWorld.y * SAMPLE_DT_S;
      vz += aWorld.z * SAMPLE_DT_S;
    }

    float vmag = sqrtf(vx*vx + vy*vy + vz*vz);
    m.release_mph = vmag * 2.23694f;

    // Launch angles from the orientation quaternion at release.
    // q maps body→world. The disc's body z-axis in world frame gives tilt:
    //   world_z_of_disc = R(q) * (0,0,1)
    // hyzer = roll = atan2(world_z.y, world_z.z)  (tilt around forward axis)
    // nose  = pitch = asin(-world_z.x)            (tilt around lateral axis)
    Vec3 discZ = qRotate(q, {0, 0, 1});
    m.launch_hyzer_deg = atan2f(discZ.y, discZ.z) * 180.0f / (float)M_PI;
    float clampX = discZ.x;
    if (clampX > 1.0f) clampX = 1.0f;
    if (clampX < -1.0f) clampX = -1.0f;
    m.launch_nose_deg = asinf(-clampX) * 180.0f / (float)M_PI;
  }

  m.valid = (release >= 0);
  return m;
}
