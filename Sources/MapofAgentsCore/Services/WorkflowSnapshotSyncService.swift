import Foundation

public enum WorkflowSnapshotSyncError: LocalizedError, Sendable {
    case missingRemoteSupportDirectory
    case missingActiveWorkflow
    case corruptRemoteState(String)

    public var errorDescription: String? {
        switch self {
        case .missingRemoteSupportDirectory:
            return "Could not determine the remote mapofagents support directory."
        case .missingActiveWorkflow:
            return "The remote workflow snapshot is missing its active workflow canvas."
        case .corruptRemoteState(let path):
            return "The remote workflow snapshot contains invalid JSON at \(path)."
        }
    }
}

public enum WorkflowSnapshotSyncService {
    public static func remoteMacSupportDirectory(
        mapofagentsSupportDirectory: String?,
        codexHome: String? = nil
    ) -> String? {
        if let supportDirectory = normalizedRemotePath(mapofagentsSupportDirectory) {
            return supportDirectory
        }

        return remoteMacSupportDirectory(codexHome: codexHome)
    }

    public static func remoteMacSupportDirectory(codexHome: String?) -> String? {
        guard let codexHome, !codexHome.isEmpty else {
            return nil
        }

        let normalized = codexHome.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = normalized.split(separator: "/").map(String.init)

        if components.last == ".codex", components.count > 1 {
            let home = "/" + components.dropLast().joined(separator: "/")
            return "\(home)/Library/Application Support/\(ApplicationPaths.supportDirectoryName)"
        }

        return nil
    }

    public static func loadSnapshot(
        pairedHost: MapofAgentsPairedHost,
        codexHome: String? = nil,
        includeRelayEndpoints: Bool = true,
        readFile: @escaping @Sendable (String) async throws -> Data
    ) async throws -> WorkflowSnapshot {
        guard let supportDirectory = remoteMacSupportDirectory(
            mapofagentsSupportDirectory: pairedHost.mapofagentsSupportDirectory,
            codexHome: codexHome
        ) else {
            throw WorkflowSnapshotSyncError.missingRemoteSupportDirectory
        }

        return try await loadSnapshot(
            supportDirectory: supportDirectory,
            includeRelayEndpoints: includeRelayEndpoints,
            readFile: readFile
        )
    }

    public static func loadSnapshot(
        supportDirectory: String,
        includeRelayEndpoints: Bool = true,
        readFile: @escaping @Sendable (String) async throws -> Data
    ) async throws -> WorkflowSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let libraryData = try await readFile(join(supportDirectory, "workflows/library.json"))
        let library = try decoder.decode(WorkflowLibrarySnapshot.self, from: libraryData)
        try library.validateWorkflowIDs()

        var graphsByWorkflowID: [String: AgentGraph] = [:]
        for workflow in library.workflows {
            let filename = "\(ApplicationPaths.safeFileComponent(workflow.id)).json"
            let path = join(supportDirectory, "workflows/\(filename)")
            do {
                let data = try await readFile(path)
                graphsByWorkflowID[workflow.id] = try decoder.decode(AgentGraph.self, from: data)
            } catch {
                let legacyFilename = "\(ApplicationPaths.legacySafeFileComponent(workflow.id)).json"
                let legacyPath = join(supportDirectory, "workflows/\(legacyFilename)")
                if legacyPath != path,
                   let data = try? await readFile(legacyPath),
                   let graph = try? decoder.decode(AgentGraph.self, from: data) {
                    graphsByWorkflowID[workflow.id] = graph
                } else {
                    if workflow.id == library.activeWorkflowID {
                        throw WorkflowSnapshotSyncError.missingActiveWorkflow
                    }
                    throw WorkflowSnapshotIntegrityError.missingWorkflowGraph(workflow.id)
                }
            }
        }

        let workflowEventsPath = join(supportDirectory, "workflow-events.json")
        let workflowEvents: [WorkflowEvent] = try await decodeOptionalSnapshotFile(
            path: workflowEventsPath,
            decoder: decoder,
            readFile: readFile
        ) ?? []

        let relayEndpoints: [AppServerRelayEndpoint]
        if includeRelayEndpoints {
            let relayEndpointsPath = join(supportDirectory, "relay-endpoints.json")
            relayEndpoints = try await decodeOptionalSnapshotFile(
                path: relayEndpointsPath,
                decoder: decoder,
                readFile: readFile
            ) ?? []
        } else {
            relayEndpoints = []
        }

        let snapshot = WorkflowSnapshot(
            library: library,
            graphsByWorkflowID: graphsByWorkflowID,
            workflowEvents: workflowEvents,
            relayEndpoints: relayEndpoints
        )
        try snapshot.validateForActivation()
        return snapshot
    }

    private static func decodeOptionalSnapshotFile<T: Decodable>(
        path: String,
        decoder: JSONDecoder,
        readFile: @escaping @Sendable (String) async throws -> Data
    ) async throws -> T? {
        let data: Data
        do {
            data = try await readFile(path)
        } catch {
            return nil
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WorkflowSnapshotSyncError.corruptRemoteState(path)
        }
    }

    private static func normalizedRemotePath(_ path: String?) -> String? {
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty else {
            return nil
        }

        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "/" : "/\(trimmed)"
    }

    private static func join(_ base: String, _ component: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedComponent = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "/\(trimmedBase)/\(trimmedComponent)"
    }
}
