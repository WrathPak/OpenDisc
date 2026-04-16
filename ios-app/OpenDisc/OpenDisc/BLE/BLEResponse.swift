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
    let peak_rpm: Float
    let release_rpm: Float
    let release_mph: Float
    let peak_g: Float
    let launch_hyzer: Float
    let launch_nose: Float
    let wobble: Float
    let duration_ms: Int
    let release_idx: Int
    let motion_start_idx: Int
    let stationary_end: Int
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
}
