import XCTest
@testable import BeWaterMyFriend

final class DrinkMathTests: XCTestCase {
    func testScalesPer100mlToDrunkVolume() throws {
        // 330 ml drink → × 3.3
        let scaled = try XCTUnwrap(DrinkMath.scale(10, toVolumeML: 330))
        XCTAssertEqual(scaled, 33, accuracy: 0.0001)
    }

    func testUnknownValueStaysUnknown() {
        XCTAssertNil(DrinkMath.scale(nil, toVolumeML: 330))
    }

    func testZeroIsKnownAndStaysZero() {
        XCTAssertEqual(DrinkMath.scale(0, toVolumeML: 330), 0)
    }

    func testPer100mlFromTotalIsInverseOfScale() throws {
        // Espresso: 63 mg in 30 ml → 210 mg / 100 ml
        let per100 = try XCTUnwrap(DrinkMath.per100ml(fromTotal: 63, volumeML: 30))
        XCTAssertEqual(per100, 210, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(DrinkMath.scale(per100, toVolumeML: 30)), 63, accuracy: 0.0001)
    }

    func testPer100mlWithZeroVolumeIsUnknown() {
        XCTAssertNil(DrinkMath.per100ml(fromTotal: 63, volumeML: 0))
    }

    func testAlcoholGramsForBeer() {
        // 330 ml × 5 % × 0.789 g/ml = 13.0185 g
        XCTAssertEqual(DrinkMath.alcoholGrams(volumeML: 330, alcoholPercent: 5), 13.0185, accuracy: 0.0001)
    }

    func testNoAlcoholWhenPercentMissingOrZero() {
        XCTAssertEqual(DrinkMath.alcoholGrams(volumeML: 330, alcoholPercent: nil), 0)
        XCTAssertEqual(DrinkMath.alcoholGrams(volumeML: 330, alcoholPercent: 0), 0)
    }

    func testStandardDrinks() {
        XCTAssertEqual(DrinkMath.standardDrinks(alcoholGrams: 13.0185), 1.30185, accuracy: 0.0001)
    }
}
