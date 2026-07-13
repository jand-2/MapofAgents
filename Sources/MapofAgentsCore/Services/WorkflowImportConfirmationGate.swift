import Foundation
import Observation

public struct WorkflowImportConfirmationRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let authorizationID: UUID
    public let sourceHostID: HostID
    public let sourceName: String

    public init(
        id: UUID = UUID(),
        authorizationID: UUID,
        sourceHostID: HostID,
        sourceName: String
    ) {
        self.id = id
        self.authorizationID = authorizationID
        self.sourceHostID = sourceHostID
        self.sourceName = sourceName
    }
}

@MainActor
@Observable
public final class WorkflowImportConfirmationGate {
    public private(set) var pendingRequest: WorkflowImportConfirmationRequest?

    @ObservationIgnored private var continuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var recentDecision: (authorizationID: UUID, approved: Bool)?

    public init() {}

    public func requestApproval(
        authorizationID: UUID = UUID(),
        sourceHostID: HostID,
        sourceName: String
    ) async -> Bool {
        if let recentDecision,
           recentDecision.authorizationID == authorizationID {
            return recentDecision.approved
        }

        guard continuation == nil else {
            return false
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            pendingRequest = WorkflowImportConfirmationRequest(
                authorizationID: authorizationID,
                sourceHostID: sourceHostID,
                sourceName: sourceName
            )
        }
    }

    public func approve() {
        resolve(approved: true)
    }

    public func cancel() {
        resolve(approved: false)
    }

    private func resolve(approved: Bool) {
        guard let continuation, let pendingRequest else { return }
        self.continuation = nil
        self.pendingRequest = nil
        recentDecision = (authorizationID: pendingRequest.authorizationID, approved: approved)
        continuation.resume(returning: approved)
    }
}
