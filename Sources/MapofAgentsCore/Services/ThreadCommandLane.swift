import Foundation

/// Serializes mutating App Server command sequences by immutable thread
/// identity while allowing commands for different threads to proceed
/// independently.
///
/// A permit deliberately spans the full command sequence (for example,
/// `thread/resume` followed by `turn/start`). Serializing the individual RPCs
/// would still allow two callers to interleave those operations.
actor ThreadCommandLane {
    struct Permit: Sendable {
        fileprivate let identity: String
        fileprivate let id: UUID
    }

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Permit, Error>
    }

    private var activePermitIDs: [String: UUID] = [:]
    private var waiters: [String: [Waiter]] = [:]

    func acquire(for identity: String) async throws -> Permit {
        precondition(!identity.isEmpty, "Thread command identities must not be empty")
        try Task.checkCancellation()

        let id = UUID()
        if activePermitIDs[identity] == nil {
            activePermitIDs[identity] = id
            return Permit(identity: identity, id: id)
        }

        let permit = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Permit, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiters[identity, default: []].append(
                    Waiter(id: id, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: id, identity: identity)
            }
        }

        do {
            try Task.checkCancellation()
            return permit
        } catch {
            // `release` may win the race with cancellation and grant this
            // waiter immediately before the cancellation callback runs. In
            // that case acquisition owns the permit and must hand it on.
            release(permit)
            throw error
        }
    }

    func release(_ permit: Permit) {
        guard activePermitIDs[permit.identity] == permit.id else {
            assertionFailure("Attempted to release a stale thread command permit")
            return
        }

        guard var queued = waiters[permit.identity], !queued.isEmpty else {
            activePermitIDs[permit.identity] = nil
            waiters[permit.identity] = nil
            return
        }

        let next = queued.removeFirst()
        waiters[permit.identity] = queued.isEmpty ? nil : queued
        activePermitIDs[permit.identity] = next.id
        next.continuation.resume(
            returning: Permit(identity: permit.identity, id: next.id)
        )
    }

    private func cancelWaiter(id: UUID, identity: String) {
        guard var queued = waiters[identity],
              let index = queued.firstIndex(where: { $0.id == id }) else {
            // The waiter either already acquired the permit (and the
            // post-resume cancellation check will release it) or completed.
            return
        }

        let waiter = queued.remove(at: index)
        waiters[identity] = queued.isEmpty ? nil : queued
        waiter.continuation.resume(throwing: CancellationError())
    }

    /// Cancels queued commands without revoking an operation that already owns
    /// a permit. The active operation remains responsible for releasing its
    /// permit, while disconnect/stop callers can deterministically drain every
    /// waiter that has not started.
    func cancelAll() {
        let queued = waiters.values.flatMap { $0 }
        waiters.removeAll()
        for waiter in queued {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    func waitingCommandCount(for identity: String) -> Int {
        waiters[identity]?.count ?? 0
    }

    func activeIdentityCount() -> Int {
        activePermitIDs.count
    }
}
