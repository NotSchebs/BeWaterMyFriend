import SwiftUI

/// Daily goal: set by hand, or suggested from weight, workouts and weather,
/// with the calculation shown line by line.
struct GoalSection: View {
    @AppStorage(SettingsKey.dailyGoalML) private var goalML = SettingsDefault.dailyGoalML
    @AppStorage(SettingsKey.goalMode) private var goalMode = "manual"
    @AppStorage(SettingsKey.temperatureUnit) private var unitRaw = TemperatureUnit.celsius.rawValue
    private var service = GoalService.shared

    var body: some View {
        Section {
            Picker("Goal", selection: $goalMode) {
                Text("Manual").tag("manual")
                Text("Suggested").tag("suggested")
            }
            .pickerStyle(.segmented)

            if goalMode == "manual" {
                Stepper(value: $goalML, in: 500...6000, step: 250) {
                    LabeledContent("Daily water goal", value: Format.ml(goalML))
                }
            } else {
                LabeledContent("Today's goal") {
                    HStack(spacing: 8) {
                        if service.isUpdating { ProgressView() }
                        Text(Format.ml(goalML)).bold()
                    }
                }
                if let b = service.breakdown {
                    GoalBreakdownRows(breakdown: b, rules: GoalService.rules(),
                                      unit: TemperatureUnit(rawValue: unitRaw) ?? .celsius,
                                      weightFromHealth: service.weightIsFromHealth)
                }
                NavigationLink("Adjust the formula") {
                    GoalRulesView()
                }
            }
        } header: {
            Text("Daily water goal")
        } footer: {
            Text(goalMode == "manual"
                 ? "An estimate, not medical advice. Choose what fits you."
                 : "Calculated each day. An estimate, not medical advice; switch to Manual any time to set your own goal.")
        }
        .onChange(of: goalMode) { _, mode in
            guard mode == "suggested" else { return }
            Task {
                await HealthReader.shared.requestReadAccess(weight: true, workouts: true)
                await service.refresh(refreshWeather: true)
            }
        }
    }
}

/// The calculation, one line per part.
struct GoalBreakdownRows: View {
    var breakdown: GoalBreakdown
    var rules: GoalRules
    var unit: TemperatureUnit
    var weightFromHealth: Bool

    var body: some View {
        let b = breakdown
        row("Body weight \(Format.amount(b.weightKg, unit: "kg"))\(weightFromHealth ? " (Health)" : "") × \(Int(rules.mlPerKg)) ml/kg",
            Format.ml(b.totalWaterML))
        row("From food (about \(Int((rules.foodShare * 100).rounded())) %)", "− \(Format.ml(b.fromFoodML))")
        if b.workoutML > 0 {
            row("Workouts today (\(Int(b.workoutMinutes.rounded())) min)", "+ \(Format.ml(b.workoutML))")
        }
        if let temp = b.maxTempC {
            if b.heatML > 0 {
                row("Hot day (max \(unit.format(temp)))", "+ \(Format.ml(b.heatML))")
            } else if b.coldML > 0 {
                row("Cold day (max \(unit.format(temp)))", "+ \(Format.ml(b.coldML))")
            } else {
                row("Weather (max \(unit.format(temp)))", "+ 0 ml")
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// Every number of the formula, adjustable, with sources.
struct GoalRulesView: View {
    @AppStorage(SettingsKey.weightFromHealth) private var weightFromHealth = true
    @AppStorage(SettingsKey.manualWeightKg) private var manualWeight = 70.0
    @AppStorage(SettingsKey.goalMlPerKg) private var mlPerKg = GoalRules().mlPerKg
    @AppStorage(SettingsKey.useWorkouts) private var useWorkouts = true
    @AppStorage(SettingsKey.workoutMlPerHour) private var workoutMlPerHour = GoalRules().workoutMLPerHour
    @AppStorage(SettingsKey.useWeather) private var useWeather = false
    @AppStorage(SettingsKey.heatThresholdC) private var heatThreshold = GoalRules().heatThresholdC
    @AppStorage(SettingsKey.heatExtraML) private var heatExtra = GoalRules().heatExtraML
    @AppStorage(SettingsKey.heatMaxExtraML) private var heatMaxExtra = GoalRules().heatMaxExtraML
    @AppStorage(SettingsKey.coldThresholdC) private var coldThreshold = GoalRules().coldThresholdC
    @AppStorage(SettingsKey.coldExtraML) private var coldExtra = GoalRules().coldExtraML
    @AppStorage(SettingsKey.temperatureUnit) private var unitRaw = TemperatureUnit.celsius.rawValue
    @State private var locationDenied = false

    private var unit: TemperatureUnit { TemperatureUnit(rawValue: unitRaw) ?? .celsius }

    var body: some View {
        Form {
            Section {
                Toggle("Weight from Apple Health", isOn: $weightFromHealth)
                if !weightFromHealth {
                    Stepper(value: $manualWeight, in: 30...200, step: 1) {
                        LabeledContent("My weight", value: Format.amount(manualWeight, unit: "kg"))
                    }
                }
                Stepper(value: $mlPerKg, in: 25...50, step: 1) {
                    LabeledContent("Water per kg", value: "\(Int(mlPerKg)) ml")
                }
            } header: {
                Text("Body weight")
            } footer: {
                Text(weightFromHealth
                     ? "Uses your latest weight in Apple Health, so the goal follows your weight. If there is none, \(Format.amount(manualWeight, unit: "kg")) is used. About 20 % of water comes from food, so the app takes that part off."
                     : "About 20 % of water comes from food, so the app takes that part off.")
            }

            Section {
                Toggle("Add workouts from Apple Health", isOn: $useWorkouts)
                if useWorkouts {
                    Stepper(value: $workoutMlPerHour, in: 250...2000, step: 250) {
                        LabeledContent("Extra per hour", value: Format.ml(workoutMlPerHour))
                    }
                }
            } header: {
                Text("Workouts")
            } footer: {
                Text("People typically sweat 0.5 to 2 litres per hour of exercise, more in heat.")
            }

            Section {
                Toggle("Adjust for weather", isOn: $useWeather)
                if locationDenied {
                    Text("Location is turned off for BeWaterMyFriend. You can allow it in the iPhone's Settings app.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if useWeather {
                    Picker("Unit", selection: $unitRaw) {
                        ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: temperature($heatThreshold), in: unit.fromCelsius(20)...unit.fromCelsius(40), step: 1) {
                        LabeledContent("Hot from", value: unit.format(heatThreshold))
                    }
                    Stepper(value: $heatExtra, in: 0...1500, step: 50) {
                        LabeledContent("Extra from \(unit.format(heatThreshold))", value: Format.ml(heatExtra))
                    }
                    Stepper(value: $heatMaxExtra, in: 0...2000, step: 50) {
                        LabeledContent("Extra at \(unit.format(GoalRules().heatMaxC))+", value: Format.ml(heatMaxExtra))
                    }
                    Stepper(value: temperature($coldThreshold), in: unit.fromCelsius(-15)...unit.fromCelsius(10), step: 1) {
                        LabeledContent("Cold up to", value: unit.format(coldThreshold))
                    }
                    Stepper(value: $coldExtra, in: 0...1000, step: 250) {
                        LabeledContent("Extra on cold days", value: Format.ml(coldExtra))
                    }
                }
            } header: {
                Text("Weather")
            } footer: {
                Text("Uses today's highest temperature where you are (approximate location, from Open-Meteo). On hot days the extra rises evenly with the temperature, up to \(unit.format(GoalRules().heatMaxC)). Cold also counts: the body makes more urine and you feel less thirsty.")
            }

            Section("Sources") {
                Text("EFSA Panel on Dietetic Products, Nutrition and Allergies (2010). Scientific Opinion on Dietary Reference Values for water. EFSA Journal 8(3):1459. About 20–30 % of water comes from food.")
                Text("Mallett LJ et al. (2021). Total water intake by kilogram of body weight. Nutrition & Dietetics 78(5):496–505. Median for adults: 35.5 ml/kg (food and drinks). This is what people drink, not a minimum requirement.")
                Text("Orysiak J et al. (2025). Hydration of Workers in Thermal Environments—Practical Recommendation. Nutrients 18(1):64. In heat: 150–250 ml every 15–20 minutes while working (NIOSH/OSHA); drinks needed from about 25 °C outdoors or below 10 °C.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .dojoBackground()
        .navigationTitle("Goal formula")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: useWeather) { _, on in
            locationDenied = on && WeatherService.shared.isDenied
            Task { await GoalService.shared.refresh(refreshWeather: true) }
        }
        .onChange(of: [mlPerKg, manualWeight, workoutMlPerHour, heatThreshold, heatExtra, heatMaxExtra, coldThreshold, coldExtra]) {
            Task { await GoalService.shared.refresh() }
        }
        .onChange(of: [weightFromHealth, useWorkouts]) {
            Task { await GoalService.shared.refresh() }
        }
    }

    /// Shows and edits a °C value in the chosen unit.
    private func temperature(_ celsius: Binding<Double>) -> Binding<Double> {
        Binding(
            get: { unit.fromCelsius(celsius.wrappedValue).rounded() },
            set: { celsius.wrappedValue = unit.toCelsius($0) }
        )
    }
}
