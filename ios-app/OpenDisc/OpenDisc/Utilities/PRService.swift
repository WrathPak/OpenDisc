import Foundation
import SwiftData

/// Detects personal records (top MPH) at throw-save time.
enum PRService {
    /// Returns a human-readable PR callout if `candidate` is a new personal best
    /// across one of: all-time, this disc, this throw type, this hand.
    /// Returns nil if the throw is invalid or not a new record in any bucket.
    ///
    /// `history` must already include `candidate`. Runs an in-memory scan — fine
    /// for thousands of throws.
    static func checkForPR(candidate: ThrowData, history: [ThrowData]) -> String? {
        guard candidate.mph > 0 else { return nil }
        let others = history.filter { $0.persistentModelID != candidate.persistentModelID && $0.mph > 0 }

        // All-time — most impressive, announce first.
        if others.map(\.mph).max().map({ candidate.mph > $0 }) ?? true {
            if !others.isEmpty {
                return "New personal best: \(String(format: "%.0f", candidate.mph)) miles per hour"
            }
        }

        // Per-disc
        if let disc = candidate.disc {
            let sameDisc = others.filter { $0.disc?.persistentModelID == disc.persistentModelID }
            if !sameDisc.isEmpty, candidate.mph > (sameDisc.map(\.mph).max() ?? 0) {
                return "New best with \(disc.displayName): \(String(format: "%.0f", candidate.mph)) miles per hour"
            }
        }

        // Per throw type
        let sameType = others.filter { $0.throwType == candidate.throwType }
        if !sameType.isEmpty, candidate.mph > (sameType.map(\.mph).max() ?? 0) {
            return "New \(candidate.throwType.lowercased()) best: \(String(format: "%.0f", candidate.mph)) miles per hour"
        }

        // Per hand
        let sameHand = others.filter { $0.throwHand == candidate.throwHand }
        if !sameHand.isEmpty, candidate.mph > (sameHand.map(\.mph).max() ?? 0) {
            return "New \(candidate.throwHand) best: \(String(format: "%.0f", candidate.mph)) miles per hour"
        }

        return nil
    }
}
