import ActivityKit
import AppIntents
import Foundation

@available(iOS 17.0, *)
private enum RestActivityIntentSupport {
    static func activity(for id: String) -> Activity<RestActivityAttributes>? {
        Activity<RestActivityAttributes>.activities.first {
            $0.activityState == .active && $0.attributes.restId == id
        }
    }

    static func remainingMilliseconds(_ state: RestActivityAttributes.ContentState, now: Date = Date()) -> Int64 {
        guard !state.paused, let endAt = state.endAt else {
            return max(0, state.leftMs)
        }
        return max(0, Int64((endAt.timeIntervalSince(now) * 1000).rounded()))
    }

    static func update(
        _ activity: Activity<RestActivityAttributes>,
        state: RestActivityAttributes.ContentState
    ) async {
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    static func pause(_ id: String) async {
        guard let activity = activity(for: id) else { return }
        var state = activity.content.state
        let leftMs = remainingMilliseconds(state)
        state.endAt = nil
        state.leftMs = leftMs
        state.paused = true
        RestActivityActionQueue.append(
            type: "pause", endAt: nil, leftMs: leftMs, totalMs: state.totalMs, paused: true
        )
        await update(activity, state: state)
    }

    static func resume(_ id: String) async {
        guard let activity = activity(for: id) else { return }
        var state = activity.content.state
        let leftMs = max(0, state.leftMs)
        let endAt = Date().addingTimeInterval(Double(leftMs) / 1000)
        state.endAt = endAt
        state.leftMs = leftMs
        state.paused = false
        RestActivityActionQueue.append(
            type: "resume", endAt: endAt, leftMs: leftMs, totalMs: state.totalMs, paused: false
        )
        await update(activity, state: state)
    }

    static func adjust(_ id: String, by delta: Int64) async {
        guard let activity = activity(for: id) else { return }
        var state = activity.content.state
        let current = remainingMilliseconds(state)
        let leftMs = max(1_000, current + delta)
        let totalMs = max(state.totalMs, leftMs)
        let endAt = state.paused ? nil : Date().addingTimeInterval(Double(leftMs) / 1000)
        state.endAt = endAt
        state.leftMs = leftMs
        state.totalMs = totalMs
        RestActivityActionQueue.append(
            type: "adjust", endAt: endAt, leftMs: leftMs, totalMs: totalMs, paused: state.paused
        )
        await update(activity, state: state)
    }

    static func skip(_ id: String) async {
        guard let activity = activity(for: id) else { return }
        let state = activity.content.state
        RestActivityActionQueue.append(
            type: "skip", endAt: nil, leftMs: 0, totalMs: state.totalMs, paused: false
        )
        await activity.end(nil, dismissalPolicy: .immediate)
    }
}

@available(iOS 17.0, *)
struct RestPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause"
    static let isDiscoverable = false

    @Parameter(title: "Rest") var restId: String

    init() {}

    init(restId: String) {
        self.restId = restId
    }

    func perform() async throws -> some IntentResult {
        await RestActivityIntentSupport.pause(restId)
        return .result()
    }
}

@available(iOS 17.0, *)
struct RestResumeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume"
    static let isDiscoverable = false

    @Parameter(title: "Rest") var restId: String

    init() {}

    init(restId: String) {
        self.restId = restId
    }

    func perform() async throws -> some IntentResult {
        await RestActivityIntentSupport.resume(restId)
        return .result()
    }
}

@available(iOS 17.0, *)
struct RestMinusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Minus 15 seconds"
    static let isDiscoverable = false

    @Parameter(title: "Rest") var restId: String

    init() {}

    init(restId: String) {
        self.restId = restId
    }

    func perform() async throws -> some IntentResult {
        await RestActivityIntentSupport.adjust(restId, by: -15_000)
        return .result()
    }
}

@available(iOS 17.0, *)
struct RestPlusIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Plus 15 seconds"
    static let isDiscoverable = false

    @Parameter(title: "Rest") var restId: String

    init() {}

    init(restId: String) {
        self.restId = restId
    }

    func perform() async throws -> some IntentResult {
        await RestActivityIntentSupport.adjust(restId, by: 15_000)
        return .result()
    }
}

@available(iOS 17.0, *)
struct RestSkipIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip"
    static let isDiscoverable = false

    @Parameter(title: "Rest") var restId: String

    init() {}

    init(restId: String) {
        self.restId = restId
    }

    func perform() async throws -> some IntentResult {
        await RestActivityIntentSupport.skip(restId)
        return .result()
    }
}
