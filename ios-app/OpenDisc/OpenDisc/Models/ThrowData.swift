import Foundation
import SwiftData

@Model
final class ThrowData {
    var timestamp: Date
    var releaseMPH: Float
    var releaseRPM: Float
    var peakRPM: Float
    var peakG: Float
    var launchHyzer: Float
    var launchNose: Float
    var wobble: Float
    var durationMS: Int
    var isValid: Bool

    var displayMPH: String {
        releaseMPH < 0 ? "--" : String(format: "%.1f", releaseMPH)
    }

    var displayRPM: String {
        String(format: "%.0f", releaseRPM)
    }

    var displayHyzer: String {
        String(format: "%.1f\u{00B0}", launchHyzer)
    }

    init(timestamp: Date, releaseMPH: Float, releaseRPM: Float, peakRPM: Float,
         peakG: Float, launchHyzer: Float, launchNose: Float, wobble: Float,
         durationMS: Int, isValid: Bool) {
        self.timestamp = timestamp
        self.releaseMPH = releaseMPH
        self.releaseRPM = releaseRPM
        self.peakRPM = peakRPM
        self.peakG = peakG
        self.launchHyzer = launchHyzer
        self.launchNose = launchNose
        self.wobble = wobble
        self.durationMS = durationMS
        self.isValid = isValid
    }
}
