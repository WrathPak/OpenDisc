#ifndef SENSORS_H
#define SENSORS_H

#include <Arduino.h>
#include <Wire.h>

#define IMU_ADDR   0x6A
#define MAG_ADDR   0x1C

// LSM6DSV320X registers
#define WHO_AM_I       0x0F
#define CTRL1          0x10
#define CTRL2          0x11
#define CTRL3          0x12
#define CTRL4          0x13
#define CTRL5          0x14
#define CTRL6          0x15
#define CTRL8          0x17
#define CTRL9          0x18
#define CTRL10         0x19
#define CTRL1_XL_HG    0x4E
#define OUTX_L_G       0x22
#define OUTX_L_A       0x28
#define OUTX_L_HG      0x34  // UI_OUTX_L_A_OIS_HG (HG accel data)

// LIS3MDL registers
#define MAG_WHO_AM_I   0x0F
#define MAG_CTRL1      0x20
#define MAG_CTRL2      0x21
#define MAG_CTRL3      0x22
#define MAG_CTRL4      0x23
#define MAG_OUT_X_L    0x28

// Sensitivities
// LSM6DSV320X empirically caps at ±2000 dps — neither HP mode + CTRL6=0x5
// nor HA mode + CTRL6=0x5 unlocks 4000 dps, even though ST's driver claims
// 0x5 should give 4000 dps. Verified with 6 RPM hand rotation test: chip
// reports 2x expected rate when GYRO_SENS=0.140. So we stick with 2000 dps.
// Gyro ceiling = 333 RPM; above that, throw analyzer uses accel-derived RPM.
#define GYRO_SENS    0.070f     // ±2000 dps → 70 mdps/LSB
#define ACCEL_SENS   0.000488f  // ±16g → 0.488 mg/LSB
#define HG_SENS      0.00977f
#define MAG_SENS     (1.0f / 6842.0f)

struct RawSample {
  unsigned long timestamp_us;
  int16_t gx, gy, gz;
  int16_t ax, ay, az;
  int16_t hx, hy, hz;
  int16_t mx, my, mz;
};

struct ThrowMetrics {
  float peak_rpm;
  float release_rpm;
  float release_mph;       // -1 if integration failed
  float peak_accel_g;
  float launch_hyzer_deg;
  float launch_nose_deg;
  float wobble_deg;
  uint32_t duration_ms;
  int16_t release_index;       // -1 if not detected
  int16_t motion_start_index;  // -1 if not detected
  int16_t stationary_end;      // -1 if no stationary window
  bool valid;
};

struct ImuDiag {
  uint8_t whoami;
  uint8_t ctrl1;
  uint8_t ctrl2;
  uint8_t ctrl3;
  uint8_t ctrl4;
  uint8_t ctrl5;
  uint8_t ctrl6;
  uint8_t ctrl8;
  uint8_t ctrl9;
  uint8_t ctrl10;
  uint8_t ctrl1_xl_hg;
};

void writeReg(uint8_t addr, uint8_t reg, uint8_t val);
uint8_t readReg(uint8_t addr, uint8_t reg);
void readRegs(uint8_t addr, uint8_t reg, uint8_t* buf, uint8_t len);
bool scanAndVerify();
bool initIMU();
bool initMag();
void readSample(RawSample* s);
ImuDiag readImuDiag();

#endif
