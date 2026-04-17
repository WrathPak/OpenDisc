import Foundation
import SwiftData

enum StatsDateRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "7d"
    case month = "30d"
    case all = "All"

    var id: String { rawValue }

    func includes(_ date: Date, now: Date = Date()) -> Bool {
        switch self {
        case .all: return true
        case .today:
            return Calendar.current.isDate(date, inSameDayAs: now)
        case .week:
            return date >= now.addingTimeInterval(-7 * 24 * 3600)
        case .month:
            return date >= now.addingTimeInterval(-30 * 24 * 3600)
        }
    }
}

enum StatsTypeFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case backhand = "BH"
    case forehand = "FH"

    var id: String { rawValue }
}

enum StatsHandFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case right = "RH"
    case left = "LH"

    var id: String { rawValue }
}

struct StatsFilter {
    var dateRange: StatsDateRange = .week
    var discID: PersistentIdentifier? = nil
    var typeFilter: StatsTypeFilter = .all
    var handFilter: StatsHandFilter = .all
    var excludeNotAThrow: Bool = true

    func apply(to throws_: [ThrowData]) -> [ThrowData] {
        let now = Date()
        return throws_.filter { t in
            guard dateRange.includes(t.timestamp, now: now) else { return false }
            if let discID, t.disc?.persistentModelID != discID { return false }
            switch typeFilter {
            case .all: break
            case .backhand: if t.throwType != ThrowType.backhand.rawValue { return false }
            case .forehand: if t.throwType != ThrowType.forehand.rawValue { return false }
            }
            switch handFilter {
            case .all: break
            case .right: if t.throwHand != ThrowHand.right.rawValue { return false }
            case .left: if t.throwHand != ThrowHand.left.rawValue { return false }
            }
            if excludeNotAThrow && t.tag == ThrowTag.notAThrow.rawValue { return false }
            return true
        }
    }
}
