import AVFoundation

@MainActor
enum VoiceManager {
    private static let synthesizer = AVSpeechSynthesizer()

    static func announceThrow(_ throwData: ThrowResponse, settings: VoiceSettings) {
        guard settings.enabled, throwData.valid else { return }

        var parts: [String] = []

        if settings.callMPH, throwData.mph >= 0 {
            parts.append(String(format: "%.0f miles per hour", throwData.mph))
        }
        if settings.callRPM {
            parts.append(String(format: "%.0f R P M", throwData.rpm))
        }
        if settings.callHyzer {
            let dir = throwData.hyzer >= 0 ? "hyzer" : "anhyzer"
            parts.append(String(format: "%.0f degrees %@", abs(throwData.hyzer), dir))
        }
        if settings.callNose {
            let dir = throwData.nose >= 0 ? "nose up" : "nose down"
            parts.append(String(format: "%.0f degrees %@", abs(throwData.nose), dir))
        }
        if settings.callWobble {
            parts.append(String(format: "%.0f wobble", throwData.wobble))
        }
        if settings.callPeakG {
            parts.append(String(format: "%.0f Gs", throwData.peak_g))
        }

        guard !parts.isEmpty else { return }

        let text = parts.joined(separator: ", ")
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = settings.speechRate
        utterance.volume = settings.volume
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }
}
