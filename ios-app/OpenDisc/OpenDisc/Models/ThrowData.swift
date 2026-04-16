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
    var hyzer: Float       // raw from device (always RHBH convention)
    var nose: Float
    var wobble: Float
    var durationMS: Int
    var isValid: Bool
    var notes: String
    var tag: String
    var throwType: String  // ThrowType raw value
    var throwHand: String  // ThrowHand raw value
    var disc: Disc?

    /// Hyzer adjusted for handedness. LH flips the sign.
    var adjustedHyzer: Float {
        let hand = ThrowHand(rawValue: throwHand) ?? .right
        return hand.isLeft ? -hyzer : hyzer
    }

    var displayMPH: String {
        mph < 0 ? "--" : String(format: "%.1f", mph)
    }

    var displayRPM: String {
        String(format: "%.0f", rpm)
    }

    var displayHyzer: String {
        let h = adjustedHyzer
        let label = h >= 0 ? "hyzer" : "anhy"
        return String(format: "%.1f\u{00B0} %@", abs(h), label)
    }

    var displayThrowType: String {
        let type = ThrowType(rawValue: throwType) ?? .backhand
        let hand = ThrowHand(rawValue: throwHand) ?? .right
        return "\(hand.rawValue) \(type.rawValue)"
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
        self.hyzer = hyzer
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
