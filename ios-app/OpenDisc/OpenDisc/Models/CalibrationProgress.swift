import Foundation

struct CalibrationProgress: Sendable {
    let points: Int
    let target: Int
    let rpm: Float
    let rpmMin: Float
    let rpmMax: Float
    let hint: String

    var progress: Double {
        guard target > 0 else { return 0 }
        return min(Double(points) / Double(target), 1.0)
    }

    var isReady: Bool {
        points >= target
    }

    init(from response: CalProgressResponse) {
        self.points = response.pts
        self.target = response.target
        self.rpm = response.rpm
        self.rpmMin = response.rpm_min
        self.rpmMax = response.rpm_max
        self.hint = response.hint
    }
}

struct CalibrationResult: Sendable {
    let accepted: Bool
    let radius: Float
    let rx: Float
    let ry: Float
    let points: Int
    let rpmMin: Float
    let rpmMax: Float
    let message: String

    var radiusMM: Float { radius * 1000 }

    init(from response: CalResultResponse) {
        self.accepted = response.accepted
        self.radius = response.radius
        self.rx = response.rx
        self.ry = response.ry
        self.points = response.points
        self.rpmMin = response.rpm_min
        self.rpmMax = response.rpm_max
        self.message = response.msg
    }
}
