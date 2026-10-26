import Foundation

/// The days of a month laid out in weeks, for the History calendar.
nonisolated enum CalendarGrid {
    /// Midnight of each day of the month, padded with `nil` so the first day
    /// sits under its weekday (weeks start on the calendar's first weekday,
    /// Monday in Switzerland). Always whole weeks.
    static func cells(forMonthContaining date: Date, calendar: Calendar) -> [Date?] {
        guard let month = calendar.dateInterval(of: .month, for: date),
              let dayCount = calendar.range(of: .day, in: .month, for: date)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: month.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(calendar.date(byAdding: .day, value: offset, to: month.start))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Short weekday names in display order ("Mo", "Tu", …).
    static func weekdaySymbols(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols.isEmpty
            ? calendar.shortWeekdaySymbols : calendar.shortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start]).map { String($0.prefix(2)) }
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}
