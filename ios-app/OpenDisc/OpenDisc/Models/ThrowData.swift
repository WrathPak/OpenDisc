import Foundation
import SwiftData

enum ThrowTag: String, Codable, CaseIterable {
    case none = "None"
    case good = "Good throw"
    case notAThrow = "Not a throw"
    case edgeCase = "Edge case"
    case custom = "Custom"
}

enum ThrowType: String, Codable, CaseIterable {
    case backhand = "Backhand"
    case forehand = "Forehand"
}

enum ThrowHand: String, Codable, CaseIterable {
    case right = "RH"
    case left = "LH"

    var isLeft: Bool { self == .left }
}

@Model
final class ThrowData {
    var timestamp: Date
    var mph: Float
    var rpm: Float
    var peakG: Float
    var hyzer: Float       // stored already flipped for handedness at record time
    var nose: Float
    var wobble: Float
    var durationMS: Int
    var isValid: Bool
    var notes: String
    var tag: String
    var throwType: String  // ThrowType raw value
    var throwHand: String  // ThrowHand raw value
    var disc: Disc?

    /// Encoded `[DumpSampleResponse]` from the `dump_raw` BLE stream.
    /// Used to reconstruct the 3D trajectory on demand. Optional because old
    /// throws and throws where the dump failed/was skipped won't have it.
    var rawSamples: Data?

    /// Release sample index within the raw buffer (matches `ThrowResponse.release_idx`).
    var releaseIdx: Int = 0

    /// Calibration chip offset at the time of the throw, for trajectory reconstruction.
    var calRx: Float = 0
    var calRy: Float = 0

    /// Vertical launch angle (deg). +up, -down. 0 when strapdown failed (same as mph < 0).
    var launchAngle: Float = 0

    /// Decoded raw samples, or nil if not available.
    var decodedSamples: [DumpSampleResponse]? {
        guard let data = rawSamples else { return nil }
        return try? JSONDecoder().decode([DumpSampleResponse].self, from: data)
    }

    /// True if this throw has raw data suitable for trajectory reconstruction.
    var hasTrajectoryData: Bool {
        guard let data = rawSamples else { return false }
        return data.count > 0
    }

    var displayMPH: String {
        mph < 0 ? "--" : String(format: "%.1f", mph)
    }

    var displayRPM: String {
        String(format: "%.0f", rpm)
    }

    var displayHyzer: String {
        let label = hyzer >= 0 ? "hyzer" : "anhy"
        return String(format: "%.1f\u{00B0} %@", abs(hyzer), label)
    }

    /// Launch angle display. Returns "--" when unavailable, "flat" when near zero, else "6.4° up/down".
    var displayLaunch: String {
        guard mph >= 0 else { return "--" }
        if abs(launchAngle) < 0.5 { return "flat" }
        let dir = launchAngle >= 0 ? "up" : "down"
        return String(format: "%.1f\u{00B0} %@", abs(launchAngle), dir)
    }

    /// Dimensionless ratio of rim tangential speed to forward speed.
    /// nil when mph is invalid. Target ~0.50 BH, ~0.30 FH.
    var advanceRatio: Float? {
        guard mph > 0 else { return nil }
        let radius = disc?.radius ?? 0.105
        let rpsRad = rpm * 2 * .pi / 60
        let mps = mph * 0.44704
        guard mps > 0 else { return nil }
        return (rpsRad * radius) / mps
    }

    var advanceRatioTarget: Float {
        throwType == ThrowType.forehand.rawValue ? 0.30 : 0.50
    }

    /// Simulated carry in feet. Treat as a rough first-order estimate —
    /// the simulator uses a single neutral-driver aero profile.
    var predictedCarryFeet: Float? {
        guard mph > 0 else { return nil }
        return FlightSimulator.predict(
            mph: mph,
            launchAngleDeg: launchAngle,
            hyzerDeg: hyzer
        )?.carryFeet
    }

    var displayThrowType: String {
        let type = ThrowType(rawValue: throwType) ?? .backhand
        let hand = ThrowHand(rawValue: throwHand) ?? .right
        return "\(hand.rawValue) \(type.rawValue)"
    }

    /// Call when changing throwHand on an existing throw to re-flip hyzer.
    func toggleHand(to newHand: ThrowHand) {
        let currentHand = ThrowHand(rawValue: throwHand) ?? .right
        if currentHand != newHand {
            hyzer = -hyzer
            throwHand = newHand.rawValue
        }
    }

    init(timestamp: Date, mph: Float, rpm: Float, peakG: Float,
         hyzer: Float, nose: Float, wobble: Float,
         durationMS: Int, isValid: Bool, disc: Disc? = nil,
         notes: String = "", tag: String = ThrowTag.none.rawValue,
         throwType: ThrowType = .backhand, throwHand: ThrowHand = .right) {
        self.timestamp = timestamp
        self.mph = mph
        self.rpm = rpm
        self.peakG = peakG
        // Flip hyzer at record time for LH
        self.hyzer = throwHand.isLeft ? -hyzer : hyzer
        self.nose = nose
        self.wobble = wobble
        self.durationMS = durationMS
        self.isValid = isValid
        self.disc = disc
        self.notes = notes
        self.tag = tag
        self.throwType = throwType.rawValue
        self.throwHand = throwHand.rawValue
    }
}
