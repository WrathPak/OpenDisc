import Foundation
import SwiftData

enum ThrowTag: String, Codable, CaseIterable {
    case none = "None"
    case good = "Good throw"
    case notAThrow = "Not a throw"
    case edgeCase = "Edge case"
    case custom = "Custom"
}

@Model
final class ThrowData {
    var timestamp: Date
    var mph: Float
    var rpm: Float
    var peakG: Float
    var hyzer: Float
    var nose: Float
    var wobble: Float
    var durationMS: Int
    var isValid: Bool
    var notes: String
    var tag: String
    var disc: Disc?

    var displayMPH: String {
        mph < 0 ? "--" : String(format: "%.1f", mph)
    }

    var displayRPM: String {
        String(format: "%.0f", rpm)
    }

    var displayHyzer: String {
        String(format: "%.1f\u{00B0}", hyzer)
    }

    init(timestamp: Date, mph: Float, rpm: Float, peakG: Float,
         hyzer: Float, nose: Float, wobble: Float,
         durationMS: Int, isValid: Bool, disc: Disc? = nil,
         notes: String = "", tag: String = ThrowTag.none.rawValue) {
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
    }
}
