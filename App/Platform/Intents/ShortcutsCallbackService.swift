import Foundation
import PTCore

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Persisted record of a registered x-callback-url callback pair.
struct ShortcutsCallback: Codable, Equatable, Sendable {
    let requestId: String
    let success: URL?
    let error: URL?
    let createdAt: Date
}

/// Manages x-callback-url callbacks fired by App Intents / Shortcuts.
///
/// The Shortcuts (iOS) / Automator (macOS) ecosystem uses the
/// `x-callback-url` pattern: callers pass `x-success` and `x-error`
/// URLs that the receiver opens when an asynchronous task finishes.
/// PaperTok Reader registers those callbacks here so it can fire them
/// after the relevant intent completes — even if the app is killed and
/// relaunched in between.
final class ShortcutsCallbackService: @unchecked Sendable {
    static let shared = ShortcutsCallbackService()

    static let storageKey = "app_intents.pending_callbacks.v1"

    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "ai.papertok.shortcuts.callbacks")

    init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
    }

    // MARK: - Registration

    func registerCallback(requestId: String, success: URL?, error: URL?) {
        queue.sync {
            var all = loadLocked()
            all.removeAll { $0.requestId == requestId }
            all.append(
                ShortcutsCallback(
                    requestId: requestId,
                    success: success,
                    error: error,
                    createdAt: Date()
                )
            )
            saveLocked(all)
        }
    }

    func callback(forRequestId requestId: String) -> ShortcutsCallback? {
        queue.sync { loadLocked().first(where: { $0.requestId == requestId }) }
    }

    func allPending() -> [ShortcutsCallback] {
        queue.sync { loadLocked() }
    }

    func remove(requestId: String) {
        queue.sync {
            var all = loadLocked()
            all.removeAll { $0.requestId == requestId }
            saveLocked(all)
        }
    }

    // MARK: - Notification

    @MainActor
    func notifySuccess(requestId: String, result: [String: String]) {
        guard let entry = callback(forRequestId: requestId), let url = entry.success else {
            remove(requestId: requestId)
            return
        }
        let target = appendingQueryItems(to: url, items: result)
        open(url: target)
        remove(requestId: requestId)
    }

    @MainActor
    func notifyError(requestId: String, error: Error) {
        guard let entry = callback(forRequestId: requestId), let url = entry.error else {
            remove(requestId: requestId)
            return
        }
        let nsError = error as NSError
        let payload: [String: String] = [
            "errorCode": String(nsError.code),
            "errorMessage": error.localizedDescription,
            "errorDomain": nsError.domain,
        ]
        let target = appendingQueryItems(to: url, items: payload)
        open(url: target)
        remove(requestId: requestId)
    }

    // MARK: - Helpers

    private func appendingQueryItems(to url: URL, items: [String: String]) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var queryItems = components.queryItems ?? []
        for (key, value) in items {
            queryItems.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    @MainActor
    private func open(url: URL) {
#if canImport(UIKit)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
#endif
    }

    private func loadLocked() -> [ShortcutsCallback] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([ShortcutsCallback].self, from: data)) ?? []
    }

    private func saveLocked(_ callbacks: [ShortcutsCallback]) {
        guard let data = try? JSONEncoder().encode(callbacks) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
