#if os(iOS)
import MapofAgentsCore
import Foundation
import Observation

@MainActor
@Observable
final class IPhonePairingCoordinator {
    struct PendingPairingApproval: Identifiable {
        let id = UUID()
        let payload: MapofAgentsPairingPayload
        let sourceDescription: String

        var title: String {
            payload.name.isEmpty ? "Paired Mac" : payload.name
        }

        var endpointSummary: String {
            payload.preferredEndpoints
                .prefix(3)
                .map { $0.url.absoluteString }
                .joined(separator: "\n")
        }
    }

    var pairedHost: MapofAgentsPairedHost?
    var pendingPairingApproval: PendingPairingApproval?
    var isConnectingPairedHost = false
    var syncMessage: String?
    var errorMessage: String?

    private var didAttemptLaunchConfiguredRemote = false
    private let storedHostKey: String
    private let userDefaults: UserDefaults

    init(
        storedHostKey: String = "mapofagents.primaryPairedHost",
        userDefaults: UserDefaults = .standard
    ) {
        self.storedHostKey = storedHostKey
        self.userDefaults = userDefaults
    }

    func loadStoredPairedHost() {
        let encoded = storedPairedHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !encoded.isEmpty else {
            pairedHost = nil
            return
        }
        let decoded: MapofAgentsPairedHost
        do {
            decoded = try MapofAgentsPairedHost.decode(from: encoded)
        } catch {
            pairedHost = nil
            errorMessage = "Saved pairing could not be read: \(error.localizedDescription)"
            return
        }

        do {
            pairedHost = try pairedHostWithResolvedToken(decoded)
        } catch {
            pairedHost = decoded
            errorMessage = "Could not secure the saved paired Mac token: \(error.localizedDescription)"
        }
    }

    func connectRemote(
        name: String,
        endpoint: String,
        bearerToken: String?,
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) {
        let endpointURL: URL
        do {
            endpointURL = try validatedIPhoneEndpoint(endpoint)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        Task {
            syncMessage = "Connecting to \(name)..."
            let hostID = await supervisorStore.connectRemote(
                name: name,
                endpoint: endpointURL.absoluteString,
                bearerToken: bearerToken
            )
            await graphStore.applySupervisorMachines(supervisorStore.machines)
            await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)

            guard let hostID,
                  let machine = supervisorStore.machines.first(where: { $0.id == hostID }),
                  machine.status == .connected else {
                syncMessage = nil
                errorMessage = "Could not connect to \(endpointURL.absoluteString)."
                return
            }

            if machine.platform == .macOS || machine.name.localizedCaseInsensitiveContains("mac") {
                _ = await syncWorkflowFromMac(hostID, nil)
            } else {
                syncMessage = "Connected to \(machine.name)."
                errorMessage = nil
            }
        }
    }

    func connectLaunchConfiguredRemoteIfNeeded(
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) async {
        guard !didAttemptLaunchConfiguredRemote else { return }
        didAttemptLaunchConfiguredRemote = true

        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["MAPOFAGENTS_REMOTE_ENDPOINT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !endpoint.isEmpty else {
            let storedHost = storedPairedHost.trimmingCharacters(in: .whitespacesAndNewlines)
            if !storedHost.isEmpty {
                await connectStoredPairedHost(
                    storedHost,
                    graphStore: graphStore,
                    supervisorStore: supervisorStore,
                    syncWorkflowFromMac: syncWorkflowFromMac
                )
            }
            return
        }

        let name = environment["MAPOFAGENTS_REMOTE_NAME"] ?? "mac-host.lan"
        let token = environment["MAPOFAGENTS_REMOTE_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldLoadWorkflow = environment["MAPOFAGENTS_AUTO_LOAD_WORKFLOW"] != "0"

        let endpointURL: URL
        do {
            endpointURL = try validatedIPhoneEndpoint(endpoint)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        syncMessage = "Connecting to \(name)..."
        let hostID = await supervisorStore.connectRemote(
            name: name,
            endpoint: endpointURL.absoluteString,
            bearerToken: token?.isEmpty == false ? token : nil
        )
        await graphStore.applySupervisorMachines(supervisorStore.machines)
        await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)

        guard let hostID else {
            syncMessage = nil
            errorMessage = "Could not connect to \(endpointURL.absoluteString)."
            return
        }

        if shouldLoadWorkflow {
            _ = await syncWorkflowFromMac(hostID, nil)
        } else {
            syncMessage = "Connected to \(name)."
            errorMessage = nil
        }
    }

    func connectPairingCode(
        _ code: String,
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) {
        Task {
            await connectPairingString(
                code,
                graphStore: graphStore,
                supervisorStore: supervisorStore,
                syncWorkflowFromMac: syncWorkflowFromMac
            )
        }
    }

    func preparePairingURL(_ url: URL) {
        do {
            let payload = try MapofAgentsPairingPayload.decode(from: url)
            try payload.validateForImport()
            pendingPairingApproval = PendingPairingApproval(
                payload: payload,
                sourceDescription: url.absoluteString
            )
            errorMessage = nil
        } catch {
            pendingPairingApproval = nil
            errorMessage = error.localizedDescription
        }
    }

    func cancelPendingPairingApproval() {
        pendingPairingApproval = nil
    }

    func approvePendingPairingURL(
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) {
        guard let pendingPairingApproval else { return }
        let payload = pendingPairingApproval.payload
        self.pendingPairingApproval = nil

        Task {
            do {
                try await connectPairingPayload(
                    payload,
                    graphStore: graphStore,
                    supervisorStore: supervisorStore,
                    syncWorkflowFromMac: syncWorkflowFromMac
                )
            } catch {
                syncMessage = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func reconnectPairedHost(
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) {
        guard let pairedHost else { return }
        Task {
            do {
                try await connectPairedHost(
                    pairedHost,
                    syncWorkflow: true,
                    graphStore: graphStore,
                    supervisorStore: supervisorStore,
                    syncWorkflowFromMac: syncWorkflowFromMac
                )
            } catch {
                syncMessage = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshPairedConnectionIfNeeded(
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore
    ) async {
        guard let pairedHost else { return }
        do {
            try await connectPairedHost(
                pairedHost,
                syncWorkflow: false,
                graphStore: graphStore,
                supervisorStore: supervisorStore,
                syncWorkflowFromMac: { _, _ in true }
            )
        } catch {
            syncMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    func forgetPairing(disconnect: (HostID) -> Void) {
        guard let host = pairedHost else {
            storedPairedHost = ""
            return
        }
        do {
            try MapofAgentsPairingTokenVault.delete(for: host.id)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        pairedHost = nil
        storedPairedHost = ""
        syncMessage = nil
        errorMessage = nil
        disconnect(host.id)
    }

    private func connectPairingString(
        _ code: String,
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) async {
        do {
            let payload = try MapofAgentsPairingPayload.decode(from: code)
            try await connectPairingPayload(
                payload,
                graphStore: graphStore,
                supervisorStore: supervisorStore,
                syncWorkflowFromMac: syncWorkflowFromMac
            )
        } catch {
            syncMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func connectPairingPayload(
        _ payload: MapofAgentsPairingPayload,
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) async throws {
        try payload.validateForImport()
        let pairedHost = MapofAgentsPairedHost(payload: payload)

        try await connectPairedHost(
            pairedHost,
            syncWorkflow: true,
            graphStore: graphStore,
            supervisorStore: supervisorStore,
            syncWorkflowFromMac: syncWorkflowFromMac
        )
    }

    private func connectStoredPairedHost(
        _ encoded: String,
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) async {
        do {
            let pairedHost = try pairedHostWithResolvedToken(try MapofAgentsPairedHost.decode(from: encoded))
            self.pairedHost = pairedHost
            try await connectPairedHost(
                pairedHost,
                syncWorkflow: true,
                graphStore: graphStore,
                supervisorStore: supervisorStore,
                syncWorkflowFromMac: syncWorkflowFromMac
            )
        } catch {
            syncMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func connectPairedHost(
        _ pairedHost: MapofAgentsPairedHost,
        syncWorkflow: Bool,
        graphStore: GraphStore,
        supervisorStore: WorkflowSupervisorStore,
        syncWorkflowFromMac: @escaping (HostID, MapofAgentsPairedHost?) async -> Bool
    ) async throws {
        guard !isConnectingPairedHost else { return }
        var workingHost = pairedHost
        var validationFailures: [String] = []
        let endpoints = workingHost.preferredEndpoints
            .compactMap { endpoint -> MapofAgentsPairingEndpoint? in
                do {
                    _ = try validatedIPhoneEndpoint(endpoint.url.absoluteString)
                    return endpoint
                } catch {
                    validationFailures.append("\(endpoint.url.absoluteString): \(error.localizedDescription)")
                    return nil
                }
            }
        guard !endpoints.isEmpty else {
            throw IPhoneEndpointValidationError.noUsablePairedEndpoints(validationFailures.first)
        }

        isConnectingPairedHost = true
        syncMessage = "Connecting to \(workingHost.name)..."
        errorMessage = nil
        defer { isConnectingPairedHost = false }

        var lastFailure: String?
        var syncFailureCount = 0
        for endpoint in endpoints {
            syncMessage = "Connecting to \(workingHost.name) via \(endpoint.kind.rawValue)..."
            errorMessage = nil
            let hostID = await supervisorStore.connectRemote(
                id: workingHost.id,
                name: workingHost.name,
                endpoint: endpoint.url.absoluteString,
                bearerToken: workingHost.bearerToken,
                markFailureOnFailure: false
            )
            await graphStore.applySupervisorMachines(supervisorStore.machines)
            await supervisorStore.updateWorkflowThreads(graphStore.workflowThreadRefs)

            if let hostID,
               let machine = supervisorStore.machines.first(where: { $0.id == hostID }),
               machine.status == .connected {
                if !syncWorkflow {
                    workingHost.recordSuccessfulConnection(to: endpoint)
                    try persistPairedHost(workingHost)
                    syncMessage = "Connected to \(machine.name)."
                    errorMessage = nil
                    return
                }

                if await syncWorkflowFromMac(hostID, workingHost) {
                    workingHost.recordSuccessfulConnection(to: endpoint)
                    try persistPairedHost(workingHost)
                    syncMessage = "Loaded workflows from \(machine.name)."
                    return
                }

                syncFailureCount += 1
                let syncFailure = errorMessage ?? "Workflow sync failed."
                lastFailure = "Connected to \(endpoint.url.absoluteString), but \(syncFailure)"
                workingHost.recordConnectionFailure(to: endpoint, message: lastFailure ?? "Workflow sync failed.")
                try persistPairedHost(workingHost)
                await supervisorStore.recordRelayEndpointAttemptFailure(hostID: workingHost.id, message: lastFailure ?? "Workflow sync failed.")
                await graphStore.applySupervisorMachines(supervisorStore.machines)
                errorMessage = nil
                continue
            }

            lastFailure = "Could not connect to \(endpoint.url.absoluteString)."
            workingHost.recordConnectionFailure(to: endpoint, message: lastFailure ?? "Connection failed.")
            try persistPairedHost(workingHost)
        }

        let failureSummary: String
        if syncFailureCount > 0 {
            failureSummary = lastFailure.map {
                "Connected to \(workingHost.name), but workflow sync failed on \(syncFailureCount) endpoint\(syncFailureCount == 1 ? "" : "s"). Last error: \($0)"
            } ?? "Connected to \(workingHost.name), but workflow sync failed."
        } else {
            failureSummary = lastFailure.map {
                "Could not connect to \(workingHost.name) using \(endpoints.count) endpoint\(endpoints.count == 1 ? "" : "s"). Last error: \($0)"
            } ?? "Could not connect to \(workingHost.name)."
        }

        if lastFailure != nil {
            await supervisorStore.recordRelayEndpointAttemptFailure(hostID: workingHost.id, message: failureSummary)
            await graphStore.applySupervisorMachines(supervisorStore.machines)
        }
        syncMessage = nil
        errorMessage = failureSummary
    }

    private var storedPairedHost: String {
        get { userDefaults.string(forKey: storedHostKey) ?? "" }
        set { userDefaults.set(newValue, forKey: storedHostKey) }
    }

    private func persistPairedHost(_ host: MapofAgentsPairedHost) throws {
        var upgradedHost = host
        upgradedHost.persistenceVersion = MapofAgentsPairedHost.currentPersistenceVersion
        try MapofAgentsPairingTokenVault.save(upgradedHost.bearerToken, for: upgradedHost.id)
        var storedHost = upgradedHost
        storedHost.bearerToken = ""
        storedPairedHost = try storedHost.encodedString()
        pairedHost = upgradedHost
    }

    private func pairedHostWithResolvedToken(_ host: MapofAgentsPairedHost) throws -> MapofAgentsPairedHost {
        guard host.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try MapofAgentsPairingTokenVault.save(host.bearerToken, for: host.id)
            return host
        }

        var resolved = host
        resolved.bearerToken = MapofAgentsPairingTokenVault.load(for: host.id) ?? ""
        return resolved
    }

    private func validatedIPhoneEndpoint(_ endpoint: String) throws -> URL {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw IPhoneEndpointValidationError.empty
        }

        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let url = components.url else {
            throw IPhoneEndpointValidationError.absoluteWebSocketRequired
        }

        guard scheme == "ws" || scheme == "wss" else {
            throw IPhoneEndpointValidationError.unsupportedScheme(scheme)
        }

        guard let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              url.host != nil else {
            throw IPhoneEndpointValidationError.missingHost
        }

        guard MapofAgentsPairingEndpoint.isSecureIPhoneCompanionEndpoint(url) else {
            if MapofAgentsPairingEndpoint.isCleartextIPAddressEndpoint(url) {
                throw IPhoneEndpointValidationError.cleartextIPAddress
            }
            throw IPhoneEndpointValidationError.insecureRemoteEndpoint
        }

        return url
    }
}

private enum IPhoneEndpointValidationError: LocalizedError {
    case empty
    case absoluteWebSocketRequired
    case unsupportedScheme(String)
    case missingHost
    case cleartextIPAddress
    case insecureRemoteEndpoint
    case noUsablePairedEndpoints(String?)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Enter an absolute ws:// or wss:// App Server endpoint."
        case .absoluteWebSocketRequired:
            return "Enter an absolute ws:// or wss:// App Server URL, for example ws://mac-mini.tailnet.ts.net:18945."
        case .unsupportedScheme(let scheme):
            return "Use ws:// or wss:// for remote App Server endpoints. \(scheme):// is not supported."
        case .missingHost:
            return "Remote App Server endpoints must include a host name."
        case .cleartextIPAddress:
            return MapofAgentsPairingError.cleartextIPAddressEndpointRequiresDNSName.localizedDescription
        case .insecureRemoteEndpoint:
            return MapofAgentsPairingError.insecureRemoteEndpointRequiresTLS.localizedDescription
        case .noUsablePairedEndpoints(let detail):
            if let detail {
                return "The paired Mac does not have a usable iPhone endpoint. \(detail)"
            }
            return "The paired Mac does not have a usable iPhone endpoint."
        }
    }
}
#endif
