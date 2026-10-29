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
