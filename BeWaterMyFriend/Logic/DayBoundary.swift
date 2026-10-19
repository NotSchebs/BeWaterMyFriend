import Foundation

/// Decides which "logical day" a moment belongs to, given a custom day end.
///
/// With a day end of 03:00 the logical day "16 Oct" runs from 16 Oct 03:00 to
/// 17 Oct 03:00, so a drink at 01:00 on 17 Oct still counts for 16 Oct.
/// All arithmetic goes through `Calendar`, never "+ 86 400 seconds", so days
/// with a daylight-saving change (23 or 25 hours) are handled correctly.
nonisolated struct DayBoundary: Sendable {
    /// Minutes after midnight at which a day ends (0 = midnight, 180 = 03:00).
    var dayEndMinutes: Int
    var calendar: Calendar

    init(dayEndMinutes: Int = 0, calendar: Calendar = .current) {
        self.dayEndMinutes = max(0, min(dayEndMinutes, 23 * 60 + 59))
        self.calendar = calendar
    }

    /// Midnight (00:00) of the calendar date that names the logical day of `date`.
    func logicalDay(for date: Date) -> Date {
        let midnight = calendar.startOfDay(for: date)
        if date < boundary(onCalendarDay: midnight) {
            return calendar.date(byAdding: .day, value: -1, to: midnight)!
        }
        return midnight
    }

    /// The exact time span covered by a logical day (start inclusive, end exclusive).
    func interval(forLogicalDay day: Date) -> DateInterval {
        let midnight = calendar.startOfDay(for: day)
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: midnight)!
        return DateInterval(
            start: boundary(onCalendarDay: midnight),
            end: boundary(onCalendarDay: nextMidnight)
        )
    }

    /// The moment the day-end time occurs on a given calendar day. If that
    /// wall-clock time doesn't exist (spring-forward gap) the next valid time is
    /// used; if it occurs twice (fall-back) the first occurrence is used.
    private func boundary(onCalendarDay midnight: Date) -> Date {
        guard dayEndMinutes > 0 else { return midnight }
        var components = calendar.dateComponents([.year, .month, .day], from: midnight)
        components.hour = dayEndMinutes / 60
        components.minute = dayEndMinutes % 60
        return calendar.nextDate(
            after: midnight,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) ?? midnight
    }
}
