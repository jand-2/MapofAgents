import Foundation

public enum WorkflowSnapshotReadFailureKind: Sendable {
    case notFound
    case authorizationDenied
    case timedOut
    case transport
}

public protocol WorkflowSnapshotReadErrorCategorizing: Error {
    var workflowSnapshotReadFailureKind: WorkflowSnapshotReadFailureKind { get }
}

public enum WorkflowSnapshotSyncError: LocalizedError, Sendable {
    case missingRemoteSupportDirectory
    case missingRequiredFile(String)
    case missingActiveWorkflow
    case authorizationDenied(String)
    case timedOut(String)
    case transportFailure(path: String, message: String)
    case corruptRemoteState(String)
    case unsupportedSnapshotFormat(Int)

    public var errorDescription: String? {
        switch self {
        case .missingRemoteSupportDirectory:
            return "Could not determine the remote mapofagents support directory."
        case .missingRequiredFile(let path):
            return "The remote workflow snapshot is missing a required file at \(path)."
        case .missingActiveWorkflow:
            return "The remote workflow snapshot is missing its active workflow canvas."
        case .authorizationDenied(let path):
            return "The remote host denied access to the workflow snapshot file at \(path)."
        case .timedOut(let path):
            return "Reading the remote workflow snapshot timed out at \(path)."
        case .transportFailure(let path, let message):
            return "Could not read the remote workflow snapshot at \(path): \(message)"
        case .corruptRemoteState(let path):
            return "The remote workflow snapshot contains invalid data at \(path)."
        case .unsupportedSnapshotFormat(let version):
            return "The remote workflow snapshot uses unsupported format version \(version)."
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

        let pointerPath = join(supportDirectory, "workflow-snapshots/current.json")
        let stateDirectory: String
        if let pointerData = try await readOptionalFile(path: pointerPath, readFile: readFile) {
            let pointer: WorkflowSnapshotPointer = try decode(
                WorkflowSnapshotPointer.self,
                from: pointerData,
                path: pointerPath,
                decoder: decoder
            )
            do {
                try pointer.validate()
            } catch WorkflowSnapshotPersistenceError.unsupportedFormatVersion(let version) {
                throw WorkflowSnapshotSyncError.unsupportedSnapshotFormat(version)
            } catch {
                throw WorkflowSnapshotSyncError.corruptRemoteState(pointerPath)
            }

            stateDirectory = join(
                supportDirectory,
                "workflow-snapshots/\(pointer.activeSnapshotID)"
            )
            let metadataPath = join(stateDirectory, "metadata.json")
            let metadataData = try await readRequiredFile(path: metadataPath, readFile: readFile)
            let metadata: WorkflowSnapshotMetadata = try decode(
                WorkflowSnapshotMetadata.self,
                from: metadataData,
                path: metadataPath,
                decoder: decoder
            )
            do {
                try metadata.validate(expectedSnapshotID: pointer.activeSnapshotID)
            } catch WorkflowSnapshotPersistenceError.unsupportedFormatVersion(let version) {
                throw WorkflowSnapshotSyncError.unsupportedSnapshotFormat(version)
            } catch {
                throw WorkflowSnapshotSyncError.corruptRemoteState(metadataPath)
            }
        } else {
            stateDirectory = supportDirectory
        }

        return try await loadSnapshot(
            stateDirectory: stateDirectory,
            includeRelayEndpoints: includeRelayEndpoints,
            decoder: decoder,
            readFile: readFile
        )
    }

    private static func loadSnapshot(
        stateDirectory: String,
        includeRelayEndpoints: Bool,
        decoder: JSONDecoder,
        readFile: @escaping @Sendable (String) async throws -> Data
    ) async throws -> WorkflowSnapshot {
        let libraryPath = join(stateDirectory, "workflows/library.json")
        let libraryData = try await readRequiredFile(path: libraryPath, readFile: readFile)
        let library: WorkflowLibrarySnapshot = try decode(
            WorkflowLibrarySnapshot.self,
            from: libraryData,
            path: libraryPath,
            decoder: decoder
        )
        try library.validateWorkflowIDs()

        var graphsByWorkflowID: [String: AgentGraph] = [:]
        for workflow in library.workflows {
            let filename = "\(ApplicationPaths.safeFileComponent(workflow.id)).json"
            let path = join(stateDirectory, "workflows/\(filename)")
            var graphData = try await readOptionalFile(path: path, readFile: readFile)
            var resolvedPath = path

            if graphData == nil {
                let legacyFilename = "\(ApplicationPaths.legacySafeFileComponent(workflow.id)).json"
                let legacyPath = join(stateDirectory, "workflows/\(legacyFilename)")
                if legacyPath != path {
                    graphData = try await readOptionalFile(path: legacyPath, readFile: readFile)
                    resolvedPath = legacyPath
                }
            }

            guard let graphData else {
                if workflow.id == library.activeWorkflowID {
                    throw WorkflowSnapshotSyncError.missingActiveWorkflow
                }
                throw WorkflowSnapshotIntegrityError.missingWorkflowGraph(workflow.id)
            }
            graphsByWorkflowID[workflow.id] = try decode(
                AgentGraph.self,
                from: graphData,
                path: resolvedPath,
                decoder: decoder
            )
        }

        let workflowEventsPath = join(stateDirectory, "workflow-events.json")
        let workflowEvents: [WorkflowEvent] = try await decodeOptionalSnapshotFile(
            path: workflowEventsPath,
            decoder: decoder,
            readFile: readFile
        ) ?? []

        let relayEndpoints: [AppServerRelayEndpoint]
        if includeRelayEndpoints {
            let relayEndpointsPath = join(stateDirectory, "relay-endpoints.json")
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
        guard let data = try await readOptionalFile(path: path, readFile: readFile) else {
            return nil
        }
        return try decode(T.self, from: data, path: path, decoder: decoder)
    }

    private static func readRequiredFile(
        path: String,
        readFile: @escaping @Sendable (String) async throws -> Data
    ) async throws -> Data {
        guard let data = try await readOptionalFile(path: path, readFile: readFile) else {
            throw WorkflowSnapshotSyncError.missingRequiredFile(path)
        }
        return data
    }

    private static func readOptionalFile(
        path: String,
        readFile: @escaping @Sendable (String) async throws -> Data
    ) async throws -> Data? {
        do {
            return try await readFile(path)
        } catch {
            switch readFailureKind(for: error) {
            case .notFound:
                return nil
            case .authorizationDenied:
                throw WorkflowSnapshotSyncError.authorizationDenied(path)
            case .timedOut:
                throw WorkflowSnapshotSyncError.timedOut(path)
            case .transport:
                throw WorkflowSnapshotSyncError.transportFailure(
                    path: path,
                    message: error.localizedDescription
                )
            }
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        path: String,
        decoder: JSONDecoder
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw WorkflowSnapshotSyncError.corruptRemoteState(path)
        }
    }

    private static func readFailureKind(for error: Error) -> WorkflowSnapshotReadFailureKind {
        if let categorized = error as? any WorkflowSnapshotReadErrorCategorizing {
            return categorized.workflowSnapshotReadFailureKind
        }

        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .timedOut
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case CocoaError.fileNoSuchFile.rawValue,
                 CocoaError.fileReadNoSuchFile.rawValue:
                return .notFound
            case CocoaError.fileReadNoPermission.rawValue,
                 CocoaError.fileWriteNoPermission.rawValue:
                return .authorizationDenied
            default:
                break
            }
        }

        if case .daemonProxyRequestTimedOut = error as? CodexAppServerError {
            return .timedOut
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("enoent") || message.contains("no such file") || message.contains("not found") {
            return .notFound
        }
        if message.contains("eacces") || message.contains("permission denied") || message.contains("unauthorized") {
            return .authorizationDenied
        }
        if message.contains("timed out") || message.contains("timeout") {
            return .timedOut
        }
        return .transport
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
