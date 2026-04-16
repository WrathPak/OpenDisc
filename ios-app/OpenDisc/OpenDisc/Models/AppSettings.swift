import Foundation

enum Handedness: String, Codable, CaseIterable {
    case right = "Right"
    case left = "Left"
}

struct AppSettings: Codable, Equatable {
    var handedness: Handedness = .right

    private static let key = "AppSettings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    func adjustedHyzer(_ rawHyzer: Float) -> Float {
        handedness == .left ? -rawHyzer : rawHyzer
    }

    func hyzerLabel(_ rawHyzer: Float) -> String {
        let adjusted = adjustedHyzer(rawHyzer)
        let dir = adjusted >= 0 ? "hyzer" : "anhyzer"
        return String(format: "%.1f\u{00B0} %@", abs(adjusted), dir)
    }
}
