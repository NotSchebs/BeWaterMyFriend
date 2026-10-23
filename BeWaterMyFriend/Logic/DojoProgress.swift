import Foundation

/// Belt ranks of the ninja drop, earned by days on which the water goal was
/// reached. Rewards only ever go up: the highest rank is remembered, so a belt
/// is never lost (not even after raising the goal or deleting entries).
nonisolated enum Belt: Int, CaseIterable, Comparable, Sendable {
    case white, yellow, orange, green, blue, purple, brown, black

    /// Total goal days needed for this belt.
    var requiredGoalDays: Int {
        switch self {
        case .white: 0
        case .yellow: 3
        case .orange: 7
        case .green: 14
        case .blue: 30
        case .purple: 50
        case .brown: 75
        case .black: 100
        }
    }

    var name: String {
        switch self {
        case .white: "White belt"
        case .yellow: "Yellow belt"
        case .orange: "Orange belt"
        case .green: "Green belt"
        case .blue: "Blue belt"
        case .purple: "Purple belt"
        case .brown: "Brown belt"
        case .black: "Black belt"
        }
    }

    var title: String {
        switch self {
        case .white: "Novice"
        case .yellow: "Droplet"
        case .orange: "Stream"
        case .green: "River"
        case .blue: "Lake"
        case .purple: "Waterfall"
        case .brown: "Ocean"
        case .black: "Water master"
        }
    }

    var next: Belt? { Belt(rawValue: rawValue + 1) }

    static func belt(forGoalDays days: Int) -> Belt {
        allCases.last { days >= $0.requiredGoalDays } ?? .white
    }

    static func < (lhs: Belt, rhs: Belt) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct DojoStats: Equatable, Sendable {
    /// Days on which the goal was reached.
    var goalDays = 0
    /// Consecutive goal days up to today. Today only extends a streak, it never
    /// breaks it while the day is still running.
    var currentStreak = 0
    var bestStreak = 0
}

enum DojoProgress {
    /// - Parameters:
    ///   - days: daily summaries (only days with entries).
    ///   - today: the current logical day (midnight of its calendar date).
    static func stats(days: [DaySummary], goalML: Double, today: Date, calendar: Calendar) -> DojoStats {
        let goalDates = Set(days.filter { $0.goalReached(goalML: goalML) }.map(\.day))
        var stats = DojoStats(goalDays: goalDates.count)

        // Best streak: walk the goal dates in order.
        var run = 0
        var previous: Date?
        for day in goalDates.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            stats.bestStreak = max(stats.bestStreak, run)
            previous = day
        }

        // Current streak: count back from today (or yesterday if today isn't done yet).
        var cursor = goalDates.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        while goalDates.contains(cursor) {
            stats.currentStreak += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return stats
    }

    /// The companion's size: grows from 80 % to 100 % with today's progress.
    static func companionScale(progress: Double) -> Double {
        0.8 + 0.2 * min(max(progress, 0), 1)
    }
}

extension Belt: Identifiable {
    var id: Int { rawValue }
}
