# OpenDisc

An open-source disc golf throw analyzer — a DIY alternative to TechDisc built with off-the-shelf components.

## What It Does

OpenDisc captures high-rate IMU data during a disc golf throw and computes:

- **Release speed (MPH)** via strapdown inertial integration
- **Spin rate (RPM)** from gyroscope + accelerometer fallback for high-speed throws
- **Launch hyzer angle** — quaternion-derived, immune to centripetal contamination
- **Launch nose angle** — quaternion-derived
- **Wobble** — off-axis precession after release
- **Peak G-force** — using a ±320g high-G accelerometer

The device auto-arms on motion, captures a 1-second burst at 960 Hz, analyzes the throw on-device, and serves the results via a web UI and BLE.

## Hardware

| Component | Part | Approx Cost |
|---|---|---|
| Microcontroller | ESP32-C6 Super Mini (4MB) | $5 |
| IMU | BerryIMU 320G (LSM6DSV320X + LIS3MDL) | $30 |
| Battery | 3.7V LiPo (any small cell) | $5 |
| Total | | **~$40** |

### Wiring

| ESP32-C6 | BerryIMU 320G |
|---|---|
| GPIO6 | SDA |
| GPIO7 | SCL |
| 3.3V | VCC |
| GND | GND |

## Firmware

The firmware is an Arduino sketch in [`firmware/opendisc/`](firmware/opendisc/).

### Building

Requires:
- [Arduino CLI](https://arduino.github.io/arduino-cli/) or Arduino IDE
- ESP32 board package (`esp32:esp32` v3.x)
- [NimBLE-Arduino](https://github.com/h2zero/NimBLE-Arduino) library (v2.x)

```bash
# Install ESP32 board support
arduino-cli core install esp32:esp32

# Install NimBLE
arduino-cli lib install NimBLE-Arduino

# Compile (must use huge_app partition for WiFi + BLE)
arduino-cli compile --fqbn "esp32:esp32:esp32c6:PartitionScheme=huge_app" firmware/opendisc

# Upload
arduino-cli upload -p COM_PORT --fqbn "esp32:esp32:esp32c6:PartitionScheme=huge_app" firmware/opendisc
```

### Features

- **Web UI** at `opendisc.local` — live readings, throw cards, throw history, calibration with guided progress bar, settings
- **BLE** (Nordic UART Service) — full command protocol for iOS/Android app integration
- **Auto-arm** — detects throw motion automatically, no button press needed
- **Calibration** — vectorial regression determines the IMU chip's exact position on the disc for centripetal correction
- **Strapdown MPH** — integrates body-frame acceleration to compute disc center-of-mass velocity at release, with centripetal subtraction, gyro bias correction, and HG accel fallback
- **Accel-fallback RPM** — when the gyro saturates above ~333 RPM, RPM is derived from centripetal force using the calibrated chip offset and the ±320g high-G accelerometer

### Sensor Notes

The LSM6DSV320X on the BerryIMU 320G empirically caps at ±2000 dps gyro (333 RPM) despite ST's driver claiming ±4000 dps support via FS_G=0x5. Real disc golf throws (500–1500 RPM) exceed this, so the firmware automatically falls back to accelerometer-derived RPM using the calibrated chip radius. See the firmware comments for the full investigation.

## iOS App

The [`ios-app/`](ios-app/) folder contains the BLE protocol specification for building a companion iOS app:

- [`OPENDISC_BLE_SPEC.md`](ios-app/OPENDISC_BLE_SPEC.md) — complete BLE command reference, state machine, calibration/throw flows, CoreBluetooth code snippets, and suggested screen layouts

The iOS app is under development. Contributions welcome.

## Calibration

Before first use, the IMU chip's physical offset from the disc's spin axis must be calibrated:

1. Mount the OpenDisc module on a disc (or any flat spinning surface like a lazy susan)
2. Open the web UI or connect via BLE
3. Start calibration and spin the disc at varying speeds (200–500 RPM)
4. The firmware fits a vectorial regression to determine the chip's body-frame position vector `(rx, ry)`
5. This calibration is stored in flash and survives power cycles

The calibrated offset is used for:
- Centripetal-corrected hyzer/nose angles during spin
- Accurate MPH via centripetal subtraction in the strapdown integration
- Accelerometer-derived RPM when the gyro clips

## Project Structure

```
OpenDisc/
├── README.md
├── firmware/
│   └── opendisc/          # Arduino sketch
│       ├── opendisc.ino   # Main sketch (WiFi, routes, loop, settings)
│       ├── sensors.h/cpp  # LSM6DSV320X + LIS3MDL register config & reads
│       ├── analyzer.h/cpp # Throw analysis (strapdown, release detection)
│       ├── ble.h/cpp      # BLE server (NimBLE NUS, command parser)
│       └── page.h         # Web UI (HTML/CSS/JS in PROGMEM)
└── ios-app/
    └── OPENDISC_BLE_SPEC.md  # BLE protocol spec for iOS development
```

## Contributing

This is an early-stage project. Areas where help is needed:

- iOS app (Swift/SwiftUI + CoreBluetooth)
- Android app
- PCB design for a compact disc-mountable module
- 3D-printable enclosure designs
- Flight analysis (post-release IMU data for fade/turn detection)
- Battery monitoring integration

## License

Open source. License TBD.
