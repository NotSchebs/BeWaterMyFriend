import XCTest
@testable import BeWaterMyFriend

final class GoalCalculatorTests: XCTestCase {
    private let rules = GoalRules()

    func testBaseFromBodyWeightMinusFood() {
        let b = GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: nil, rules: rules)
        XCTAssertEqual(b.totalWaterML, 2450)
        XCTAssertEqual(b.fromFoodML, 490)
        XCTAssertEqual(b.baseML, 1960)
        XCTAssertEqual(b.goalML, 1950, "rounded to 50 ml")
    }

    func testOneHourWorkoutAddsOneLitre() {
        let b = GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 60, maxTempC: nil, rules: rules)
        XCTAssertEqual(b.workoutML, 1000)
        XCTAssertEqual(b.goalML, 2950)
        let half = GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 45, maxTempC: nil, rules: rules)
        XCTAssertEqual(half.workoutML, 750)
    }

    func testHeatFromThreshold() {
        XCTAssertEqual(GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: 27.9, rules: rules).heatML, 0)
        XCTAssertEqual(GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: 28, rules: rules).heatML, 500)
    }

    func testColdFromThreshold() {
        XCTAssertEqual(GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: 3, rules: rules).coldML, 250)
        XCTAssertEqual(GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: 3.1, rules: rules).coldML, 0)
    }

    func testMildWeatherAndNoWeatherAddNothing() {
        let mild = GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: 15, rules: rules)
        XCTAssertEqual(mild.heatML + mild.coldML, 0)
        let none = GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: nil, rules: rules)
        XCTAssertNil(none.maxTempC)
        XCTAssertEqual(none.goalML, mild.goalML)
    }

    func testEverythingTogether() {
        // 80 kg, 90 min BJJ, 31 °C: 2,240 + 1,500 + 500 = 4,240 → 4,250
        let b = GoalCalculator.breakdown(weightKg: 80, workoutMinutes: 90, maxTempC: 31, rules: rules)
        XCTAssertEqual(b.goalML, 4250)
    }

    func testGoalStaysInSensibleRange() {
        XCTAssertEqual(GoalCalculator.breakdown(weightKg: 0, workoutMinutes: 0, maxTempC: nil, rules: rules).goalML, 1000)
        XCTAssertEqual(GoalCalculator.breakdown(weightKg: 150, workoutMinutes: 600, maxTempC: 40, rules: rules).goalML, 6000)
        XCTAssertEqual(GoalCalculator.breakdown(weightKg: 70, workoutMinutes: -30, maxTempC: nil, rules: rules).workoutML, 0)
    }

    func testCustomRules() {
        var custom = rules
        custom.mlPerKg = 30
        custom.foodShare = 0
        custom.heatThresholdC = 25
        let b = GoalCalculator.breakdown(weightKg: 70, workoutMinutes: 0, maxTempC: 26, rules: custom)
        XCTAssertEqual(b.goalML, 2600)  // 2,100 + 500 heat
    }

    func testFahrenheitConversion() {
        let f = TemperatureUnit.fahrenheit
        XCTAssertEqual(f.fromCelsius(28), 82.4, accuracy: 0.001)
        XCTAssertEqual(f.toCelsius(82.4), 28, accuracy: 0.001)
        XCTAssertEqual(f.format(3), "37 °F")
        XCTAssertEqual(TemperatureUnit.celsius.format(28), "28 °C")
    }
}

final class OpenMeteoTests: XCTestCase {
    /// Real response for Zurich, 25 Oct 2026.
    private let zurichResponse = #"""
    {"latitude":47.376667,"longitude":8.543693,"timezone":"Europe/Zurich","daily_units":{"time":"iso8601","temperature_2m_max":"°C"},"daily":{"time":["2026-10-25"],"temperature_2m_max":[13.4]}}
    """#

    func testParsesTodaysMaximum() {
        XCTAssertEqual(OpenMeteo.parseMaxTemperature(Data(zurichResponse.utf8)), 13.4)
    }

    func testBadResponsesGiveNil() {
        XCTAssertNil(OpenMeteo.parseMaxTemperature(Data("<html>error</html>".utf8)))
        XCTAssertNil(OpenMeteo.parseMaxTemperature(Data(#"{"daily":{"temperature_2m_max":[]}}"#.utf8)))
    }

    func testLocationIsRoundedBeforeSending() throws {
        let url = try XCTUnwrap(OpenMeteo.url(latitude: 47.376667, longitude: 8.543693))
        XCTAssertTrue(url.absoluteString.contains("latitude=47.38&longitude=8.54"), url.absoluteString)
    }
}
