#ifndef ANALYZER_H
#define ANALYZER_H

#include "sensors.h"

#define STATIONARY_WINDOW      32
#define STATIONARY_OMEGA_DPS   15.0f
#define STATIONARY_G_MIN       0.85f
#define STATIONARY_G_MAX       1.15f
#define MOTION_START_DPS       30.0f
#define RELEASE_G_THRESHOLD    1.5f
#define RELEASE_HOLD_SAMPLES   8
#define RELEASE_MIN_SPIN_DPS   60.0f
#define MAIN_ACCEL_CLIP_RAW    32000
#define GYRO_CLIP_RAW          28000    // ~3920 dps at 140 mdps/LSB ≈ 653 RPM
#define SAMPLE_DT_S            (1.0f / 960.0f)
#define GRAVITY_MS2            9.80665f

struct CalVector {
  float rx, ry;      // chip body-frame position from disc center (m)
  float radius;      // |r| = sqrt(rx²+ry²)
};

ThrowMetrics analyzeThrow(const RawSample* ring,
                          uint16_t ringSize,
                          uint16_t triggerIndex,
                          uint16_t preTrigger,
                          const CalVector& cal);

#endif
