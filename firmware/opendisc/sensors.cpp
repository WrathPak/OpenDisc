#include "sensors.h"

void writeReg(uint8_t addr, uint8_t reg, uint8_t val) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(val);
  Wire.endTransmission();
}

uint8_t readReg(uint8_t addr, uint8_t reg) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(addr, (uint8_t)1);
  return Wire.read();
}

void readRegs(uint8_t addr, uint8_t reg, uint8_t* buf, uint8_t len) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.endTransmission(false);
  Wire.requestFrom(addr, len);
  for (uint8_t i = 0; i < len && Wire.available(); i++) {
    buf[i] = Wire.read();
  }
}

bool scanAndVerify() {
  bool ok = true;
  Wire.beginTransmission(IMU_ADDR);
  if (Wire.endTransmission() != 0) {
    Serial.println("[FAIL] No IMU at 0x6A");
    ok = false;
  } else {
    uint8_t id = readReg(IMU_ADDR, WHO_AM_I);
    Serial.printf("[OK] IMU 0x6A WHO_AM_I=0x%02X\n", id);
  }
  Wire.beginTransmission(MAG_ADDR);
  if (Wire.endTransmission() != 0) {
    Serial.println("[FAIL] No Mag at 0x1C");
    ok = false;
  } else {
    uint8_t id = readReg(MAG_ADDR, MAG_WHO_AM_I);
    Serial.printf("[OK] Mag 0x1C WHO_AM_I=0x%02X\n", id);
  }
  return ok;
}

bool initIMU() {
  // LSM6DSV320X register config:
  //   CTRL1/CTRL2: [3:0]=ODR (0x9=960Hz), [6:4]=OP_MODE (0=HP)
  //   CTRL6: [2:0]=FS_G, [3]=must be 1 (default), [6:4]=LPF1_G_BW
  //          Write 0x0D for ±4000 dps (FS_G=5 + bit3 preserved)
  //          ST driver bug: enum says 0x5 but that clears bit3, capping at 2000
  //   CTRL8: [1:0]=FS_XL (0x3=±16g)
  //   CTRL1_XL_HG: [2:0]=FS_HG, [5:3]=ODR_HG, [7]=regout_en
  //
  // FS_G change requires gyro power-down (ODR_G=0) first.

  writeReg(IMU_ADDR, CTRL3, 0x44);           // BDU + IF_INC
  delay(10);

  // Accel: 960 Hz HP, ±16g
  writeReg(IMU_ADDR, CTRL1, 0x09);           // ODR_XL=0x9 (960Hz), OP_MODE_XL=HP
  delay(10);
  writeReg(IMU_ADDR, CTRL8, 0x03);           // FS_XL=±16g
  delay(10);

  // Gyro FS change requires power-down first
  writeReg(IMU_ADDR, CTRL2, 0x00);           // power down to change FS
  delay(10);
  writeReg(IMU_ADDR, CTRL6, 0x0D);           // FS_G=5 (±4000 dps) + bit3=1
  delay(10);
  writeReg(IMU_ADDR, CTRL2, 0x09);           // ODR_G=0x9 (960Hz), OP_MODE_G=HP
  delay(10);

  // HG accel: 960 Hz, ±320g, output enabled
  // 1 0 100 100 = 0xA4
  writeReg(IMU_ADDR, CTRL1_XL_HG, 0xA4);
  delay(10);

  uint8_t c1  = readReg(IMU_ADDR, CTRL1);
  uint8_t c2  = readReg(IMU_ADDR, CTRL2);
  uint8_t c6  = readReg(IMU_ADDR, CTRL6);
  uint8_t c8  = readReg(IMU_ADDR, CTRL8);
  uint8_t chg = readReg(IMU_ADDR, CTRL1_XL_HG);
  Serial.printf("[IMU] CTRL1=0x%02X CTRL2=0x%02X CTRL6=0x%02X CTRL8=0x%02X HG=0x%02X\n",
                c1, c2, c6, c8, chg);
  Serial.printf("[IMU]  ODR_XL=0x%X OP_XL=%d | ODR_G=0x%X OP_G=%d | FS_G=0x%X FS_XL=%d\n",
                c1 & 0x0F, (c1 >> 4) & 0x07,
                c2 & 0x0F, (c2 >> 4) & 0x07,
                c6 & 0x0F, c8 & 0x03);
  return true;
}

bool initMag() {
  writeReg(MAG_ADDR, MAG_CTRL1, 0x7C);
  delay(10);
  writeReg(MAG_ADDR, MAG_CTRL2, 0x00);
  delay(10);
  writeReg(MAG_ADDR, MAG_CTRL3, 0x00);
  delay(10);
  writeReg(MAG_ADDR, MAG_CTRL4, 0x0C);
  delay(10);
  return true;
}

ImuDiag readImuDiag() {
  ImuDiag d;
  d.whoami     = readReg(IMU_ADDR, WHO_AM_I);
  d.ctrl1      = readReg(IMU_ADDR, CTRL1);
  d.ctrl2      = readReg(IMU_ADDR, CTRL2);
  d.ctrl3      = readReg(IMU_ADDR, CTRL3);
  d.ctrl4      = readReg(IMU_ADDR, CTRL4);
  d.ctrl5      = readReg(IMU_ADDR, CTRL5);
  d.ctrl6      = readReg(IMU_ADDR, CTRL6);
  d.ctrl8      = readReg(IMU_ADDR, CTRL8);
  d.ctrl9      = readReg(IMU_ADDR, CTRL9);
  d.ctrl10     = readReg(IMU_ADDR, CTRL10);
  d.ctrl1_xl_hg = readReg(IMU_ADDR, CTRL1_XL_HG);
  return d;
}

void readSample(RawSample* s) {
  uint8_t buf[6];
  s->timestamp_us = micros();

  readRegs(IMU_ADDR, OUTX_L_G, buf, 6);
  s->gx = (int16_t)(buf[1] << 8 | buf[0]);
  s->gy = (int16_t)(buf[3] << 8 | buf[2]);
  s->gz = (int16_t)(buf[5] << 8 | buf[4]);

  readRegs(IMU_ADDR, OUTX_L_A, buf, 6);
  s->ax = (int16_t)(buf[1] << 8 | buf[0]);
  s->ay = (int16_t)(buf[3] << 8 | buf[2]);
  s->az = (int16_t)(buf[5] << 8 | buf[4]);

  readRegs(IMU_ADDR, OUTX_L_HG, buf, 6);
  s->hx = (int16_t)(buf[1] << 8 | buf[0]);
  s->hy = (int16_t)(buf[3] << 8 | buf[2]);
  s->hz = (int16_t)(buf[5] << 8 | buf[4]);

  readRegs(MAG_ADDR, MAG_OUT_X_L, buf, 6);
  s->mx = (int16_t)(buf[1] << 8 | buf[0]);
  s->my = (int16_t)(buf[3] << 8 | buf[2]);
  s->mz = (int16_t)(buf[5] << 8 | buf[4]);
}
