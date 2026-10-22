import HealthKit
import XCTest
@testable import App

final class HealthKitPluginTests: XCTestCase {
    func testMapsEverySharedWorkoutType() {
        XCTAssertEqual(HealthKitPlugin.activityType(for: "strength_training"), .traditionalStrengthTraining)
        XCTAssertEqual(HealthKitPlugin.activityType(for: "walking"), .walking)
        XCTAssertEqual(HealthKitPlugin.activityType(for: "running"), .running)
        XCTAssertEqual(HealthKitPlugin.activityType(for: "biking_stationary"), .cycling)
        XCTAssertEqual(HealthKitPlugin.activityType(for: "elliptical"), .elliptical)
        XCTAssertEqual(HealthKitPlugin.activityType(for: "stair_climbing_machine"), .stairClimbing)
        XCTAssertEqual(HealthKitPlugin.activityType(for: "other_workout"), .other)
    }

    func testMapsUnknownWorkoutTypeToOther() {
        XCTAssertEqual(HealthKitPlugin.activityType(for: "something_else"), .other)
        XCTAssertEqual(HealthKitPlugin.activityType(for: nil), .other)
    }

    func testBodyMassHelperStoresKilograms() {
        let quantity = HealthKitPlugin.bodyMassQuantity(for: 72.5)
        let kilograms = quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))

        XCTAssertEqual(kilograms, 72.5, accuracy: 0.000_001)
    }
}
