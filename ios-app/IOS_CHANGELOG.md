# iOS App Changelog

Firmware changes that affect the iOS app. Check this after pulling new firmware.

---

## 2026-04-17

### New field: `launch` in `throw` response

Firmware now emits `launch` alongside `hyzer` and `nose` — the vertical angle of the disc's velocity vector at release, in degrees. Positive = throwing up, negative = throwing down. Returns `0.0` when the strapdown integration can't resolve a direction (e.g. no stationary reference, or horizontal speed below 0.1 m/s).

This is the third of TechDisc's six core metrics; add it to the throw detail grid. Decode `launch: Float` from `ThrowResponse`, persist as `ThrowData.launchAngle`, show on `ThrowDetailView`. See `ios-app/IOS_TODO.md` item 1 for full plan.

Unlike hyzer, launch angle is directionally invariant — no left-hand flipping needed.

---

## 2026-04-16

### Breaking: throw data schema changed

The `throw` response no longer has `peak_rpm`, `release_rpm`, or `release_mph`. They've been replaced with simpler field names:

**Old:**
```json
{
  "peak_rpm": 850,
  "release_rpm": 620,
  "release_mph": 52.3,
  "launch_hyzer": 12.5,
  "launch_nose": -3.2
}
```

**New:**
```json
{
  "rpm": 620,
  "mph": 52.3,
  "hyzer": 12.5,
  "nose": -3.2
}
```

- `rpm` is the spin rate at release (was `release_rpm`). There is no separate peak RPM.
- `mph` is the disc speed at release (was `release_mph`). Returns `-1` if strapdown integration failed.
- `hyzer` and `nose` (were `launch_hyzer` and `launch_nose`). Now computed relative to the throw direction, not body axes. Works regardless of chip mounting or throw type.

Update your Swift models and any JSON decoding to use the new field names.

### Hyzer/nose are now throw-relative

Angles are computed from the velocity vector at release. "Forward" is whichever direction the disc is actually flying. Positive hyzer = left edge down from behind the disc. Positive nose = nose up. No chip orientation calibration needed.

### WiFi power management commands added

New BLE commands: `wifi_off` and `wifi_on`. See section 3.8 in `OPENDISC_BLE_SPEC.md`. WiFi auto-restores 5 min after BLE disconnect.

### Wider capture buffer

Pre-trigger and post-trigger both increased to 960 samples (1 second each, 2 seconds total). More room for the strapdown to find a stationary reference.

### Stationary window fallback

If no perfectly still moment exists in the pre-trigger buffer, the analyzer now uses the quietest 16-sample window it can find. Indoor/quick throws should now produce MPH values instead of returning -1.

### New: `dump_raw` command for training data

Send `{"cmd":"dump_raw"}` after a throw to stream the full 1920-sample ring buffer (960 Hz, 2 seconds) over BLE. Each sample arrives as a separate notification:

```json
{"type":"dump","status":"start","samples":1920}
{"type":"d","i":-960,"ax":26,"ay":-16,"az":2071,"gx":-1,"gy":2,"gz":-3,"hx":0,"hy":0,"hz":0}
{"type":"d","i":-959, ...}
...
{"type":"d","i":959, ...}
{"type":"dump","status":"done"}
```

`i` is the sample index relative to trigger (negative = pre-trigger). Takes about 5-10 seconds over BLE. Store alongside throw tags for building training datasets.

If no throw has been captured, returns `{"type":"dump","status":"no_throw"}`.

### iOS TODO: hyzer sign convention for left-handed throwers

The firmware reports hyzer as positive when the left edge of the disc is lower (looking from behind in the flight direction). This matches the conventional "hyzer" label for RHBH throws.

For LHBH throwers, the same physical tilt is conventionally called "anhyzer." The firmware number is still physically correct, just the label is inverted.

Suggested app behavior: add a handedness setting (RH/LH). For LH, negate the hyzer value before displaying and swap the hyzer/anhyzer labels. The raw data stays the same.

### iOS TODO: throw tagging for training data

After each throw detection, show a tag picker so the user can label the throw:
- "Good throw"
- "Not a throw" (false trigger)
- "Edge case"
- Custom text label

Store tags locally alongside throw metrics. Add an "Export dataset" option that dumps all tagged throws as JSON. Optionally pull the raw burst via `dump_raw` for throws the user flags as interesting.

This data is for improving release detection, tuning thresholds, and eventually training a classifier to auto-reject bad detections.

### 4000 dps gyro unlocked!

GYRO_SENS changed from 0.070 to 0.140 (140 mdps/LSB). Gyro ceiling is now 666 RPM instead of 333. The `dump_raw` gyro values now need to be multiplied by 0.140 (not 0.070) for dps. Update any raw data conversion constants in the app.

The fix was CTRL6 = 0x0D instead of 0x05. Bit 3 of CTRL6 defaults to 1 and must stay 1 for 4000 dps to work. ST's driver has a bug where it uses 0x5 which clears this bit.

### iOS TODO: 3D throw trajectory visualization

The `dump_raw` data contains everything needed to reconstruct the disc's 3D path through space during the throw. Implementation:

1. Pull raw burst via `{"cmd":"dump_raw"}` (1920 samples, 960 Hz, 2 seconds)
2. Run strapdown inertial integration on the phone:
   - Find the quietest window in the pre-trigger samples as stationary reference
   - Initialize orientation quaternion from gravity direction
   - For each sample forward:
     - Integrate gyro to update quaternion: `q = q * deltaQ(omega, dt)`
     - Rotate body-frame accel to world frame: `a_world = R(q) * a_body`
     - Subtract gravity: `a_world.z -= 9.81`
     - Subtract centripetal: `a_body -= omega^2 * (cal_rx, cal_ry, 0)` (before rotation)
     - Integrate velocity: `v += a_world * dt`
     - Integrate position: `p += v * dt`
3. Output: arrays of `(position, orientation, velocity)` at each timestep

Raw-to-physical conversion constants:
- Gyro: `raw * 0.140` = degrees/sec (multiply by pi/180 for rad/s)
- Accel: `raw * 0.000488` = g (multiply by 9.81 for m/s²)
- HG accel: `raw * 0.00977` = g
- Use HG accel when any main accel axis `|raw| > 32000`
- Sample rate: 960 Hz, dt = 1/960 s
- Sample index `i` is relative to trigger. Negative = pre-trigger.

Visualization ideas:
- SceneKit or RealityKit 3D path with a disc model at each keyframe
- Color the path by speed (blue=slow, red=fast)
- Show disc orientation as a flat disc model tilted at each point
- Mark the release point (where accel drops to ~1g)
- Mark the stationary reference point (start of integration)
- Overlay: reach-back distance, release height, launch angle arc
- Compare multiple throws by overlaying trajectories

Drift note: position accuracy degrades with double integration. Over a 1-second throw window expect ±10-20 cm of drift by the end. Good enough for form visualization and throw comparison, not for absolute distance measurement.
