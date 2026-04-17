# OpenDisc BLE Protocol Specification

**Version:** 1.0
**Hardware:** ESP32-C6 Super Mini + BerryIMU 320G (LSM6DSV320X + LIS3MDL)
**Firmware:** OpenDisc Web + BLE

---

## 1. Overview

OpenDisc is a disc golf throw analyzer that captures high-rate IMU data during a throw and computes release metrics: MPH, RPM, launch hyzer/nose angles, wobble, and peak G-force. The device runs on an ESP32-C6 with a BerryIMU 320G sensor board.

The iOS app connects via BLE to:
- View live sensor readings in real time
- Receive automatic throw analysis after each throw
- Run sensor calibration (required once per disc mounting)
- Manage settings (auto-arm, trigger threshold)
- View throw history

---

## 2. BLE Services

### 2.1 Nordic UART Service (NUS) — Primary Data Channel

All commands and responses flow through this single service using JSON strings.

| Item | UUID |
|---|---|
| **Service** | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` |
| **RX Characteristic** (app writes here) | `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` |
| **TX Characteristic** (device notifies here) | `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` |

**RX properties:** Write, Write Without Response
**TX properties:** Notify

The app MUST enable notifications on the TX characteristic after connecting. All device responses, live streams, and push events arrive as TX notifications.

### 2.2 Device Information Service (0x180A)

| Characteristic | UUID | Value |
|---|---|---|
| Firmware Revision | `0x2A26` | `"1.0.0"` |
| Model Number | `0x2A24` | `"OpenDisc"` |
| Manufacturer Name | `0x2A29` | `"OpenDisc"` |

### 2.3 Battery Service (0x180F) — Future

| Characteristic | UUID | Value |
|---|---|---|
| Battery Level | `0x2A19` | `0-100` (uint8, percent) |

Currently returns 0. Will be functional when voltage divider hardware is added.

### 2.4 MTU

The device requests MTU 256 on connection. iOS typically negotiates 185-251 bytes. JSON payloads that exceed the negotiated MTU are automatically fragmented by the BLE stack — no app-side reassembly needed for NimBLE + CoreBluetooth.

### 2.5 Advertising

- **Device name:** `OpenDisc`
- **Advertising interval:** 100 ms (fast) for first 30 s, then 500 ms (slow)
- **Connectable:** Yes
- **Advertised services:** NUS UUID

---

## 3. Command Reference

Commands are JSON objects written to the **RX characteristic**. Every command has a `"cmd"` field. Responses arrive as JSON notifications on the **TX characteristic** with a `"type"` field.

### 3.1 `status` — Get Device Status

**Request:**
```json
{"cmd":"status"}
```

**Response:**
```json
{
  "type": "status",
  "state": "IDLE",
  "auto_arm": true,
  "radius": 0.0306,
  "cal_rx": 0.00287,
  "cal_ry": 0.00708,
  "has_throw": false,
  "fw_version": "1.0.0"
}
```

| Field | Type | Description |
|---|---|---|
| `state` | string | `"IDLE"`, `"ARMED"`, `"CAPTURING"`, `"DONE"`, `"CALIBRATING"` |
| `auto_arm` | bool | Whether auto-arm is enabled |
| `radius` | float | Calibrated chip offset in meters (0 = uncalibrated) |
| `cal_rx` | float | X component of chip position vector (meters) |
| `cal_ry` | float | Y component of chip position vector (meters) |
| `has_throw` | bool | Whether a throw has been captured since last boot |
| `fw_version` | string | Firmware version |

### 3.2 `live_start` / `live_stop` — Live Sensor Stream

**Request:**
```json
{"cmd":"live_start"}
```

Starts streaming live sensor data at 10 Hz via TX notifications. Each notification:

```json
{
  "type": "live",
  "rpm_gyro": 211.3,
  "rpm_accel": 215.0,
  "accel_g": 1.02,
  "hg_g": 1.0,
  "hyzer": 2.1,
  "nose": -1.3,
  "gyro_clipped": false,
  "state": "IDLE"
}
```

| Field | Type | Unit | Description |
|---|---|---|---|
| `rpm_gyro` | float | RPM | Gyroscope-derived spin rate (accurate up to 666 RPM) |
| `rpm_accel` | float | RPM | Accelerometer-derived spin rate (requires calibration, valid above 666 RPM). `-1` if uncalibrated. `0` if gyro < 20 RPM. |
| `accel_g` | float | g | Total acceleration magnitude |
| `hg_g` | float | g | High-G accelerometer magnitude |
| `hyzer` | float | degrees | Disc hyzer angle (positive = hyzer, negative = anhyzer). Centripetal-corrected if calibrated. |
| `nose` | float | degrees | Disc nose angle (positive = nose up). Centripetal-corrected if calibrated. |
| `gyro_clipped` | bool | — | True if gyro is saturated (>660 RPM) |
| `state` | string | — | Current device state |

**Stop:**
```json
{"cmd":"live_stop"}
```

### 3.3 `arm` — Manual Arm

**Request:**
```json
{"cmd":"arm"}
```

**Response:**
```json
{"type":"ack","msg":"Armed! Waiting for throw..."}
```

Arms the burst capture. The device transitions to `ARMED` state and waits for the trigger threshold to be exceeded. When auto-arm is enabled, this is unnecessary but can be used as a manual override.

### 3.4 `throw` — Get Last Throw Data

**Request:**
```json
{"cmd":"throw"}
```

**Response:**
```json
{
  "type": "throw",
  "valid": true,
  "rpm": 620.0,
  "mph": 52.3,
  "peak_g": 45.2,
  "hyzer": 12.5,
  "nose": -3.2,
  "launch": 6.4,
  "wobble": 8.1,
  "duration_ms": 280,
  "release_idx": 412,
  "motion_start_idx": 180,
  "stationary_end": 95
}
```

| Field | Type | Unit | Description |
|---|---|---|---|
| `valid` | bool | — | False if no throw captured or release not detected |
| `rpm` | float | RPM | Spin rate at the moment of release. Uses gyro below 660 RPM, accel fallback above. |
| `mph` | float | MPH | Disc center-of-mass speed at release. `-1` if strapdown integration failed. |
| `peak_g` | float | g | Peak acceleration during capture (uses HG accel if main clips) |
| `hyzer` | float | degrees | Hyzer angle at release, relative to throw direction. Positive = left edge down from behind the disc. |
| `nose` | float | degrees | Nose angle at release, relative to throw direction. Positive = nose up. |
| `launch` | float | degrees | Launch angle — vertical angle of the velocity vector at release. Positive = up, negative = down. `0` if strapdown integration failed or horizontal speed was too low to resolve a direction. |
| `wobble` | float | degrees | RMS off-axis rotation over 100 ms after release |
| `duration_ms` | int | ms | Time from first motion to release |
| `release_idx` | int | — | Sample index of release point in ring buffer |
| `motion_start_idx` | int | — | Sample index of motion start |
| `stationary_end` | int | — | Sample index of last stationary sample |

**RPM:** uses the gyroscope (140 mdps/LSB) when below 666 RPM. Above that the gyro saturates at 4000 dps, so RPM is computed from centripetal force on the HG accelerometer using the calibrated chip radius.

**MPH:** strapdown inertial integration from a stationary reference to the release point. Corrected for centripetal offset, tangential acceleration, gyro bias, and HG accel substitution when the main accelerometer clips. If no stationary window is found, falls back to the quietest 16-sample window in the pre-trigger buffer.

**Hyzer/nose:** computed from the disc's orientation quaternion decomposed into the throw's own reference frame. "Forward" is the horizontal component of the velocity vector at release. Works regardless of chip mounting orientation or throw type (RHBH, forehand, etc). Falls back to centripetal-corrected accelerometer angles if the strapdown doesn't produce a usable velocity vector.

### 3.5 `cal_start` / `cal_stop` — Calibration

**Start:**
```json
{"cmd":"cal_start"}
```

**Response:**
```json
{"type":"ack","msg":"Calibrating - vary spin 200-500 RPM"}
```

Device transitions to `CALIBRATING` state. During calibration, the device pushes progress updates at 5 Hz:

```json
{
  "type": "cal_progress",
  "pts": 145,
  "target": 200,
  "rpm": 312.5,
  "rpm_min": 180.0,
  "rpm_max": 450.0,
  "hint": "Good - keep varying the spin"
}
```

| Hint | Meaning |
|---|---|
| `"Spin faster (aim 200-600 RPM)"` | Current RPM below 150 |
| `"Good - keep varying the spin"` | In range, collecting |
| `"Vary the speed - need a wider range"` | Points collected but RPM span < 100 |
| `"Too fast - gyro clipping"` | RPM above gyro ceiling |
| `"Ready - tap Stop"` | Target points reached |

**Stop:**
```json
{"cmd":"cal_stop"}
```

**Response:**
```json
{
  "type": "cal_result",
  "accepted": true,
  "radius": 0.0306,
  "rx": 0.00287,
  "ry": 0.00708,
  "points": 452,
  "rpm_min": 165.0,
  "rpm_max": 420.0,
  "msg": "Calibration saved: 452 pts, 165-420 RPM, r=30.6mm"
}
```

Calibration is **rejected** (accepted=false) if:
- Fewer than 20 valid data points
- RPM span less than 100 RPM
- Computed radius <= 0

Accepted calibration is persisted to NVS and survives power cycles.

**Calibration method:** Vectorial OLS regression fitting `ax = cx * omega^2 + bx` and `ay = cy * omega^2 + by` separately. The slopes `(cx, cy)` give the chip's body-frame position vector from the disc's spin axis. This is more robust than scalar magnitude fitting because it uses sign information and is unbiased by gravity leakage noise.

### 3.6 `settings_get` / `settings_set` — Device Settings

**Get:**
```json
{"cmd":"settings_get"}
```

**Response:**
```json
{
  "type": "settings",
  "auto_arm": true,
  "trigger_g": 3.0
}
```

**Set (partial update):**
```json
{"cmd":"settings_set","auto_arm":false,"trigger_g":2.5}
```

**Response:** Same as get, echoing the new values.

| Setting | Type | Range | Default | Description |
|---|---|---|---|---|
| `auto_arm` | bool | — | `true` | Automatically arm when gyro detects motion (>200 dps for 3 consecutive samples) |
| `trigger_g` | float | 1.5 - 8.0 | 3.0 | Acceleration threshold (g) that triggers burst capture while armed |

### 3.7 `imudiag` — IMU Register Diagnostic

**Request:**
```json
{"cmd":"imudiag"}
```

**Response:**
```json
{
  "type": "imudiag",
  "whoami": "0x73",
  "ctrl1": "0x09",
  "ctrl2": "0x09",
  "ctrl6": "0x04",
  "ctrl8": "0x03",
  "ctrl9": "0x00",
  "ctrl1_xl_hg": "0xA4",
  "fs_g": "4000 dps",
  "fs_xl": "16 g"
}
```

### 3.8 `wifi_off` / `wifi_on` — WiFi Power Management

Disabling WiFi saves significant battery (~100 mA). WiFi auto-restores 5 minutes after BLE disconnect so the device stays accessible if the app loses connection.

**Disable WiFi:**
```json
{"cmd":"wifi_off"}
```

**Response:**
```json
{"type":"ack","msg":"WiFi off. Restores 5 min after BLE disconnect."}
```

**Re-enable WiFi:**
```json
{"cmd":"wifi_on"}
```

**Response:**
```json
{"type":"ack","msg":"WiFi on."}
```

WiFi is always on at boot. It only turns off when a BLE client explicitly requests it. If the BLE client disconnects while WiFi is off, WiFi automatically comes back after 5 minutes.

### 3.9 `dump_raw` — Raw Burst Data for Training

Streams the full ring buffer from the most recent capture. 1920 samples at 960 Hz (1s pre-trigger + 1s post-trigger). Uses a **binary-framed** protocol on the same TX characteristic as JSON messages; clients disambiguate by the leading byte (`0xFF` = binary frame, `0x7B` (`{`) = JSON).

**Request:**
```json
{"cmd":"dump_raw"}
```

**Response sequence:**
```text
{"type":"dump","status":"start","samples":1920,"frames":240,"spf":8,"fmt":"bin1"}
<binary frame 0>     // seq=0, 8 samples
<binary frame 1>     // seq=1, 8 samples
...
<binary frame 239>   // seq=239, 8 samples (last frame may be shorter)
{"type":"dump","status":"done"}
```

If no capture exists: `{"type":"dump","status":"no_throw"}`.

**Binary frame layout** (little-endian throughout):

| Offset | Size | Field | Value |
|---|---|---|---|
| 0 | 1 byte  | magic    | `0xFF` |
| 1 | 1 byte  | version  | `0x01` |
| 2 | 2 bytes | seq      | frame index, `0 ≤ seq < frames` |
| 4 | 1 byte  | count    | samples in this frame (≤ `spf`) |
| 5 | 1 byte  | reserved | `0x00` |
| 6 | 20 × count bytes | samples | packed int16 LE, 10 fields per sample |

Each sample is 10 `int16 LE` values in this order: `i, ax, ay, az, gx, gy, gz, hx, hy, hz`.

| Field | Description |
|---|---|
| `i` | Sample index relative to trigger. Negative = pre-trigger, range `-960..959`. |
| `ax/ay/az` | Raw 16-bit accelerometer (main, ±16g) |
| `gx/gy/gz` | Raw 16-bit gyroscope (±4000 dps) |
| `hx/hy/hz` | Raw 16-bit high-G accelerometer (±320g) |

Total frame size with `spf=8` is 166 bytes, which fits under the default 185-byte BLE notification MTU. Firmware paces ~15 ms per frame, so the full dump takes ~3–5 s over BLE.

To convert raw values: multiply by `GYRO_SENS=0.140` for dps, `ACCEL_SENS=0.000488` for g, `HG_SENS=0.00977` for g.

**Ordering and loss:** Frames are sent in sequential `seq` order but a client should not assume zero loss — track which seq numbers arrived, detect gaps, and sort the flattened sample list by `i` before using it.

**Legacy protocol:** Older firmware (pre-2026-04-17) sent one `{"type":"d",...}` JSON notification per sample. Clients that still need to talk to old firmware can keep a `.d` handler — the new firmware never emits `d` frames, so the two code paths don't collide.

---

## 4. Device State Machine

```
         auto-arm (gyro > 200 dps)
              or manual "arm"
    IDLE ─────────────────────────> ARMED
     ^                                |
     |                                | accel > trigger_g
     |  auto-return after 2s          v
     |  (if auto_arm enabled)    CAPTURING
     |                                |
     |                                | post-trigger samples complete
     └──────────── DONE <────────────┘
                    |
                    | analyzeThrow() runs automatically
                    | "throw_ready" pushed to BLE

    IDLE ──── "cal_start" ───> CALIBRATING ──── "cal_stop" ───> IDLE
```

**Key behaviors:**
- Auto-arm requires `auto_arm = true` and the device to be in `IDLE` state
- After `DONE`, the analyzer runs automatically and results are cached
- If `auto_arm` is enabled, device returns to `IDLE` after 2 seconds in `DONE`
- `CALIBRATING` blocks arming; `ARMED`/`CAPTURING` blocks calibration

---

## 5. Push Events

These are sent automatically via TX notify without a prior command:

| Event | When | Purpose |
|---|---|---|
| `{"type":"state","state":"ARMED"}` | On any state transition | Keep app UI in sync |
| `{"type":"throw_ready"}` | After analyzer completes in DONE state | App should fetch throw data |

The app should always listen for these even when not actively streaming live data.

---

## 6. Calibration Flow (iOS App)

1. Check `status.radius` — if 0, show "Calibration Required" screen
2. User places disc on a flat spinning surface (lazy susan, turntable)
3. App sends `{"cmd":"cal_start"}`
4. Display progress bar and hint text from `cal_progress` events
5. User varies spin speed across 200-500 RPM range
6. When progress bar is full (pts >= target), show "Ready" state
7. User taps Stop — app sends `{"cmd":"cal_stop"}`
8. Check `cal_result.accepted`:
   - `true`: show success with radius value, proceed to dashboard
   - `false`: show error with reason, offer retry

---

## 7. Throw Flow (iOS App)

1. Dashboard shows live readings (subscribe with `live_start`)
2. Device auto-arms when it detects motion (state changes to `ARMED`)
3. User throws the disc
4. Device captures 960 Hz burst (200 ms pre-trigger + 800 ms post-trigger)
5. State transitions: `ARMED` -> `CAPTURING` -> `DONE`
6. Analyzer runs automatically, device pushes `throw_ready`
7. App sends `{"cmd":"throw"}` to fetch metrics
8. Display throw card: MPH, RPM, launch angles, wobble, peak G
9. Append to local throw history (persist in app's UserDefaults/CoreData)
10. Device returns to `IDLE` after 2s (if auto-arm), ready for next throw

---

## 8. Sensor Specifications

| Sensor | Chip | Range | ODR | Notes |
|---|---|---|---|---|
| Gyroscope | LSM6DSV320X | +-4000 dps | 960 Hz | Max measurable: 666 RPM. Above this, accel fallback. |
| Accelerometer | LSM6DSV320X | +-16 g | 960 Hz | Main accel for live + strapdown integration |
| High-G Accel | LSM6DSV320X | +-320 g | 960 Hz | Used when main clips. Centripetal at high RPM. |
| Magnetometer | LIS3MDL | +-8 gauss | 80 Hz | Not currently used for throw analysis |

**Burst capture:** 960 samples at 960 Hz = 1 second total (192 pre-trigger + 768 post-trigger).

---

## 9. iOS Implementation Notes

### CoreBluetooth Setup

```swift
// CBCentralManager
let central = CBCentralManager(delegate: self, queue: .main)

// Scan for OpenDisc
let nusServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
central.scanForPeripherals(withServices: [nusServiceUUID])

// On discover: connect
central.connect(peripheral)

// On connect: discover services -> discover characteristics
// Enable notifications on TX characteristic (6E400003...)
peripheral.setNotifyValue(true, for: txCharacteristic)
```

### Sending Commands

```swift
let cmd = #"{"cmd":"status"}"#
let data = cmd.data(using: .utf8)!
peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)
```

### Receiving Responses

```swift
func peripheral(_ peripheral: CBPeripheral,
                didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    guard let data = characteristic.value,
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let type = json["type"] as? String else { return }

    switch type {
    case "live":    handleLiveUpdate(json)
    case "throw":   handleThrowData(json)
    case "status":  handleStatus(json)
    case "state":   handleStateChange(json)
    case "throw_ready": fetchThrowData()
    case "cal_progress": handleCalProgress(json)
    case "cal_result":   handleCalResult(json)
    default: break
    }
}
```

### Background Mode

To receive throw notifications while the app is backgrounded:
1. Enable "Uses Bluetooth LE accessories" in Background Modes capability
2. The app will wake on BLE notifications even when not in foreground
3. Use `CBCentralManager(delegate:queue:options:)` with `CBCentralManagerOptionRestoreIdentifierKey` for state restoration

### Reconnection

```swift
// On disconnect:
func centralManager(_ central: CBCentralManager,
                    didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    // Auto-reconnect
    central.connect(peripheral)
}
```

CoreBluetooth handles reconnection attempts automatically once `connect()` is called. The system will reconnect when the device comes back in range, even if the app is backgrounded.

---

## 10. Suggested App Screens

### Scan / Connect
- List of discovered OpenDisc devices (by name + signal strength)
- Tap to connect
- Show connection progress

### Dashboard (Main Screen)
- Large MPH display from last throw (or "--" if none)
- Live RPM gauge (gyro or accel, whichever is active)
- Live hyzer/nose angle indicators
- Status badge: IDLE / ARMED / CAPTURING / DONE
- Auto-arm indicator
- "Arm" button (manual override)

### Throw Detail
- MPH (large, primary)
- Release RPM
- Peak RPM
- Launch hyzer angle
- Launch nose angle
- Wobble
- Peak G
- Duration (ms)
- Timestamp

### Throw History
- Scrollable list of past throws
- Each row: timestamp, MPH, RPM, hyzer
- Tap for full detail
- Store locally in app (UserDefaults or CoreData)

### Calibration
- Step-by-step guided flow
- Progress bar with sample count
- RPM range indicator
- Hint text (from device)
- Start / Stop buttons
- Result display (radius in mm, accepted/rejected)

### Settings
- Auto-arm toggle
- Trigger threshold slider (1.5 - 8.0 g)
- WiFi enable/disable (future)
- Firmware version display
- IMU diagnostic view (register dump)
- "Forget Calibration" button (re-trigger cal flow)

---

## 11. Error Handling

| Scenario | App Behavior |
|---|---|
| BLE disconnect during throw | Show "Disconnected" banner, auto-reconnect, fetch throw data on reconnect |
| Throw with no calibration | Device still captures but MPH = -1. App should prompt calibration. |
| Cal rejected | Show reason (too few points / narrow RPM range), offer retry |
| Strapdown integration fails | `release_mph = -1`. App shows "--" for MPH, other metrics still valid. |
| Gyro clipping during throw | Transparent — firmware automatically uses accel fallback for RPM |

---

## 12. Future Extensions

- **Battery monitoring** — hardware voltage divider + Battery Service characteristic
- **CSV export** — dump raw burst capture via BLE (chunked transfer)
- **Multi-disc profiles** — store cal data per disc, switch via settings
- **Flight analysis** — use post-release IMU data for fade/turn detection
- **Apple Watch companion** — quick-glance throw summary via WatchConnectivity
