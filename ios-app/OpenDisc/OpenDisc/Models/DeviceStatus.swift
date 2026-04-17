import Foundation

struct DeviceStatus: Sendable {
    let state: DeviceState
    let autoArm: Bool
    let radius: Float
    let calRX: Float
    let calRY: Float
    let hasThrow: Bool
    let firmwareVersion: String
    /// Firmware-reported monotonic throw counter. nil on firmware <1.0.1.
    let throwSeq: Int?

    var isCalibrated: Bool { radius > 0 }
    var radiusMM: Float { radius * 1000 }

    init(from response: StatusResponse) {
        self.state = DeviceState(from: response.state)
        self.autoArm = response.auto_arm
        self.radius = response.radius
        self.calRX = response.cal_rx
        self.calRY = response.cal_ry
        self.hasThrow = response.has_throw
        self.firmwareVersion = response.fw_version
        self.throwSeq = response.throw_seq
    }
}
