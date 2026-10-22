import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct OpenGymLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(restColor(context.state.accent, fallback: .green))
                .activitySystemActionForegroundColor(restColor(context.state.ink, fallback: .white))
        } dynamicIsland: { context in
            let accent = restColor(context.state.accent, fallback: .green)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state)
                        .font(.title3.monospacedDigit())
                        .frame(maxWidth: 100, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    RestControls(restId: context.attributes.restId, paused: context.state.paused)
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(accent)
            } compactTrailing: {
                RestCountdown(state: context.state)
                    .font(.caption.monospacedDigit())
            } minimal: {
                Image(systemName: "timer").foregroundStyle(accent)
            }
            .keylineTint(accent)
        }
    }
}

private struct RestLockScreenView: View {
    let context: ActivityViewContext<RestActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(context.state.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                RestCountdown(state: context.state)
                    .font(.title2.monospacedDigit())
            }
            RestControls(restId: context.attributes.restId, paused: context.state.paused)
        }
        .padding()
    }
}

private struct RestCountdown: View {
    let state: RestActivityAttributes.ContentState

    var body: some View {
        if !state.paused, let endAt = state.endAt {
            let startAt = endAt.addingTimeInterval(-Double(max(0, state.totalMs)) / 1000)
            Text(timerInterval: startAt...endAt, countsDown: true)
        } else {
            Text(remainingText(state.leftMs))
        }
    }
}

private struct RestControls: View {
    let restId: String
    let paused: Bool

    var body: some View {
        HStack(spacing: 14) {
            if paused {
                Button(intent: RestResumeIntent(restId: restId)) {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button(intent: RestPauseIntent(restId: restId)) {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
            Button(intent: RestMinusIntent(restId: restId)) {
                Label("−15", systemImage: "minus")
            }
            Button(intent: RestPlusIntent(restId: restId)) {
                Label("+15", systemImage: "plus")
            }
            Button(intent: RestSkipIntent(restId: restId)) {
                Label("Skip", systemImage: "forward.end.fill")
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
    }
}

private func remainingText(_ milliseconds: Int64) -> String {
    let seconds = max(0, Int((milliseconds + 999) / 1000))
    return String(format: "%02d:%02d", seconds / 60, seconds % 60)
}

private func restColor(_ value: String, fallback: Color) -> Color {
    var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard let number = UInt64(hex, radix: 16) else { return fallback }

    if hex.count == 8 {
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: Double((number >> 24) & 0xFF) / 255
        )
    }
    guard hex.count == 6 else { return fallback }
    return Color(
        red: Double((number >> 16) & 0xFF) / 255,
        green: Double((number >> 8) & 0xFF) / 255,
        blue: Double(number & 0xFF) / 255
    )
}
