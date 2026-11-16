import XCTest
@testable import BCLCore
import BCLShared

final class ChargePolicyEngineTests: XCTestCase {

    func testChargesUntilTheLimitAndStopsAtIt() {
        var engine = ChargePolicyEngine()
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 80), socPercent: 79), .allow)
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 80), socPercent: 80), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 80), socPercent: 81), .inhibit)
    }

    func testHoldsUntilTheChargeFallsThreePercentBelowTheLimit() {
        var engine = ChargePolicyEngine()
        let config = BCLSettings(limitPercent: 80)
        XCTAssertEqual(engine.evaluate(settings: config, socPercent: 80), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: config, socPercent: 79), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: config, socPercent: 78), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: config, socPercent: 77), .allow)
    }

    func testAlreadyAboveTheLimitInhibitsImmediately() {
        var engine = ChargePolicyEngine()
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 80), socPercent: 96), .inhibit)
    }

    func testRaisingTheLimitWhileHeldReEnablesCharging() {
        var engine = ChargePolicyEngine()
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 60), socPercent: 65), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 80), socPercent: 65), .allow)
    }

    func testLoweringTheLimitWhileHeldKeepsChargingInhibited() {
        var engine = ChargePolicyEngine()
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 80), socPercent: 82), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: BCLSettings(limitPercent: 60), socPercent: 79), .inhibit)
    }

    func testTheReArmPointIsAlwaysBelowTheLimit() {
        let floor = BCLSettings(limitPercent: 50)
        XCTAssertEqual(floor.rearmPercent, 47)
        var engine = ChargePolicyEngine()
        XCTAssertEqual(engine.evaluate(settings: floor, socPercent: 50), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: floor, socPercent: 48), .inhibit)
        XCTAssertEqual(engine.evaluate(settings: floor, socPercent: 47), .allow)
    }

    func testSettingsClampToTheSliderRange() {
        XCTAssertEqual(BCLSettings(limitPercent: 240).limitPercent, 80)
        XCTAssertEqual(BCLSettings(limitPercent: 5).limitPercent, 50)
        XCTAssertEqual(BCLSettings().limitPercent, 80)
        XCTAssertEqual(BCLSettings.limitRange, 50...80)
    }

    func testSettingsSurviveJSONRoundTrip() {
        let original = BCLSettings(limitPercent: 65)
        XCTAssertEqual(BCLSettings.decode(fromJSON: original.encodedJSON()), original)
    }
}
