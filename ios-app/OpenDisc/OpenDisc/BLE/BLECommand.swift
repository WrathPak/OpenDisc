import Foundation

enum BLECommand {
    case status
    case liveStart
    case liveStop
    case arm
    case getThrow
    case calStart
    case calStop
    case settingsGet
    case settingsSet(autoArm: Bool?, triggerG: Float?)
    case wifiOn
    case wifiOff
    case imuDiag

    var jsonData: Data {
        var dict: [String: Any] = [:]
        switch self {
        case .status:       dict["cmd"] = "status"
        case .liveStart:    dict["cmd"] = "live_start"
        case .liveStop:     dict["cmd"] = "live_stop"
        case .arm:          dict["cmd"] = "arm"
        case .getThrow:     dict["cmd"] = "throw"
        case .calStart:     dict["cmd"] = "cal_start"
        case .calStop:      dict["cmd"] = "cal_stop"
        case .settingsGet:  dict["cmd"] = "settings_get"
        case .settingsSet(let autoArm, let triggerG):
            dict["cmd"] = "settings_set"
            if let autoArm { dict["auto_arm"] = autoArm }
            if let triggerG { dict["trigger_g"] = triggerG }
        case .wifiOn:       dict["cmd"] = "wifi_on"
        case .wifiOff:      dict["cmd"] = "wifi_off"
        case .imuDiag:      dict["cmd"] = "imudiag"
        }
        return (try? JSONSerialization.data(withJSONObject: dict)) ?? Data()
    }
}
