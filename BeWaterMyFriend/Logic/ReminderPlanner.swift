import Foundation

/// When the user wants to be reminded.
nonisolated struct ReminderSettings: Equatable, Sendable {
    /// Minutes after midnight.
    var startMinutes = 9 * 60
    var endMinutes = 18 * 60
    /// Roughly how often, in minutes.
    var intervalMinutes = 60
    /// Skip today's reminders while the user is ahead of an even pace.
    var skipWhenOnTrack = true
}

/// Plans reminder times. Pure, so it can be tested with a seeded random generator.
///
/// The window is cut into slots of `intervalMinutes`. Each slot gets one
/// reminder at a random moment, but never sooner than a third of an interval
/// after the previous one. That way reminders feel natural (9:12, 10:47, 11:30…)
/// instead of robotic, while still coming about once per interval.
nonisolated enum ReminderPlanner {
    static func times<R: RandomNumberGenerator>(on day: Date, settings: ReminderSettings,
                                                calendar: Calendar, using random: inout R) -> [Date] {
        let interval = max(settings.intervalMinutes, 5)
        guard settings.endMinutes > settings.startMinutes else { return [] }
        let midnight = calendar.startOfDay(for: day)
        let minGap = Double(interval) / 3

        var result: [Date] = []
        var previous: Double?  // minutes after midnight
        var slotStart = Double(settings.startMinutes)
        while slotStart < Double(settings.endMinutes) {
            let slotEnd = min(slotStart + Double(interval), Double(settings.endMinutes))
            let earliest = max(slotStart, (previous ?? -Double.infinity) + minGap)
            if earliest < slotEnd {
                let minute = Double.random(in: earliest..<slotEnd, using: &random).rounded(.down)
                if let date = time(minute: minute, on: midnight, calendar: calendar) {
                    result.append(date)
                    previous = minute
                }
            }
            slotStart += Double(interval)
        }
        return result
    }

    /// Share of the daily goal the user "should" have by `date` if drinking
    /// evenly from the start to the end of the reminder window.
    static func expectedFraction(at date: Date, settings: ReminderSettings, calendar: Calendar) -> Double {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        let minute = Double((comps.hour ?? 0) * 60 + (comps.minute ?? 0))
        let span = Double(settings.endMinutes - settings.startMinutes)
        guard span > 0 else { return 1 }
        return min(max((minute - Double(settings.startMinutes)) / span, 0), 1)
    }

    /// Today's times after `now`, without the ones the user is already on track for.
    static func todaysTimes(_ times: [Date], now: Date, progress: Double,
                            settings: ReminderSettings, calendar: Calendar) -> [Date] {
        times.filter { time in
            guard time > now else { return false }
            if settings.skipWhenOnTrack && progress >= expectedFraction(at: time, settings: settings, calendar: calendar) {
                return false
            }
            return true
        }
    }

    private static func time(minute: Double, on midnight: Date, calendar: Calendar) -> Date? {
        let m = Int(minute)
        return calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: midnight)
    }
}
