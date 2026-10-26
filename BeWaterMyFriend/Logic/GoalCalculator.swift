import Foundation

/// The user's choices for the suggested goal. All values are adjustable estimates.
nonisolated struct GoalRules: Equatable, Sendable {
    /// Total water (food + drinks) per kg of body weight. Default: the median
    /// for adults in Mallett et al. 2021 (35.5 ml/kg), rounded.
    var mlPerKg = 35.0
    /// Share of total water that comes from food. EFSA (2010) assumes 20–30 %;
    /// the app tracks drinks only, so this part is taken off.
    var foodShare = 0.2
    /// Extra per hour of workout (common sweat losses: 0.5–2 l per hour).
    var workoutMLPerHour = 1000.0
    /// From this maximum temperature, hot days add `heatExtraML`…
    var heatThresholdC = 28.0
    var heatExtraML = 500.0
    /// …rising evenly to `heatMaxExtraML` at `heatMaxC` and above.
    var heatMaxC = 45.0
    var heatMaxExtraML = 1000.0
    /// Today's maximum temperature at or below this adds `coldExtraML`
    /// (cold makes you pee more and feel less thirsty).
    var coldThresholdC = 3.0
    var coldExtraML = 250.0
}

/// What the suggested goal is made of, so the app can show the calculation.
nonisolated struct GoalBreakdown: Codable, Equatable, Sendable {
    var weightKg: Double
    /// Total water need from body weight (food + drinks).
    var totalWaterML: Double
    /// Part of that expected from food.
    var fromFoodML: Double
    var baseML: Double { totalWaterML - fromFoodML }
    var workoutMinutes: Double
    var workoutML: Double
    /// Today's maximum temperature, if weather is used.
    var maxTempC: Double?
    var heatML: Double
    var coldML: Double
    /// Rounded to 50 ml.
    var goalML: Double
}

nonisolated enum GoalCalculator {
    /// Goals are kept within a sensible range, whatever the inputs.
    static let minimumGoalML = 1000.0
    static let maximumGoalML = 6000.0

    static func breakdown(weightKg: Double, workoutMinutes: Double, maxTempC: Double?,
                          rules: GoalRules) -> GoalBreakdown {
        let weight = max(weightKg, 0)
        let total = weight * rules.mlPerKg
        let food = total * min(max(rules.foodShare, 0), 0.9)
        let workout = max(workoutMinutes, 0) / 60 * rules.workoutMLPerHour
        var heat = 0.0, cold = 0.0
        if let temp = maxTempC {
            heat = heatExtra(at: temp, rules: rules)
            if temp <= rules.coldThresholdC { cold = rules.coldExtraML }
        }
        let raw = total - food + workout + heat + cold
        let goal = min(max((raw / 50).rounded() * 50, minimumGoalML), maximumGoalML)
        return GoalBreakdown(weightKg: weight, totalWaterML: total, fromFoodML: food, workoutMinutes: max(workoutMinutes, 0),
                             workoutML: workout, maxTempC: maxTempC, heatML: heat, coldML: cold, goalML: goal)
    }

    /// 0 below the threshold; from `heatExtraML` at the threshold rising evenly
    /// to `heatMaxExtraML` at `heatMaxC`; capped there. Rounded to 50 ml.
    static func heatExtra(at temp: Double, rules: GoalRules) -> Double {
        guard temp >= rules.heatThresholdC else { return 0 }
        let span = rules.heatMaxC - rules.heatThresholdC
        let share = span > 0 ? min((temp - rules.heatThresholdC) / span, 1) : 1
        let extra = rules.heatExtraML + share * max(rules.heatMaxExtraML - rules.heatExtraML, 0)
        return (extra / 50).rounded() * 50
    }
}

/// Celsius / Fahrenheit for showing and entering temperatures. Stored in °C.
nonisolated enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit

    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }

    func fromCelsius(_ c: Double) -> Double { self == .celsius ? c : c * 9 / 5 + 32 }
    func toCelsius(_ value: Double) -> Double { self == .celsius ? value : (value - 32) * 5 / 9 }

    func format(_ celsius: Double) -> String {
        "\(Int(fromCelsius(celsius).rounded())) \(symbol)"
    }
}
