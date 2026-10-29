import Foundation

/// "Around this time you usually have …" for the Add drink screen: the drink
/// logged on the most different days within 90 minutes (time of day) of now,
/// over the last 30 days. It needs at least 3 such days, so one random coffee
/// doesn't count as a habit. On a tie, the drink logged most recently wins.
enum DrinkSuggestion {
    static let window = 90  // minutes either side
    static let lookBackDays = 30
    static let minimumDays = 3

    /// The most recent log of the usual drink (to pre-fill the editor), or nil.
    static func usual(entries: [DrinkEntry], now: Date, calendar: Calendar) -> DrinkEntry? {
        guard let since = calendar.date(byAdding: .day, value: -lookBackDays, to: now) else { return nil }
        let nowMinute = minuteOfDay(now, calendar)
        var groups: [String: (days: Set<Date>, latest: DrinkEntry)] = [:]
        for entry in entries where entry.timestamp >= since && entry.timestamp <= now {
            let diff = abs(minuteOfDay(entry.timestamp, calendar) - nowMinute)
            guard min(diff, 24 * 60 - diff) <= window else { continue }  // 23:30 is close to 00:15
            let key = "\(QuickLogRules.normalized(entry.name))|\(entry.category.rawValue)|\(Int(entry.volumeML))"
            let day = calendar.startOfDay(for: entry.timestamp)
            if var group = groups[key] {
                group.days.insert(day)
                if entry.timestamp > group.latest.timestamp { group.latest = entry }
                groups[key] = group
            } else {
                groups[key] = ([day], entry)
            }
        }
        return groups.values
            .filter { $0.days.count >= minimumDays }
            .max { ($0.days.count, $0.latest.timestamp) < ($1.days.count, $1.latest.timestamp) }?
            .latest
    }

    private static func minuteOfDay(_ date: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
