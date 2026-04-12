import Foundation
import PTCore

enum PendingAIRequestSource: String, Codable, Sendable {
    case appIntent
    case shareExtension
}

enum PendingAIRequestStatus: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
}

struct PendingAIRequestImage: Codable, Equatable, Sendable {
    let filename: String
    let mediaType: String
    let data: Data
}

struct PendingAIRequest: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let prompt: String
    let images: [PendingAIRequestImage]
    let source: PendingAIRequestSource
    let createdAt: Date
    var status: PendingAIRequestStatus
    var responseText: String?
    var errorMessage: String?
}

struct PendingAIRequestStore {
    static let storageKey = "app_intents.pending_ai_requests.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = AppConfig.groupDefaults) {
        self.defaults = defaults
    }

    var requests: [PendingAIRequest] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([PendingAIRequest].self, from: data)) ?? []
    }

    @discardableResult
    func enqueue(
        prompt: String,
        images: [PendingAIRequestImage],
        source: PendingAIRequestSource,
        createdAt: Date = Date()
    ) -> PendingAIRequest {
        var all = requests
        let request = PendingAIRequest(
            id: UUID(),
            prompt: prompt,
            images: images,
            source: source,
            createdAt: createdAt,
            status: .pending,
            responseText: nil,
            errorMessage: nil
        )
        all.insert(request, at: 0)
        save(all)
        return request
    }

    func markStarted(id: UUID) {
        mutate(id: id) {
            $0.status = .running
            $0.errorMessage = nil
        }
    }

    func markCompleted(id: UUID, responseText: String) {
        mutate(id: id) {
            $0.status = .completed
            $0.responseText = responseText
            $0.errorMessage = nil
        }
    }

    func markFailed(id: UUID, message: String) {
        mutate(id: id) {
            $0.status = .failed
            $0.errorMessage = message
        }
    }

    private func mutate(id: UUID, _ transform: (inout PendingAIRequest) -> Void) {
        var all = requests
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        transform(&all[index])
        save(all)
    }

    private func save(_ requests: [PendingAIRequest]) {
        guard let data = try? JSONEncoder().encode(requests) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
