#if os(macOS)
import AppKit
import Foundation
import MapofAgentsCore
import MapofAgentsUI
import Observation

struct MapofAgentsAppSessionServices: Sendable {
    var hasActivePairedDevices: @Sendable () -> Bool
    var migrateLegacyPersistentRoutes: @Sendable () async throws -> Void
    var ensurePairingHostRunning: @Sendable () async throws -> Void
    var terminatePairingHostRuntime: @Sendable () -> Void
    var startHookBridge: @Sendable (
        _ defaultHostID: HostID,
        _ onEvents: @escaping @MainActor @Sendable ([WorkflowEvent]) -> Void
    ) -> Task<Void, Never>
    var runtimeUpdateService: CodexRuntimeUpdateService = .live
    var pairingSupervisionInterval: Duration

    static let live = MapofAgentsAppSessionServices(
        hasActivePairedDevices: {
            MapofAgentsMacPairingService.hasActivePairedDevices()
        },
        migrateLegacyPersistentRoutes: {
            try await MapofAgentsMacPairingService.migrateLegacyPersistentRoutesIfNeeded()
        },
        ensurePairingHostRunning: {
            try await MapofAgentsMacPairingService.ensureHostServerRunning()
        },
        terminatePairingHostRuntime: {
            try? MapofAgentsMacPairingService.terminateHostRuntime()
        },
        startHookBridge: { defaultHostID, onEvents in
            WorkflowHookEventFileBridge(defaultHostID: defaultHostID).start(onEvents: onEvents)
        },
        pairingSupervisionInterval: .seconds(30)
    )
}

/// Process-lifetime owners shared by every incarnation of the main window.
///
/// SwiftUI may destroy and recreate a `Window`'s content after it is closed.
/// Keeping these stores and background tasks on the `App` prevents a reopened
/// window from starting a second App Server, supervisor, hook reader, or pairing
/// host against the same persistence files.
@MainActor
@Observable
final class MapofAgentsAppSession {
    let repository: LocalControlRoomStore
    let graphStore: GraphStore
    let runtimeStore: CodexRuntimeStore
    let providerRuntimeStore: AgentProviderRuntimeStore
    let supervisorStore: WorkflowSupervisorStore
    let threadCatalogStore: ThreadCatalogStore
    let workflowLibrary: WorkflowLibraryCoordinator
    let threadCreation: ThreadCreationCoordinator
    let bootstrapErrorMessage: String?

    private(set) var pairingHostError: String?
    private(set) var isStarted = false
    private(set) var runtimeUpdatePhase: CodexRuntimeUpdatePhase = .idle
    private(set) var runtimeVersionStatus = CodexRuntimeVersionStatus(
        installedVersion: nil,
        runningVersion: nil
    )
    private(set) var runtimeUpdateMessage: String?
    private(set) var workflowMessageRelayError: String?

    @ObservationIgnored private let services: MapofAgentsAppSessionServices
    @ObservationIgnored private let workflowMessageRelay: WorkflowMessageFileRelay
    @ObservationIgnored private var pairingHostSupervisionTask: Task<Void, Never>?
    @ObservationIgnored private var hookEventBridgeTask: Task<Void, Never>?
    @ObservationIgnored private var workflowMessageRelayTask: Task<Void, Never>?
    @ObservationIgnored private var runtimeUpdateTask: Task<Void, Never>?
    @ObservationIgnored private var runtimeUpdateTaskID: UUID?
    @ObservationIgnored private var lifecycleGeneration: UInt = 0
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init(
        paths injectedPaths: ApplicationPaths? = nil,
        services: MapofAgentsAppSessionServices = .live,
        observesApplicationTermination: Bool = true
    ) {
        let paths: ApplicationPaths
        let bootstrapErrorMessage: String?
        if let injectedPaths {
            paths = injectedPaths
            bootstrapErrorMessage = nil
        } else {
            do {
                paths = try ApplicationPaths.defaultPaths()
                bootstrapErrorMessage = nil
            } catch {
                paths = ApplicationPaths(
                    applicationSupportDirectory: URL(fileURLWithPath: NSTemporaryDirectory())
                        .appendingPathComponent(ApplicationPaths.supportDirectoryName, isDirectory: true)
                )
                bootstrapErrorMessage = "Using temporary app storage because the normal Application Support folder could not be prepared: \(error.localizedDescription)"
            }
        }

        let repository = LocalControlRoomStore(paths: paths)
        self.repository = repository
        self.graphStore = GraphStore(repository: repository)
        self.runtimeStore = CodexRuntimeStore()
        self.providerRuntimeStore = AgentProviderRuntimeStore(repository: repository)
        self.supervisorStore = WorkflowSupervisorStore()
        self.threadCatalogStore = ThreadCatalogStore()
        self.workflowLibrary = WorkflowLibraryCoordinator(repository: repository)
        self.threadCreation = ThreadCreationCoordinator()
        self.bootstrapErrorMessage = bootstrapErrorMessage
        self.services = services
        self.workflowMessageRelay = WorkflowMessageFileRelay(
            rootDirectoryURL: injectedPaths == nil
                ? WorkflowMessageFileRelay.defaultRootDirectoryURL
                : paths.applicationSupportDirectory
                    .appendingPathComponent("test-workflow-message-relay", isDirectory: true)
        )

        if observesApplicationTermination {
            let terminateRuntime = services.terminatePairingHostRuntime
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                // App termination may not leave enough time for a newly-created
                // main-actor task, so tear down the external runtime synchronously.
                terminateRuntime()
                Task { @MainActor [weak self] in
                    self?.stop(terminateRuntime: false)
                }
            }
        }
    }

    func start() async {
        guard !isStarted else { return }
        lifecycleGeneration &+= 1
        isStarted = true
        supervisorStore.start()
        startWorkflowHookEventBridge()
        startWorkflowMessageRelay()

        if services.hasActivePairedDevices() {
            ensurePairingHostSupervision()
        } else {
            try? await services.migrateLegacyPersistentRoutes()
        }
    }

    func ensurePairingHostSupervision() {
        guard pairingHostSupervisionTask == nil else { return }
        let services = services
        pairingHostSupervisionTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await services.ensurePairingHostRunning()
                    self?.pairingHostError = nil
                } catch {
                    self?.pairingHostError = error.localizedDescription
                }

                do {
                    try await Task.sleep(for: services.pairingSupervisionInterval)
                } catch {
                    return
                }
            }
        }
    }

    var runtimeUpdateUnavailableReason: String? {
        if runtimeUpdateTask != nil || runtimeUpdatePhase.isBusy || runtimeStore.isRuntimeMaintenanceInProgress {
            return "A runtime update operation is already in progress."
        }
        if runtimeStore.connectionState == .connecting {
            return "Wait for the local Codex connection to finish starting before updating."
        }
        if runtimeStore.hasInFlightRuntimeWrites {
            return "Wait for the current local Codex operation before updating."
        }
        let activeWorkCount = runtimeStore.activeRuntimeWorkCount
        if activeWorkCount > 0 {
            let unit = activeWorkCount == 1 ? "thread" : "threads"
            return "Wait for \(activeWorkCount) active local \(unit) before updating."
        }
        if !isStarted {
            return "MapofAgents is still starting."
        }
        return nil
    }

    func refreshRuntimeUpdateStatus() async {
        guard !runtimeUpdatePhase.isBusy else { return }
        runtimeUpdatePhase = .checking
        runtimeUpdateMessage = nil
        do {
            runtimeVersionStatus = try await services.runtimeUpdateService.versionStatus()
            runtimeUpdatePhase = .idle
        } catch {
            runtimeUpdatePhase = .failed
            runtimeUpdateMessage = error.localizedDescription
        }
    }

    func updateCodexRuntime() {
        guard runtimeUpdateTask == nil else { return }
        if let unavailableReason = runtimeUpdateUnavailableReason {
            runtimeUpdatePhase = .failed
            runtimeUpdateMessage = unavailableReason
            return
        }

        guard runtimeStore.beginRuntimeMaintenance() else {
            runtimeUpdatePhase = .failed
            runtimeUpdateMessage = "A local Codex operation started before maintenance could begin. Wait for it to finish and try again."
            return
        }

        let taskID = UUID()
        let generation = lifecycleGeneration
        runtimeUpdateTaskID = taskID
        runtimeUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.runtimeUpdateTaskID == taskID {
                    self.runtimeUpdateTask = nil
                    self.runtimeUpdateTaskID = nil
                }
            }
            await self.performCodexRuntimeUpdate(generation: generation)
        }
    }

    func stop(terminateRuntime: Bool = true) {
        guard isStarted
                || pairingHostSupervisionTask != nil
                || hookEventBridgeTask != nil
                || workflowMessageRelayTask != nil
                || runtimeUpdateTask != nil
        else {
            return
        }
        isStarted = false
        lifecycleGeneration &+= 1
        if runtimeUpdateTask != nil {
            runtimeUpdateTask?.cancel()
            runtimeUpdatePhase = .idle
            runtimeUpdateMessage = "Runtime restart canceled while MapofAgents stops."
        }
        pairingHostSupervisionTask?.cancel()
        pairingHostSupervisionTask = nil
        hookEventBridgeTask?.cancel()
        hookEventBridgeTask = nil
        workflowMessageRelayTask?.cancel()
        workflowMessageRelayTask = nil
        providerRuntimeStore.shutdown()
        if terminateRuntime {
            services.terminatePairingHostRuntime()
        }
    }

    private func performCodexRuntimeUpdate(generation: UInt) async {
        defer { runtimeStore.endRuntimeMaintenance() }
        guard canContinueRuntimeUpdate(generation: generation) else { return }

        runtimeUpdatePhase = .updating
        runtimeUpdateMessage = "Downloading and verifying the latest standalone Codex runtime…"

        var disconnectedLocalRuntime = false

        do {
            let update = try await services.runtimeUpdateService.applyUpdate()
            guard canContinueRuntimeUpdate(generation: generation) else { return }

            runtimeVersionStatus = try await services.runtimeUpdateService.versionStatus()
            guard canContinueRuntimeUpdate(generation: generation) else { return }

            let shouldRestartRuntime = Self.shouldRestartCodexRuntime(
                update: update,
                daemonStatus: runtimeVersionStatus,
                connectionState: runtimeStore.connectionState,
                connectedRuntimeVersion: runtimeStore.runtimeVersion
            )
            guard shouldRestartRuntime else {
                runtimeUpdatePhase = .succeeded
                runtimeUpdateMessage = "Standalone Codex \(update.installedVersion) is already up to date."
                return
            }

            guard runtimeStore.activeRuntimeWorkCount == 0,
                  !runtimeStore.hasInFlightRuntimeWrites
            else {
                throw RuntimeUpdateLifecycleError.localWorkBecameActive
            }

            runtimeUpdatePhase = .restarting
            runtimeUpdateMessage = "Restarting the local Codex App Server with \(update.installedVersion)…"

            await runtimeStore.disconnectForRuntimeUpdate()
            disconnectedLocalRuntime = true
            guard canContinueRuntimeUpdate(generation: generation) else { return }

            runtimeVersionStatus = try await services.runtimeUpdateService.restartDaemonAndVerify()
            guard canContinueRuntimeUpdate(generation: generation) else { return }

            runtimeUpdatePhase = .reconnecting
            runtimeUpdateMessage = "Reconnecting MapofAgents to Codex…"
            await runtimeStore.connectAfterRuntimeUpdate()
            guard canContinueRuntimeUpdate(generation: generation) else {
                await runtimeStore.disconnectForRuntimeUpdate()
                return
            }
            disconnectedLocalRuntime = false

            guard runtimeStore.connectionState == .connected else {
                runtimeUpdatePhase = .failed
                runtimeUpdateMessage = "Codex \(update.installedVersion) was installed, but MapofAgents could not reconnect: \(runtimeStore.statusMessage)"
                return
            }
            guard runtimeStore.runtimeVersion == update.installedVersion else {
                let connectedVersion = runtimeStore.runtimeVersion ?? "an unknown version"
                runtimeUpdatePhase = .failed
                runtimeUpdateMessage = "Standalone Codex \(update.installedVersion) is installed, but MapofAgents reconnected to \(connectedVersion). Try restarting the runtime again."
                return
            }

            runtimeUpdatePhase = .succeeded
            if update.didUpdate {
                runtimeUpdateMessage = "Updated Codex from \(update.previousVersion) to \(update.installedVersion)."
            } else {
                runtimeUpdateMessage = "Restarted and reconnected Codex \(update.installedVersion)."
            }
        } catch {
            guard canContinueRuntimeUpdate(generation: generation) else { return }
            if disconnectedLocalRuntime {
                runtimeUpdatePhase = .reconnecting
                await runtimeStore.connectAfterRuntimeUpdate()
                guard canContinueRuntimeUpdate(generation: generation) else {
                    await runtimeStore.disconnectForRuntimeUpdate()
                    return
                }
            }
            if let status = try? await services.runtimeUpdateService.versionStatus() {
                runtimeVersionStatus = status
            }
            runtimeUpdatePhase = .failed
            runtimeUpdateMessage = error.localizedDescription
        }
    }

    private func canContinueRuntimeUpdate(generation: UInt) -> Bool {
        isStarted && lifecycleGeneration == generation && !Task.isCancelled
    }

    nonisolated static func shouldRestartCodexRuntime(
        update: CodexRuntimeUpdateResult,
        daemonStatus: CodexRuntimeVersionStatus,
        connectionState: HostStatus,
        connectedRuntimeVersion: String?
    ) -> Bool {
        update.didUpdate
            || daemonStatus.needsRestart
            || connectionState != .connected
            || connectedRuntimeVersion != update.installedVersion
    }

    private func startWorkflowHookEventBridge() {
        guard hookEventBridgeTask == nil else { return }
        hookEventBridgeTask = services.startHookBridge(runtimeStore.localHost.id) { [weak self] events in
            guard let self else { return }
            for event in events where self.shouldRecordHookWorkflowEvent(event) {
                self.runtimeStore.recordWorkflowEvent(event)
            }
        }
    }

    private func startWorkflowMessageRelay() {
        guard workflowMessageRelayTask == nil else { return }
        do {
            workflowMessageRelayTask = try workflowMessageRelay.start { [weak self] request in
                guard let self else {
                    return WorkflowMessageRelayResult(
                        requestID: request.requestID,
                        success: false,
                        detail: "MapofAgents stopped before it could deliver the message."
                    )
                }
                return await self.deliverWorkflowMessage(request)
            }
            workflowMessageRelayError = nil
        } catch {
            workflowMessageRelayError = error.localizedDescription
        }
    }

    private func deliverWorkflowMessage(
        _ request: WorkflowMessageRelayRequest
    ) async -> WorkflowMessageRelayResult {
        guard request.sourceHostID == runtimeStore.localHost.id else {
            return await relayFailure(
                request,
                detail: "The local provider relay can only accept requests from a thread running on this Mac."
            )
        }
        guard let sourceNode = workflowThreadNode(
            provider: request.sourceProvider,
            hostID: request.sourceHostID,
            threadID: request.sourceThreadID
        ) else {
            return await relayFailure(
                request,
                detail: "The source thread is not a node on the active MapofAgents canvas."
            )
        }
        guard let targetNode = workflowThreadNode(
            provider: request.targetProvider,
            hostID: request.targetHostID,
            threadID: request.targetThreadID
        ), let targetThreadRef = targetNode.metadata.threadRef else {
            return await relayFailure(
                request,
                detail: "The target thread is not a node on the active MapofAgents canvas."
            )
        }
        guard sourceNode.id != targetNode.id else {
            return await relayFailure(request, detail: "A workflow thread cannot relay a message to itself.")
        }
        if targetThreadRef.provider != .codex,
           targetThreadRef.hostID != runtimeStore.localHost.id {
            return await relayFailure(
                request,
                sourceNode: sourceNode,
                targetNode: targetNode,
                detail: "External provider threads currently run only on the local MapofAgents Mac."
            )
        }

        let trimmedMessage = request.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let relayedMessage = """
        Message from \"\(sourceNode.title)\" (\(request.sourceProvider.displayName)) on the same MapofAgents canvas:

        \(trimmedMessage)
        """
        let canvasWorkspaceID = graphStore.graph.workspaceID

        do {
            switch targetThreadRef.provider {
            case .codex:
                if targetThreadRef.hostID == runtimeStore.localHost.id {
                    try await runtimeStore.sendMessage(
                        relayedMessage,
                        to: targetThreadRef,
                        model: targetNode.metadata.model,
                        reasoningEffort: targetNode.metadata.reasoningEffort,
                        permissions: targetNode.metadata.threadPermissions
                    )
                } else {
                    try await supervisorStore.sendMessage(
                        relayedMessage,
                        to: targetThreadRef,
                        model: targetNode.metadata.model,
                        reasoningEffort: targetNode.metadata.reasoningEffort,
                        permissions: targetNode.metadata.threadPermissions
                    )
                }
            case .gemini, .grok:
                try await providerRuntimeStore.sendMessage(
                    relayedMessage,
                    to: targetThreadRef,
                    model: targetNode.metadata.model,
                    reasoningEffort: targetNode.metadata.reasoningEffort
                )
            }

            await recordRelayRoute(
                workspaceID: canvasWorkspaceID,
                sourceNode: sourceNode,
                targetNode: targetNode,
                snippet: trimmedMessage,
                deliveryState: .delivered
            )
            let reply = await relayReply(for: targetThreadRef)
            return WorkflowMessageRelayResult(
                requestID: request.requestID,
                success: true,
                detail: reply == nil
                    ? "Delivered to \"\(targetNode.title)\"; the target turn started."
                    : "Delivered to \"\(targetNode.title)\"; the target provider completed its response.",
                reply: reply
            )
        } catch {
            await recordRelayRoute(
                workspaceID: canvasWorkspaceID,
                sourceNode: sourceNode,
                targetNode: targetNode,
                snippet: trimmedMessage,
                deliveryState: .failed
            )
            return WorkflowMessageRelayResult(
                requestID: request.requestID,
                success: false,
                detail: error.localizedDescription
            )
        }
    }

    private func relayReply(for threadRef: ThreadRef) async -> String? {
        guard threadRef.provider != .codex,
              let transcript = try? await providerRuntimeStore.loadTranscript(for: threadRef) else {
            return nil
        }
        guard let reply = transcript.messages.last(where: { message in
            message.role == .assistant
                && !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.text else {
            return nil
        }
        let maximumReplyBytes = 512 * 1_024
        guard reply.utf8.count > maximumReplyBytes else { return reply }
        return String(decoding: reply.utf8.prefix(maximumReplyBytes), as: UTF8.self)
            + "\n\n[Reply truncated by MapofAgents.]"
    }

    private func recordRelayRoute(
        workspaceID: WorkspaceID,
        sourceNode: CanvasNode,
        targetNode: CanvasNode,
        snippet: String,
        deliveryState: MessageRouteDeliveryState
    ) async {
        guard graphStore.graph.workspaceID == workspaceID,
              graphStore.graph.nodes[sourceNode.id] != nil,
              graphStore.graph.nodes[targetNode.id] != nil else {
            return
        }
        await graphStore.createMessageEdge(
            from: sourceNode.id,
            to: targetNode.id,
            snippet: snippet,
            deliveryState: deliveryState
        )
    }

    private func workflowThreadNode(
        provider: AgentProvider,
        hostID: HostID,
        threadID: String
    ) -> CanvasNode? {
        graphStore.graph.nodes.values.first { node in
            guard node.kind == .codexThread,
                  let threadRef = node.metadata.threadRef else {
                return false
            }
            return threadRef.provider == provider
                && threadRef.hostID == hostID
                && threadRef.threadID.caseInsensitiveCompare(threadID) == .orderedSame
        }
    }

    private func relayFailure(
        _ request: WorkflowMessageRelayRequest,
        sourceNode: CanvasNode? = nil,
        targetNode: CanvasNode? = nil,
        detail: String
    ) async -> WorkflowMessageRelayResult {
        if let sourceNode, let targetNode {
            await graphStore.createMessageEdge(
                from: sourceNode.id,
                to: targetNode.id,
                snippet: request.message,
                deliveryState: .failed
            )
        }
        return WorkflowMessageRelayResult(
            requestID: request.requestID,
            success: false,
            detail: detail
        )
    }

    private func shouldRecordHookWorkflowEvent(_ event: WorkflowEvent) -> Bool {
        if event.kind == .threadCreated {
            let sourceMatches = event.threadID.map { threadID in
                graphStore.workflowThreadRefs.contains { threadRef in
                    threadRef.matches(hostID: event.hostID, threadID: threadID)
                }
            } ?? false
            let childMatches = event.childThreadID.map { threadID in
                graphStore.workflowThreadRefs.contains { threadRef in
                    threadRef.matches(hostID: event.childHostID, threadID: threadID)
                }
            } ?? false
            return sourceMatches || childMatches
        }
        if event.kind == .folderCreated {
            guard event.childFolderPath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                return false
            }
            return graphStore.containsWorkflowThread(hostID: event.hostID, threadID: event.threadID)
        }

        guard let threadID = event.threadID else { return false }
        return graphStore.workflowThreadRefs.contains { threadRef in
            threadRef.matches(hostID: event.hostID, threadID: threadID)
        }
    }
}


private enum RuntimeUpdateLifecycleError: LocalizedError {
    case localWorkBecameActive

    var errorDescription: String? {
        switch self {
        case .localWorkBecameActive:
            return "A local Codex turn became active during the update check. The runtime was not restarted."
        }
    }
}
#endif
