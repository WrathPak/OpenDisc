# OpenDisc

Open source disc golf throw analyzer. Cheap off-the-shelf parts, ~$40 total, does what a TechDisc does.

## What it measures

- Release speed (MPH)
- Spin rate (RPM), including throws above 333 RPM where the gyro maxes out
- Launch hyzer and nose angles
- Wobble (off-axis rotation after release)
- Peak G-force (up to 320g)

It auto-arms when you move the disc, captures a 1-second burst at 960 Hz, crunches the numbers on-device, and shows you the results over WiFi or BLE.

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

That's it. Four wires.

## Building the firmware

The firmware lives in `firmware/opendisc/`. It's a standard Arduino sketch.

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

**Web UI** runs at `opendisc.local` with live sensor readouts, throw results, throw history (saved in your phone's browser), calibration walkthrough, and settings.

**BLE** uses a Nordic UART Service so a native app can talk to it. Full protocol spec is in `ios-app/OPENDISC_BLE_SPEC.md`.

**Auto-arm** picks up when you start your throwing motion. No button to press.

**Speed (MPH)** is computed by integrating accelerometer data from the windup through release. The firmware tracks orientation with a quaternion, subtracts gravity in the world frame, and corrects for the chip's offset from disc center so you get the actual disc speed, not the chip's speed.

**RPM** comes from the gyro up to about 333 RPM. Above that the gyro saturates (the chip tops out at 2000 dps despite the datasheet saying otherwise), so the firmware switches to computing RPM from centripetal force measured by the high-G accelerometer. This requires calibration.

**Angles** at release come from the integrated quaternion orientation, not raw accelerometer readings. Raw accel is useless for angles during spin because centripetal force swamps the gravity signal.

## Calibration

You need to calibrate once per mounting so the firmware knows where the IMU chip sits relative to the disc's center. Stick it on a lazy susan or turntable, spin it at a few different speeds, and the firmware figures out the chip's position from the centripetal force pattern.

This gets stored in flash and sticks across reboots. The calibration is used for correcting angles, computing MPH accurately, and the accelerometer RPM fallback.

## Gyro range note

The LSM6DSV320X on the BerryIMU 320G won't actually run at 4000 dps even though ST's own driver says it should. We tested every register combination. It caps at 2000 dps (about 333 RPM). For real throws that spin faster than that, the accelerometer fallback handles it. If you figure out how to unlock 4000 dps on this chip, please open an issue.

## iOS app

The `ios-app/` folder has a BLE protocol spec (`OPENDISC_BLE_SPEC.md`) with everything you need to build a companion app: command format, response schemas, state machine, calibration and throw flows, CoreBluetooth snippets, and screen layout suggestions.

The app itself hasn't been built yet.

## Project layout

```
firmware/opendisc/
  opendisc.ino      Main sketch
  sensors.h/.cpp    IMU register setup and raw reads
  analyzer.h/.cpp   Throw analysis (strapdown integration, release detection)
  ble.h/.cpp        BLE server and command handling
  page.h            Web UI (HTML/JS/CSS baked into flash)

ios-app/
  OPENDISC_BLE_SPEC.md   BLE protocol reference for app development
```

## Want to help?

This is early. Lots to do:

- iOS app (Swift + CoreBluetooth)
- Android app
- Custom PCB so it's not a rats nest of wires
- 3D printable case that fits inside a disc
- Post-release flight analysis (fade, turn, skip detection)
- Battery voltage monitoring (needs a resistor divider to an ADC pin)

## License

TBD.
