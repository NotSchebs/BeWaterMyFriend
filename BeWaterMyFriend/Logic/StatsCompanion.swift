import CoreGraphics
import Foundation

/// Where the drop stands on the Stats screen and what it says. Pure and tested;
/// StatsView only draws what this decides. There's only ever one drop: on the
/// bar the user tapped, or else on the spot the insight sentence is about.
enum StatsCompanion {
    enum Chart: Equatable { case daily, weekday, caffeine, alcohol }

    /// A bar the drop stands on: a day (daily, caffeine, alcohol) or a weekday.
    struct Pin: Equatable {
        var chart: Chart
        var day: Date?
        var weekday: Int?
    }

    struct Spot: Equatable {
        var chart: Chart
        var day: Date?
        var weekday: Int?
        var text: String
        var mood: CompanionMood
        /// Share of the goal, for the drop's fill and size.
        var progress: Double
    }

    /// The tapped bar (`pin`), or the insight's spot when nothing is tapped.
    /// nil when there's nothing to stand on (too little data, a bar without data).
    static func spot(pin: Pin?, report: StatsReport, weekdays: [WeekdayPoint], entries: [DrinkEntry],
                     goalML: Double, calendar: Calendar, today: Date, taps: Int) -> Spot? {
        if let pin {
            return spot(for: pin, text: nil, report: report, weekdays: weekdays, goalML: goalML,
                        calendar: calendar, seed: taps)
        }
        guard let insight = StatsInsight.make(report: report, entries: entries, calendar: calendar,
                                              seed: CompanionLines.daySeed(today, calendar: calendar)) else { return nil }
        let target: Pin = switch insight.target {
        case .daily(let day): Pin(chart: .daily, day: day)
        case .weekday(let weekday): Pin(chart: .weekday, weekday: weekday)
        case .caffeine(let day): Pin(chart: .caffeine, day: day)
        }
        return spot(for: target, text: insight.text, report: report, weekdays: weekdays, goalML: goalML,
                    calendar: calendar, seed: taps)
    }

    private static func spot(for pin: Pin, text: String?, report: StatsReport, weekdays: [WeekdayPoint],
                             goalML: Double, calendar: Calendar, seed: Int) -> Spot? {
        if pin.chart == .weekday {
            guard let weekday = pin.weekday, let point = weekdays.first(where: { $0.weekday == weekday }) else { return nil }
            return Spot(chart: .weekday, weekday: weekday,
                        text: text ?? CompanionLines.statsWeekday(ml: point.averageML,
                                                                  weekdayText: calendar.weekdaySymbols[weekday - 1], seed: seed),
                        mood: .calm, progress: goalML > 0 ? point.averageML / goalML : 0)
        }
        guard let day = pin.day, let point = report.points.first(where: { calendar.isDate($0.day, inSameDayAs: day) }) else { return nil }
        let dayText = point.day.formatted(.dateTime.weekday(.abbreviated).day().month())
        let line: String = switch pin.chart {
        case .caffeine: CompanionLines.statsCaffeine(mg: point.caffeineMg, dayText: dayText, seed: seed)
        case .alcohol: CompanionLines.statsAlcohol(standardDrinks: point.standardDrinks, dayText: dayText, seed: seed)
        default: CompanionLines.statsDay(ml: point.ml, goalML: goalML, dayText: dayText, seed: seed)
        }
        return Spot(chart: pin.chart, day: point.day, text: text ?? line,
                    mood: CompanionLogic.dayMood(standardDrinks: point.standardDrinks, caffeineMg: point.caffeineMg),
                    progress: goalML > 0 ? (point.ml ?? 0) / goalML : 0)
    }

    /// Which donut slice a tap hit: the angle from 12 o'clock, clockwise (the
    /// way Swift Charts draws it), compared with each drink's running total.
    /// nil for the hole in the middle or outside the ring.
    static func donutSlice(at point: CGPoint, in size: CGSize, totals: [TintTotal],
                           innerRatio: Double = 0.55) -> DrinkTint? {
        let dx = point.x - size.width / 2, dy = point.y - size.height / 2
        let radius = min(size.width, size.height) / 2
        let distance = (dx * dx + dy * dy).squareRoot()
        let total = totals.reduce(0) { $0 + $1.ml }
        guard distance >= radius * innerRatio, distance <= radius, total > 0 else { return nil }
        var angle = atan2(dx, -dy)
        if angle < 0 { angle += 2 * .pi }
        let target = angle / (2 * .pi) * total
        var running = 0.0
        return totals.first { slice in
            running += slice.ml
            return target <= running
        }?.tint
    }
}
