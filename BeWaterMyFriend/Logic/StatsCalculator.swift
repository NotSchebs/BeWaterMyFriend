import Foundation

/// One day in a chart. `ml` is nil when nothing was logged (no data, not zero).
nonisolated struct DayPoint: Identifiable, Equatable, Sendable {
    var day: Date
    var ml: Double?
    var caffeineMg: Double
    var standardDrinks: Double
    var goalReached: Bool
    var id: Date { day }
}

/// Average per week, for the trend chart.
nonisolated struct WeekPoint: Identifiable, Equatable, Sendable {
    /// First day of the week.
    var weekStart: Date
    var averageML: Double?
    var goalDays: Int
    var loggedDays: Int
    var id: Date { weekStart }
}

nonisolated struct WeekdayPoint: Identifiable, Equatable, Sendable {
    /// 1 = Sunday … 7 = Saturday (Calendar's numbering).
    var weekday: Int
    var averageML: Double
    var id: Int { weekday }
}

/// The numbers behind the Stats tab, for the last `days` logical days.
nonisolated struct StatsReport: Equatable, Sendable {
    var points: [DayPoint]
    var loggedDays: Int
    var goalDays: Int
    var averageML: Double?
    /// Change of the average compared with the period before, in percent.
    var averageChangePercent: Double?
    var totalCaffeineMg: Double
    var totalStandardDrinks: Double
    var bestDay: DayPoint?
    var tintTotals: [TintTotal]
    var goalRate: Double { loggedDays > 0 ? Double(goalDays) / Double(loggedDays) : 0 }
}

enum StatsCalculator {
    /// Report for the `days` logical days ending with `today`.
    static func report(entries: [DrinkEntry], days: Int, goalML: Double, today: Date,
                       boundary: DayBoundary) -> StatsReport {
        let summaries = Dictionary(Summaries.daily(entries: entries, boundary: boundary).map { ($0.day, $0) },
                                   uniquingKeysWith: { a, _ in a })
        let points = range(days: days, ending: today, calendar: boundary.calendar).map { day in
            let s = summaries[day]
            return DayPoint(day: day, ml: s.map(\.goalFluidML), caffeineMg: s?.caffeineMg ?? 0,
                            standardDrinks: s?.standardDrinks ?? 0, goalReached: s?.goalReached(goalML: goalML) ?? false)
        }
        let previous = range(days: days, ending: boundary.calendar.date(byAdding: .day, value: -days, to: today)!,
                             calendar: boundary.calendar).compactMap { summaries[$0]?.goalFluidML }

        let logged = points.compactMap(\.ml)
        let average = logged.isEmpty ? nil : logged.reduce(0, +) / Double(logged.count)
        let previousAverage = previous.isEmpty ? nil : previous.reduce(0, +) / Double(previous.count)
        var change: Double?
        if let average, let previousAverage, previousAverage > 0 {
            change = (average - previousAverage) / previousAverage * 100
        }

        let start = boundary.interval(forLogicalDay: points.first?.day ?? today).start
        let end = boundary.interval(forLogicalDay: today).end
        let inRange = entries.filter { $0.timestamp >= start && $0.timestamp < end }

        return StatsReport(
            points: points,
            loggedDays: logged.count,
            goalDays: points.filter(\.goalReached).count,
            averageML: average,
            averageChangePercent: change,
            totalCaffeineMg: points.reduce(0) { $0 + $1.caffeineMg },
            totalStandardDrinks: points.reduce(0) { $0 + $1.standardDrinks },
            bestDay: points.filter { $0.ml != nil }.max { ($0.ml ?? 0) < ($1.ml ?? 0) },
            tintTotals: CompanionLogic.tintTotals(entries: inRange).sorted { $0.ml > $1.ml }
        )
    }

    /// Weekly averages for the last `weeks` weeks (weeks start on the calendar's first weekday).
    static func weeks(entries: [DrinkEntry], weeks: Int, goalML: Double, today: Date,
                      boundary: DayBoundary) -> [WeekPoint] {
        let calendar = boundary.calendar
        let summaries = Summaries.daily(entries: entries, boundary: boundary)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let inWeek = summaries.filter { $0.day >= start && $0.day < end }
            let total = inWeek.reduce(0) { $0 + $1.goalFluidML }
            return WeekPoint(weekStart: start, averageML: inWeek.isEmpty ? nil : total / Double(inWeek.count),
                             goalDays: inWeek.filter { $0.goalReached(goalML: goalML) }.count, loggedDays: inWeek.count)
        }
    }

    /// Average per weekday over the given points (days without data are skipped).
    static func weekdays(_ points: [DayPoint], calendar: Calendar) -> [WeekdayPoint] {
        var sums: [Int: (Double, Int)] = [:]
        for point in points {
            guard let ml = point.ml else { continue }
            let weekday = calendar.component(.weekday, from: point.day)
            let current = sums[weekday] ?? (0, 0)
            sums[weekday] = (current.0 + ml, current.1 + 1)
        }
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        return order.compactMap { day in
            sums[day].map { WeekdayPoint(weekday: day, averageML: $0.0 / Double($0.1)) }
        }
    }

    /// The `days` logical days ending with `today`, oldest first.
    static func range(days: Int, ending today: Date, calendar: Calendar) -> [Date] {
        (0..<max(days, 1)).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: today)) }
    }
}
