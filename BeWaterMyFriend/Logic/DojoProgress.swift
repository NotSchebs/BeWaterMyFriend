import Foundation

/// Ranks of the ninja drop, earned by days on which the water goal was reached.
/// Coloured belts lead to the black belt; after that come ten Dan ranks, like in
/// judo and BJJ ("black belt is only the beginning"). Rewards only go up: the
/// highest rank is remembered, so it's never lost (not even after raising the
/// goal or deleting entries). The only reset is the optional prestige, which
/// the user has to confirm.
nonisolated enum Belt: Int, CaseIterable, Comparable, Sendable {
    case white, yellow, orange, green, blue, purple, brown, black
    case dan1, dan2, dan3, dan4, dan5, dan6, dan7, dan8, dan9, dan10

    /// Goal days needed for this rank.
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
        case .dan1: 150
        case .dan2: 200
        case .dan3: 275
        case .dan4: 365
        case .dan5: 450
        case .dan6: 550
        case .dan7: 650
        case .dan8: 750
        case .dan9: 875
        case .dan10: 1000
        }
    }

    /// 1…10 for Dan ranks, `nil` for coloured belts.
    var danLevel: Int? {
        rawValue >= Belt.dan1.rawValue ? rawValue - Belt.black.rawValue : nil
    }

    var isDan: Bool { danLevel != nil }

    var name: String {
        switch self {
        case .white: return "White belt"
        case .yellow: return "Yellow belt"
        case .orange: return "Orange belt"
        case .green: return "Green belt"
        case .blue: return "Blue belt"
        case .purple: return "Purple belt"
        case .brown: return "Brown belt"
        case .black: return "Black belt"
        default:
            let level = danLevel ?? 1
            let suffix = switch level { case 1: "st"; case 2: "nd"; case 3: "rd"; default: "th" }
            return "\(level)\(suffix) Dan"
        }
    }

    /// Japanese rank name for Dan ranks.
    var japaneseName: String? {
        switch self {
        case .dan1: "Shodan"
        case .dan2: "Nidan"
        case .dan3: "Sandan"
        case .dan4: "Yondan"
        case .dan5: "Godan"
        case .dan6: "Rokudan"
        case .dan7: "Nanadan"
        case .dan8: "Hachidan"
        case .dan9: "Kudan"
        case .dan10: "Jūdan"
        default: nil
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
        case .dan1: "Tide"
        case .dan2: "Current"
        case .dan3: "Rapids"
        case .dan4: "Monsoon"
        case .dan5: "Glacier"
        case .dan6: "Typhoon"
        case .dan7: "Abyss"
        case .dan8: "Tsunami"
        case .dan9: "Moon tide"
        case .dan10: "Sea dragon"
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

/// Goal days and streaks of finished days older than a week, counted once and
/// stored. Those days can't change any more (drinks can only be logged two
/// days back), so the app doesn't have to recalculate years of history on
/// every update: it only looks at the days after `throughDay`.
struct DojoArchive: Codable, Equatable, Sendable {
    /// Last archived logical day (midnight), or nil when nothing is archived yet.
    var throughDay: Date?
    var goalDays = 0
    var bestStreak = 0
    /// Consecutive goal days ending exactly on `throughDay`.
    var trailingRun = 0

    /// How many recent days stay "live" (recalculated on every update).
    static let liveDays = 7

    /// The last day that should be archived for `today`.
    static func archiveLimit(today: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -liveDays, to: today)!
    }

    /// Adds the days after `throughDay` up to and including `newThrough`.
    /// `days` are the summaries for that range (days without entries may be missing).
    func advanced(through newThrough: Date, days: [DaySummary], goalML: Double, calendar: Calendar) -> DojoArchive {
        var result = self
        let goalDates = Set(days.filter { $0.goalReached(goalML: goalML) }.map(\.day))
        // Start the day after the old boundary; on the first run, at the first logged day.
        guard var cursor = throughDay.flatMap({ calendar.date(byAdding: .day, value: 1, to: $0) })
                ?? days.map(\.day).min() else {
            result.throughDay = newThrough
            return result
        }
        while cursor <= newThrough {
            if goalDates.contains(cursor) {
                result.goalDays += 1
                result.trailingRun += 1
                result.bestStreak = max(result.bestStreak, result.trailingRun)
            } else {
                result.trailingRun = 0
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        result.throughDay = newThrough
        return result
    }
}

enum DojoProgress {
    /// Stats from the archive plus the recent days after it.
    static func stats(recentDays: [DaySummary], archive: DojoArchive, goalML: Double,
                      today: Date, calendar: Calendar) -> DojoStats {
        let recent = recentDays.filter { archive.throughDay == nil || $0.day > archive.throughDay! }
        let goalDates = Set(recent.filter { $0.goalReached(goalML: goalML) }.map(\.day))
        var stats = DojoStats(goalDays: archive.goalDays + goalDates.count, currentStreak: 0, bestStreak: archive.bestStreak)

        // Walk from the day after the archive to today, continuing the archived run.
        let first = archive.throughDay.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) }
            ?? recent.map(\.day).min() ?? today
        var run = archive.trailingRun
        var cursor = first
        while cursor <= today {
            if goalDates.contains(cursor) {
                run += 1
                stats.bestStreak = max(stats.bestStreak, run)
            } else if cursor < today {
                run = 0  // today doesn't break a streak while it's still running
            }
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor)!
        }
        stats.currentStreak = run
        return stats
    }

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

    /// Goal days that count toward the current rank. Prestige restarts the
    /// ranks from white belt; goal days before it are kept in history but no
    /// longer count toward the belt.
    static func rankGoalDays(bestTotal: Int, currentTotal: Int, prestigeBase: Int) -> Int {
        max(max(bestTotal, currentTotal) - prestigeBase, 0)
    }

    /// Prestige is offered once the highest Dan rank is reached.
    static func canPrestige(_ belt: Belt) -> Bool { belt == .dan10 }

    /// The companion's size: grows from 80 % to 100 % with today's progress.
    static func companionScale(progress: Double) -> Double {
        0.8 + 0.2 * min(max(progress, 0), 1)
    }
}

extension Belt: Identifiable {
    var id: Int { rawValue }
}
