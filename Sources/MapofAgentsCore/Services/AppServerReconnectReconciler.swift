import Foundation

/// Fixed work limits for reconnect recovery. Reconciliation is advisory state
/// repair, so it must never monopolize the transport needed by user commands.
struct AppServerReconnectPolicy: Sendable {
    var loadedThreadLimit: Int
    var maximumTargetThreadCount: Int
    var maximumConcurrentThreadReads: Int
    var requestTimeout: Duration

    static let `default` = AppServerReconnectPolicy(
        loadedThreadLimit: 200,
        maximumTargetThreadCount: 32,
        maximumConcurrentThreadReads: 4,
        requestTimeout: .seconds(4)
    )
}

struct AppServerReconnectPlan: Equatable, Sendable {
    var targetThreadIDs: [String]
    var omittedThreadIDs: Set<String>

    static func make(
        desiredThreadIDs: Set<String>,
        loadedThreadIDs: Set<String>,
        maximumTargetThreadCount: Int
    ) -> AppServerReconnectPlan {
        let limit = max(desiredThreadIDs.count, maximumTargetThreadCount)
        var selected: [String] = []
        var seen = Set<String>()

        // Workflow and explicitly retained subscriptions have priority over
        // incidental loaded threads when the bounded scan cannot cover both.
        for threadID in desiredThreadIDs.sorted()
        where seen.insert(threadID).inserted {
            selected.append(threadID)
        }
        for threadID in loadedThreadIDs.sorted()
        where selected.count < limit && seen.insert(threadID).inserted {
            selected.append(threadID)
        }

        let allThreadIDs = desiredThreadIDs.union(loadedThreadIDs)
        return AppServerReconnectPlan(
            targetThreadIDs: selected,
            omittedThreadIDs: allThreadIDs.subtracting(seen)
        )
    }
}

/// Shared local/remote App Server snapshot reader. Callers remain responsible
/// for connection-generation and live-update gating before publishing results.
enum AppServerReconnectReconciler {
    typealias Request = @Sendable (
        AppServerMethod,
        JSONValue,
        Duration
    ) async throws -> JSONValue

    private struct ThreadObservation: Sendable {
        var threadID: String
        var catalogEntry: ThreadCatalogEntry?
        var transcript: ThreadTranscript?
        var hasAuthoritativeCatalogStatus: Bool
        var failure: String?
    }

    static func reconcile(
        hostID: HostID,
        hostName: String,
        desiredThreads: [String: ThreadRef],
        policy: AppServerReconnectPolicy = .default,
        request: @escaping Request
    ) async -> AppServerReconnectReconciliation {
        var loadedThreadIDs = Set<String>()
        var loadedThreadListError: String?

        do {
            let result = try await request(
                .listLoadedThreads,
                .object([
                    "limit": .number(Double(policy.loadedThreadLimit)),
                ]),
                policy.requestTimeout
            )
            loadedThreadIDs = Set(
                ThreadCatalogEntry.loadedThreadIDs(from: result)
                    .prefix(policy.loadedThreadLimit)
            )
        } catch {
            loadedThreadListError = error.localizedDescription
        }

        let plan = AppServerReconnectPlan.make(
            desiredThreadIDs: Set(desiredThreads.keys),
            loadedThreadIDs: loadedThreadIDs,
            maximumTargetThreadCount: policy.maximumTargetThreadCount
        )
        let observations = await observeThreads(
            plan.targetThreadIDs,
            hostID: hostID,
            hostName: hostName,
            desiredThreads: desiredThreads,
            maximumConcurrency: policy.maximumConcurrentThreadReads,
            requestTimeout: policy.requestTimeout,
            request: request
        )

        var catalogEntriesByID: [String: ThreadCatalogEntry] = [:]
        var transcriptsByThreadID: [String: ThreadTranscript] = [:]
        var authoritativeStatusThreadIDs = Set<String>()
        var failuresByThreadID: [String: String] = [:]
        for observation in observations {
            if let catalogEntry = observation.catalogEntry {
                catalogEntriesByID[observation.threadID] = catalogEntry
            }
            if let transcript = observation.transcript {
                transcriptsByThreadID[observation.threadID] = transcript
            }
            if observation.hasAuthoritativeCatalogStatus {
                authoritativeStatusThreadIDs.insert(observation.threadID)
            }
            if let failure = observation.failure {
                failuresByThreadID[observation.threadID] = failure
            }
        }

        return AppServerReconnectReconciliation(
            hostID: hostID,
            targetThreadIDs: Set(plan.targetThreadIDs),
            loadedThreadIDs: loadedThreadIDs,
            catalogEntries: plan.targetThreadIDs.compactMap { catalogEntriesByID[$0] },
            transcriptsByThreadID: transcriptsByThreadID,
            failuresByThreadID: failuresByThreadID,
            loadedThreadListError: loadedThreadListError,
            authoritativeCatalogStatusThreadIDs: authoritativeStatusThreadIDs,
            omittedThreadIDs: plan.omittedThreadIDs
        )
    }

    private static func observeThreads(
        _ threadIDs: [String],
        hostID: HostID,
        hostName: String,
        desiredThreads: [String: ThreadRef],
        maximumConcurrency: Int,
        requestTimeout: Duration,
        request: @escaping Request
    ) async -> [ThreadObservation] {
        guard !threadIDs.isEmpty else { return [] }
        let concurrency = max(1, min(maximumConcurrency, threadIDs.count))

        return await withTaskGroup(of: ThreadObservation.self) { group in
            var nextIndex = 0
            var observations: [ThreadObservation] = []
            observations.reserveCapacity(threadIDs.count)

            func addNext() {
                guard nextIndex < threadIDs.count else { return }
                let threadID = threadIDs[nextIndex]
                nextIndex += 1
                group.addTask {
                    await observeThread(
                        threadID,
                        hostID: hostID,
                        hostName: hostName,
                        desiredThread: desiredThreads[threadID],
                        requestTimeout: requestTimeout,
                        request: request
                    )
                }
            }

            for _ in 0..<concurrency {
                addNext()
            }
            while let observation = await group.next() {
                observations.append(observation)
                addNext()
            }
            return observations.sorted { $0.threadID < $1.threadID }
        }
    }

    private static func observeThread(
        _ threadID: String,
        hostID: HostID,
        hostName: String,
        desiredThread: ThreadRef?,
        requestTimeout: Duration,
        request: @escaping Request
    ) async -> ThreadObservation {
        var threadRef = desiredThread ?? ThreadRef(
            hostID: hostID,
            threadID: threadID,
            cwd: ""
        )
        var catalogEntry: ThreadCatalogEntry?
        var transcript: ThreadTranscript?
        var hasAuthoritativeCatalogStatus = false
        var failures: [String] = []

        do {
            let result = try await request(
                .readThread,
                .object(["threadId": .string(threadID)]),
                requestTimeout
            )
            let threadValue = result["thread"] ?? result
            hasAuthoritativeCatalogStatus = containsThreadStatus(threadValue)
            if let entry = ThreadCatalogEntry.appServerThread(
                from: threadValue,
                hostID: hostID,
                hostName: hostName
            ) {
                catalogEntry = entry
                threadRef = entry.threadRef
            } else if let resolved = CodexRuntimeStore.threadRef(
                from: threadValue,
                hostID: hostID,
                cwdHint: threadRef.cwd
            ) {
                threadRef = resolved
            } else {
                failures.append("The App Server returned an invalid thread record.")
            }
        } catch {
            failures.append(error.localizedDescription)
        }

        do {
            let result = try await request(
                .listTurns,
                .object([
                    "threadId": .string(threadID),
                    "limit": .number(1),
                    "sortDirection": .string("desc"),
                    "itemsView": .string("summary"),
                ]),
                requestTimeout
            )
            transcript = ThreadTranscriptParser.transcript(
                from: result,
                threadRef: threadRef
            ).sortedChronologically()
        } catch {
            failures.append("Turn state: \(error.localizedDescription)")
        }

        return ThreadObservation(
            threadID: threadID,
            catalogEntry: catalogEntry,
            transcript: transcript,
            hasAuthoritativeCatalogStatus: hasAuthoritativeCatalogStatus,
            failure: failures.isEmpty ? nil : failures.joined(separator: " ")
        )
    }

    private static func containsThreadStatus(_ value: JSONValue) -> Bool {
        value["status"] != nil
            || value["loadedStatus"] != nil
            || value["loaded_status"] != nil
            || value["state"] != nil
    }
}

/// Applies one thread observation without allowing a stale/empty turn list to
/// contradict an explicit current status returned by `thread/read`.
enum AppServerReconnectStateReducer {
    static func apply(
        catalogEntry: ThreadCatalogEntry?,
        transcript: ThreadTranscript?,
        catalogStatusIsAuthoritative: Bool,
        to state: inout ThreadRuntimeState
    ) {
        let previousActiveTurnID = (
            state.status == .running
                || state.status == .needsInput
                || state.activeFlags.contains(.running)
        ) ? state.activeTurnID : nil
        let hasTurns = transcript?.turnTimeline?.turns.isEmpty == false
        let latestTurn = transcript?.turnTimeline?.turns.max(by: { lhs, rhs in
            (lhs.completedAt ?? lhs.startedAt) < (rhs.completedAt ?? rhs.startedAt)
        })
        if hasTurns, let transcript {
            state.currentActivitySummary = nil
            state.reconcileAfterLatestTranscriptRead(transcript)
        }

        if let catalogEntry,
           catalogStatusIsAuthoritative || !hasTurns {
            applyCatalogStatus(catalogEntry, to: &state)

            // A current active `thread/read` can legitimately race a one-turn
            // history page that still ends at the previous completed turn.
            // Never label that completed id as the active turn.
            if catalogStatusIsAuthoritative,
               (catalogEntry.loadedStatus == .running
                    || catalogEntry.loadedStatus == .needsInput),
               let latestTurn,
               (latestTurn.completedAt != nil
                    || latestTurn.status == .complete
                    || latestTurn.status == .failed) {
                state.activeTurnID = previousActiveTurnID == latestTurn.id
                    ? nil
                    : previousActiveTurnID
            }
        }
    }

    private static func applyCatalogStatus(
        _ entry: ThreadCatalogEntry,
        to state: inout ThreadRuntimeState
    ) {
        state.status = entry.loadedStatus
        state.lastActivityAt = max(state.lastActivityAt, entry.lastActivityAt)
        state.lastError = entry.lastError
        state.activeFlags.remove(.running)
        state.activeFlags.remove(.waitingOnApproval)
        state.activeFlags.remove(.waitingOnUserInput)
        state.activeFlags.remove(.failed)

        switch entry.loadedStatus {
        case .running:
            state.activeFlags.insert(.running)
            state.lastError = nil
        case .needsInput:
            state.activeFlags.insert(.waitingOnUserInput)
        case .failed:
            state.activeFlags.insert(.failed)
        case .idle, .complete, .unknown:
            break
        }
        if entry.loadedStatus == .complete {
            state.activeItemIDs = []
        }
        state.currentActivitySummary = entry.latestEventSummary
            ?? activitySummary(for: entry.loadedStatus)
    }

    static func activitySummary(for status: ThreadRunStatus) -> String {
        switch status {
        case .running:
            return "Turn running"
        case .needsInput:
            return "Waiting for input"
        case .failed:
            return "Turn failed"
        case .complete:
            return "Turn completed"
        case .idle, .unknown:
            return "Reconciled with Codex App Server"
        }
    }
}
