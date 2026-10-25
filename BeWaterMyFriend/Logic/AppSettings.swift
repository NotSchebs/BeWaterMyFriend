import Foundation

/// UserDefaults keys and defaults for `@AppStorage`.
enum SettingsKey {
    static let dailyGoalML = "dailyGoalML"
    static let dayEndMinutes = "dayEndMinutes"
    static let companionEnabled = "companionEnabled"
    static let didSeedPresets = "didSeedPresets"
    static let dojoBestGoalDays = "dojoBestGoalDays"
    static let dojoBelt = "dojoBelt"
    static let prestigeLevel = "prestigeLevel"
    /// Total goal days at the last prestige; ranks count from here.
    static let prestigeBaseGoalDays = "prestigeBaseGoalDays"
    static let healthSyncEnabled = "healthSyncEnabled"
    static let healthWriteDelay = "healthWriteDelay"
    static let appearance = "appearance"
    static let remindersEnabled = "remindersEnabled"
    static let reminderStartMinutes = "reminderStartMinutes"
    static let reminderEndMinutes = "reminderEndMinutes"
    static let reminderIntervalMinutes = "reminderIntervalMinutes"
    static let reminderSkipOnTrack = "reminderSkipOnTrack"
}

/// Light, dark, or follow the system setting.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum SettingsDefault {
    /// A common starting estimate; the user should adjust it.
    static let dailyGoalML = 2000.0
    static let dayEndMinutes = 0
    static let companionEnabled = true
}
