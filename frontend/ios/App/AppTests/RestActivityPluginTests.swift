import Foundation
import XCTest
@testable import App

@available(iOS 17.0, *)
final class RestActivityPluginTests: XCTestCase {
    func testConvertsEpochMillisecondsAndNilToZero() {
        let date = Date(timeIntervalSince1970: 1_735_689_600.123)

        XCTAssertEqual(RestActivityActionQueue.epochMilliseconds(date), 1_735_689_600_123)
        XCTAssertEqual(RestActivityActionQueue.epochMilliseconds(nil), 0)
    }

    func testPausedContentStateSerializesWithoutAnEndDate() throws {
        let state = RestActivityAttributes.ContentState(
            endAt: nil,
            leftMs: 15_000,
            totalMs: 90_000,
            paused: true,
            title: "Rest over",
            accent: "#FF453A",
            ink: "#FFFFFF"
        )

        let decoded = try JSONDecoder().decode(
            RestActivityAttributes.ContentState.self,
            from: JSONEncoder().encode(state)
        )

        XCTAssertNil(decoded.endAt)
        XCTAssertEqual(decoded.leftMs, 15_000)
        XCTAssertEqual(decoded.totalMs, 90_000)
        XCTAssertTrue(decoded.paused)
    }

    func testActionQueueKeepsOnlyTheNewestTwentyActions() {
        let actions = (0..<25).map { index in
            RestActivityActionQueue.makeAction(
                type: "adjust",
                endAt: nil,
                leftMs: Int64(index),
                totalMs: 90_000,
                paused: true
            )
        }

        let bounded = RestActivityActionQueue.bounded(actions)

        XCTAssertEqual(bounded.count, 20)
        XCTAssertEqual(bounded.first?.leftMs, 5)
        XCTAssertEqual(bounded.last?.leftMs, 24)
    }

    func testAllLiveActivityActionNamesRemainSerializable() throws {
        let names = ["pause", "resume", "adjust", "adjust", "skip"]
        let actions = names.map {
            RestActivityActionQueue.makeAction(
                type: $0,
                endAt: nil,
                leftMs: 0,
                totalMs: 90_000,
                paused: false
            )
        }

        let decoded = try JSONDecoder().decode(
            [RestActivityActionQueue.RestActivityAction].self,
            from: JSONEncoder().encode(actions)
        )

        XCTAssertEqual(decoded.map(\.type), names)
    }
}
