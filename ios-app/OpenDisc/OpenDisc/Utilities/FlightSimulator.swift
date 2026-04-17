import Foundation
import simd

/// Simple 3-DOF point-mass disc flight simulator. Treats orientation as
/// constant (no roll dynamics) and uses fixed lift/drag coefficients — good
/// enough for a first-order carry estimate that responds to mph, launch angle,
/// and hyzer. A full 6-DOF aero sim with stability-dependent coefficients is
/// a larger follow-up.
///
/// The output should be treated as "what a neutral driver would carry given
/// this release" — not a calibrated per-disc prediction.
enum FlightSimulator {
    struct Result {
        let carryFeet: Float
        let apexFeet: Float
        let path: [SIMD3<Float>]  // (x, y, z) in metres
    }

    // Disc + environment constants (neutral driver).
    private static let mass: Float = 0.175       // kg
    private static let area: Float = 0.0568      // m² — full disc planform, not just rim
    private static let airDensity: Float = 1.225 // kg/m³
    private static let gravity: Float = 9.81     // m/s²
    private static let cL: Float = 0.7           // lift coeff, typical driver
    private static let cD: Float = 0.08          // drag coeff, typical driver
    private static let releaseHeight: Float = 1.5 // m
    private static let dt: Float = 0.01          // s
    private static let maxTime: Float = 15       // s — hard cutoff

    /// Predict carry from a released throw.
    /// - mph: forward speed at release
    /// - launchAngleDeg: vertical angle of velocity at release (+up, -down)
    /// - hyzerDeg: bank angle; contributes to a lateral force but does not
    ///   affect carry in this simplified 2D model (we project onto flight plane).
    static func predict(mph: Float,
                        launchAngleDeg: Float,
                        hyzerDeg: Float = 0) -> Result? {
        guard mph > 0 else { return nil }
        let speed = mph * 0.44704 // m/s
        let θ = launchAngleDeg * .pi / 180
        var v = SIMD3<Float>(speed * cos(θ), 0, speed * sin(θ))
        var p = SIMD3<Float>(0, 0, releaseHeight)
        var path: [SIMD3<Float>] = [p]
        var apex: Float = releaseHeight
        var t: Float = 0

        // Reduce lift as hyzer increases — a heavily banked disc generates
        // more sideways force and less vertical lift. cos^2 is a rough proxy.
        let hyzerRad = hyzerDeg * .pi / 180
        let liftScale = cos(hyzerRad) * cos(hyzerRad)

        while p.z > 0 && t < maxTime {
            let vMag = simd_length(v)
            guard vMag > 0.1 else { break }
            let vHat = v / vMag

            // Drag opposes velocity.
            let dragMag = 0.5 * airDensity * vMag * vMag * cD * area
            let drag = -dragMag * vHat

            // Lift perpendicular to velocity in the vertical plane.
            // For simplicity, lift vector = (-vx*vz, 0, vx² + vy²) normalized,
            // scaled by |lift|. In 2D (y = 0) this reduces to rotating vHat 90° up.
            let liftMag = 0.5 * airDensity * vMag * vMag * cL * area * liftScale
            // Perpendicular in xz plane, rotated +90° from velocity (up from direction of motion).
            let lift = SIMD3<Float>(x: -vHat.z, y: Float(0), z: vHat.x) * liftMag

            let acc = (drag + lift) / mass + SIMD3<Float>(x: Float(0), y: Float(0), z: -gravity)
            v += acc * dt
            p += v * dt
            path.append(p)
            if p.z > apex { apex = p.z }
            t += dt
        }

        // Interpolate final point to z = 0 for a cleaner carry number.
        if let last = path.last, last.z < 0, path.count >= 2 {
            let prev = path[path.count - 2]
            let frac = prev.z / (prev.z - last.z)
            let landing = prev + (last - prev) * frac
            path[path.count - 1] = landing
        }

        let carry = path.last.map { simd_length(SIMD2<Float>($0.x, $0.y)) } ?? 0
        return Result(
            carryFeet: carry * 3.28084,
            apexFeet: apex * 3.28084,
            path: path
        )
    }
}
