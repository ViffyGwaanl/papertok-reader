import Foundation
import AppIntents
import PTCore

enum MultiStepShortcutError: LocalizedError {
    case missingParameter(String)
    case stepFailed(intent: ShortcutIntentType, message: String)
    case unsupportedIntent(ShortcutIntentType)

    var errorDescription: String? {
        switch self {
        case .missingParameter(let key):
            return AppLocalization.format(
                "intent.multi_step.error.missing_parameter_format",
                "Missing required parameter: %@",
                key
            )
        case .stepFailed(let intent, let message):
            return AppLocalization.format(
                "intent.multi_step.error.step_failed_format",
                "Step %@ failed: %@",
                intent.rawValue,
                message
            )
        case .unsupportedIntent(let intent):
            return AppLocalization.format(
                "intent.multi_step.error.unsupported_intent_format",
                "Unsupported intent: %@",
                intent.rawValue
            )
        }
    }
}

/// Executes a sequence of `ShortcutStep`s by dispatching each one to
/// the appropriate `AppIntent`.
///
/// The executor:
/// - Persists every step through `PendingShortcutQueue` so a crash or
///   app kill mid-chain can resume on next launch.
/// - Threads intermediate results through a string-keyed dictionary
///   ("context") so later steps can reference earlier outputs via the
///   `${stepN.output}` placeholder.
/// - Supports a tiny conditional grammar: a parameter named `if` whose
///   value resolves (after substitution) to one of `false`, `0`, or the
///   empty string causes the step to be skipped.
/// - On unrecoverable failure, fires the corresponding error callback
///   via `ShortcutsCallbackService` and stops the chain.
final class MultiStepShortcutExecutor: @unchecked Sendable {
    static let shared = MultiStepShortcutExecutor()

    private let queue: PendingShortcutQueue
    private let callbacks: ShortcutsCallbackService

    init(
        queue: PendingShortcutQueue = .shared,
        callbacks: ShortcutsCallbackService = .shared
    ) {
        self.queue = queue
        self.callbacks = callbacks
    }

    /// Run a fresh batch of steps in order. Returns each step's result.
    @discardableResult
    func execute(steps: [ShortcutStep]) async throws -> [ShortcutResult] {
        for step in steps {
            await queue.enqueue(step)
        }
        return try await drain()
    }

    /// Resume execution of any persisted pending steps. Used at app
    /// launch via `PendingShortcutQueue.shared`.
    @discardableResult
    func resumePending() async -> [ShortcutResult] {
        (try? await drain()) ?? []
    }

    // MARK: - Drain loop

    private func drain() async throws -> [ShortcutResult] {
        var collected: [ShortcutResult] = []
        var context: [String: String] = [:]
        var stepIndex = 0

        while let step = await queue.next() {
            stepIndex += 1
            let resolved = resolve(parameters: step.parameters, context: context)

            if shouldSkip(parameters: resolved) {
                let skipped = ShortcutResult.ok(output: nil, values: ["skipped": "true"])
                await queue.complete(step, result: skipped)
                collected.append(skipped)
                merge(result: skipped, into: &context, index: stepIndex)
                continue
            }

            await queue.markRunning(step)
            let result: ShortcutResult
            do {
                result = try await perform(step: step, parameters: resolved)
            } catch {
                let failure = ShortcutResult.failure(error)
                await queue.complete(step, result: failure)
                collected.append(failure)
                if let requestId = resolved["requestId"] {
                    await callbacks.notifyError(requestId: requestId, error: error)
                }
                throw MultiStepShortcutError.stepFailed(
                    intent: step.intent,
                    message: error.localizedDescription
                )
            }

            await queue.complete(step, result: result)
            collected.append(result)
            merge(result: result, into: &context, index: stepIndex)

            if let requestId = resolved["requestId"], result.success {
                await callbacks.notifySuccess(requestId: requestId, result: result.values)
            }
        }

        return collected
    }

    // MARK: - Dispatch

    private func perform(
        step: ShortcutStep,
        parameters: [String: String]
    ) async throws -> ShortcutResult {
        switch step.intent {
        case .openBook:
            guard let title = parameters["bookTitle"] else {
                throw MultiStepShortcutError.missingParameter("bookTitle")
            }
            var intent = OpenBookIntent()
            intent.bookTitle = title
            _ = try await intent.perform()
            return .ok(values: ["bookTitle": title])

        case .askAI:
            guard let question = parameters["question"] else {
                throw MultiStepShortcutError.missingParameter("question")
            }
            let response = try await ShortcutAIService().sendMessage(prompt: question, images: nil)
            return .ok(output: response, values: ["response": response])

        case .sendMessage:
            guard let prompt = parameters["prompt"] else {
                throw MultiStepShortcutError.missingParameter("prompt")
            }
            let response = try await ShortcutAIService().sendMessage(prompt: prompt, images: nil)
            return .ok(output: response, values: ["response": response])

        case .searchBooks:
            guard let query = parameters["query"] else {
                throw MultiStepShortcutError.missingParameter("query")
            }
            var intent = SearchBooksIntent()
            intent.query = query
            let result = try await intent.perform()
            return .ok(output: result.value, values: ["matches": result.value ?? ""])

        case .getReadingStats:
            var intent = GetReadingStatsIntent()
            if let scopeRaw = parameters["scope"],
               let scope = ReadingStatsScope(rawValue: scopeRaw) {
                intent.scope = scope
            }
            let result = try await intent.perform()
            return .ok(output: result.value, values: ["summary": result.value ?? ""])

        case .createNote:
            guard let title = parameters["bookTitle"] else {
                throw MultiStepShortcutError.missingParameter("bookTitle")
            }
            guard let text = parameters["noteText"] else {
                throw MultiStepShortcutError.missingParameter("noteText")
            }
            var intent = CreateNoteIntent()
            intent.bookTitle = title
            intent.noteText = text
            intent.color = parameters["color"]
            let result = try await intent.perform()
            return .ok(output: result.value, values: ["confirmation": result.value ?? ""])
        }
    }

    // MARK: - Context plumbing

    private func resolve(
        parameters: [String: String],
        context: [String: String]
    ) -> [String: String] {
        parameters.mapValues { value in
            var result = value
            for (key, replacement) in context {
                result = result.replacingOccurrences(of: "${\(key)}", with: replacement)
            }
            return result
        }
    }

    private func shouldSkip(parameters: [String: String]) -> Bool {
        guard let condition = parameters["if"] else { return false }
        let trimmed = condition.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty || trimmed == "false" || trimmed == "0" || trimmed == "no"
    }

    private func merge(
        result: ShortcutResult,
        into context: inout [String: String],
        index: Int
    ) {
        if let output = result.output {
            context["step\(index).output"] = output
            context["last.output"] = output
        }
        for (key, value) in result.values {
            context["step\(index).\(key)"] = value
            context["last.\(key)"] = value
        }
    }
}
