import Foundation
import simd

/// A single point along the reconstructed throw trajectory.
struct TrajectoryPoint {
    /// Position in world frame (meters). X/Y horizontal, Z vertical.
    let position: SIMD3<Float>
    /// Disc orientation quaternion (body to world).
    let orientation: simd_quatf
    /// Speed magnitude (m/s).
    let speed: Float
    /// Time relative to trigger index (seconds; negative = pre-trigger).
    let time: Float
    /// True if this is the release sample.
    let isRelease: Bool
}

/// Result of running the strapdown integration.
struct Trajectory {
    let points: [TrajectoryPoint]
    let releaseIndex: Int
    let stationaryIndex: Int
    /// Max position magnitude across the path (for camera framing).
    let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
}

/// Strapdown inertial integration from a raw `dump_raw` sample set.
///
/// Reconstructs the disc's 3D path in the world frame using the same algorithm
/// the firmware runs for MPH/angle computation, but over the full ring buffer
/// instead of just the release window.
///
/// Accuracy notes:
/// - Position drift accumulates roughly quadratically. Over 1 s expect a few
///   cm of error; over the full 2 s burst expect 10-20 cm.
/// - Orientation is more robust. Gyro bias estimated from the stationary
///   window keeps the quaternion from drifting meaningfully over 2 s.
/// Reason trajectory reconstruction failed, with enough context to diagnose.
enum TrajectoryError: Error, CustomStringConvertible {
    case tooFewSamples(count: Int)
    case noStationaryWindow(samplesSearched: Int)
    case lowGravityReading(magnitude: Float, samplesSearched: Int)

    var description: String {
        switch self {
        case .tooFewSamples(let count):
            return "Only \(count) samples in the dump — need at least 64."
        case .noStationaryWindow(let searched):
            return "Couldn't find a still reference window in \(searched) samples."
        case .lowGravityReading(let magnitude, let searched):
            return String(format:
                "Accel reading during the quietest window was only %.2f g — need ~1.0 g. "
                + "Tried %d search positions. The disc may have been in motion for "
                + "the entire burst, or the IMU is miscalibrated.",
                magnitude, searched)
        }
    }
}

enum TrajectoryEngine {
    /// Compute trajectory from raw burst samples.
    ///
    /// - Parameters:
    ///   - samples: Raw dump samples (expected length ~1920). Must be ordered
    ///     by index `i` ascending (pre-trigger negative through post-trigger).
    ///   - releaseIndex: Sample index within `samples` array for the release
    ///     point, or nil to auto-detect from motion profile.
    ///   - calRx: Calibrated chip-to-CoM offset X (meters). Pass 0 if uncal.
    ///   - calRy: Calibrated chip-to-CoM offset Y (meters). Pass 0 if uncal.
    /// - Returns: Reconstructed trajectory.
    /// - Throws: `TrajectoryError` describing why reconstruction failed.
    static func compute(samples: [DumpSampleResponse],
                        releaseIndex: Int? = nil,
                        calRx: Float = 0,
                        calRy: Float = 0) throws -> Trajectory {
        guard samples.count >= 64 else {
            throw TrajectoryError.tooFewSamples(count: samples.count)
        }

        // 1. Find the quietest 16-sample window anywhere in the buffer.
        //    (Earlier code restricted search to the first half; that
        //    assumed the pre-trigger region was stationary, which breaks
        //    when the thrower has already wound up their backswing before
        //    the ring fills. Searching the whole buffer gives us a chance
        //    of finding the stationary moment before the wind-up or after
        //    catching.)
        let searchEnd = max(16, samples.count - 16)
        guard let stationaryStart = findStationaryWindow(samples: samples,
                                                         start: 0,
                                                         end: searchEnd,
                                                         length: 16) else {
            throw TrajectoryError.noStationaryWindow(samplesSearched: samples.count)
        }
        let stationaryEnd = stationaryStart + 16

        // 2. Estimate gyro bias and gravity direction from the stationary window.
        var biasSum = SIMD3<Float>.zero
        var accelSum = SIMD3<Float>.zero
        for i in stationaryStart..<stationaryEnd {
            let s = samples[i]
            biasSum += SIMD3(Float(s.gx), Float(s.gy), Float(s.gz)) * IMUConstants.gyroSens
            accelSum += SIMD3(Float(s.ax), Float(s.ay), Float(s.az)) * IMUConstants.accelSens
        }
        let gyroBias = biasSum / 16.0
        let gravityBody = accelSum / 16.0   // in g units, body frame

        // 3. Initialize world-to-body quaternion so that gravity in the body
        //    frame maps to (0, 0, -1) in the world frame (i.e. -Z is down).
        let gravityMag = simd_length(gravityBody)
        guard gravityMag > 0.5 else {
            throw TrajectoryError.lowGravityReading(magnitude: gravityMag,
                                                    samplesSearched: samples.count)
        }
        let gravityBodyNormalized = gravityBody / gravityMag
        // Rotate body "down" vector to world "down" vector
        let worldDown = SIMD3<Float>(0, 0, -1)
        var q = quaternionFromVectors(gravityBodyNormalized, worldDown)

        // 4. Forward-integrate from the stationary window through the end.
        //    Skip samples before the stationary window -- they'd have unknown
        //    history. We record them as zero-position pre-stationary frames
        //    just so the array index aligns with the input samples.
        var points: [TrajectoryPoint] = []
        points.reserveCapacity(samples.count)

        // Pad pre-stationary samples with stationary state
        let preStationaryPoint = TrajectoryPoint(
            position: .zero,
            orientation: q,
            speed: 0,
            time: 0,
            isRelease: false
        )
        for i in 0..<stationaryStart {
            let t = Float(samples[i].i) * IMUConstants.dt
            points.append(TrajectoryPoint(
                position: .zero,
                orientation: q,
                speed: 0,
                time: t,
                isRelease: false
            ))
            _ = preStationaryPoint
        }

        var position = SIMD3<Float>.zero
        var velocity = SIMD3<Float>.zero
        let dt = IMUConstants.dt

        // Bounds tracking
        var minPos = SIMD3<Float>.zero
        var maxPos = SIMD3<Float>.zero

        for i in stationaryStart..<samples.count {
            let s = samples[i]
            let t = Float(s.i) * dt

            // Body-frame angular rate (rad/s) with bias subtracted.
            let gyroDps = SIMD3<Float>(Float(s.gx), Float(s.gy), Float(s.gz)) * IMUConstants.gyroSens
            let omega = (gyroDps - gyroBias) * IMUConstants.dps2rad

            // Body-frame linear acceleration. Use HG when main clips.
            let mainClipped = abs(s.ax) > IMUConstants.mainAccelClipThreshold ||
                              abs(s.ay) > IMUConstants.mainAccelClipThreshold ||
                              abs(s.az) > IMUConstants.mainAccelClipThreshold
            let accelG: SIMD3<Float>
            if mainClipped {
                accelG = SIMD3(Float(s.hx), Float(s.hy), Float(s.hz)) * IMUConstants.hgAccelSens
            } else {
                accelG = SIMD3(Float(s.ax), Float(s.ay), Float(s.az)) * IMUConstants.accelSens
            }
            var accelBody = accelG * IMUConstants.g2mps2

            // Subtract centripetal force in body frame: a_c = omega x (omega x r)
            // where r = (calRx, calRy, 0) is the chip position from CoM.
            if calRx != 0 || calRy != 0 {
                let r = SIMD3<Float>(calRx, calRy, 0)
                let centripetal = simd_cross(omega, simd_cross(omega, r))
                accelBody -= centripetal
            }

            // Rotate body to world.
            var accelWorld = q.act(accelBody)
            // Subtract gravity in world frame (Z is up, so subtract +g from Z).
            accelWorld.z -= IMUConstants.gravity

            // Integrate velocity and position (Euler).
            velocity += accelWorld * dt
            position += velocity * dt

            // Update orientation using first-order quaternion integration.
            // dq = 0.5 * omega_quat * q * dt
            let omegaQuat = simd_quatf(real: 0, imag: omega * 0.5 * dt)
            let dq = omegaQuat * q
            q = simd_quatf(vector: q.vector + dq.vector)
            q = q.normalized

            let speed = simd_length(velocity)
            let isRelease = (releaseIndex != nil && i == releaseIndex!)

            points.append(TrajectoryPoint(
                position: position,
                orientation: q,
                speed: speed,
                time: t,
                isRelease: isRelease
            ))

            minPos = simd_min(minPos, position)
            maxPos = simd_max(maxPos, position)
        }

        return Trajectory(
            points: points,
            releaseIndex: releaseIndex ?? -1,
            stationaryIndex: stationaryStart,
            bounds: (min: minPos, max: maxPos)
        )
    }

    /// Finds the starting index of the N-sample window with the lowest total
    /// gyro + accel variance. Matches the firmware's stationary-window fallback.
    private static func findStationaryWindow(samples: [DumpSampleResponse],
                                             start: Int,
                                             end: Int,
                                             length: Int) -> Int? {
        guard end - start >= length else { return nil }

        var bestStart = start
        var bestScore = Float.greatestFiniteMagnitude

        for w in start...(end - length) {
            var gyroSumSq: Float = 0
            var accelMeanSq: Float = 0

            // Sum-of-squares gyro magnitude
            for k in 0..<length {
                let s = samples[w + k]
                let gx = Float(s.gx) * IMUConstants.gyroSens
                let gy = Float(s.gy) * IMUConstants.gyroSens
                let gz = Float(s.gz) * IMUConstants.gyroSens
                gyroSumSq += gx * gx + gy * gy + gz * gz
            }

            // Accel deviation from 1 g magnitude
            for k in 0..<length {
                let s = samples[w + k]
                let ax = Float(s.ax) * IMUConstants.accelSens
                let ay = Float(s.ay) * IMUConstants.accelSens
                let az = Float(s.az) * IMUConstants.accelSens
                let mag = sqrtf(ax * ax + ay * ay + az * az)
                let dev = mag - 1.0
                accelMeanSq += dev * dev
            }

            // Weighted combined score (gyro dominates motion signal)
            let score = gyroSumSq + accelMeanSq * 1000.0

            if score < bestScore {
                bestScore = score
                bestStart = w
            }
        }

        return bestStart
    }

    /// Computes the shortest-arc rotation quaternion from `from` to `to`.
    /// Both vectors must be unit length.
    private static func quaternionFromVectors(_ from: SIMD3<Float>,
                                              _ to: SIMD3<Float>) -> simd_quatf {
        let dot = simd_dot(from, to)
        if dot > 0.9999 {
            return simd_quatf(real: 1, imag: .zero)
        }
        if dot < -0.9999 {
            // 180 degree rotation -- pick any orthogonal axis
            let axis = abs(from.x) < 0.9
                ? simd_normalize(simd_cross(from, SIMD3<Float>(1, 0, 0)))
                : simd_normalize(simd_cross(from, SIMD3<Float>(0, 1, 0)))
            return simd_quatf(angle: .pi, axis: axis)
        }
        let axis = simd_normalize(simd_cross(from, to))
        let angle = acosf(dot)
        return simd_quatf(angle: angle, axis: axis)
    }
}
