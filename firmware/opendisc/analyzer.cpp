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
  m.mph = -1;
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

  // Also track the "quietest" window in case no perfect stationary is found
  float quietScore[16] = {};  // rolling score for 16-sample windows
  int quietIdx = 0;
  float bestQuietScore = 1e9f;
  int bestQuietEnd = -1;

  for (uint16_t i = 0; i < ringSize; i++) {
    const RawSample& s = at(i);

    // Peak RPM (gyro or accel fallback)
    float rpm = sampleRpm(s, cal);
    if (rpm > peakRpm) peakRpm = rpm;

    // Peak accel
    float g = accelMagG(s);
    if (g > peakG) peakG = g;

    // Stationary window detection (strict)
    if (stationaryEnd < 0) {
      float w = omegaMagDps(s);
      bool still = (w < STATIONARY_OMEGA_DPS) &&
                   (g >= STATIONARY_G_MIN) && (g <= STATIONARY_G_MAX);
      if (still) {
        run++;
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

      // Track quietest 16-sample window (fallback if no perfect stationary)
      if (i < preTrigger) {  // only in pre-trigger region
        float score = w + fabsf(g - 1.0f) * 100.0f;  // penalize non-1g
        quietScore[quietIdx % 16] = score;
        quietIdx++;
        if (quietIdx >= 16) {
          float avg = 0;
          for (int j = 0; j < 16; j++) avg += quietScore[j];
          avg /= 16.0f;
          if (avg < bestQuietScore) {
            bestQuietScore = avg;
            bestQuietEnd = i;
          }
        }
      }
    } else if (motionStart < 0) {
      if (omegaMagDps(s) > MOTION_START_DPS) motionStart = i;
    }
  }

  // Fallback: use quietest 16-sample window if no perfect stationary found
  if (stationaryEnd < 0 && bestQuietEnd >= 15) {
    stationaryEnd = bestQuietEnd;
    // Compute bias from this quieter window
    gyroBias = {0,0,0};
    biasCount = 0;
    for (int i = bestQuietEnd - 15; i <= bestQuietEnd; i++) {
      const RawSample& s = at(i);
      gyroBias.x += s.gx * GYRO_SENS;
      gyroBias.y += s.gy * GYRO_SENS;
      gyroBias.z += s.gz * GYRO_SENS;
      biasCount++;
    }
  }

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
    m.rpm = sampleRpm(rs, cal);

    // Accel-based angles as fallback (centripetal-corrected).
    // Overwritten by quaternion if strapdown succeeds.
    {
      bool clip;
      Vec3 a = getAccelMs2(rs, &clip);
      Vec3 w = getGyroRads(rs, gyroBias);
      float w2 = w.x*w.x + w.y*w.y + w.z*w.z;
      float ax_c = a.x - w2 * cal.rx;
      float ay_c = a.y - w2 * cal.ry;
      m.launch_hyzer_deg = atan2f(ay_c, a.z) * 180.0f / (float)M_PI;
      m.launch_nose_deg = atan2f(-ax_c, sqrtf(ay_c*ay_c + a.z*a.z)) * 180.0f / (float)M_PI;
    }

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
    m.mph = vmag * 2.23694f;

    // Launch angle: vertical angle of the velocity vector at release.
    // Positive = throwing up, negative = throwing down. 0 means flat.
    // Only meaningful when horizontal speed is nonzero.
    {
      float hspd = sqrtf(vx*vx + vy*vy);
      if (hspd > 0.1f) {
        m.launch_angle_deg = atan2f(vz, hspd) * 180.0f / (float)M_PI;
      }
    }

    // Launch angles relative to the THROW DIRECTION, not body axes.
    // This makes angles independent of how the chip is mounted on the disc.
    //
    // 1. disc_normal = R(q) * (0,0,1) = disc's "up" in world frame
    // 2. throw_fwd = normalize(vx, vy, 0) = horizontal flight direction
    // 3. throw_right = cross(throw_fwd, world_up)
    //
    // Decompose disc_normal into the throw frame:
    //   n_fwd   = dot(disc_normal, throw_fwd)   -> nose component
    //   n_right = dot(disc_normal, throw_right)  -> hyzer component
    //   n_up    = dot(disc_normal, world_up)     -> vertical component
    //
    // hyzer = atan2(-n_right, n_up)  (positive = left edge down from thrower POV)
    // nose  = atan2(-n_fwd, n_up)    (positive = nose up)

    Vec3 discN = qRotate(q, {0, 0, 1});

    float hspd = sqrtf(vx*vx + vy*vy);
    if (hspd > 0.5f) {  // need meaningful horizontal velocity
      float fwd_x = vx / hspd;
      float fwd_y = vy / hspd;
      // throw_right = cross((fwd_x, fwd_y, 0), (0, 0, 1)) = (fwd_y, -fwd_x, 0)
      float right_x = fwd_y;
      float right_y = -fwd_x;

      float n_fwd   = discN.x * fwd_x   + discN.y * fwd_y;    // dot with forward
      float n_right = discN.x * right_x + discN.y * right_y;  // dot with right
      float n_up    = discN.z;                                  // dot with (0,0,1)

      m.launch_hyzer_deg = atan2f(-n_right, n_up) * 180.0f / (float)M_PI;
      m.launch_nose_deg  = atan2f(-n_fwd, n_up)   * 180.0f / (float)M_PI;
    }
    // else: keep accel-based fallback angles from Pass 2
  }

  m.valid = (release >= 0);
  return m;
}
