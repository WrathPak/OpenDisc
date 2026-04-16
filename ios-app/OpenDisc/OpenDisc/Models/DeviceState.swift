import SwiftUI

enum DeviceState: String, CaseIterable, Sendable {
    case idle = "IDLE"
    case armed = "ARMED"
    case capturing = "CAPTURING"
    case done = "DONE"
    case calibrating = "CALIBRATING"
    case unknown = "UNKNOWN"

    init(from string: String) {
        self = DeviceState(rawValue: string) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .idle:        "Idle"
        case .armed:       "Armed"
        case .capturing:   "Capturing"
        case .done:        "Done"
        case .calibrating: "Calibrating"
        case .unknown:     "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .idle:        .secondary
        case .armed:       .green
        case .capturing:   .orange
        case .done:        .blue
        case .calibrating: .purple
        case .unknown:     .gray
        }
    }

    var systemImage: String {
        switch self {
        case .idle:        "circle"
        case .armed:       "scope"
        case .capturing:   "waveform.path"
        case .done:        "checkmark.circle"
        case .calibrating: "gyroscope"
        case .unknown:     "questionmark.circle"
        }
    }
}
