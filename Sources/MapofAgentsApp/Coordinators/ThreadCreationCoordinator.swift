import MapofAgentsCore
import MapofAgentsUI
import Foundation
import Observation

@MainActor
@Observable
final class ThreadCreationCoordinator {
    var remoteModelsByHostID: [HostID: [AgentModelOption]] = [:]
    var remoteMentionCandidatesByContext: [String: [MentionCandidate]] = [:]
    var catalogRevision = 0
    var errorMessage: String?
    private var pendingCreateKeys: Set<String> = []

    func modelOptions(for target: CanvasNode?, localHostID: HostID) -> [AgentModelOption]? {
        guard let hostID = remoteHostID(for: target, localHostID: localHostID) else {
            return nil
        }
        return remoteModelsByHostID[hostID]
    }

    func mentionCandidates(for target: CanvasNode?, localHostID: HostID) -> [MentionCandidate] {
        guard let hostID = remoteHostID(for: target, localHostID: localHostID),
              let cwd = targetCWD(for: target, localHostID: localHostID)
        else {
            return []
        }
        return remoteMentionCandidatesByContext[catalogKey(hostID: hostID, cwd: cwd)] ?? []
    }

    func mentionCandidates(for threadRef: ThreadRef?, localHostID: HostID) -> [MentionCandidate] {
        guard let threadRef, threadRef.hostID != localHostID else {
            return []
        }
        return remoteMentionCandidatesByContext[catalogKey(hostID: threadRef.hostID, cwd: threadRef.cwd)] ?? []
    }

    func refreshThreadFormCatalog(
        for target: CanvasNode?,
        localHostID: HostID,
        supervisorStore: WorkflowSupervisorStore
    ) {
        guard let hostID = remoteHostID(for: target, localHostID: localHostID) else {
            return
        }
        refreshRemoteCatalog(hostID: hostID, cwd: targetCWD(for: target, localHostID: localHostID), supervisorStore: supervisorStore)
    }

    func refreshMentionCatalog(
        for threadRef: ThreadRef?,
        localHostID: HostID,
        supervisorStore: WorkflowSupervisorStore
    ) {
        guard let threadRef, threadRef.hostID != localHostID else {
            return
        }
        refreshRemoteCatalog(hostID: threadRef.hostID, cwd: threadRef.cwd, supervisorStore: supervisorStore)
    }

    func isTargetAvailable(
        _ target: CanvasNode,
        localHostID: HostID,
        localConnectionState: HostStatus,
        supervisorStore: WorkflowSupervisorStore,
        allowsLocalRuntime: Bool
    ) -> Bool {
        let hostID = target.metadata.hostID ?? localHostID
        if hostID == localHostID {
            return allowsLocalRuntime && localConnectionState == .connected
        }
        return supervisorStore.hasRelay(for: hostID)
    }

    func createThread(
        _ request: NewThreadRequest,
        graphStore: GraphStore,
        runtimeStore: CodexRuntimeStore,
        providerRuntimeStore: AgentProviderRuntimeStore?,
        supervisorStore: WorkflowSupervisorStore,
        allowsLocalRuntime: Bool,
        localDefaultDirectory: String,
        localRuntimeUnavailableMessage: String
    ) async -> Bool {
        guard let target = graphStore.graph.nodes[request.targetNodeID] else { return false }
        guard let targetContext = resolveTarget(
            request: request,
            target: target,
            localHostID: runtimeStore.localHost.id,
            localDefaultDirectory: localDefaultDirectory
        ) else {
            return false
        }

        if request.provider != .codex,
           targetContext.hostID != runtimeStore.localHost.id {
            errorMessage = "\(request.provider.displayName) threads currently run on this Mac. Select a local machine or project."
            return false
        }

        if request.provider == .codex,
           targetContext.hostID == runtimeStore.localHost.id && !allowsLocalRuntime {
            errorMessage = localRuntimeUnavailableMessage
            return false
        }

        if request.provider == .codex,
           targetContext.hostID != runtimeStore.localHost.id,
           !supervisorStore.hasRelay(for: targetContext.hostID) {
            errorMessage = "Connect this folder's machine before creating a thread."
            return false
        }

        let createKey = pendingCreateKey(for: request, context: targetContext)
        guard !pendingCreateKeys.contains(createKey) else {
            errorMessage = "Already creating this thread."
            return false
        }
        pendingCreateKeys.insert(createKey)
        defer {
            pendingCreateKeys.remove(createKey)
        }

        do {
            let creationOutcome: ThreadCreationOutcome
            let trimmedInitialPrompt = request.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            let initialPromptExecutionText = WorkflowPromptEnvelope.escapingReservedEnvelope(
                in: trimmedInitialPrompt
            )
            switch request.provider {
            case .codex:
                if targetContext.hostID == runtimeStore.localHost.id {
                    creationOutcome = try await runtimeStore.createThread(
                        cwd: targetContext.cwd,
                        name: request.name,
                        model: request.modelID,
                        reasoningEffort: request.reasoningEffort,
                        permissions: request.permissions,
                        initialPrompt: ""
                    )
                } else {
                    creationOutcome = try await supervisorStore.createThread(
                        on: targetContext.hostID,
                        cwd: targetContext.cwd,
                        name: request.name,
                        model: request.modelID,
                        reasoningEffort: request.reasoningEffort,
                        permissions: request.permissions,
                        initialPrompt: ""
                    )
                }
            case .gemini, .grok:
                guard let providerRuntimeStore else {
                    throw AgentProviderRuntimeError.unsupportedPlatform
                }
                creationOutcome = try await providerRuntimeStore.createThread(
                    provider: request.provider,
                    hostID: targetContext.hostID,
                    cwd: targetContext.cwd,
                    name: request.name,
                    model: request.modelID,
                    reasoningEffort: request.reasoningEffort,
                    adoptProviderGeneratedTitle: request.adoptProviderGeneratedTitle
                )
            }
            let threadRef = creationOutcome.threadRef
            var partialWarnings = creationOutcome.warning.map { [$0] } ?? []

            await graphStore.addThreadNode(
                threadRef: threadRef,
                model: request.modelID,
                reasoningEffort: request.reasoningEffort,
                title: threadRef.name ?? request.name,
                anchorFolderID: targetContext.anchorFolderID,
                platform: targetContext.platform,
                permissions: request.permissions
            )

            if !trimmedInitialPrompt.isEmpty {
                do {
                    if request.provider != .codex {
                        guard let providerRuntimeStore else {
                            throw AgentProviderRuntimeError.unsupportedPlatform
                        }
                        try await providerRuntimeStore.sendMessage(
                            initialPromptExecutionText,
                            to: threadRef,
                            model: request.modelID,
                            reasoningEffort: request.reasoningEffort
                        )
                    } else if targetContext.hostID == runtimeStore.localHost.id {
                        try await runtimeStore.sendMessage(
                            initialPromptExecutionText,
                            to: threadRef,
                            model: request.modelID,
                            reasoningEffort: request.reasoningEffort,
                            permissions: request.permissions
                        )
                    } else {
                        try await supervisorStore.sendMessage(
                            initialPromptExecutionText,
                            to: threadRef,
                            model: request.modelID,
                            reasoningEffort: request.reasoningEffort,
                            permissions: request.permissions
                        )
                    }
                } catch {
                    partialWarnings.append(
                        "Thread created, but the initial prompt could not be sent: \(error.localizedDescription)"
                    )
                    errorMessage = partialWarnings.joined(separator: " ")
                    return true
                }
            }

            errorMessage = partialWarnings.isEmpty ? nil : partialWarnings.joined(separator: " ")
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func workflowMapHostIDs(in graph: AgentGraph, excludingLocalHostID localHostID: HostID? = nil) -> Set<HostID> {
        var hostIDs = Set<HostID>()

        for node in graph.nodes.values {
            switch node.kind {
            case .machine, .folder:
                if let hostID = node.metadata.hostID {
                    hostIDs.insert(hostID)
                }
            case .codexThread:
                if let hostID = node.metadata.threadRef?.hostID ?? node.metadata.hostID {
                    hostIDs.insert(hostID)
                }
            }
        }

        if let localHostID {
            hostIDs.remove(localHostID)
        }
        return hostIDs
    }

    func targetCWD(for node: CanvasNode?, localHostID: HostID, localDefaultDirectory: String? = nil) -> String? {
        guard let node else { return nil }

        switch node.kind {
        case .folder:
            return node.metadata.folderPath
        case .machine:
            return ThreadDefaultCWDResolver.defaultCWD(
                for: node,
                localHostID: localHostID,
                localDefaultDirectory: localDefaultDirectory
            )
        case .codexThread:
            return node.metadata.threadRef?.cwd
        }
    }

    private func refreshRemoteCatalog(hostID: HostID, cwd: String?, supervisorStore: WorkflowSupervisorStore) {
        guard supervisorStore.hasRelay(for: hostID) else { return }

        Task { @MainActor in
            async let modelsTask = try? supervisorStore.models(on: hostID)
            async let mentionsTask = supervisorStore.mentionCandidates(on: hostID, cwd: cwd)
            let models = await modelsTask
            let mentions = await mentionsTask

            if let models, !models.isEmpty {
                remoteModelsByHostID[hostID] = models
            }
            remoteMentionCandidatesByContext[catalogKey(hostID: hostID, cwd: cwd)] = mentions
            catalogRevision += 1
        }
    }

    private func resolveTarget(
        request: NewThreadRequest,
        target: CanvasNode,
        localHostID: HostID,
        localDefaultDirectory: String
    ) -> ThreadTargetContext? {
        switch request.targetKind {
        case .folder:
            guard let folderPath = target.metadata.folderPath else {
                errorMessage = "The selected folder is missing a path."
                return nil
            }
            return ThreadTargetContext(
                cwd: folderPath,
                hostID: target.metadata.hostID ?? localHostID,
                platform: target.metadata.platform ?? .unknown,
                anchorFolderID: target.id
            )
        case .machine:
            guard let machineHostID = target.metadata.hostID else {
                errorMessage = "The selected machine is missing a host id."
                return nil
            }
            guard let machineCWD = ThreadDefaultCWDResolver.defaultCWD(
                for: target,
                localHostID: localHostID,
                localDefaultDirectory: localDefaultDirectory
            ) else {
                errorMessage = "The selected machine is missing a default folder."
                return nil
            }
            return ThreadTargetContext(
                cwd: machineCWD,
                hostID: machineHostID,
                platform: target.metadata.platform ?? .unknown,
                anchorFolderID: nil
            )
        }
    }

    private func remoteHostID(for target: CanvasNode?, localHostID: HostID) -> HostID? {
        guard let hostID = target?.metadata.hostID,
              hostID != localHostID else {
            return nil
        }
        return hostID
    }

    private func catalogKey(hostID: HostID, cwd: String?) -> String {
        "\(hostID.rawValue)|\(cwd ?? "")"
    }

    private func pendingCreateKey(for request: NewThreadRequest, context: ThreadTargetContext) -> String {
        [
            request.targetKind.rawValue,
            request.provider.rawValue,
            context.hostID.rawValue,
            context.cwd,
            request.name.trimmingCharacters(in: .whitespacesAndNewlines),
            request.modelID,
            request.reasoningEffort,
            request.permissions.approvalPolicy.rawValue,
            request.permissions.sandboxMode.rawValue,
            request.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            request.adoptProviderGeneratedTitle ? "provider-title" : "map-title",
        ].joined(separator: "\u{1F}")
    }
}

private struct ThreadTargetContext {
    var cwd: String
    var hostID: HostID
    var platform: HostPlatform
    var anchorFolderID: NodeID?
}
