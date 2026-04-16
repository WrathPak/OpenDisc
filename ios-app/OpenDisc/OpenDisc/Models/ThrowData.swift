import Foundation
import SwiftData

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
         durationMS: Int, isValid: Bool) {
        self.timestamp = timestamp
        self.mph = mph
        self.rpm = rpm
        self.peakG = peakG
        self.hyzer = hyzer
        self.nose = nose
        self.wobble = wobble
        self.durationMS = durationMS
        self.isValid = isValid
    }
}
