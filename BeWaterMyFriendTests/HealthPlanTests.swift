import SwiftData
import XCTest
@testable import BeWaterMyFriend

@MainActor
final class HealthPlanTests: XCTestCase {
    private let boundary = DayBoundary(dayEndMinutes: 3 * 60, calendar: zurich)

    private func value(_ quantity: HealthQuantity, in samples: [PlannedSample]) -> Double? {
        samples.first { $0.quantity == quantity }?.value
    }

    func testWaterOnlyForPlainWater() {
        let samples = HealthPlan.samples(for: DrinkEntry(name: "Water", category: .water, volumeML: 250))
        XCTAssertEqual(samples, [PlannedSample(quantity: .water, value: 250)])
    }

    func testBeerWritesHydrationWaterAndStandardDrinks() throws {
        let beer = DrinkEntry(name: "Beer", category: .beer, volumeML: 330, alcoholPercent: 5)
        let samples = HealthPlan.samples(for: beer)
        XCTAssertEqual(try XCTUnwrap(value(.water, in: samples)), 313.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(value(.alcoholicBeverages, in: samples)), 1.30185, accuracy: 0.0001)
    }

    func testNutrientsAreScaledAndUnknownOrZeroSkipped() throws {
        var nutrients = Nutrients()
        nutrients.caffeineMg = 210
        nutrients.sugarG = 0
        let espresso = DrinkEntry(name: "Espresso", category: .coffee, volumeML: 30, nutrientsPer100ml: nutrients)
        let samples = HealthPlan.samples(for: espresso)
        XCTAssertEqual(try XCTUnwrap(value(.nutrient(.caffeine), in: samples)), 63, accuracy: 0.0001)
        XCTAssertNil(value(.nutrient(.sugar), in: samples), "zero is not written")
        XCTAssertNil(value(.nutrient(.magnesium), in: samples), "unknown is not written")
        XCTAssertNil(value(.alcoholicBeverages, in: samples))
    }

    func testZeroHydrationWritesNoWater() {
        let entry = DrinkEntry(name: "Shot", category: .spirits, volumeML: 40, alcoholPercent: 40, hydrationPercent: 0)
        XCTAssertNil(value(.water, in: HealthPlan.samples(for: entry)))
    }

    func testEveryQuantityHasAKnownUnit() {
        let known: Set<String> = ["ml", "count", "g", "mg", "µg", "kcal"]
        for quantity in HealthQuantity.all {
            XCTAssertTrue(known.contains(quantity.unit), "\(quantity) has unit \(quantity.unit)")
        }
        XCTAssertEqual(HealthQuantity.all.count, 2 + Nutrient.allCases.count)
    }

    // MARK: Due dates

    func testImmediatelyIsDueAtLastChange() {
        let changed = date(2026, 10, 23, 10, 0)
        XCTAssertEqual(HealthPlan.dueDate(timestamp: date(2026, 10, 23, 9, 0), modifiedAt: changed,
                                          delay: .immediately, boundary: boundary), changed)
    }

    func testOneHourCountsFromLastChange() {
        XCTAssertEqual(HealthPlan.dueDate(timestamp: date(2026, 10, 23, 9, 0), modifiedAt: date(2026, 10, 23, 10, 0),
                                          delay: .oneHour, boundary: boundary),
                       date(2026, 10, 23, 11, 0))
    }

    func testEndOfDayUsesCustomDayEnd() {
        // Day end 03:00 → the logical day of 23 Oct ends on 24 Oct at 03:00.
        XCTAssertEqual(HealthPlan.dueDate(timestamp: date(2026, 10, 23, 22, 0), modifiedAt: date(2026, 10, 23, 22, 0),
                                          delay: .endOfDay, boundary: boundary),
                       date(2026, 10, 24, 3, 0))
    }

    func testEditingAnOldEntryAtEndOfDayIsDueRightAway() {
        let edit = date(2026, 10, 25, 12, 0)
        XCTAssertEqual(HealthPlan.dueDate(timestamp: date(2026, 10, 20, 12, 0), modifiedAt: edit,
                                          delay: .endOfDay, boundary: boundary), edit)
    }

    func testLegacyEntryWithoutModifiedAtUsesTimestamp() {
        let time = date(2026, 10, 23, 9, 0)
        XCTAssertEqual(HealthPlan.dueDate(timestamp: time, modifiedAt: nil, delay: .oneHour, boundary: boundary),
                       time.addingTimeInterval(3600))
    }

    func testIsDueOnlyWhenPendingAndTimeHasCome() {
        let entry = DrinkEntry(timestamp: date(2026, 10, 23, 9, 0), name: "Water", category: .water, volumeML: 250)
        entry.modifiedAt = date(2026, 10, 23, 9, 0)
        XCTAssertFalse(HealthPlan.isDue(entry, delay: .oneHour, boundary: boundary, now: date(2026, 10, 23, 9, 59)))
        XCTAssertTrue(HealthPlan.isDue(entry, delay: .oneHour, boundary: boundary, now: date(2026, 10, 23, 10, 0)))
        entry.healthWrittenAt = entry.modifiedAt  // written
        XCTAssertFalse(HealthPlan.isDue(entry, delay: .oneHour, boundary: boundary, now: date(2026, 10, 23, 12, 0)))
    }

    // MARK: Deletes

    func testDeletingAWrittenEntryQueuesItsHealthSamples() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let written = DrinkEntry(name: "Water", category: .water, volumeML: 250)
        written.healthSyncID = UUID()
        written.healthWrittenAt = written.modifiedAt
        let notWritten = DrinkEntry(name: "Tea", category: .tea, volumeML: 250)
        context.insert(written)
        context.insert(notWritten)
        try context.save()

        EntryActions.delete([written, notWritten], in: context, defaults: defaults)

        XCTAssertEqual(PendingHealthDeletes.all(defaults: defaults), [written.healthSyncID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<DrinkEntry>()), 0)
    }
}
