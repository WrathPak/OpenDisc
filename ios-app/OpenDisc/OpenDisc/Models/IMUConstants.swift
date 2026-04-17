import Foundation

/// Raw IMU sensor conversion constants.
///
/// These match the firmware (`firmware/opendisc/sensors.h`). The `dump_raw`
/// BLE command streams unconverted int16 samples; multiply by these constants
/// to get physical units.
enum IMUConstants {
    /// Gyroscope: dps per LSB. Firmware runs at 4000 dps full-scale.
    /// Ceiling: 666 RPM before clipping.
    static let gyroSens: Float = 0.140

    /// Main accelerometer: g per LSB (+-16 g full-scale).
    static let accelSens: Float = 0.000488

    /// High-G accelerometer: g per LSB (+-320 g full-scale).
    static let hgAccelSens: Float = 0.00977

    /// Magnetometer: gauss per LSB (unused by trajectory engine).
    static let magSens: Float = 1.0 / 6842.0

    /// Sample rate of the burst ring buffer.
    static let sampleRate: Float = 960

    /// Time delta between samples (seconds).
    static let dt: Float = 1.0 / 960.0

    /// Earth gravity (m/s^2).
    static let gravity: Float = 9.81

    /// Main accel saturates near ±32767. Switch to HG accel above this.
    static let mainAccelClipThreshold: Int16 = 32000

    /// Degrees to radians.
    static let dps2rad: Float = .pi / 180.0

    /// g to m/s^2.
    static let g2mps2: Float = 9.81
}
