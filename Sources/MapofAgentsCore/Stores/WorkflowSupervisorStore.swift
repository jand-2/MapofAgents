import Foundation
import Observation

public struct RelayEndpointAttemptState: Hashable, Sendable {
    public var hostID: HostID
    public var endpointName: String
    public var endpointURL: URL
    public var attemptCount: Int
    public var consecutiveFailures: Int
    public var lastAttemptAt: Date?
    public var nextAttemptAt: Date?
    public var lastError: String?

    public init(
        hostID: HostID,
        endpointName: String,
        endpointURL: URL,
        attemptCount: Int = 0,
        consecutiveFailures: Int = 0,
        lastAttemptAt: Date? = nil,
        nextAttemptAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.hostID = hostID
        self.endpointName = endpointName
        self.endpointURL = endpointURL
        self.attemptCount = attemptCount
        self.consecutiveFailures = consecutiveFailures
        self.lastAttemptAt = lastAttemptAt
        self.nextAttemptAt = nextAttemptAt
        self.lastError = lastError
    }

    public func canAttempt(at date: Date = Date()) -> Bool {
        guard let nextAttemptAt else { return true }
        return date >= nextAttemptAt
    }
}

@MainActor
@Observable
public final class WorkflowSupervisorStore {
    public private(set) var machines: [SupervisorMachine] = []
    public private(set) var eventEnvelopes: [SupervisorEventEnvelope] = []
    public private(set) var workflowEvents: [WorkflowEvent] = []
    public private(set) var relayEndpoints: [AppServerRelayEndpoint] = []
    public private(set) var relayEndpointAttempts: [HostID: RelayEndpointAttemptState] = [:]
    public private(set) var tailnetMachines: [TailnetMachine] = []
    public private(set) var isDiscoveringTailnet = false
    public private(set) var tailnetDiscoveryMessage: String?
    public private(set) var codexRemotes: [CodexDesktopRemote] = []
    public private(set) var isDiscoveringCodexRemotes = false
    public private(set) var codexRemoteDiscoveryMessage: String?
    public private(set) var codexRemoteDiagnostics: [HostID: [RuntimeDiagnosticStep]] = [:]
    public private(set) var pendingAttentionRequests: [RuntimeAttentionRequest] = []
    public private(set) var threadRuntimeStates: [String: ThreadRuntimeState] = [:]
    public private(set) var lastWriteReconciliations: [HostID: AppServerWriteReconciliation] = [:]
    public private(set) var reconciledThreadCatalogEntries: [String: ThreadCatalogEntry] = [:]

    private let supervisor: WorkflowSupervisor
    private var relays: [HostID: AppServerWebSocketWorkflowRelay] = [:]
    private var relayGenerations: [HostID: UUID] = [:]
    private var relayConnectionIDs: [HostID: AppServerConnectionID] = [:]
    private var remoteTunnels: [HostID: CodexRemoteTunnel] = [:]
    private var activeRelayEndpointsByHostID: [HostID: AppServerRelayEndpoint] = [:]
    private var codexRemoteRecoveryFailures: [HostID: Int] = [:]
    @ObservationIgnored nonisolated(unsafe) private var codexRemoteRecoveryTasks: [HostID: Task<Void, Never>] = [:]
    @ObservationIgnored nonisolated(unsafe) private var snapshotTask: Task<Void, Never>?
    private var localHostID = HostID(rawValue: "local")
    private var workflowThreadRefs: [ThreadRef] = []
    private var reconnectingRuntimeStateIDs: Set<String> = []
    private var hasAttemptedTailnetDiscovery = false
    private var hasAttemptedCodexRemoteDiscovery = false
    private let hostRegistry: HostRegistry

    public init(
        supervisor: WorkflowSupervisor = WorkflowSupervisor(),
        hostRegistry: HostRegistry = .shared
    ) {
        self.supervisor = supervisor
        self.hostRegistry = hostRegistry
    }

    deinit {
        snapshotTask?.cancel()
        codexRemoteRecoveryTasks.values.forEach { $0.cancel() }
    }

    public func start() {
        guard snapshotTask == nil else { return }
        snapshotTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    guard let store = self else {
                        return
                    }
                    await store.refreshSnapshots()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func registerLocalHost(_ host: AgentHost) async {
        localHostID = host.id
        await supervisor.upsertMachine(SupervisorMachine(host: host))
        await refreshSnapshots()
    }

    public func restoreWorkflowEvents(_ events: [WorkflowEvent]) async {
        for event in events.sorted(by: { $0.createdAt < $1.createdAt }) {
            reduceRuntimeState(event: event)
            await supervisor.ingest(event, from: event.hostID ?? localHostID)
        }
        await refreshSnapshots()
    }

    public func ingestLocalEvents(_ events: [WorkflowEvent], host: AgentHost) async {
        await registerLocalHost(host)
        for event in events {
            reduceRuntimeState(event: event)
            await supervisor.ingest(event, from: event.hostID ?? host.id)
        }
        await refreshSnapshots()
    }

    @discardableResult
    public func connectRemote(
        name: String,
        endpoint: String,
        bearerToken: String? = nil,
        accessTokenProvider: (any AppServerAccessTokenProviding)? = nil,
        attachmentStagingRoot: String? = nil,
        markFailureOnFailure: Bool = true
    ) async -> HostID? {
        await connectRemote(
            id: nil,
            name: name,
            endpoint: endpoint,
            bearerToken: bearerToken,
            accessTokenProvider: accessTokenProvider,
            attachmentStagingRoot: attachmentStagingRoot,
            markFailureOnFailure: markFailureOnFailure
        )
    }

    @discardableResult
    public func connectRemote(
        id: HostID?,
        name: String,
        endpoint: String,
        bearerToken: String? = nil,
        accessTokenProvider: (any AppServerAccessTokenProviding)? = nil,
        attachmentStagingRoot: String? = nil,
        markFailureOnFailure: Bool = true
    ) async -> HostID? {
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedEndpoint),
              AppServerRelayEndpoint.endpointStructureError(url) == nil else {
            return nil
        }

        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let machineID = await hostRegistry.hostID(
            explicitID: id,
            name: resolvedName,
            endpointURL: url
        )
        let relayEndpoint = AppServerRelayEndpoint(
            id: machineID,
            name: resolvedName.isEmpty ? Self.defaultName(for: url) : resolvedName,
            url: url,
            bearerToken: bearerToken
        )

        if let securityError = AppServerRelayEndpoint.connectionSecurityError(
            url: relayEndpoint.url,
            bearerToken: accessTokenProvider == nil ? relayEndpoint.bearerToken : "provided-at-connect"
        ) {
            await supervisor.upsertMachine(
                SupervisorMachine(
                    id: machineID,
                    name: relayEndpoint.name,
                    endpointDescription: relayEndpoint.url.absoluteString,
                    status: .failed,
                    lastError: securityError
                )
            )
            await refreshSnapshots()
            return nil
        }

        await connectRemote(
            relayEndpoint,
            accessTokenProvider: accessTokenProvider,
            attachmentStagingRoot: attachmentStagingRoot,
            markFailureOnFailure: markFailureOnFailure
        )
        return machineID
    }

    public func restoreRelayEndpoints(_ endpoints: [AppServerRelayEndpoint]) async {
        for endpoint in endpoints {
            guard Self.shouldRestoreRelayEndpoint(endpoint) else {
                continue
            }
            await connectRemote(endpoint)
        }
    }

    public func updateWorkflowThreads(_ threadRefs: [ThreadRef]) async {
        workflowThreadRefs = threadRefs

        for relay in relays.values {
            await relay.updateWorkflowThreads(threadRefs)
        }
    }

    public func retainThreadSubscription(_ threadRef: ThreadRef, owner: String) async {
        guard let relay = relays[threadRef.hostID] else { return }
        await relay.retainThreadSubscription(threadRef, owner: owner)
    }

    public func releaseThreadSubscription(_ threadRef: ThreadRef, owner: String) async {
        guard let relay = relays[threadRef.hostID] else { return }
        await relay.releaseThreadSubscription(threadID: threadRef.threadID, owner: owner)
    }

    public func discoverTailnetMachinesIfNeeded() async {
        guard !hasAttemptedTailnetDiscovery else { return }
        await discoverTailnetMachines()
    }

    public func discoverCodexRemotesIfNeeded() async {
        guard !hasAttemptedCodexRemoteDiscovery else { return }
        await discoverCodexRemotes()
    }

    public func discoverTailnetMachines() async {
        guard !isDiscoveringTailnet else { return }

        hasAttemptedTailnetDiscovery = true
        isDiscoveringTailnet = true
        tailnetDiscoveryMessage = nil

        do {
            tailnetMachines = try await TailnetDiscoveryService.discover()
            if tailnetMachines.isEmpty {
                tailnetDiscoveryMessage = "No tailnet machines found."
            }
        } catch {
            tailnetMachines = []
            tailnetDiscoveryMessage = error.localizedDescription
        }

        isDiscoveringTailnet = false
    }

    public func discoverCodexRemotes() async {
        guard !isDiscoveringCodexRemotes else { return }

        hasAttemptedCodexRemoteDiscovery = true
        isDiscoveringCodexRemotes = true
        codexRemoteDiscoveryMessage = nil

        do {
            codexRemotes = try await CodexDesktopRemoteService.discover()
            if codexRemotes.isEmpty {
                codexRemoteDiscoveryMessage = "No Codex Desktop remotes found."
            }
        } catch {
            codexRemotes = []
            codexRemoteDiscoveryMessage = error.localizedDescription
        }

        isDiscoveringCodexRemotes = false
    }

    public func connectCodexRemote(_ remote: CodexDesktopRemote) async {
        await connectCodexRemote(remote, cancelPendingRecovery: true, retryOnFailure: false)
    }

    private func connectCodexRemote(
        _ remote: CodexDesktopRemote,
        cancelPendingRecovery: Bool,
        retryOnFailure: Bool
    ) async {
        if cancelPendingRecovery {
            cancelCodexRemoteRecovery(hostID: remote.id)
        }

        codexRemoteDiagnostics[remote.id] = CodexRemoteTunnelService.pendingConnectionDiagnosticSteps(for: remote)
        await supervisor.upsertMachine(
            SupervisorMachine(
                id: remote.id,
                name: remote.displayName,
                endpointDescription: remote.hostname ?? "Codex Desktop remote",
                status: .connecting,
                platform: remote.platform
            )
        )
        await refreshSnapshots()

        do {
            if let existingRelay = relays.removeValue(forKey: remote.id) {
                await existingRelay.stop(markDisconnected: false)
            }
            if let existingTunnel = remoteTunnels[remote.id] {
                existingTunnel.stop()
                remoteTunnels[remote.id] = nil
            }
            activeRelayEndpointsByHostID[remote.id] = nil

            let tunnelResult = try await CodexRemoteTunnelService.startTunnelWithDiagnostics(
                for: remote,
                onDiagnosticsUpdate: { [weak self] steps in
                    await MainActor.run {
                        self?.codexRemoteDiagnostics[remote.id] = steps
                    }
                }
            )
            let tunnel = tunnelResult.tunnel
            var diagnostics = tunnelResult.diagnostics
            remoteTunnels[remote.id] = tunnel
            if await connectRemote(tunnel.endpoint) {
                await hostRegistry.record(id: remote.id, name: remote.displayName, endpointURL: tunnel.endpoint.url)
                diagnostics.append(
                    RuntimeDiagnosticStep(
                        id: "relay-handshake",
                        title: "Relay handshake connected",
                        status: .passed,
                        detail: tunnel.endpoint.url.absoluteString,
                        evidence: "initialize + initialized over workflow relay endpoint"
                    )
                )
                codexRemoteDiagnostics[remote.id] = diagnostics
                codexRemoteRecoveryFailures[remote.id] = nil
            } else {
                tunnel.stop()
                remoteTunnels[remote.id] = nil
                if let failedRelay = relays.removeValue(forKey: remote.id) {
                    await failedRelay.stop(markDisconnected: false)
                }
                activeRelayEndpointsByHostID[remote.id] = nil
                diagnostics.append(
                    RuntimeDiagnosticStep(
                        id: "relay-handshake",
                        title: "Relay handshake connected",
                        status: .failed,
                        detail: "Tunnel opened, but the Codex App Server handshake failed.",
                        evidence: "workflow relay initialize failed after tunnel verification",
                        action: .restartAppServer
                    )
                )
                codexRemoteDiagnostics[remote.id] = diagnostics
                if retryOnFailure {
                    await scheduleCodexRemoteRecovery(
                        hostID: remote.id,
                        reason: "Relay handshake failed after rebuilding the SSH tunnel."
                    )
                }
            }
        } catch {
            if let tunnelError = error as? CodexRemoteTunnelError, !tunnelError.diagnosticSteps.isEmpty {
                codexRemoteDiagnostics[remote.id] = tunnelError.diagnosticSteps
            } else {
                codexRemoteDiagnostics[remote.id] = [
                    RuntimeDiagnosticStep(id: "connect", title: "Remote connection", status: .failed, detail: error.localizedDescription),
                ]
            }
            await supervisor.upsertMachine(
                SupervisorMachine(
                    id: remote.id,
                    name: remote.displayName,
                    endpointDescription: remote.hostname ?? "Codex Desktop remote",
                    status: .failed,
                    platform: remote.platform,
                    lastError: error.localizedDescription
                )
            )
            await refreshSnapshots()
            if retryOnFailure {
                await scheduleCodexRemoteRecovery(hostID: remote.id, reason: error.localizedDescription)
            }
        }
    }

    public func diagnoseCodexRemote(_ remote: CodexDesktopRemote) async {
        codexRemoteDiagnostics[remote.id] = CodexRemoteTunnelService.pendingConnectionDiagnosticSteps(for: remote)

        codexRemoteDiagnostics[remote.id] = await CodexRemoteTunnelService.diagnose(
            remote: remote,
            onDiagnosticsUpdate: { [weak self] steps in
                await MainActor.run {
                    self?.codexRemoteDiagnostics[remote.id] = steps
                }
            }
        )
    }

    public func performCodexRemoteAction(_ action: RuntimeDiagnosticAction, for remote: CodexDesktopRemote) async {
        codexRemoteDiagnostics[remote.id] = [
            RuntimeDiagnosticStep(
                id: action.rawValue,
                title: action.runningTitle,
                status: .running,
                detail: remote.hostname ?? remote.hostID
            ),
        ]

        do {
            switch action {
            case .installCodexCLI:
                try await CodexRemoteTunnelService.installCodexCLI(on: remote)
                codexRemoteDiagnostics[remote.id] = await CodexRemoteTunnelService.diagnose(
                    remote: remote,
                    onDiagnosticsUpdate: { [weak self] steps in
                        await MainActor.run {
                            self?.codexRemoteDiagnostics[remote.id] = steps
                        }
                    }
                )
            case .updateCodexCLI:
                try await CodexRemoteTunnelService.updateCodexCLI(on: remote)
                codexRemoteDiagnostics[remote.id] = await CodexRemoteTunnelService.diagnose(
                    remote: remote,
                    onDiagnosticsUpdate: { [weak self] steps in
                        await MainActor.run {
                            self?.codexRemoteDiagnostics[remote.id] = steps
                        }
                    }
                )
            case .startAppServer:
                try await CodexRemoteTunnelService.startAppServer(on: remote)
                await connectCodexRemote(remote)
            case .restartAppServer:
                try await CodexRemoteTunnelService.restartAppServer(on: remote)
                await connectCodexRemote(remote)
            }
        } catch {
            codexRemoteDiagnostics[remote.id] = [
                RuntimeDiagnosticStep(
                    id: action.rawValue,
                    title: action.failureTitle,
                    status: .failed,
                    detail: error.localizedDescription,
                    action: action
                ),
            ]
            await supervisor.upsertMachine(
                SupervisorMachine(
                    id: remote.id,
                    name: remote.displayName,
                    endpointDescription: remote.hostname ?? "Codex Desktop remote",
                    status: .failed,
                    platform: remote.platform,
                    lastError: error.localizedDescription
                )
            )
            await refreshSnapshots()
        }
    }

    public func refreshConnections(for hostIDs: Set<HostID>) async {
        guard !hostIDs.isEmpty else { return }

        await discoverCodexRemotes()
        await discoverTailnetMachines()

        for hostID in hostIDs where hostID != localHostID {
            if hasRelay(for: hostID) {
                continue
            }

            if let remote = codexRemotes.first(where: { $0.id == hostID }), remote.isConnectable {
                if CodexRemoteIdentityStore.requiresPreparation(for: remote) {
                    codexRemoteDiagnostics[remote.id] = [
                        RuntimeDiagnosticStep(
                            id: "prepare-identity",
                            title: "Prepare SSH Key",
                            status: .warning,
                            detail: "Use the Machines panel antenna once to prepare this remote's SSH key."
                        ),
                    ]
                    continue
                }
                await connectCodexRemote(remote)
            } else if let endpoint = relayEndpoints.first(where: { $0.id == hostID }) {
                await connectRemote(endpoint, respectBackoff: true)
            } else if let endpoint = activeRelayEndpointsByHostID[hostID] {
                await connectRemote(endpoint, respectBackoff: true)
            }
        }

        await refreshSnapshots()
    }

    public func hasRelay(for hostID: HostID) -> Bool {
        relays[hostID] != nil
            && machines.first(where: { $0.id == hostID })?.status == .connected
    }

    public func activeRelayEndpoint(for hostID: HostID) -> AppServerRelayEndpoint? {
        if let endpoint = activeRelayEndpointsByHostID[hostID] {
            return endpoint
        }

        guard let machine = machines.first(where: { $0.id == hostID }) else {
            return nil
        }
        return AppServerRelayEndpoint(machine: machine)
    }

    public func canAttemptRelayEndpoint(for hostID: HostID, at date: Date = Date()) -> Bool {
        relayEndpointAttempts[hostID]?.canAttempt(at: date) ?? true
    }

    @discardableResult
    public func stageRelayEndpointAttempt(
        _ relayEndpoint: AppServerRelayEndpoint,
        at date: Date = Date()
    ) async -> RelayEndpointAttemptState {
        let previous = relayEndpointAttempts[relayEndpoint.id]
        let state = RelayEndpointAttemptState(
            hostID: relayEndpoint.id,
            endpointName: relayEndpoint.name,
            endpointURL: relayEndpoint.url,
            attemptCount: (previous?.attemptCount ?? 0) + 1,
            consecutiveFailures: previous?.consecutiveFailures ?? 0,
            lastAttemptAt: date
        )
        relayEndpointAttempts[relayEndpoint.id] = state
        upsertRelayEndpoint(relayEndpoint)
        await supervisor.upsertMachine(
            SupervisorMachine(
                id: relayEndpoint.id,
                name: relayEndpoint.name,
                endpointDescription: relayEndpoint.url.absoluteString,
                status: .connecting
            )
        )
        await refreshSnapshots()
        return state
    }

    @discardableResult
    public func recordRelayEndpointAttemptFailure(
        hostID: HostID,
        message: String,
        at date: Date = Date()
    ) async -> RelayEndpointAttemptState? {
        guard var state = relayEndpointAttempts[hostID] else {
            if machines.contains(where: { $0.id == hostID }) {
                await supervisor.updateMachineFailure(hostID, message: message)
                await refreshSnapshots()
            }
            return nil
        }

        state.consecutiveFailures += 1
        state.lastError = message
        state.nextAttemptAt = date.addingTimeInterval(
            Self.relayEndpointRetryDelay(forConsecutiveFailures: state.consecutiveFailures)
        )
        relayEndpointAttempts[hostID] = state
        await supervisor.updateMachineFailure(hostID, message: message)
        await refreshSnapshots()
        return state
    }

    @discardableResult
    public func recordRelayEndpointAttemptSuccess(hostID: HostID) async -> RelayEndpointAttemptState? {
        guard var state = relayEndpointAttempts[hostID] else {
            if machines.contains(where: { $0.id == hostID }) {
                await supervisor.updateMachineStatus(hostID, status: .connected)
                await refreshSnapshots()
            }
            return nil
        }

        state.consecutiveFailures = 0
        state.nextAttemptAt = nil
        state.lastError = nil
        relayEndpointAttempts[hostID] = state
        await supervisor.updateMachineStatus(hostID, status: .connected)
        await refreshSnapshots()
        return state
    }

    public static func relayEndpointRetryDelay(forConsecutiveFailures failures: Int) -> TimeInterval {
        TimeInterval(min(30, max(2, failures * 2)))
    }

    public static func codexRemoteRecoveryDelay(forConsecutiveFailures failures: Int) -> TimeInterval {
        TimeInterval(min(30, max(2, failures * 2)))
    }

    public func codexRemote(for hostID: HostID) -> CodexDesktopRemote? {
        codexRemotes.first { $0.id == hostID }
    }

    public func createThread(
        on hostID: HostID,
        cwd: String,
        name: String,
        model: String,
        reasoningEffort: String,
        permissions: AgentThreadPermissions = .default,
        initialPrompt: String
    ) async throws -> ThreadCreationOutcome {
        guard let relay = relays[hostID] else {
            throw CodexAppServerError.disconnected
        }
        return try await relay.createThread(
            cwd: cwd,
            name: name,
            model: model,
            reasoningEffort: reasoningEffort,
            permissions: permissions,
            initialPrompt: initialPrompt
        )
    }

    public func models(on hostID: HostID) async throws -> [AgentModelOption] {
        guard let relay = relays[hostID] else {
            throw CodexAppServerError.disconnected
        }
        return try await relay.listModels()
    }

    public func mentionCandidates(on hostID: HostID, cwd: String?) async -> [MentionCandidate] {
        guard let relay = relays[hostID] else {
            return []
        }
        return await relay.mentionCandidates(cwd: cwd)
    }

    public func threadCatalogEntries(on hostID: HostID, limit: Int = 100, archived: Bool = false) async throws -> [ThreadCatalogEntry] {
        guard let relay = relays[hostID] else {
            throw CodexAppServerError.disconnected
        }
        let entries = try await relay.threadCatalogEntries(limit: limit, archived: archived)
        return entries.map { $0.applying(runtimeState: threadRuntimeStates[$0.id]) }
    }

    public func searchThreadCatalog(on hostID: HostID, query: String, limit: Int = 50) async throws -> [ThreadCatalogEntry] {
        guard let relay = relays[hostID] else {
            throw CodexAppServerError.disconnected
        }
        return try await relay.searchThreadCatalog(query: query, limit: limit)
    }

    public func loadedThreadCatalogEntries(on hostID: HostID, limit: Int = 100) async -> [ThreadCatalogEntry] {
        guard let relay = relays[hostID] else {
            return []
        }
        return await relay.loadedThreadCatalogEntries(limit: limit)
    }

    public func reconnect(_ hostID: HostID) async {
        if hostID.rawValue.hasPrefix("codex-remote-"),
           let remote = await codexRemoteForRecovery(hostID: hostID),
           remote.isConnectable {
            await connectCodexRemote(remote)
            return
        }

        guard let endpoint = relayEndpoints.first(where: { $0.id == hostID }) else {
            return
        }
        await connectRemote(endpoint, respectBackoff: true)
    }

    public func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript {
        try await loadTranscriptPage(for: threadRef, cursor: nil)
    }

    public func loadOlderTranscriptPage(for threadRef: ThreadRef, cursor: String) async throws -> ThreadTranscript {
        try await loadTranscriptPage(for: threadRef, cursor: cursor)
    }

    private func loadTranscriptPage(for threadRef: ThreadRef, cursor: String?) async throws -> ThreadTranscript {
        guard let relay = relays[threadRef.hostID] else {
            throw CodexAppServerError.disconnected
        }
        let result: AppServerTranscriptLoadResult
        if let cursor {
            result = try await relay.loadOlderTranscriptPageWithRolloutPath(for: threadRef, cursor: cursor)
        } else {
            result = try await relay.loadTranscriptWithRolloutPath(for: threadRef)
        }

        let transcriptToResolve: ThreadTranscript
        if let remote = await codexRemoteForTranscript(hostID: threadRef.hostID),
           let rolloutPath = result.rolloutPath,
           let rolloutTranscript = try? await CodexRemoteTunnelService.loadRemoteRolloutTranscript(
                on: remote,
                path: rolloutPath,
                threadRef: threadRef
           ),
           !rolloutTranscript.messages.isEmpty {
            transcriptToResolve = ThreadTranscriptParser.transcriptByAddingImageAttachments(
                from: rolloutTranscript,
                to: result.transcript,
                appendMissingMessages: false
            )
        } else {
            transcriptToResolve = result.transcript
        }

        let resolvedTranscript = await resolveRemoteImageAttachments(in: transcriptToResolve)
        upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
            if cursor == nil {
                state.reconcileAfterLatestTranscriptRead(resolvedTranscript)
            } else {
                state.prepareForTranscriptRead()
            }
        }
        return resolvedTranscript
    }

    public func loadMapofAgentsWorkflowSnapshot(
        from hostID: HostID,
        pairedHost: MapofAgentsPairedHost? = nil,
        includeRelayEndpoints: Bool = true
    ) async throws -> WorkflowSnapshot {
        guard let relay = relays[hostID] else {
            throw CodexAppServerError.disconnected
        }

        let machine = machines.first { $0.id == hostID }

        if let pairedHost {
            return try await WorkflowSnapshotSyncService.loadSnapshot(
                pairedHost: pairedHost,
                codexHome: machine?.codexHome,
                includeRelayEndpoints: includeRelayEndpoints
            ) { path in
                try await relay.readFile(path: path)
            }
        }

        guard let supportDirectory = WorkflowSnapshotSyncService.remoteMacSupportDirectory(codexHome: machine?.codexHome) else {
            throw WorkflowSnapshotSyncError.missingRemoteSupportDirectory
        }

        return try await WorkflowSnapshotSyncService.loadSnapshot(
            supportDirectory: supportDirectory,
            includeRelayEndpoints: includeRelayEndpoints
        ) { path in
            try await relay.readFile(path: path)
        }
    }

    public func resolveThread(threadID: String, hostID: HostID, cwdHint: String? = nil) async -> ThreadRef? {
        guard let relay = relays[hostID] else {
            return nil
        }
        return await relay.resolveThread(threadID: threadID, cwdHint: cwdHint)
    }

    private func resolveRemoteImageAttachments(in transcript: ThreadTranscript) async -> ThreadTranscript {
        let relays = relays
        let remote = await codexRemoteForTranscript(hostID: transcript.threadRef.hostID)

        return await TranscriptAssetCache.resolveArtifacts(in: transcript) { attachment in
            guard let sourcePath = TranscriptAssetCache.sourceReadPath(for: attachment, in: transcript.threadRef) else {
                return nil
            }

            if let relay = relays[attachment.sourceHostID],
               let data = try? await relay.readFile(path: sourcePath) {
                return data
            }

            if attachment.sourceHostID == transcript.threadRef.hostID,
               let remote {
                return try await CodexRemoteTunnelService.loadRemoteFileData(on: remote, path: sourcePath)
            }

            return nil
        }
    }

    private func codexRemoteForTranscript(hostID: HostID) async -> CodexDesktopRemote? {
        if let remote = codexRemote(for: hostID) {
            return remote
        }

        guard let discovered = try? await CodexDesktopRemoteService.discover() else {
            return nil
        }
        codexRemotes = discovered
        return discovered.first { $0.id == hostID }
    }

    private func codexRemoteForRecovery(hostID: HostID) async -> CodexDesktopRemote? {
        if let remote = codexRemote(for: hostID), remote.isConnectable {
            return remote
        }

        guard let discovered = try? await CodexDesktopRemoteService.discover() else {
            return nil
        }
        codexRemotes = discovered
        return discovered.first { $0.id == hostID && $0.isConnectable }
    }

    func hasPendingCodexRemoteRecovery(for hostID: HostID) -> Bool {
        codexRemoteRecoveryTasks[hostID] != nil
    }

    func hasActiveCodexRemoteRecovery(for hostID: HostID) -> Bool {
        codexRemoteRecoveryFailures[hostID] != nil
    }

    @discardableResult
    private func cancelCodexRemoteRecovery(hostID: HostID) -> Bool {
        let hadPendingRecovery = codexRemoteRecoveryTasks[hostID] != nil
            || codexRemoteRecoveryFailures[hostID] != nil
        codexRemoteRecoveryTasks[hostID]?.cancel()
        codexRemoteRecoveryTasks[hostID] = nil
        codexRemoteRecoveryFailures[hostID] = nil
        return hadPendingRecovery
    }

    func scheduleCodexRemoteRecovery(hostID: HostID, reason: String) async {
        guard codexRemoteRecoveryTasks[hostID] == nil else {
            return
        }

        let failureCount = (codexRemoteRecoveryFailures[hostID] ?? 0) + 1
        codexRemoteRecoveryFailures[hostID] = failureCount
        let delay = Self.codexRemoteRecoveryDelay(forConsecutiveFailures: failureCount)
        let delayDescription = "\(Int(delay))s"

        codexRemoteDiagnostics[hostID] = [
            RuntimeDiagnosticStep(
                id: "route-recovery",
                title: "Route recovery",
                status: .running,
                detail: "Retrying in \(delayDescription): \(reason)",
                evidence: "stop stale WebSocket relay, stop stale SSH tunnel, rediscover Codex remote, rebuild authenticated tunnel",
                action: .restartAppServer
            ),
        ]
        if let machine = machines.first(where: { $0.id == hostID }) {
            await supervisor.upsertMachine(
                SupervisorMachine(
                    id: machine.id,
                    name: machine.name,
                    endpointDescription: machine.endpointDescription,
                    status: .connecting,
                    platform: machine.platform,
                    codexHome: machine.codexHome,
                    lastEventAt: machine.lastEventAt,
                    lastError: reason
                )
            )
            await refreshSnapshots()
        }

        codexRemoteRecoveryTasks[hostID] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.runCodexRemoteRecovery(hostID: hostID)
        }
    }

    private func runCodexRemoteRecovery(hostID: HostID) async {
        codexRemoteRecoveryTasks[hostID] = nil
        guard hasActiveCodexRemoteRecovery(for: hostID) else {
            return
        }
        guard let remote = await codexRemoteForRecovery(hostID: hostID) else {
            guard hasActiveCodexRemoteRecovery(for: hostID) else {
                return
            }
            codexRemoteDiagnostics[hostID] = [
                RuntimeDiagnosticStep(
                    id: "route-recovery",
                    title: "Route recovery",
                    status: .failed,
                    detail: "Codex Desktop remote is not discoverable yet.",
                    evidence: "rediscover Codex Desktop remotes from local state",
                    action: .restartAppServer
                ),
            ]
            await supervisor.updateMachineFailure(hostID, message: "Codex Desktop remote is not discoverable yet.")
            await refreshSnapshots()
            return
        }

        guard hasActiveCodexRemoteRecovery(for: hostID) else {
            return
        }
        await connectCodexRemote(remote, cancelPendingRecovery: false, retryOnFailure: true)
    }

    public func sendMessage(
        _ text: String,
        to threadRef: ThreadRef,
        model: String?,
        reasoningEffort: String?,
        permissions: AgentThreadPermissions? = nil,
        attachments: [ChatInputAttachment] = []
    ) async throws {
        guard let relay = relays[threadRef.hostID] else {
            throw CodexAppServerError.disconnected
        }
        try await relay.sendMessage(
            text,
            to: threadRef,
            model: model,
            reasoningEffort: reasoningEffort,
            permissions: permissions,
            attachments: attachments
        )
        upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
            state.status = .running
            state.activeFlags.insert(.running)
            state.liveAssistantText = ""
            state.lastActivityAt = Date()
        }
    }

    public func interruptThread(_ threadRef: ThreadRef) async throws -> String {
        guard let relay = relays[threadRef.hostID] else {
            throw CodexAppServerError.disconnected
        }
        let activeTurnID = threadRuntimeStates[threadRef.qualifiedID]?.activeTurnID
        let turnID = try await relay.interruptThread(threadRef, activeTurnID: activeTurnID)
        upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
            state.status = .complete
            state.activeFlags.remove(.running)
            state.liveAssistantText = ""
            state.currentActivitySummary = "Turn stopped"
        }
        return turnID
    }

    public func recordWorkflowEvent(_ event: WorkflowEvent) async {
        reduceRuntimeState(event: event)
        await supervisor.ingest(event, from: event.hostID ?? localHostID)
        await refreshSnapshots()
    }

    public func respondToAttentionRequest(_ request: RuntimeAttentionRequest, allow: Bool) async throws {
        guard request.supportsApprovalDecision else {
            throw CodexAppServerError.server("This request needs a typed response and cannot be answered with Allow/Deny.")
        }
        guard let hostID = request.hostID,
              let requestID = request.requestID,
              let connectionID = request.connectionID,
              let relay = relays[hostID] else {
            throw CodexAppServerError.staleServerRequest
        }

        try await relay.respondToServerRequest(
            id: requestID,
            result: request.appServerApprovalResult(allow: allow),
            connectionID: connectionID
        )
        removeAttentionRequest(hostID: hostID, requestID: requestID.stringValue)
    }

    public func respondToAttentionRequest(_ request: RuntimeAttentionRequest, text: String) async throws {
        guard request.supportsTypedResponse else {
            throw CodexAppServerError.server("This request cannot be answered with typed input.")
        }
        guard let hostID = request.hostID,
              let requestID = request.requestID,
              let connectionID = request.connectionID,
              let relay = relays[hostID] else {
            throw CodexAppServerError.staleServerRequest
        }

        try await relay.respondToServerRequest(
            id: requestID,
            result: request.appServerTextResponseResult(text),
            connectionID: connectionID
        )
        removeAttentionRequest(hostID: hostID, requestID: requestID.stringValue)
    }

    public func declineTypedAttentionRequest(_ request: RuntimeAttentionRequest) async throws {
        guard request.supportsTypedResponse else {
            throw CodexAppServerError.server("This request does not support typed responses.")
        }
        guard let hostID = request.hostID,
              let requestID = request.requestID,
              let connectionID = request.connectionID,
              let relay = relays[hostID] else {
            throw CodexAppServerError.staleServerRequest
        }

        try await relay.respondToServerRequest(
            id: requestID,
            result: request.appServerTextDeclineResult(),
            connectionID: connectionID
        )
        removeAttentionRequest(hostID: hostID, requestID: requestID.stringValue)
    }

    private func upsertAttentionRequest(_ request: RuntimeAttentionRequest) {
        pendingAttentionRequests.removeAll { $0.id == request.id }
        pendingAttentionRequests.insert(request, at: 0)
        if pendingAttentionRequests.count > 80 {
            pendingAttentionRequests.removeLast(pendingAttentionRequests.count - 80)
        }
        if let hostID = request.hostID, let threadID = request.threadID {
            upsertRuntimeState(hostID: hostID, threadID: threadID) { state in
                state.applyAttentionRequest(request)
            }
        }
    }

    private func removeAttentionRequest(hostID: HostID, requestID: String) {
        pendingAttentionRequests.removeAll { request in
            request.hostID == hostID
                && (request.requestID?.stringValue == requestID || request.id == requestID)
        }
        resolveAttentionRequest(hostID: hostID, requestID: requestID)
    }

    public func archiveThread(_ threadRef: ThreadRef) async throws {
        guard let relay = relays[threadRef.hostID] else {
            throw CodexAppServerError.disconnected
        }
        try await relay.archiveThread(threadRef)
    }

    public func forkThread(_ threadRef: ThreadRef, model: String?) async throws -> ThreadRef {
        guard let relay = relays[threadRef.hostID] else {
            throw CodexAppServerError.disconnected
        }
        return try await relay.forkThread(threadRef, model: model)
    }

    @discardableResult
    private func connectRemote(
        _ relayEndpoint: AppServerRelayEndpoint,
        accessTokenProvider: (any AppServerAccessTokenProviding)? = nil,
        attachmentStagingRoot: String? = nil,
        markFailureOnFailure: Bool = true,
        respectBackoff: Bool = false
    ) async -> Bool {
        if let securityError = AppServerRelayEndpoint.connectionSecurityError(
            url: relayEndpoint.url,
            bearerToken: accessTokenProvider == nil ? relayEndpoint.bearerToken : "provided-at-connect"
        ) {
            await supervisor.upsertMachine(
                SupervisorMachine(
                    id: relayEndpoint.id,
                    name: relayEndpoint.name,
                    endpointDescription: relayEndpoint.url.absoluteString,
                    status: .failed,
                    lastError: securityError
                )
            )
            await refreshSnapshots()
            return false
        }

        guard !respectBackoff || canAttemptRelayEndpoint(for: relayEndpoint.id) else {
            return false
        }

        await hostRegistry.record(id: relayEndpoint.id, name: relayEndpoint.name, endpointURL: relayEndpoint.url)

        markHostRuntimeStatesReconciling(hostID: relayEndpoint.id)
        relayConnectionIDs[relayEndpoint.id] = nil
        if let existingRelay = relays[relayEndpoint.id] {
            await existingRelay.stop(markDisconnected: false)
        }

        await stageRelayEndpointAttempt(relayEndpoint)
        let relayGeneration = UUID()
        relayGenerations[relayEndpoint.id] = relayGeneration
        let relay = AppServerWebSocketWorkflowRelay(
            endpoint: relayEndpoint,
            supervisor: supervisor,
            accessTokenProvider: accessTokenProvider,
            attachmentStagingRoot: attachmentStagingRoot,
            reportsConnectionFailures: markFailureOnFailure,
            onAttentionRequest: { [weak self] request in
                Task { @MainActor in
                    guard self?.relayGenerations[relayEndpoint.id] == relayGeneration else { return }
                    self?.upsertAttentionRequest(request)
                }
            },
            onAttentionResolved: { [weak self] hostID, requestID in
                Task { @MainActor in
                    guard self?.relayGenerations[hostID] == relayGeneration else { return }
                    self?.removeAttentionRequest(hostID: hostID, requestID: requestID)
                }
            },
            onConnected: { [weak self] hostID, connectionID in
                await MainActor.run {
                    guard self?.relayGenerations[hostID] == relayGeneration else { return }
                    self?.recordRelayConnectionReady(
                        hostID: hostID,
                        connectionID: connectionID
                    )
                }
            },
            onNotification: { [weak self] hostID, notification in
                await MainActor.run {
                    guard self?.relayGenerations[hostID] == relayGeneration else { return }
                    self?.handleRemoteNotification(notification, hostID: hostID)
                }
            },
            onDisconnected: { [weak self] hostID in
                await self?.handleRelayDisconnected(
                    hostID: hostID,
                    expectedRelayGeneration: relayGeneration
                )
            },
            onWriteReconciled: { [weak self] reconciliation in
                Task { @MainActor in
                    guard self?.relayGenerations[reconciliation.hostID] == relayGeneration else { return }
                    self?.applyWriteReconciliation(reconciliation)
                }
            },
            onReconnectReconciled: { [weak self] reconciliation in
                await MainActor.run {
                    guard self?.relayGenerations[reconciliation.hostID] == relayGeneration else { return }
                    self?.applyReconnectReconciliation(reconciliation)
                }
            }
        )
        relays[relayEndpoint.id] = relay
        await relay.updateWorkflowThreads(workflowThreadRefs)
        let didConnect = await relay.start()
        if didConnect {
            await relay.setReportsConnectionFailures(true)
            await recordRelayEndpointAttemptSuccess(hostID: relayEndpoint.id)
        } else if markFailureOnFailure {
            let message = await relay.lastFailureMessage() ?? "Connection failed."
            await recordRelayEndpointAttemptFailure(hostID: relayEndpoint.id, message: message)
        }
        await refreshSnapshots()
        return didConnect
    }

    public func disconnect(_ machineID: HostID) async {
        guard machineID != localHostID else { return }
        cancelCodexRemoteRecovery(hostID: machineID)
        relayEndpoints.removeAll { $0.id == machineID }
        if let tunnel = remoteTunnels.removeValue(forKey: machineID) {
            tunnel.stop()
        }
        activeRelayEndpointsByHostID[machineID] = nil
        relayGenerations[machineID] = nil
        clearHostScopedRuntimeState(hostID: machineID)
        if let relay = relays.removeValue(forKey: machineID) {
            await relay.stop()
        } else {
            await supervisor.updateMachineStatus(machineID, status: .disconnected)
        }
        await refreshSnapshots()
    }

    private func upsertRelayEndpoint(_ relayEndpoint: AppServerRelayEndpoint) {
        activeRelayEndpointsByHostID[relayEndpoint.id] = relayEndpoint

        guard Self.shouldPersistRelayEndpoint(relayEndpoint) else {
            return
        }

        if !relayEndpoints.contains(where: { $0.id == relayEndpoint.id }) {
            relayEndpoints.append(relayEndpoint)
        } else {
            relayEndpoints = relayEndpoints.map { $0.id == relayEndpoint.id ? relayEndpoint : $0 }
        }
    }

    public func refreshSnapshots() async {
        let nextMachines = await supervisor.machineSnapshot()
        if machines != nextMachines {
            machines = nextMachines
        }

        let nextEventEnvelopes = await supervisor.recentEvents(limit: 120)
        if eventEnvelopes != nextEventEnvelopes {
            eventEnvelopes = nextEventEnvelopes
            workflowEvents = nextEventEnvelopes.map(\.event)
        }
    }

    private func handleRemoteNotification(_ notification: CodexServerNotification, hostID: HostID) {
        guard relays[hostID] != nil else {
            return
        }
        reduceRuntimeState(notification: notification, hostID: hostID)
    }

    func applyWriteReconciliation(_ reconciliation: AppServerWriteReconciliation) {
        lastWriteReconciliations[reconciliation.hostID] = reconciliation
        for entry in reconciliation.observedCatalogEntries {
            reconciledThreadCatalogEntries[entry.id] = entry
        }

        if let transcript = reconciliation.transcript,
           let threadRef = reconciliation.affectedThreadRefs.first {
            upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
                state.reconcileAfterLatestTranscriptRead(transcript)
                state.currentActivitySummary = reconciliation.confirmedCommitted
                    ? "State confirmed after reconnect"
                    : "State refreshed after an unconfirmed write"
            }
        } else if reconciliation.confirmedCommitted {
            for threadRef in reconciliation.affectedThreadRefs {
                upsertRuntimeState(hostID: threadRef.hostID, threadID: threadRef.threadID) { state in
                    state.lastActivityAt = Date()
                    state.currentActivitySummary = "State confirmed after reconnect"
                    if reconciliation.method == .startTurn {
                        state.status = .running
                        state.activeFlags.insert(.running)
                    }
                }
            }
        }

        if reconciliation.method == .archiveThread,
           reconciliation.confirmedCommitted,
           let threadID = reconciliation.affectedThreadRefs.first?.threadID {
            let key = ThreadRef.qualifiedID(hostID: reconciliation.hostID, threadID: threadID)
            threadRuntimeStates[key] = nil
            reconciledThreadCatalogEntries[key] = nil
        }
    }

    func applyReconnectReconciliation(_ reconciliation: AppServerReconnectReconciliation) {
        if let connectionID = reconciliation.connectionID {
            guard relayConnectionIDs[reconciliation.hostID] == connectionID else {
                return
            }
            if let connectionEpochGate = reconciliation.connectionEpochGate {
                guard connectionEpochGate.accepts(connectionID) else {
                    return
                }
            }
        }

        let eligibleThreadIDs = Set(
            reconciliation.targetThreadIDs.filter { threadID in
                guard !reconciliation.skippedThreadIDsDueToLiveUpdates.contains(threadID) else {
                    return false
                }
                let key = ThreadRef.qualifiedID(
                    hostID: reconciliation.hostID,
                    threadID: threadID
                )
                // New loaded threads have no prior state and may be created by
                // the snapshot. Existing states must still carry the marker
                // installed at disconnect; a live event removes that marker.
                return threadRuntimeStates[key] == nil
                    || reconnectingRuntimeStateIDs.contains(key)
            }
        )
        let entriesByThreadID = Dictionary(
            uniqueKeysWithValues: reconciliation.catalogEntries.map {
                ($0.threadRef.threadID, $0)
            }
        )
        for entry in reconciliation.catalogEntries
        where eligibleThreadIDs.contains(entry.threadRef.threadID) {
            reconciledThreadCatalogEntries[entry.id] = entry
        }

        for threadID in reconciliation.targetThreadIDs.sorted() {
            let key = ThreadRef.qualifiedID(hostID: reconciliation.hostID, threadID: threadID)
            guard eligibleThreadIDs.contains(threadID) else {
                reconnectingRuntimeStateIDs.remove(key)
                continue
            }
            let failure = reconciliation.failuresByThreadID[threadID]
            let transcript = reconciliation.transcriptsByThreadID[threadID]
            let entry = entriesByThreadID[threadID]

            upsertRuntimeState(hostID: reconciliation.hostID, threadID: threadID) { state in
                AppServerReconnectStateReducer.apply(
                    catalogEntry: entry,
                    transcript: transcript,
                    catalogStatusIsAuthoritative: reconciliation
                        .authoritativeCatalogStatusThreadIDs
                        .contains(threadID),
                    to: &state
                )

                if let failure {
                    state.currentActivitySummary = "Could not fully verify after reconnect — last known state"
                    state.lastError = state.lastError ?? failure
                } else if state.currentActivitySummary == nil {
                    state.currentActivitySummary = Self.reconciledActivitySummary(for: state.status)
                }
            }

            if failure == nil {
                reconnectingRuntimeStateIDs.remove(key)
            }
        }

        for key in reconnectingRuntimeStateIDs.sorted() {
            guard var state = threadRuntimeStates[key],
                  state.hostID == reconciliation.hostID,
                  !reconciliation.targetThreadIDs.contains(state.threadID) else {
                continue
            }
            if reconciliation.omittedThreadIDs.contains(state.threadID) {
                state.currentActivitySummary = "Last known state — deferred by bounded reconnect scan"
                reconnectingRuntimeStateIDs.remove(key)
            } else {
                state.currentActivitySummary = reconciliation.loadedThreadListError == nil
                    ? "Last known state — thread was not loaded after reconnect"
                    : "Could not verify loaded threads after reconnect — last known state"
            }
            threadRuntimeStates[key] = state
        }
    }

    private static func reconciledActivitySummary(for status: ThreadRunStatus) -> String {
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
            return AppServerReconnectStateReducer.activitySummary(for: status)
        }
    }

    private func handleRelayDisconnected(
        hostID: HostID,
        expectedRelayGeneration: UUID
    ) async {
        guard relayGenerations[hostID] == expectedRelayGeneration else {
            return
        }
        relayConnectionIDs[hostID] = nil
        markHostRuntimeStatesReconciling(hostID: hostID)
        guard remoteTunnels[hostID] != nil else {
            return
        }

        let failedRelay = relays.removeValue(forKey: hostID)
        relayGenerations[hostID] = nil
        let failedTunnel = remoteTunnels.removeValue(forKey: hostID)
        activeRelayEndpointsByHostID[hostID] = nil
        failedTunnel?.stop()
        if let failedRelay {
            await failedRelay.stop(markDisconnected: false)
        }

        await scheduleCodexRemoteRecovery(
            hostID: hostID,
            reason: "The App Server route dropped; rebuilding the SSH tunnel."
        )
    }

    private func reduceRuntimeState(notification: CodexServerNotification, hostID: HostID) {
        guard let threadID = Self.threadID(from: notification.params) else {
            return
        }
        reconnectingRuntimeStateIDs.remove(
            ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
        )

        if notification.method == "item/agentMessage/delta",
           let delta = notification.params?["delta"]?.stringValue {
            upsertRuntimeState(hostID: hostID, threadID: threadID) { state in
                state.appendAssistantDelta(delta)
            }
            return
        }

        if notification.method.contains("item/") {
            let itemID = notification.params?["itemId"]?.stringValue
                ?? notification.params?["itemID"]?.stringValue
                ?? notification.params?["item_id"]?.stringValue
                ?? notification.params?["item"]?["id"]?.stringValue
            if let itemID {
                upsertRuntimeState(hostID: hostID, threadID: threadID) { state in
                    state.recordItemActivity(method: notification.method, itemID: itemID)
                }
            }
        }

        if let event = WorkflowEvent.appServerEvent(from: notification, hostID: hostID) {
            reduceRuntimeState(event: event)
        }
    }

    private func reduceRuntimeState(event: WorkflowEvent) {
        guard let threadID = event.threadID else { return }
        let hostID = event.hostID ?? localHostID
        reconnectingRuntimeStateIDs.remove(
            ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
        )
        upsertRuntimeState(hostID: hostID, threadID: threadID) { state in
            state.apply(event: event, markUnread: event.kind != .turnStarted)
        }
    }

    private func upsertRuntimeState(
        hostID: HostID,
        threadID: String,
        update: (inout ThreadRuntimeState) -> Void
    ) {
        guard !threadID.isEmpty else { return }
        let key = ThreadRef.qualifiedID(hostID: hostID, threadID: threadID)
        var state = threadRuntimeStates[key] ?? ThreadRuntimeState(hostID: hostID, threadID: threadID)
        update(&state)
        threadRuntimeStates[key] = state
    }

    private func resolveAttentionRequest(hostID: HostID, requestID: String) {
        for key in threadRuntimeStates.keys where key.hasPrefix("\(hostID.rawValue)::") {
            guard var state = threadRuntimeStates[key] else { continue }
            state.resolveAttentionRequest(requestID)
            threadRuntimeStates[key] = state
        }
    }

    private static func threadID(from params: JSONValue?) -> String? {
        AppServerNotificationNormalizer.threadID(from: params)
    }

    func markHostRuntimeStatesReconciling(hostID: HostID) {
        pendingAttentionRequests.removeAll { $0.hostID == hostID }
        lastWriteReconciliations[hostID] = nil

        for key in threadRuntimeStates.keys.sorted() {
            guard var state = threadRuntimeStates[key],
                  state.hostID == hostID || key.hasPrefix("\(hostID.rawValue)::") else {
                continue
            }
            reconnectingRuntimeStateIDs.insert(key)
            state.pendingRequestIDs = []
            state.activeFlags.remove(.waitingOnApproval)
            state.activeFlags.remove(.waitingOnUserInput)
            state.liveAssistantText = ""
            state.currentActivitySummary = "Reconnecting — showing last known state"
            threadRuntimeStates[key] = state
        }
    }

    func recordRelayConnectionReady(
        hostID: HostID,
        connectionID: AppServerConnectionID
    ) {
        relayConnectionIDs[hostID] = connectionID
    }

    private func clearHostScopedRuntimeState(hostID: HostID) {
        pendingAttentionRequests.removeAll { $0.hostID == hostID }
        lastWriteReconciliations[hostID] = nil
        reconciledThreadCatalogEntries = reconciledThreadCatalogEntries.filter {
            $0.value.threadRef.hostID != hostID
        }
        threadRuntimeStates = threadRuntimeStates.filter { key, state in
            state.hostID != hostID && !key.hasPrefix("\(hostID.rawValue)::")
        }
        reconnectingRuntimeStateIDs = reconnectingRuntimeStateIDs.filter {
            !$0.hasPrefix("\(hostID.rawValue)::")
        }
        relayConnectionIDs[hostID] = nil
    }

    private static func defaultName(for url: URL) -> String {
        if let host = url.host(), !host.isEmpty {
            return host
        }
        return "Remote machine"
    }

    private static func machineID(for url: URL) -> String {
        let raw = url.absoluteString.lowercased()
        let allowed = CharacterSet.alphanumerics
        let scalars = raw.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let compact = String(scalars)
            .replacingOccurrences(of: "--", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "relay-\(compact.prefix(72))"
    }

    private static func shouldRestoreRelayEndpoint(_ endpoint: AppServerRelayEndpoint) -> Bool {
        guard shouldPersistRelayEndpoint(endpoint) else {
            return false
        }
        guard endpoint.connectionSecurityError == nil else {
            return false
        }
        return true
    }

    private static func shouldPersistRelayEndpoint(_ endpoint: AppServerRelayEndpoint) -> Bool {
        guard !endpoint.id.rawValue.hasPrefix("codex-remote-") else {
            return false
        }

        guard let host = endpoint.url.host()?.lowercased() else {
            return true
        }

        let isTailnetDirectHost = host.contains(".tail")
            || host.hasSuffix(".ts.net")
            || host.hasPrefix("100.")
            || host.hasPrefix("fd7a:")
        return !isTailnetDirectHost
    }
}

public extension SupervisorMachine {
    init(host: AgentHost) {
        self.init(
            id: host.id,
            name: host.name,
            endpointDescription: host.endpointDescription,
            status: SupervisorMachineStatus(host.status),
            platform: host.platform,
            codexHome: host.codexHome,
            lastEventAt: host.lastSeenAt
        )
    }
}

private extension SupervisorMachineStatus {
    init(_ hostStatus: HostStatus) {
        switch hostStatus {
        case .connected:
            self = .connected
        case .connecting:
            self = .connecting
        case .disconnected:
            self = .disconnected
        case .unavailable:
            self = .failed
        }
    }
}

private extension RuntimeDiagnosticAction {
    var runningTitle: String {
        switch self {
        case .installCodexCLI:
            return "Installing Codex CLI"
        case .updateCodexCLI:
            return "Updating Codex CLI"
        case .startAppServer:
            return "Starting App Server"
        case .restartAppServer:
            return "Restarting App Server"
        }
    }

    var failureTitle: String {
        switch self {
        case .installCodexCLI:
            return "Install Codex CLI"
        case .updateCodexCLI:
            return "Update Codex CLI"
        case .startAppServer:
            return "Start App Server"
        case .restartAppServer:
            return "Restart App Server"
        }
    }
}
