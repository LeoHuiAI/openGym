import ActivityKit
import Capacitor
import CoreFoundation
import Foundation

@objc(RestActivityPlugin)
public class RestActivityPlugin: CAPPlugin {

    @objc func start(_ call: CAPPluginCall) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            call.reject("Live Activities are disabled", "unavailable")
            return
        }

        do {
            let id = try requiredString(call, "id")
            let title = try requiredString(call, "title")
            let endAt = try requiredDate(call, "endAt")
            let totalMs = try requiredMilliseconds(call, "totalMs")
            let accent = color(call, "accent") ?? "#34C759"
            let ink = color(call, "ink") ?? "#FFFFFF"
            let attributes = RestActivityAttributes(restId: id)
            let state = RestActivityAttributes.ContentState(
                endAt: endAt,
                leftMs: max(0, Int64((endAt.timeIntervalSinceNow * 1000).rounded())),
                totalMs: totalMs,
                paused: false,
                title: title,
                accent: accent,
                ink: ink
            )

            Task {
                do {
                    let all = Activity<RestActivityAttributes>.activities.filter { $0.activityState == .active }
                    let matching = all.filter { $0.attributes.restId == id }
                    for activity in all where activity.attributes.restId != id {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                    for duplicate in matching.dropFirst() {
                        await duplicate.end(nil, dismissalPolicy: .immediate)
                    }

                    if let existing = matching.first {
                        await existing.update(ActivityContent(state: state, staleDate: nil))
                    } else {
                        _ = try Activity.request(
                            attributes: attributes,
                            content: ActivityContent(state: state, staleDate: nil),
                            pushType: nil
                        )
                    }
                    call.resolve()
                } catch {
                    call.reject(error.localizedDescription, "failed", error)
                }
            }
        } catch {
            reject(call, error)
        }
    }

    @objc func update(_ call: CAPPluginCall) {
        do {
            let id = try requiredString(call, "id")
            let endAt = try optionalDate(call, "endAt")
            let totalMs = try requiredMilliseconds(call, "totalMs")
            let leftMs = try requiredMilliseconds(call, "leftMs")
            let paused = call.getBool("paused") ?? false
            let accent = color(call, "accent")
            let ink = color(call, "ink")

            Task {
                guard let activity = activeActivity(for: id) else {
                    call.reject("Live Activity is not active", "failed")
                    return
                }
                var state = activity.content.state
                state.endAt = paused ? nil : endAt
                state.leftMs = max(0, leftMs)
                state.totalMs = max(0, totalMs)
                state.paused = paused
                if let accent { state.accent = accent }
                if let ink { state.ink = ink }
                await activity.update(ActivityContent(state: state, staleDate: nil))
                call.resolve()
            }
        } catch {
            reject(call, error)
        }
    }

    @objc func pause(_ call: CAPPluginCall) {
        update(call, paused: true)
    }

    @objc func resume(_ call: CAPPluginCall) {
        update(call, paused: false)
    }

    @objc func cancel(_ call: CAPPluginCall) {
        do {
            let id = try requiredString(call, "id")
            Task {
                for activity in Activity<RestActivityAttributes>.activities
                    where activity.activityState == .active && activity.attributes.restId == id {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                call.resolve()
            }
        } catch {
            reject(call, error)
        }
    }

    @objc func consumeActions(_ call: CAPPluginCall) {
        call.resolve(["actions": RestActivityActionQueue.consume()])
    }

    private func update(_ call: CAPPluginCall, paused: Bool) {
        do {
            let id = try requiredString(call, "id")
            let endAt = try optionalDate(call, "endAt")
            let totalMs = try requiredMilliseconds(call, "totalMs")
            let leftMs = try requiredMilliseconds(call, "leftMs")

            Task {
                guard let activity = activeActivity(for: id) else {
                    call.reject("Live Activity is not active", "failed")
                    return
                }
                var state = activity.content.state
                state.endAt = paused ? nil : endAt
                state.leftMs = max(0, leftMs)
                state.totalMs = max(0, totalMs)
                state.paused = paused
                await activity.update(ActivityContent(state: state, staleDate: nil))
                call.resolve()
            }
        } catch {
            reject(call, error)
        }
    }

    private func activeActivity(for id: String) -> Activity<RestActivityAttributes>? {
        Activity<RestActivityAttributes>.activities.first {
            $0.activityState == .active && $0.attributes.restId == id
        }
    }

    private func requiredString(_ call: CAPPluginCall, _ key: String) throws -> String {
        guard let value = call.getString(key), !value.isEmpty else {
            throw PluginError.invalid("\(key) is required")
        }
        return value
    }

    private func requiredMilliseconds(_ call: CAPPluginCall, _ key: String) throws -> Int64 {
        guard let value = number(call, key), value.isFinite,
              value >= 0, value <= Double(Int64.max) else {
            throw PluginError.invalid("\(key) must be a non-negative number")
        }
        return Int64(value.rounded())
    }

    private func requiredDate(_ call: CAPPluginCall, _ key: String) throws -> Date {
        guard let value = number(call, key), value.isFinite, value > 0,
              value <= Double(Int64.max) else {
            throw PluginError.invalid("\(key) must be an epoch time in milliseconds")
        }
        return Date(timeIntervalSince1970: value / 1000)
    }

    private func optionalDate(_ call: CAPPluginCall, _ key: String) throws -> Date? {
        guard let value = number(call, key) else { return nil }
        guard value.isFinite, value >= 0, value <= Double(Int64.max) else {
            throw PluginError.invalid("\(key) must be an epoch time in milliseconds")
        }
        return value > 0 ? Date(timeIntervalSince1970: value / 1000) : nil
    }

    private func number(_ call: CAPPluginCall, _ key: String) -> Double? {
        if let value = call.getDouble(key) { return value }
        if let value = call.getInt(key) { return Double(value) }
        guard let value = call.options[key] as? NSNumber,
              CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }

    private func color(_ call: CAPPluginCall, _ key: String) -> String? {
        if let value = call.getString(key), !value.isEmpty { return value }
        guard let value = number(call, key), value >= 0, value <= Double(UInt32.max) else { return nil }
        return String(format: "#%06X", UInt32(value.rounded()) & 0x00FF_FFFF)
    }

    private func reject(_ call: CAPPluginCall, _ error: Error) {
        let code = (error as? PluginError)?.code ?? "failed"
        call.reject(error.localizedDescription, code, error)
    }

    private enum PluginError: LocalizedError {
        case invalid(String)

        var code: String { "failed" }

        var errorDescription: String? {
            if case let .invalid(message) = self { return message }
            return nil
        }
    }
}
