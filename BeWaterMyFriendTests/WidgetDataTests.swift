import SwiftData
import XCTest
@testable import BeWaterMyFriend

@MainActor
final class WidgetDataTests: XCTestCase {
    private func drink(_ name: String = "Water", _ category: DrinkCategory = .water, ml: Double = 250, at time: Date,
                       caffeinePer100: Double? = nil, alcohol: Double? = nil) -> WidgetDrink {
        var nutrients = Nutrients()
        nutrients.caffeineMg = caffeinePer100
        return WidgetDrink(name: name, categoryRaw: category.rawValue, volumeML: ml, alcoholPercent: alcohol,
                           nutrients: nutrients, timestamp: time)
    }

    private func snapshot(_ recent: [WidgetDrink], goal: Double = 2000) -> WidgetSnapshot {
        WidgetSnapshot(goalML: goal, dayEndMinutes: 0, beltRaw: Belt.blue.rawValue, prestige: 1, companionEnabled: true,
                       recent: recent, quickDrinks: [])
    }

    private func freshDefaults() -> UserDefaults {
        let name = "WidgetDataTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private let now = date(2026, 10, 31, 15, 0)

    func testStateUsesTodaysDrinksAndCountsDrinksLoggedFromTheWidget() {
        let old = drink(ml: 999, at: date(2026, 10, 30, 12))
        let today = drink(ml: 500, at: date(2026, 10, 31, 9))
        let pending = drink(ml: 250, at: date(2026, 10, 31, 14, 59))
        let state = WidgetState.make(snapshot: snapshot([old, today]), pending: [pending], now: now, calendar: zurich)
        XCTAssertEqual(state.ml, 750, accuracy: 0.001)
        XCTAssertEqual(state.progress, 0.375, accuracy: 0.001)
        XCTAssertEqual(state.belt, .blue)
        XCTAssertEqual(state.prestige, 1)
    }

    func testMoodComesFromTheDrinksAndTheWidgetKnowsWhenItChanges() throws {
        let coffee = drink("Coffee", .coffee, at: date(2026, 10, 31, 14), caffeinePer100: 40)
        let state = WidgetState.make(snapshot: snapshot([coffee]), pending: [], now: now, calendar: zurich)
        XCTAssertEqual(state.mood, .hyper)
        XCTAssertEqual(state.nextChange, date(2026, 10, 31, 17), "the caffeine wears off")
        XCTAssertEqual(state.message, CompanionLines.todayMessage(mood: .hyper, progress: state.progress))

        // Yesterday evening's beer still counts for the mood, not for today's amount.
        let beer = drink("Beer", .beer, ml: 500, at: date(2026, 10, 30, 23, 30), alcohol: 5)
        let night = WidgetState.make(snapshot: snapshot([beer]), pending: [], now: date(2026, 10, 31, 0, 30), calendar: zurich)
        XCTAssertEqual(night.mood, .tipsy)
        XCTAssertEqual(night.ml, 0)
    }

    func testPictureGoesOutOfDateAtTheEndOfTheDay() {
        let state = WidgetState.make(snapshot: snapshot([]), pending: [], now: now, calendar: zurich)
        XCTAssertEqual(state.nextChange, date(2026, 11, 1, 0, 0))
    }

    func testWithoutASnapshotTheWidgetAsksToOpenTheApp() {
        let state = WidgetState.make(snapshot: nil, pending: [], now: now, calendar: zurich)
        XCTAssertEqual(state.message, "Open the app once to start.")
        XCTAssertEqual(state.ml, 0)
    }

    func testStoreKeepsSnapshotAndPendingAndForgetsOnlyWhatItIsTold() throws {
        let defaults = freshDefaults()
        XCTAssertNil(WidgetStore.snapshot(in: defaults))
        WidgetStore.save(snapshot([drink(at: now)]), in: defaults)
        XCTAssertEqual(WidgetStore.snapshot(in: defaults)?.recent.count, 1)

        let a = drink("A", at: now), b = drink("B", at: now)
        WidgetStore.addPending(a, in: defaults)
        WidgetStore.addPending(b, in: defaults)
        XCTAssertEqual(WidgetStore.pending(in: defaults).map(\.name), ["A", "B"])
        WidgetStore.removePending(ids: [a.id], in: defaults)
        XCTAssertEqual(WidgetStore.pending(in: defaults).map(\.name), ["B"])
    }

    func testDrainingTurnsNotesIntoRealDrinksOnce() throws {
        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = freshDefaults()
        WidgetStore.addPending(drink("Espresso", .coffee, ml: 30, at: date(2026, 10, 31, 14, 12), caffeinePer100: 210), in: defaults)

        WidgetBridge.drainPending(context: context, store: defaults)
        WidgetBridge.drainPending(context: context, store: defaults)

        let entries = try context.fetch(FetchDescriptor<DrinkEntry>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.name, "Espresso")
        XCTAssertEqual(entries.first?.timestamp, date(2026, 10, 31, 14, 12), "when it was tapped, not when the app opened")
        XCTAssertEqual(try XCTUnwrap(entries.first).caffeineMg, 63, accuracy: 0.001)
        XCTAssertTrue(WidgetStore.pending(in: defaults).isEmpty)
    }

    func testSnapshotHasStarsInOrderAndOnlyRecentDrinks() throws {
        let container = try ModelContainer(for: DrinkEntry.self, DrinkPreset.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(DrinkPreset(name: "Second", category: .water, volumeML: 500, starNumber: 2, sortOrder: 0))
        context.insert(DrinkPreset(name: "First", category: .coffee, volumeML: 30, starNumber: 1, sortOrder: 1))
        context.insert(DrinkEntry(timestamp: .now.addingTimeInterval(-60), name: "New", category: .water, volumeML: 250))
        context.insert(DrinkEntry(timestamp: .now.addingTimeInterval(-5 * 86400), name: "Old", category: .water, volumeML: 250))
        try context.save()

        let snapshot = WidgetBridge.makeSnapshot(context: context, defaults: freshDefaults())
        XCTAssertEqual(snapshot.quickDrinks.map(\.name), ["First", "Second"])
        XCTAssertEqual(snapshot.quickDrinks.map(\.starNumber), [1, 2])
        XCTAssertEqual(snapshot.recent.map(\.name), ["New"])
    }

    /// The widgets' App Group must never move the drink database.
    func testDatabaseStaysInTheAppsOwnFolder() {
        let url = BeWaterMyFriendApp.storeConfiguration.url
        XCTAssertEqual(url.lastPathComponent, "default.store")
        XCTAssertTrue(url.path.contains("/Library/Application Support/"), url.path)
        XCTAssertFalse(url.path.contains("/AppGroup/"), url.path)
    }

    func testPublishingOnlyCountsRealChanges() {
        let a = snapshot([drink(at: now)])
        var b = a
        b.recent = a.recent.map { var d = $0; d.id = UUID(); return d }
        XCTAssertTrue(WidgetBridge.isSame(a, b), "a new id alone isn't a change")
        b.goalML = 2500
        XCTAssertFalse(WidgetBridge.isSame(a, b))
        XCTAssertFalse(WidgetBridge.isSame(a, nil))
    }
}
