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
