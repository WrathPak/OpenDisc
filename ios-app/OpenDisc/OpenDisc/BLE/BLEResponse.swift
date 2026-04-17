import Foundation

struct StatusResponse: Decodable {
    let type: String
    let state: String
    let auto_arm: Bool
    let radius: Float
    let cal_rx: Float
    let cal_ry: Float
    let has_throw: Bool
    let fw_version: String
    /// Firmware-supplied monotonic throw counter. nil on firmware older than 1.0.1.
    let throw_seq: Int?
}

struct LiveResponse: Decodable {
    let type: String
    let rpm_gyro: Float
    let rpm_accel: Float
    let accel_g: Float
    let hg_g: Float
    let hyzer: Float
    let nose: Float
    let gyro_clipped: Bool
    let state: String
}

struct ThrowResponse: Decodable {
    let type: String
    let valid: Bool
    let rpm: Float
    let mph: Float
    let peak_g: Float
    let hyzer: Float
    let nose: Float
    let wobble: Float
    let duration_ms: Int
    let release_idx: Int
    let motion_start_idx: Int
    let stationary_end: Int
    // Launch angle (vertical angle of the velocity vector at release).
    // Optional: older firmware doesn't emit this field.
    let launch: Float?
    /// Firmware-supplied monotonic throw counter. nil on firmware older than 1.0.1.
    let seq: Int?
}

struct ThrowReadyResponse: Decodable {
    let type: String
    let seq: Int?
}

struct StateEvent: Decodable {
    let type: String
    let state: String
}

struct CalProgressResponse: Decodable {
    let type: String
    let pts: Int
    let target: Int
    let rpm: Float
    let rpm_min: Float
    let rpm_max: Float
    let hint: String
}

struct CalResultResponse: Decodable {
    let type: String
    let accepted: Bool
    let radius: Float
    let rx: Float
    let ry: Float
    let points: Int
    let rpm_min: Float
    let rpm_max: Float
    let msg: String
}

struct SettingsResponse: Decodable {
    let type: String
    let auto_arm: Bool
    let trigger_g: Float
}

struct IMUDiagResponse: Decodable {
    let type: String
    let whoami: String
    let ctrl1: String
    let ctrl2: String
    let ctrl6: String
    let ctrl8: String
    let ctrl9: String
    let ctrl1_xl_hg: String
    let fs_g: String
    let fs_xl: String
}

struct AckResponse: Decodable {
    let type: String
    let msg: String
}

struct DumpStatusResponse: Decodable {
    let type: String
    let status: String
    let samples: Int?
    let frames: Int?
    let spf: Int?        // samples per frame (binary protocol)
    let fmt: String?     // "bin1" = binary protocol v1
    let mode: String?    // "prn" (firmware 1.1.0+), "push" (1.0.9), "pull" (legacy)
    let batch: Int?      // PRN batch size — ACK every this-many frames
}

struct DumpSampleResponse: Codable {
    let type: String
    let i: Int
    let ax: Int16
    let ay: Int16
    let az: Int16
    let gx: Int16
    let gy: Int16
    let gz: Int16
    let hx: Int16
    let hy: Int16
    let hz: Int16
}

enum BLEResponseType: String {
    case status
    case live
    case `throw`  = "throw"
    case state
    case throwReady = "throw_ready"
    case calProgress = "cal_progress"
    case calResult = "cal_result"
    case settings
    case imudiag
    case ack
    case dump
    case d
}
