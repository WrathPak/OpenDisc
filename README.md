# OpenDisc

Open source disc golf throw analyzer. About $40 in off-the-shelf parts.

## What it measures

- Release speed (MPH)
- Spin rate (RPM)
- Hyzer and nose angle at release
- Wobble
- Peak G-force

Detects your throw automatically, grabs a 1-second burst at 960 Hz, does the math on-device, and shows results on a web page or over BLE.

## Parts

| What | Part | Cost |
|---|---|---|
| MCU | ESP32-C6 Super Mini (4MB) | ~$5 |
| IMU | BerryIMU 320G (LSM6DSV320X + LIS3MDL) | ~$30 |
| Battery | Any small 3.7V LiPo | ~$5 |

### Wiring

| ESP32-C6 | BerryIMU 320G |
|---|---|
| GPIO6 | SDA |
| GPIO7 | SCL |
| 3.3V | VCC |
| GND | GND |

Four wires.

## Building the firmware

Firmware is in `firmware/opendisc/`. Standard Arduino sketch.

You need:
- [Arduino CLI](https://arduino.github.io/arduino-cli/) or Arduino IDE
- ESP32 board package (`esp32:esp32` v3.x)
- [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) library (v2.x)

```bash
arduino-cli core install esp32:esp32
arduino-cli lib install NimBLE-Arduino

# WiFi + BLE together need the large partition scheme
arduino-cli compile --fqbn "esp32:esp32:esp32c6:PartitionScheme=huge_app" firmware/opendisc
arduino-cli upload -p COM_PORT --fqbn "esp32:esp32:esp32c6:PartitionScheme=huge_app" firmware/opendisc
```

## How it works

There's a web UI at `opendisc.local` where you can see live readings, view throw results, browse history, run calibration, and change settings. Works from your phone browser.

BLE is there too (Nordic UART Service) for talking to a native app. Protocol spec is in `ios-app/OPENDISC_BLE_SPEC.md`.

The device auto-arms when it senses motion. You don't have to press anything before throwing.

MPH is calculated by integrating accelerometer data through the windup and release. The firmware tracks disc orientation using a quaternion so it can subtract gravity properly, and it accounts for the sensor chip not being at disc center.

RPM comes from the gyro. The gyro on this chip tops out around 333 RPM (2000 dps) so for faster throws the firmware calculates RPM from centripetal force on the high-G accelerometer instead. You need to run calibration for that to work.

Release angles come from the quaternion orientation, not from the accelerometer directly. Can't use raw accel for angles while the disc is spinning because centripetal force drowns out gravity.

## Calibration

Run this once whenever you mount the sensor in a new spot. Put the disc on a lazy susan, spin it at a few different speeds, and the firmware works out where the sensor chip is relative to center.

Gets saved to flash so you don't have to redo it every time you power on. The calibration feeds into the MPH calculation, angle correction, and the high-RPM accelerometer fallback.

## Gyro range

The LSM6DSV320X won't do 4000 dps even though ST's driver has a register value for it. We tried everything. Caps at 2000 dps. The accelerometer fallback covers higher spin rates. If you figure out how to get 4000 dps working on this chip, open an issue.

## iOS app

`ios-app/OPENDISC_BLE_SPEC.md` has the full BLE protocol spec for building a companion app. Commands, responses, state machine, calibration flow, throw flow, CoreBluetooth examples, screen layout ideas.

Not built yet.

## Project layout

```
firmware/opendisc/
  opendisc.ino      Main sketch
  sensors.h/.cpp    IMU register setup and raw reads
  analyzer.h/.cpp   Throw analysis, strapdown integration, release detection
  ble.h/.cpp        BLE server and command handling
  page.h            Web UI baked into flash

ios-app/
  OPENDISC_BLE_SPEC.md   BLE protocol reference
```

## Want to help?

Early days. Could use help with:

- iOS app (Swift + CoreBluetooth)
- Android app
- Custom PCB
- 3D printable enclosure that fits in a disc
- Flight analysis after release (fade, turn, skip)
- Battery monitoring (needs a voltage divider wired to an ADC pin)

## License

TBD.
