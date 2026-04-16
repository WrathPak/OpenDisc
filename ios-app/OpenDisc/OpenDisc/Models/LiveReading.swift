import Foundation

struct LiveReading: Sendable {
    let rpmGyro: Float
    let rpmAccel: Float
    let accelG: Float
    let hgG: Float
    let hyzer: Float
    let nose: Float
    let gyroClipped: Bool
    let state: String

    var bestRPM: Float {
        gyroClipped || rpmGyro > 327 ? rpmAccel : rpmGyro
    }

    init(from response: LiveResponse) {
        self.rpmGyro = response.rpm_gyro
        self.rpmAccel = response.rpm_accel
        self.accelG = response.accel_g
        self.hgG = response.hg_g
        self.hyzer = response.hyzer
        self.nose = response.nose
        self.gyroClipped = response.gyro_clipped
        self.state = response.state
    }
}
