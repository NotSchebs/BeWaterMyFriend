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
    static let reminderSmart = "reminderSmart"
    static let goalMode = "goalMode"  // "manual" or "suggested"
    static let weightFromHealth = "weightFromHealth"
    static let manualWeightKg = "manualWeightKg"
    static let goalMlPerKg = "goalMlPerKg"
    static let useWorkouts = "useWorkouts"
    static let workoutMlPerHour = "workoutMlPerHour"
    static let useWeather = "useWeather"
    static let heatThresholdC = "heatThresholdC"
    static let heatExtraML = "heatExtraML"
    static let heatMaxExtraML = "heatMaxExtraML"
    static let coldThresholdC = "coldThresholdC"
    static let coldExtraML = "coldExtraML"
    static let temperatureUnit = "temperatureUnit"
    static let goalBreakdown = "goalBreakdown"
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
