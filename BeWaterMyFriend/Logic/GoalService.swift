import Foundation
import Observation

/// Works out today's suggested goal from weight, workouts and weather, and
/// stores it as the daily goal. In manual mode it does nothing.
@MainActor
@Observable
final class GoalService {
    static let shared = GoalService()

    /// The last calculation, for showing how the goal was made.
    private(set) var breakdown: GoalBreakdown?
    private(set) var isUpdating = false
    /// True when the weight came from Apple Health in the last calculation.
    private(set) var weightIsFromHealth = false

    private var cachedTemp: (value: Double?, at: Date)?

    init() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.goalBreakdown) {
            breakdown = try? JSONDecoder().decode(GoalBreakdown.self, from: data)
        }
    }

    static func isSuggested(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: SettingsKey.goalMode) == "suggested"
    }

    static func rules(from defaults: UserDefaults = .standard) -> GoalRules {
        var r = GoalRules()
        func value(_ key: String) -> Double? { defaults.object(forKey: key) as? Double }
        r.mlPerKg = value(SettingsKey.goalMlPerKg) ?? r.mlPerKg
        r.workoutMLPerHour = value(SettingsKey.workoutMlPerHour) ?? r.workoutMLPerHour
        r.heatThresholdC = value(SettingsKey.heatThresholdC) ?? r.heatThresholdC
        r.heatExtraML = value(SettingsKey.heatExtraML) ?? r.heatExtraML
        r.heatMaxExtraML = value(SettingsKey.heatMaxExtraML) ?? r.heatMaxExtraML
        r.coldThresholdC = value(SettingsKey.coldThresholdC) ?? r.coldThresholdC
        r.coldExtraML = value(SettingsKey.coldExtraML) ?? r.coldExtraML
        return r
    }

    /// Recalculates and saves the goal. `refreshWeather` forces a new temperature.
    func refresh(defaults: UserDefaults = .standard, refreshWeather: Bool = false, now: Date = .now) async {
        guard Self.isSuggested(defaults), !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }

        let manualWeight = defaults.object(forKey: SettingsKey.manualWeightKg) as? Double ?? 70
        var weight = manualWeight
        weightIsFromHealth = false
        if defaults.object(forKey: SettingsKey.weightFromHealth) as? Bool ?? true,
           let fromHealth = await HealthReader.shared.latestWeightKg() {
            weight = fromHealth
            weightIsFromHealth = true
        }

        var minutes = 0.0
        if defaults.object(forKey: SettingsKey.useWorkouts) as? Bool ?? true {
            let boundary = DayBoundary(dayEndMinutes: defaults.integer(forKey: SettingsKey.dayEndMinutes))
            minutes = await HealthReader.shared.workoutMinutes(in: boundary.interval(forLogicalDay: boundary.logicalDay(for: now)))
        }

        var temp: Double?
        if defaults.bool(forKey: SettingsKey.useWeather) {
            // The temperature changes slowly: fetch at most once an hour.
            if !refreshWeather, let cached = cachedTemp, now.timeIntervalSince(cached.at) < 3600 {
                temp = cached.value
            } else {
                temp = await WeatherService.shared.todaysMaxTemperature()
                cachedTemp = (temp, now)
            }
        }

        let result = GoalCalculator.breakdown(weightKg: weight, workoutMinutes: minutes, maxTempC: temp,
                                              rules: Self.rules(from: defaults))
        breakdown = result
        defaults.set(result.goalML, forKey: SettingsKey.dailyGoalML)
        defaults.set(try? JSONEncoder().encode(result), forKey: SettingsKey.goalBreakdown)
    }
}
