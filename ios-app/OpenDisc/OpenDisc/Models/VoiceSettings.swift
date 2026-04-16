import Foundation

extension Notification.Name {
    static let voiceSettingsChanged = Notification.Name("voiceSettingsChanged")
}

struct VoiceSettings: Codable, Equatable {
    var enabled: Bool = true
    var callMPH: Bool = true
    var callRPM: Bool = true
    var callHyzer: Bool = false
    var callNose: Bool = false
    var callWobble: Bool = false
    var callPeakG: Bool = false
    var speechRate: Float = 0.52  // AVSpeechUtteranceDefaultSpeechRate is ~0.5
    var volume: Float = 1.0

    private static let key = "VoiceSettings"

    static func load() -> VoiceSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(VoiceSettings.self, from: data)
        else { return VoiceSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
