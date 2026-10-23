import Foundation

/// UserDefaults keys and defaults for `@AppStorage`.
enum SettingsKey {
    static let dailyGoalML = "dailyGoalML"
    static let dayEndMinutes = "dayEndMinutes"
    static let companionEnabled = "companionEnabled"
    static let didSeedPresets = "didSeedPresets"
    static let dojoBestGoalDays = "dojoBestGoalDays"
    static let dojoBelt = "dojoBelt"
    static let healthSyncEnabled = "healthSyncEnabled"
    static let healthWriteDelay = "healthWriteDelay"
}

enum SettingsDefault {
    /// A common starting estimate; the user should adjust it.
    static let dailyGoalML = 2000.0
    static let dayEndMinutes = 0
    static let companionEnabled = true
}
