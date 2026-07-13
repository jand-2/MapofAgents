import Foundation

/// Coordinates mention-catalog loads by source context.
///
/// Matching callers share one task. A canceled caller unregisters itself, and
/// the underlying load is canceled as soon as it has no remaining waiters.
public actor MentionCatalogSession {
    public struct Key: Hashable, Sendable {
        public var scope: String
        public var rootPath: String?

        public init(scope: String = "local", rootPath: String?) {
            self.scope = scope
            let trimmed = rootPath?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.rootPath = trimmed?.isEmpty == false
                ? URL(fileURLWithPath: trimmed!).standardizedFileURL.path
                : nil
        }
    }

    public typealias Loader = @Sendable () async -> [MentionCandidate]

    private struct Registration {
        var id: UUID
        var waiters: Set<UUID>
        var task: Task<[MentionCandidate], Never>
    }

    private var registrations: [Key: Registration] = [:]

    public init() {}

    public func candidates(
        for key: Key,
        loader: @escaping Loader
    ) async -> [MentionCandidate] {
        let waiterID = UUID()
        let registrationID: UUID
        let task: Task<[MentionCandidate], Never>

        if var registration = registrations[key] {
            registration.waiters.insert(waiterID)
            registrations[key] = registration
            registrationID = registration.id
            task = registration.task
        } else {
            registrationID = UUID()
            task = Task {
                guard !Task.isCancelled else { return [] }
                let candidates = await loader()
                guard !Task.isCancelled else { return [] }
                return candidates
            }
            registrations[key] = Registration(
                id: registrationID,
                waiters: [waiterID],
                task: task
            )
        }

        let cancellationTarget = self
        let candidates = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task {
                await cancellationTarget.cancelWaiter(
                    waiterID,
                    registrationID: registrationID,
                    for: key
                )
            }
        }

        finishWaiter(waiterID, registrationID: registrationID, for: key)
        guard !Task.isCancelled else { return [] }
        return candidates
    }

    func activeLoadCount() -> Int {
        registrations.count
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        registrationID: UUID,
        for key: Key
    ) {
        guard var registration = registrations[key], registration.id == registrationID else {
            return
        }
        registration.waiters.remove(waiterID)
        if registration.waiters.isEmpty {
            registrations[key] = nil
            registration.task.cancel()
        } else {
            registrations[key] = registration
        }
    }

    private func finishWaiter(
        _ waiterID: UUID,
        registrationID: UUID,
        for key: Key
    ) {
        guard var registration = registrations[key], registration.id == registrationID else {
            return
        }
        registration.waiters.remove(waiterID)
        registrations[key] = registration.waiters.isEmpty ? nil : registration
    }
}

struct MentionCatalogPublicationGeneration: Sendable {
    private(set) var current: UInt64 = 0

    mutating func begin() -> UInt64 {
        current &+= 1
        return current
    }

    func accepts(_ generation: UInt64) -> Bool {
        generation == current
    }
}
