import Foundation

/// Aggregate statistics over a set of throws. Values are nil when the input
/// is empty or the source metric is unavailable.
struct ThrowStatistics {
    let throws_: [ThrowData]

    var count: Int { throws_.count }

    private var validMPH: [Float] { throws_.map(\.mph).filter { $0 > 0 } }

    var avgMPH: Float? { mean(validMPH) }
    var bestMPH: Float? { validMPH.max() }

    var avgRPM: Float? { mean(throws_.map(\.rpm).filter { $0 > 0 }) }
    var bestRPM: Float? { throws_.map(\.rpm).filter { $0 > 0 }.max() }

    var avgHyzer: Float? { mean(throws_.map(\.hyzer)) }
    var avgNose: Float? { mean(throws_.map(\.nose)) }
    var avgWobble: Float? { mean(throws_.map(\.wobble)) }

    var avgLaunch: Float? {
        let vals = throws_.filter { $0.mph > 0 }.map(\.launchAngle)
        return mean(vals)
    }

    var avgAdvanceRatio: Float? {
        let vals = throws_.compactMap { $0.advanceRatio }
        return mean(vals)
    }

    /// PR throws, top 3 by MPH.
    var prThrows: [ThrowData] {
        throws_.filter { $0.mph > 0 }
            .sorted { $0.mph > $1.mph }
            .prefix(3)
            .map { $0 }
    }

    /// 0-100 consistency score. Lower std-dev in mph + hyzer = higher score.
    /// Returns nil with fewer than 3 samples.
    var consistencyScore: Int? {
        guard validMPH.count >= 3 else { return nil }
        let mphScore = normalizedInverseStdDev(validMPH, scale: 6.0)
        let hyzerScore = normalizedInverseStdDev(throws_.map(\.hyzer), scale: 10.0)
        return Int(((mphScore + hyzerScore) / 2) * 100)
    }

    // MARK: - Helpers

    private func mean(_ values: [Float]) -> Float? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Float(values.count)
    }

    private func stdDev(_ values: [Float]) -> Float? {
        guard values.count > 1, let m = mean(values) else { return nil }
        let sq = values.map { ($0 - m) * ($0 - m) }
        return sqrt(sq.reduce(0, +) / Float(values.count - 1))
    }

    /// Maps std-dev to [0, 1] via `max(0, 1 - sd/scale)` — bigger `scale` is
    /// more forgiving. `scale` is the std-dev at which the score hits 0.
    private func normalizedInverseStdDev(_ values: [Float], scale: Float) -> Float {
        guard let sd = stdDev(values) else { return 0 }
        return max(0, min(1, 1 - sd / scale))
    }
}
