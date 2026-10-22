import ActivityKit
import Foundation

/// The shared model compiled into both the application and the Live Activity extension.
struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endAt: Date?
        var leftMs: Int64
        var totalMs: Int64
        var paused: Bool
        var title: String
        var accent: String
        var ink: String
    }

    var restId: String
}

/// The App Group queue used by Live Activity buttons to hand actions back to the WebView.
///
/// UserDefaults is the durable store (and therefore the one append-only key shared by the app and
/// extension). A lock file in the group container makes the read/clear operation exclusive across
/// the two processes; the NSLock is the fast path for concurrent calls in one process.
enum RestActivityActionQueue {
    static let appGroup = "group.ch.duartesantos.opengym"
    static let key = "restActivityActions"
    private static let processLock = NSLock()
    private static let lockFileName = ".restActivityActions.lock"

    private struct Action: Codable {
        let type: String
        let endsAt: Int64
        let leftMs: Int64
        let totalMs: Int64
        let paused: Bool
    }

    static func append(type: String, endAt: Date?, leftMs: Int64, totalMs: Int64, paused: Bool) {
        _ = withLock {
            guard let defaults else { return }
            var actions = read(from: defaults)
            actions.append(Action(
                type: type,
                endsAt: endAt.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) } ?? 0,
                leftMs: max(0, leftMs),
                totalMs: max(0, totalMs),
                paused: paused
            ))
            if actions.count > 20 {
                actions.removeFirst(actions.count - 20)
            }
            guard let data = try? JSONEncoder().encode(actions) else { return }
            defaults.set(data, forKey: key)
        }
    }

    /// Returns the queued dictionaries and clears the key while holding the cross-process lock.
    static func consume() -> [[String: Any]] {
        return withLock {
            guard let defaults else { return [] }
            let data = defaults.data(forKey: key)
            defaults.removeObject(forKey: key)
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data),
                  let actions = json as? [[String: Any]] else {
                return []
            }
            return actions
        } ?? []
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    private static func read(from defaults: UserDefaults) -> [Action] {
        guard let data = defaults.data(forKey: key),
              let actions = try? JSONDecoder().decode([Action].self, from: data) else {
            return []
        }
        return actions
    }

    private static func withLock<T>(_ body: () -> T) -> T? {
        processLock.lock()
        defer { processLock.unlock() }

        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            return nil
        }

        let lockURL = container.appendingPathComponent(lockFileName)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var result: T?
        var coordinationError: NSError?
        coordinator.coordinate(writingItemAt: lockURL, options: [], error: &coordinationError) { _ in
            result = body()
        }
        guard coordinationError == nil else { return nil }
        return result
    }
}
