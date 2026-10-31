import XCTest

/// Smoke tests: tap through the app like a person would and fail if it crashes.
/// They catch the bugs the logic tests can't see (threads, animations, screens),
/// like the crash on 29 Oct. Run them on the iPhone, not only in the simulator:
///
///     xcodebuild test -scheme SmokeTests -destination 'id=<iPhone UDID>'
///
/// The app runs in UI test mode (`-UITestMode`, see `AppEnvironment`): sample
/// drinks in memory, separate settings, no Health, weather or reminders. A run
/// never changes the real drinks, settings or ranks on the phone.
@MainActor
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-UITestMode"]
        app.launch()
    }

    private func tab(_ name: String) {
        app.tabBars.buttons[name].firstMatch.tap()
    }

    /// Fails if the app is no longer running (it crashed or was killed).
    private func assertAlive(_ step: String) {
        XCTAssertEqual(app.state, .runningForeground, "App stopped after: \(step)")
    }

    func testEveryTabOpens() {
        for name in ["History", "Stats", "Settings", "Today"] {
            tab(name)
            assertAlive("opening \(name)")
        }
    }

    func testFastTabSwitching() {
        for i in 0..<20 {
            tab(["Today", "History", "Stats", "Settings"][i % 4])
        }
        assertAlive("20 fast tab switches")
    }

    /// The day replay crashed reliably on the phone before the 29 Oct fix.
    func testDayReplayRepeatedlyAndWhileSwitchingTabs() {
        tab("History")
        let day = app.buttons["dayRow"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        let replay = app.buttons["replayButton"]
        XCTAssertTrue(replay.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            replay.tap()
            sleep(1)
        }
        tab("Stats")  // leave mid-replay
        tab("History")
        replay.tap()
        sleep(4)
        assertAlive("replaying the day")
    }

    func testLogADrinkThroughTheEditor() {
        app.buttons["Add drink"].firstMatch.tap()
        let water = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Glass of water'")).firstMatch
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        water.tap()
        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        assertAlive("logging a drink")
    }

    /// Opening the scan screen made the drop jump; opening it repeatedly checks it stays stable.
    func testScanScreenOpensAndClosesRepeatedly() {
        for _ in 0..<3 {
            app.buttons["Scan"].firstMatch.tap()
            let cancel = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            sleep(1)
            cancel.tap()
        }
        assertAlive("opening the scanner three times")
    }

    /// Long press → edit mode (without logging), drag, remove, add, Done.
    func testQuickLogEditMode() {
        let water = app.buttons["Log Glass of water, 250 ml"].firstMatch
        for _ in 0..<4 where !water.isHittable { app.swipeUp() }
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        water.press(forDuration: 1.0)

        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 3), "Long press should open the edit mode")
        XCTAssertFalse(app.staticTexts["Undo"].exists, "A long press must not log the drink")
        XCTAssertFalse(app.buttons["Undo"].exists, "A long press must not log the drink")

        // Drag the first tile onto the third: its position must change.
        let first = app.otherElements["quickLogEdit-Glass of water"]
        let third = app.otherElements["quickLogEdit-Espresso"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let startX = first.frame.minX
        first.press(forDuration: 0.8, thenDragTo: third)
        sleep(1)
        XCTAssertNotEqual(first.frame.minX, startX, "Dragging should move the tile")

        // Remove one.
        let remove = app.buttons["Remove Herbal tea from the Quick log"]
        if remove.exists {
            remove.tap()
            sleep(1)
            XCTAssertFalse(app.otherElements["quickLogEdit-Herbal tea"].exists)
        }

        // "+" lists drinks not in the Quick log; tapping one brings it back.
        let add = app.buttons["Add a drink to the Quick log"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.tap()
        let herbal = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Herbal tea'")).firstMatch
        XCTAssertTrue(herbal.waitForExistence(timeout: 5), "A removed drink should be offered again")
        herbal.tap()
        XCTAssertTrue(app.otherElements["quickLogEdit-Herbal tea"].waitForExistence(timeout: 5))

        done.tap()
        XCTAssertTrue(water.waitForExistence(timeout: 3), "Done should end the edit mode")
        assertAlive("editing the Quick log")
    }

    /// Congratulations, then the quote line by line, ending with "Be water, my friend."
    func testBlackBeltQuote() {
        app.terminate()
        app.launchArguments = ["-UITestMode", "-UITestBlackBelt"]
        app.launch()
        let next = app.buttons["Continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5), "The black belt screen should appear")
        XCTAssertTrue(app.staticTexts["New belt!"].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["Black belt is just the beginning"].waitForExistence(timeout: 5))
        let quote = app.staticTexts.containing(NSPredicate(format: "label ENDSWITH 'Be water, my friend.'")).firstMatch
        XCTAssertTrue(quote.waitForExistence(timeout: 10), "Should fade over to the quote on its own")
        XCTAssertTrue(app.staticTexts["— Bruce Lee"].exists)
        let done = app.buttons["Keep flowing"]
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        done.tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].firstMatch.waitForExistence(timeout: 5))
        assertAlive("the black belt quote")
    }

    /// A barcode that isn't in the database: a clear message, then manual entry.
    /// Works without internet too: then the error also offers manual entry.
    func testUnknownBarcodeIsNeverSilentlyWater() {
        app.buttons["Scan"].firstMatch.tap()
        let field = app.textFields["Barcode number"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("7610000000017")
        app.buttons["Look up"].tap()

        let manual = app.buttons["Enter it manually"]
        XCTAssertTrue(manual.waitForExistence(timeout: 15), "Should offer manual entry, not open a result")
        manual.tap()

        let add = app.buttons["Add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertFalse(add.isEnabled, "Nothing to add before a name and a type are given")

        let name = app.textFields.element(boundBy: 0)
        name.tap()
        name.typeText("Brand new drink")
        XCTAssertFalse(add.isEnabled, "A name alone isn't enough: nothing defaults to water")
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Type'")).firstMatch.tap()
        let juice = app.buttons["Juice"].firstMatch
        XCTAssertTrue(juice.waitForExistence(timeout: 3))
        juice.tap()
        XCTAssertTrue(add.isEnabled)
        add.tap()
        let notNow = app.buttons["Not now"].firstMatch
        XCTAssertTrue(notNow.waitForExistence(timeout: 3))
        notNow.tap()

        // Next time this barcode is known, without any internet.
        let scan = app.buttons["Scan"].firstMatch
        XCTAssertTrue(scan.waitForExistence(timeout: 5))
        sleep(1)
        scan.tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("7610000000017")
        app.buttons["Look up"].tap()
        XCTAssertTrue(app.textFields["Name, e.g. Rivella Rot"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["Name, e.g. Rivella Rot"].value as? String, "Brand new drink")
        assertAlive("remembering an unknown drink")
    }

    /// Everything in the Quick log edit mode, many times, as fast as a person could.
    func testQuickLogEditModeStress() {
        let water = app.buttons["Log Glass of water, 250 ml"].firstMatch
        for _ in 0..<4 where !water.isHittable { app.swipeUp() }
        XCTAssertTrue(water.waitForExistence(timeout: 5))
        for round in 0..<3 {
            water.press(forDuration: 0.8)
            let done = app.buttons["Done"].firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 3), "Round \(round)")
            let names = ["Glass of water", "Bottle of water", "Espresso", "Coffee", "Black tea", "Herbal tea"]
            for i in 0..<5 {
                app.otherElements["quickLogEdit-\(names[i])"]
                    .press(forDuration: 0.3, thenDragTo: app.otherElements["quickLogEdit-\(names[i + 1])"])
            }
            let remove = app.buttons["Remove Beer from the Quick log"]
            XCTAssertTrue(remove.exists)
            remove.tap()
            app.buttons["Add a drink to the Quick log"].tap()
            let beer = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Beer'")).firstMatch
            XCTAssertTrue(beer.waitForExistence(timeout: 5))
            beer.tap()
            XCTAssertTrue(app.otherElements["quickLogEdit-Beer"].waitForExistence(timeout: 5))
            done.tap()
            sleep(1)
        }
        // Leaving the tab during editing ends it cleanly.
        water.press(forDuration: 0.8)
        tab("Stats")
        tab("Today")
        XCTAssertTrue(app.buttons["Add drink"].firstMatch.waitForExistence(timeout: 3))
        assertAlive("stressing the Quick log")
    }

    /// Stars in Settings: numbered, a fourth needs a choice, removing moves others up.
    func testStarsInSettings() {
        tab("Settings")
        let presetsLink = app.buttons["Drink presets"].firstMatch
        for _ in 0..<5 where !presetsLink.isHittable { app.swipeUp() }
        presetsLink.tap()
        let starCoffee = app.buttons["Star Coffee for the widgets"]
        XCTAssertFalse(starCoffee.exists, "All three are taken at the start, so it's a menu")
        let replace = app.buttons["Star Coffee instead of another drink"]
        XCTAssertTrue(replace.waitForExistence(timeout: 5))
        let first = app.buttons["Glass of water, star 1. Change"]
        XCTAssertTrue(first.exists)
        first.tap()
        let removeStar = app.buttons["Remove star"]
        XCTAssertTrue(removeStar.waitForExistence(timeout: 3))
        removeStar.tap()
        XCTAssertTrue(app.buttons["Bottle of water, star 1. Change"].waitForExistence(timeout: 3), "Others move up")
        XCTAssertTrue(starCoffee.waitForExistence(timeout: 3), "A number is free now, so one tap stars it")
        starCoffee.tap()
        XCTAssertTrue(app.buttons["Coffee, star 3. Change"].waitForExistence(timeout: 3))
        assertAlive("changing stars")
    }

    func testStatsChartsCanBeTapped() {
        tab("Stats")
        let window = app.windows.firstMatch
        // Tap around the charts (bars, donut) while scrolling down.
        for _ in 0..<3 {
            for x in [0.2, 0.5, 0.8] {
                window.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.6)).tap()
            }
            app.swipeUp()
        }
        assertAlive("tapping the Stats charts")
    }
}
