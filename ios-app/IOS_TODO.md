# iOS TODO — TechDisc Parity + Stats

Work planned to reach feature parity with TechDisc's stat surface and extend beyond it. Pure iOS-side work; no firmware changes required (all new metrics derive from the existing `throw` response + `dump_raw` raw sample buffer).

Ordering below is roughly increasing scope. Items 1–3 share a `ThrowData` schema change, so do them in one PR.

---

## 1. Launch Angle

**What:** Vertical angle of the disc's *velocity vector* at release (not orientation — that's nose angle). Level throw = 0°, lobbed up = +°, driven down = −°.

**Why it matters:** Third of TechDisc's six core metrics. Critical coaching input — pairs with nose angle to diagnose angle-of-attack issues (nose up + launch flat = clean planing; nose up + launch up = "skyballing" that kills distance).

**Source:** Firmware (`launch` field in `throw` response, as of 2026-04-17). Matches hyzer/nose pattern — no iOS-side integration needed.

**Implementation:**

1. Add `let launch: Float` to `ThrowResponse` in `BLEResponse.swift`.
2. Add `var launchAngle: Float = 0` to `ThrowData` (SwiftData lightweight migration handles this — default 0 is safe for back-fill of pre-update throws).
3. Persist in `ContentView.saveThrow()` alongside the other metrics:
   ```swift
   let throwData = ThrowData(
       ...,
       launchAngle: response.launch,
       ...
   )
   ```
4. Display in `ThrowDetailView` metrics grid — green tint like hyzer/nose. Show sign with "up"/"down" label (e.g. `"6.4°"` + unit `"up"` for positive, `"down"` for negative, `"flat"` for |x| < 0.5°).
5. Optionally show in `ThrowRow` as a small label.

**Edge cases:**
- Firmware returns `0.0` when strapdown fails (same condition that makes `mph = -1`). Treat `mph < 0` as "launch unavailable" and show `--`.
- Launch angle is directionally invariant (comes from the velocity vector, not chip orientation) — no LH/RH flipping needed.

---

## 2. Advance Ratio

**What:** `(spin_rad_per_sec × disc_radius_m) / speed_m_per_s` — ratio of rim tangential speed to forward speed. Dimensionless, shown as %.

**TechDisc targets:** ~50% (backhand), ~30% (forehand). Below target = "arming it" (not enough wrist snap).

**Implementation:**

1. Add `radius: Float` field to `Disc` model. Default `0.105` (m — PDGA max disc radius). Expose in `DiscFormView` as "Radius (mm)" number field with `105` default, clamped `90...120`.
2. Computed property on `ThrowData`:
   ```swift
   var advanceRatio: Float? {
       guard mph > 0 else { return nil }
       let radius = disc?.radius ?? 0.105
       let rpsRad = rpm * 2 * .pi / 60
       let mps = mph * 0.44704
       return (rpsRad * radius) / mps
   }

   var advanceRatioTarget: Float {
       throwType == ThrowType.forehand.rawValue ? 0.30 : 0.50
   }
   ```
3. Display in `ThrowDetailView` as a `MetricCard`:
   - Value: `String(format: "%.0f%%", advanceRatio! * 100)`
   - Unit: `target: 50%` (or 30% for FH)
   - Tint: green if within ±10% of target, yellow if ±20%, orange otherwise.
4. Optionally show in `ThrowRow` as a tiny badge when far from target.

**Why disc-level radius, not session-level:** Different disc classes (putter vs distance driver) have slightly different rim diameters. Allow per-disc override. Default 105 mm is correct for ~90% of drivers.

---

## 3. Data migration

**What:** `ThrowData.launchAngle` and `Disc.radius` are new fields on existing `@Model` classes.

**Plan:**
- Both get safe defaults (`0` and `0.105`) so SwiftData's lightweight migration handles them transparently.
- Verify migration by loading a pre-update store on simulator. Old throws will show `launchAngle = 0` — the persistRawDump fallback on trajectory-equipped throws can *backfill* launch angle on first launch after update. Gate behind `launchAngle == 0 && hasTrajectoryData`.

---

## 4. Predicted Carry Distance

**What:** Extend `TrajectoryEngine` (or add a sibling `FlightSimulator`) that takes release state (position, velocity, orientation, spin) and integrates disc aerodynamics forward in time until it lands. Report carry distance + total distance (with skip/roll heuristic).

**Why:** Matches TechDisc's "simulated flight" feature and is the highest-signal "what would this have done on a real drive" readout.

**Sketch:**

1. Extract release state from existing `TrajectoryEngine`:
   - Position (set to 1.5 m release height at origin)
   - Velocity (rotate so x-axis is forward direction)
   - Orientation quaternion
   - Angular velocity (from gyro at release; gives spin axis + spin rate)
2. Write a 6-DOF forward integrator using a standard disc aero model:
   - Coefficients: Cl(α), Cd(α), Cm(α) — Hummel / Potts model works fine.
   - Parameters depend on disc stability. For MVP, use one "neutral driver" profile and tune against real throws. Long term: expose per-disc flight numbers (speed/glide/turn/fade) and map to aero coefficients.
3. Integrate at 200 Hz until `position.z <= 0` (ground). Record path.
4. Surface:
   - `predictedCarryFeet: Float`
   - `predictedPath: [SIMD3<Float>]` (for a 2D overhead flight map)
5. Reuse `TrajectoryView`'s SceneKit / Chart rendering for the post-release portion.

**Complexity:** This is the biggest item on the list. Plan on a dedicated 1–2 day pass. A reasonable MVP shortcut: a data-driven regression (`carry ≈ f(mph, rpm, launch°, nose°)`) fit from a labeled dataset once we have ~200 real throws with measured outcomes. Cheaper to build, calibrates to the actual disc/thrower. Use this as the bridge until the full aero sim is trustworthy.

---

## 5. Stats Tab (Session Aggregates)

**What:** New top-level tab (`chart.bar.xaxis`) showing aggregate statistics across filtered throws. The "better than TechDisc" feature.

**Filters (top-of-view segmented / dropdowns):**
- Date range: today / 7d / 30d / all
- Disc (single select, "All" default)
- Throw type: BH / FH / all
- Hand: RH / LH / all
- Tag: only "Good throw", exclude "Not a throw", etc.

**Aggregate cards (after filter):**
- Count
- Avg / best MPH
- Avg / best RPM
- Avg hyzer, nose, wobble, launch
- **Consistency score** — inverse std-dev across speed + hyzer (normalize, invert, 0–100 scale).
- Advance ratio avg (with target line).
- PR throws (top 3 by MPH, linkable to detail).

**Charts (use SwiftUI Charts):**
- MPH over time (scatter + rolling avg line)
- Spin vs speed scatter with advance-ratio target line overlay
- Hyzer distribution (histogram)
- Wobble distribution (histogram)

**Implementation notes:**
- All aggregation lives in a `ThrowStatistics` struct that takes `[ThrowData]` and caches computed values.
- SwiftData `@Query` with predicate for filters; fall back to in-memory filtering if predicate gets hairy.
- Keep filter state in `@AppStorage` so the tab remembers user's last view.

---

## 6. Per-Disc Detail View

**What:** Tap a disc in `DiscsView` → detail page with that disc's throw aggregates, best throw, and a spin-vs-speed scatter.

**Current state:** `DiscsView` taps go straight to edit. Change to show detail first; edit via toolbar.

**Layout:**
- Header: disc name, color swatch, total throws, date of last throw.
- Quick stats: avg MPH, avg RPM, best MPH, avg advance ratio.
- "Best throw" card linking to throw detail.
- Spin-vs-speed scatter with advance-ratio target line.
- Recent throws list (last 10, scrollable into full history filtered to this disc).

**Implementation:** new `DiscDetailView.swift`. Reuse `ThrowStatistics` from item 5 to keep aggregation code in one place.

---

## 7. Personal Records + Trends

**What:** Surface PRs and rolling trends on the dashboard and in stats.

**PR tracking:**
- Store nothing new — derived from `ThrowData`.
- "PR" = top 1 MPH all-time, per disc, per throw type, per hand.
- Detect at save time; if new PR, haptic + voice callout ("New personal best: 82 mph with the Destroyer").

**Trend display:**
- Dashboard: tiny sparkline (last 30 throws or 30 days, whichever shorter) of MPH above the live gauge.
- Stats tab: rolling 7-day / 30-day avg lines on the MPH-over-time chart.

**Implementation:**
- `PRService` static helper that queries `ThrowData` and returns current bests. Call after each throw save.
- `VoiceManager` additions for new-PR callouts.
- SwiftUI Charts for sparkline — 1-line chart, no axes, in the dashboard header.

---

## Execution order

1. **PR A (small, tight parity):** items 1 + 2 + 3 — launch angle + advance ratio + schema migration. Single commit. Biggest per-line win.
2. **PR B (medium):** item 5 — stats tab. Unlocks 6 and 7.
3. **PR C (medium):** item 6 — per-disc detail. Reuses 5's stats code.
4. **PR D (small):** item 7 — PRs + trends. Mostly UI + voice hookup.
5. **PR E (large, standalone):** item 4 — predicted carry distance. Biggest engineering. Optional data-driven MVP first, aero sim second.

---

## Known open questions

- **Release-height assumption.** The strapdown starts at origin. For distance prediction we need to assume a release height (1.5 m typical). Should this be a user setting, or derived from a one-time calibration?
- **Wind / altitude.** TechDisc ignores these. We can too for MVP; consider adding manual wind entry later.
- **Disc flight numbers.** Needed for item 4. Option: bundle the Inbounds / PDGA flight-number DB (public) and look up by brand+model; fall back to manual entry.
- **Launch angle sign for LH:** like hyzer, launch angle is directionally invariant — no flipping needed. Double-check after first real test.
