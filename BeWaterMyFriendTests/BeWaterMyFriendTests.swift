import XCTest
@testable import BeWaterMyFriend

final class BeWaterMyFriendTests: XCTestCase {
    /// Smoke test: proves the test target builds and links against the app.
    func testAppModuleLoads() {
        XCTAssertNotNil(ContentView())
    }
}
