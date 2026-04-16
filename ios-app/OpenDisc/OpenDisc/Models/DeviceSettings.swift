import Foundation

struct DeviceSettings: Sendable, Equatable {
    var autoArm: Bool
    var triggerG: Float

    init(from response: SettingsResponse) {
        self.autoArm = response.auto_arm
        self.triggerG = response.trigger_g
    }

    init(autoArm: Bool = true, triggerG: Float = 3.0) {
        self.autoArm = autoArm
        self.triggerG = triggerG
    }
}
