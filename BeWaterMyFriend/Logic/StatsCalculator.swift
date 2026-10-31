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

/// The ninja drop's one-sentence reading of the Stats charts, plus where in the
/// charts the drop stands while saying it. Picks the most notable thing; nil
/// when there's too little data to say anything honest.
enum StatsInsight {
    /// The spot the sentence is about.
    enum Target: Equatable {
        /// A bar in the daily chart.
        case daily(Date)
        /// A bar in the weekday chart (1 = Sunday … 7 = Saturday).
        case weekday(Int)
        /// A bar in the caffeine chart.
        case caffeine(Date)
    }

    struct Result: Equatable {
        var text: String
        var target: Target
    }

    static func sentence(report: StatsReport, entries: [DrinkEntry], calendar: Calendar, seed: Int = 0) -> String? {
        make(report: report, entries: entries, calendar: calendar, seed: seed)?.text
    }

    static func make(report: StatsReport, entries: [DrinkEntry], calendar: Calendar, seed: Int = 0) -> Result? {
        let logged = report.points.filter { $0.ml != nil }
        guard logged.count >= 3, let lastLogged = logged.last else { return nil }

        // 1. Weekends vs weekdays (needs both). The drop stands on the weekend
        // day that shows the difference most.
        let weekendPoints = logged.filter { calendar.isDateInWeekend($0.day) }
        let weekend = weekendPoints.compactMap(\.ml)
        let weekday = logged.filter { !calendar.isDateInWeekend($0.day) }.compactMap(\.ml)
        if weekend.count >= 1, weekday.count >= 2 {
            let we = weekend.reduce(0, +) / Double(weekend.count)
            let wd = weekday.reduce(0, +) / Double(weekday.count)
            let diff = (we - wd) / wd * 100
            if abs(diff) >= 15 {
                let n = Int(abs(diff).rounded())
                let averages = StatsCalculator.weekdays(weekendPoints, calendar: calendar)
                let spot = diff < 0 ? averages.min { $0.averageML < $1.averageML } : averages.max { $0.averageML < $1.averageML }
                let text = diff < 0
                    ? CompanionLines.pick(["You drink \(n) % less on weekends than on weekdays.",
                                           "Weekends are dry: \(n) % less than on weekdays.",
                                           "\(n) % less on weekends. Even ninjas train on Saturdays.",
                                           "Weekends run \(n) % drier. Bring a bottle along?"], seed: seed)
                    : CompanionLines.pick(["You drink \(n) % more on weekends than on weekdays.",
                                           "Weekends flow: \(n) % more than on weekdays.",
                                           "\(n) % more on weekends. Rest days suit you.",
                                           "The weekend ninja strikes: \(n) % more than on weekdays."], seed: seed)
                if let spot { return Result(text: text, target: .weekday(spot.weekday)) }
            }
        }

        // 2. Clear trend against the period before: on the latest logged day.
        if let change = report.averageChangePercent, abs(change) >= 10 {
            let n = Int(abs(change).rounded())
            let text = change > 0
                ? CompanionLines.pick(["Up \(n) % compared with before. Keep flowing!",
                                       "\(n) % more than before. I'm growing!",
                                       "Up \(n) %. The current is getting stronger.",
                                       "\(n) % more than before. Your training shows."], seed: seed)
                : CompanionLines.pick(["Down \(n) % compared with before. Let's catch up together.",
                                       "\(n) % less than before. I'm a bit thirsty.",
                                       "Down \(n) %. Every comeback starts with one sip.",
                                       "\(n) % less than before. No worries, water finds a way."], seed: seed)
            return Result(text: text, target: .daily(lastLogged.day))
        }

        // 3. Late caffeine: on the day with the most caffeine.
        let start = report.points.first?.day ?? .distantPast
        let caffeine = entries.filter { $0.timestamp >= start && $0.caffeineMg > 0 }
        let total = caffeine.reduce(0) { $0 + $1.caffeineMg }
        let late = caffeine.filter { calendar.component(.hour, from: $0.timestamp) >= 16 }.reduce(0) { $0 + $1.caffeineMg }
        if total >= 100, late / total >= 0.5, let peak = report.points.max(by: { $0.caffeineMg < $1.caffeineMg }) {
            let text = CompanionLines.pick(["Most of your caffeine comes after 4 pm. Might be worth an earlier coffee.",
                                            "Lots of late coffee: most caffeine after 4 pm. Sleeping well?",
                                            "Your caffeine likes the evening: most of it comes after 4 pm.",
                                            "After 4 pm is coffee time, it seems. A ninja also needs sleep."], seed: seed)
            return Result(text: text, target: .caffeine(peak.day))
        }

        // 4. Goal rate: on the latest goal day (or the latest logged day).
        let spot = logged.last(where: \.goalReached) ?? lastLogged
        let text = CompanionLines.pick(["You reached your goal on \(report.goalDays) of \(logged.count) logged days.",
                                        "\(report.goalDays) goal days out of \(logged.count). Osu!",
                                        "\(logged.count) days logged, \(report.goalDays) with the goal reached. Keep flowing.",
                                        "\(report.goalDays) of \(logged.count) days on target. Every day is training."], seed: seed)
        return Result(text: text, target: .daily(spot.day))
    }
}
