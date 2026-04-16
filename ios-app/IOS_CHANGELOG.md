# iOS App Changelog

Firmware changes that affect the iOS app. Check this after pulling new firmware.

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
