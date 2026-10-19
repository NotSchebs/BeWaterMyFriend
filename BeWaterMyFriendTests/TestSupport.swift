import Foundation

/// Fixed calendar in Europe/Zurich so tests don't depend on the machine's settings
/// and daylight-saving dates are known (2026: 29 Mar spring forward, 25 Oct fall back).
let zurich: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return calendar
}()

func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    zurich.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
