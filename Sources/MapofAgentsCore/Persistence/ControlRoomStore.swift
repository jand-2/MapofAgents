import Foundation
import OSLog

public enum CanvasPatch: Sendable {
    case replace(AgentGraph)
    case upsertNode(CanvasNode)
    case removeNode(NodeID)
    case moveNode(NodeID, CanvasPoint)
    case updateViewport(CanvasViewport)
    case upsertManualEdge(CanvasEdge)
    case removeManualEdge(EdgeID)
    case upsertMessageRoute(MessageRoute)
}

public protocol ControlRoomStore: Sendable {
    func loadCanvas() async throws -> AgentGraph
    func applyCanvasPatch(_ patch: CanvasPatch) async throws -> AgentGraph
    func loadWorkflowEvents() async throws -> [WorkflowEvent]
    func saveWorkflowEvents(_ events: [WorkflowEvent]) async throws
    func loadRelayEndpoints() async throws -> [AppServerRelayEndpoint]
    func saveRelayEndpoints(_ endpoints: [AppServerRelayEndpoint]) async throws
    func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript?
    func saveTranscript(_ transcript: ThreadTranscript) async throws
}

public struct WorkflowRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct WorkflowLibrarySnapshot: Codable, Hashable, Sendable {
    public var activeWorkflowID: String
    public var workflows: [WorkflowRecord]

    public init(activeWorkflowID: String, workflows: [WorkflowRecord]) {
        self.activeWorkflowID = activeWorkflowID
        self.workflows = workflows
    }
}

public enum WorkflowSnapshotIntegrityError: LocalizedError, Equatable, Sendable {
    case emptyWorkflowLibrary
    case duplicateWorkflowID(String)
    case missingActiveWorkflow(String)
    case missingWorkflowGraph(String)

    public var errorDescription: String? {
        switch self {
        case .emptyWorkflowLibrary:
            return "The workflow snapshot does not contain any workflows."
        case .duplicateWorkflowID(let id):
            return "The workflow snapshot contains duplicate workflow ID '\(id)'."
        case .missingActiveWorkflow(let id):
            return "The workflow snapshot is missing its active workflow '\(id)'."
        case .missingWorkflowGraph(let id):
            return "The workflow snapshot is missing the canvas for workflow '\(id)'."
        }
    }
}

public struct WorkflowSnapshotPointer: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var activeSnapshotID: String
    public var rollbackSnapshotIDs: [String]

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        activeSnapshotID: String,
        rollbackSnapshotIDs: [String] = []
    ) {
        self.formatVersion = formatVersion
        self.activeSnapshotID = activeSnapshotID
        self.rollbackSnapshotIDs = rollbackSnapshotIDs
    }

    public func validate() throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw WorkflowSnapshotPersistenceError.unsupportedFormatVersion(formatVersion)
        }
        guard ApplicationPaths.isSafeSnapshotID(activeSnapshotID),
              rollbackSnapshotIDs.allSatisfy(ApplicationPaths.isSafeSnapshotID) else {
            throw WorkflowSnapshotPersistenceError.invalidManifest
        }
    }
}

public struct WorkflowSnapshotMetadata: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var snapshotID: String
    public var createdAt: Date

    public init(
        formatVersion: Int = Self.currentFormatVersion,
        snapshotID: String,
        createdAt: Date = Date()
    ) {
        self.formatVersion = formatVersion
        self.snapshotID = snapshotID
        self.createdAt = createdAt
    }

    public func validate(expectedSnapshotID: String) throws {
        guard formatVersion == Self.currentFormatVersion else {
            throw WorkflowSnapshotPersistenceError.unsupportedFormatVersion(formatVersion)
        }
        guard snapshotID == expectedSnapshotID,
              ApplicationPaths.isSafeSnapshotID(snapshotID) else {
            throw WorkflowSnapshotPersistenceError.invalidSnapshotMetadata
        }
    }
}

public enum WorkflowSnapshotPersistenceError: LocalizedError, Equatable, Sendable {
    case invalidManifest
    case invalidSnapshotMetadata
    case unsupportedFormatVersion(Int)
    case noRollbackAvailable

    public var errorDescription: String? {
        switch self {
        case .invalidManifest:
            return "The workflow snapshot pointer is invalid."
        case .invalidSnapshotMetadata:
            return "The workflow snapshot metadata does not match the selected snapshot."
        case .unsupportedFormatVersion(let version):
            return "Workflow snapshot format version \(version) is not supported."
        case .noRollbackAvailable:
            return "There is no previous workflow snapshot to restore."
        }
    }
}

public enum WorkflowSnapshotCommitStep: Equatable, Sendable {
    case metadata
    case library
    case workflowGraph(String)
    case workflowEvents
    case relayEndpoints
    case activatePointer
}

public struct WorkflowSnapshot: Codable, Hashable, Sendable {
    public var library: WorkflowLibrarySnapshot
    public var graphsByWorkflowID: [String: AgentGraph]
    public var workflowEvents: [WorkflowEvent]
    public var relayEndpoints: [AppServerRelayEndpoint]

    public init(
        library: WorkflowLibrarySnapshot,
        graphsByWorkflowID: [String: AgentGraph],
        workflowEvents: [WorkflowEvent] = [],
        relayEndpoints: [AppServerRelayEndpoint] = []
    ) {
        self.library = library
        self.graphsByWorkflowID = graphsByWorkflowID
        self.workflowEvents = workflowEvents
        self.relayEndpoints = relayEndpoints
    }

    public func replacingLocalHost(with hostID: HostID, machineName: String? = nil) -> WorkflowSnapshot {
        let rewrittenGraphs = graphsByWorkflowID.mapValues { graph in
            graph.replacingLocalHost(with: hostID, machineName: machineName)
        }
        let rewrittenEvents = workflowEvents.map { event in
            guard event.hostID == HostID(rawValue: "local") else { return event }
            var rewritten = event
            rewritten.hostID = hostID
            return rewritten
        }
        return WorkflowSnapshot(
            library: library,
            graphsByWorkflowID: rewrittenGraphs,
            workflowEvents: rewrittenEvents,
            relayEndpoints: relayEndpoints
        )
    }

    public func validateForActivation() throws {
        try library.validateWorkflowIDs()

        guard library.workflows.contains(where: { $0.id == library.activeWorkflowID }) else {
            throw WorkflowSnapshotIntegrityError.missingActiveWorkflow(library.activeWorkflowID)
        }

        for workflow in library.workflows where graphsByWorkflowID[workflow.id] == nil {
            throw WorkflowSnapshotIntegrityError.missingWorkflowGraph(workflow.id)
        }
    }

    /// Connection-bound approval and diagnostic state is useful only while its
    /// originating runtime session is alive. Do not copy it into durable graph
    /// snapshots, where request payloads may also contain commands or user input.
    public func sanitizingEphemeralRuntimeState() -> WorkflowSnapshot {
        var sanitized = self
        sanitized.graphsByWorkflowID = graphsByWorkflowID.mapValues { graph in
            var graph = graph
            graph.pendingAttentionRequests = []
            graph.runtimeDiagnostics = []
            graph.nodes = graph.nodes.mapValues { node in
                var node = node
                node.metadata.hostLastError = nil
                node.metadata.appServerEndpointURL = nil
                return node
            }
            return graph
        }
        return sanitized
    }
}

public extension WorkflowLibrarySnapshot {
    func validateWorkflowIDs() throws {
        guard !workflows.isEmpty else {
            throw WorkflowSnapshotIntegrityError.emptyWorkflowLibrary
        }

        var seen = Set<String>()
        for workflow in workflows {
            guard seen.insert(workflow.id).inserted else {
                throw WorkflowSnapshotIntegrityError.duplicateWorkflowID(workflow.id)
            }
        }
    }
}

public struct ApplicationPaths: Sendable {
    public static let supportDirectoryName = "mapofagents"

    public var applicationSupportDirectory: URL

    public init(applicationSupportDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
    }

    public var canvasURL: URL {
        applicationSupportDirectory.appendingPathComponent("canvas.json")
    }

    public var workflowsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("workflows", isDirectory: true)
    }

    public var workflowSnapshotsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("workflow-snapshots", isDirectory: true)
    }

    public var workflowSnapshotPointerURL: URL {
        workflowSnapshotsDirectory.appendingPathComponent("current.json")
    }

    public func workflowSnapshotDirectory(for snapshotID: String) -> URL {
        workflowSnapshotsDirectory.appendingPathComponent(snapshotID, isDirectory: true)
    }

    public var workflowLibraryURL: URL {
        workflowsDirectory.appendingPathComponent("library.json")
    }

    public func workflowCanvasURL(for workflowID: String) -> URL {
        workflowsDirectory.appendingPathComponent("\(Self.safeFileComponent(workflowID)).json")
    }

    public func legacyWorkflowCanvasURL(for workflowID: String) -> URL {
        workflowsDirectory.appendingPathComponent("\(Self.legacySafeFileComponent(workflowID)).json")
    }

    public func workflowCanvasReadURL(for workflowID: String) -> URL {
        let primary = workflowCanvasURL(for: workflowID)
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }

        let legacy = legacyWorkflowCanvasURL(for: workflowID)
        if legacy != primary, FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }

        return primary
    }

    public var workflowEventsURL: URL {
        applicationSupportDirectory.appendingPathComponent("workflow-events.json")
    }

    public var relayEndpointsURL: URL {
        applicationSupportDirectory.appendingPathComponent("relay-endpoints.json")
    }

    public var hostRegistryURL: URL {
        applicationSupportDirectory.appendingPathComponent("host-registry.json")
    }

    public var transcriptsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("transcripts", isDirectory: true)
    }

    public func transcriptURL(for threadRef: ThreadRef) -> URL {
        let providerQualifiedHost = threadRef.provider == .codex
            ? threadRef.hostID.rawValue
            : "\(threadRef.provider.rawValue)::\(threadRef.hostID.rawValue)"
        return transcriptsDirectory.appendingPathComponent(
            "\(Self.transcriptFileComponent(hostID: providerQualifiedHost, threadID: threadRef.threadID)).json"
        )
    }

    public func legacyTranscriptURL(for threadRef: ThreadRef) -> URL {
        let safeHost = threadRef.hostID.rawValue.replacingOccurrences(of: "/", with: "_")
        let safeThread = threadRef.threadID.replacingOccurrences(of: "/", with: "_")
        return transcriptsDirectory.appendingPathComponent("\(safeHost)__\(safeThread).json")
    }

    public func transcriptReadURL(for threadRef: ThreadRef) -> URL {
        let primary = transcriptURL(for: threadRef)
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }

        let legacy = legacyTranscriptURL(for: threadRef)
        if legacy != primary, FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }

        return primary
    }

    public static func defaultPaths() throws -> ApplicationPaths {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let supportDirectory = base.appendingPathComponent(Self.supportDirectoryName, isDirectory: true)
        return ApplicationPaths(
            applicationSupportDirectory: supportDirectory
        )
    }

    public static func safeFileComponent(_ value: String) -> String {
        guard isLegacySafeFileComponent(value) else {
            return "~b64_\(base64URL(value))"
        }
        return value
    }

    public static func legacySafeFileComponent(_ value: String) -> String {
        let safe = value.map { character in
            if character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_") {
                return character
            }
            return "_"
        }
        let result = String(safe)
        return result.isEmpty ? "workflow" : result
    }

    public static func transcriptFileComponent(hostID: String, threadID: String) -> String {
        if isLegacySafeTranscriptComponent(hostID), isLegacySafeTranscriptComponent(threadID) {
            return "\(hostID)__\(threadID)"
        }

        let hostDataCount = hostID.data(using: .utf8)?.count ?? 0
        let threadDataCount = threadID.data(using: .utf8)?.count ?? 0
        return "~tx_\(hostDataCount)-\(base64URL(hostID))_\(threadDataCount)-\(base64URL(threadID))"
    }

    public static func isSafeSnapshotID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 128 && value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    private static func isLegacySafeFileComponent(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        return value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }

    private static func isLegacySafeTranscriptComponent(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("/") && !value.contains("__") && !value.contains("~")
    }

    private static func base64URL(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public actor LocalControlRoomStore: ControlRoomStore {
    private static let maximumRollbackSnapshots = 2
    private static let logger = MapofAgentsTelemetry.persistence

    private struct RelayCredentialMutation {
        var reference: String
        var previousCredential: String?
        var nextCredential: String?
    }

    private struct PreparedRelayCredentials {
        var endpoints: [AppServerRelayEndpoint]
        var mutations: [RelayCredentialMutation]
    }

    private struct RelayCredentialRecoveryJournal: Codable {
        var references: [String]
    }

    private let paths: ApplicationPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let relayCredentialVault: any AppServerRelayCredentialVault
    private let snapshotFailureInjector: (@Sendable (WorkflowSnapshotCommitStep) throws -> Void)?
    private var cachedGraph: AgentGraph?
    private var cachedLibrary: WorkflowLibrarySnapshot?
    private var didRecoverRelayCredentialJournal = false

    public init(
        paths: ApplicationPaths,
        relayCredentialVault: any AppServerRelayCredentialVault = KeychainAppServerRelayCredentialVault(),
        snapshotFailureInjector: (@Sendable (WorkflowSnapshotCommitStep) throws -> Void)? = nil
    ) {
        self.paths = paths
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.relayCredentialVault = relayCredentialVault
        self.snapshotFailureInjector = snapshotFailureInjector
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        MapofAgentsJSONCoding.configureContractDates(on: encoder)
        MapofAgentsJSONCoding.configureContractDates(on: decoder)
    }

    public func loadCanvas() async throws -> AgentGraph {
        if let cachedGraph {
            return cachedGraph
        }

        let library = try ensureWorkflowLibrary()
        let workflowID = library.activeWorkflowID

        let url = try workflowCanvasReadURL(for: workflowID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if try loadSnapshotPointer() != nil {
                throw WorkflowSnapshotIntegrityError.missingWorkflowGraph(workflowID)
            }
            let graph = AgentGraph.starter(
                localHostName: ProcessInfo.processInfo.hostName,
                codexPath: LocalCodexDiscovery.findCodexExecutable()
            )
            try writeCanvas(graph, workflowID: workflowID)
            cachedGraph = graph
            return graph
        }

        let data = try Data(contentsOf: url)
        let graph = try decoder.decode(AgentGraph.self, from: data)
        cachedGraph = graph
        return graph
    }

    public func applyCanvasPatch(_ patch: CanvasPatch) async throws -> AgentGraph {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let telemetryOperationID = Self.telemetryOperationID()
        let patchKind = Self.telemetryName(for: patch)
        var persistedNodeCount = 0
        var didSucceed = false
        defer {
            if didSucceed {
                Self.logger.info(
                    "operation=canvas_patch correlation=\(telemetryOperationID, privacy: .public) result=success patch=\(patchKind, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) nodes=\(persistedNodeCount, privacy: .public)"
                )
            } else {
                Self.logger.error(
                    "operation=canvas_patch correlation=\(telemetryOperationID, privacy: .public) result=failure patch=\(patchKind, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) nodes=\(persistedNodeCount, privacy: .public)"
                )
            }
        }

        var snapshot = try await loadWorkflowSnapshot()
        let workflowID = snapshot.library.activeWorkflowID
        var graph = try snapshot.graphsByWorkflowID[workflowID].requiredWorkflowGraph(workflowID)

        switch patch {
        case .replace(let replacement):
            graph = replacement
        case .upsertNode(let node):
            graph.upsertNode(node)
        case .removeNode(let id):
            graph.removeNode(id: id)
        case .moveNode(let id, let position):
            graph.updateNodePosition(id: id, position: position)
        case .updateViewport(let viewport):
            graph.updateViewport(viewport)
        case .upsertManualEdge(let edge):
            graph.upsertManualEdge(edge)
        case .removeManualEdge(let id):
            graph.removeEdge(id: id)
        case .upsertMessageRoute(let route):
            graph.upsertMessageRoute(route)
        }

        snapshot.graphsByWorkflowID[workflowID] = graph
        if let index = snapshot.library.workflows.firstIndex(where: { $0.id == workflowID }) {
            snapshot.library.workflows[index].updatedAt = Date()
        }
        try await replaceWorkflowSnapshot(snapshot)
        persistedNodeCount = graph.nodes.count
        didSucceed = true
        return graph
    }

    public func loadWorkflows() async throws -> [WorkflowRecord] {
        let library = try ensureWorkflowLibrary()
        return library.workflows
    }

    public func activeWorkflowID() async throws -> String {
        try ensureWorkflowLibrary().activeWorkflowID
    }

    public func activeWorkflow() async throws -> WorkflowRecord {
        let library = try ensureWorkflowLibrary()
        guard let workflow = library.workflows.first(where: { $0.id == library.activeWorkflowID }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return workflow
    }

    @discardableResult
    public func createWorkflow(name: String, graph: AgentGraph? = nil) async throws -> WorkflowRecord {
        var snapshot = try await loadWorkflowSnapshot()
        let workflow = WorkflowRecord(name: sanitizedWorkflowName(name, fallback: "New Workflow"))
        let graph = graph ?? AgentGraph.starter(
            localHostName: ProcessInfo.processInfo.hostName,
            codexPath: LocalCodexDiscovery.findCodexExecutable()
        )

        snapshot.library.workflows.append(workflow)
        snapshot.library.activeWorkflowID = workflow.id
        snapshot.graphsByWorkflowID[workflow.id] = graph
        try await replaceWorkflowSnapshot(snapshot)
        return workflow
    }

    @discardableResult
    public func duplicateActiveWorkflow(name: String) async throws -> WorkflowRecord {
        let graph = try await loadCanvas()
        return try await createWorkflow(name: name, graph: graph)
    }

    public func selectWorkflow(id: String) async throws {
        var snapshot = try await loadWorkflowSnapshot()
        guard snapshot.library.workflows.contains(where: { $0.id == id }),
              snapshot.graphsByWorkflowID[id] != nil else {
            throw CocoaError(.fileNoSuchFile)
        }

        snapshot.library.activeWorkflowID = id
        try await replaceWorkflowSnapshot(snapshot)
    }

    @discardableResult
    public func renameWorkflow(id: String, name: String) async throws -> WorkflowRecord {
        var snapshot = try await loadWorkflowSnapshot()
        guard let index = snapshot.library.workflows.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        snapshot.library.workflows[index].name = sanitizedWorkflowName(
            name,
            fallback: snapshot.library.workflows[index].name
        )
        snapshot.library.workflows[index].updatedAt = Date()
        try await replaceWorkflowSnapshot(snapshot)
        return snapshot.library.workflows[index]
    }

    public func deleteWorkflow(id: String) async throws -> WorkflowRecord {
        var snapshot = try await loadWorkflowSnapshot()
        guard snapshot.library.workflows.count > 1 else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let index = snapshot.library.workflows.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let removed = snapshot.library.workflows.remove(at: index)
        snapshot.graphsByWorkflowID[id] = nil

        if snapshot.library.activeWorkflowID == id {
            snapshot.library.activeWorkflowID = snapshot.library.workflows[
                max(0, min(index, snapshot.library.workflows.count - 1))
            ].id
        }

        try await replaceWorkflowSnapshot(snapshot)
        return removed
    }

    public func loadWorkflowSnapshot() async throws -> WorkflowSnapshot {
        let telemetryOperationID = Self.telemetryOperationID()
        if let pointer = try loadSnapshotPointer() {
            var snapshot = try loadWorkflowSnapshot(
                from: paths.workflowSnapshotDirectory(for: pointer.activeSnapshotID),
                expectedSnapshotID: pointer.activeSnapshotID,
                telemetryPhase: "active",
                telemetryOperationID: telemetryOperationID
            )
            snapshot.relayEndpoints = try resolveRelayCredentials(in: snapshot.relayEndpoints)
            return snapshot
        }

        let library = try ensureWorkflowLibrary()
        try library.validateWorkflowIDs()
        var graphsByWorkflowID: [String: AgentGraph] = [:]

        for workflow in library.workflows {
            let url = try workflowCanvasReadURL(for: workflow.id)
            if FileManager.default.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                graphsByWorkflowID[workflow.id] = try decoder.decode(AgentGraph.self, from: data)
            }
        }

        if graphsByWorkflowID[library.activeWorkflowID] == nil {
            graphsByWorkflowID[library.activeWorkflowID] = try await loadCanvas()
        }

        let snapshot = WorkflowSnapshot(
            library: library,
            graphsByWorkflowID: graphsByWorkflowID,
            workflowEvents: try await loadWorkflowEvents(),
            relayEndpoints: try await loadRelayEndpoints()
        )
        try validateSnapshot(
            snapshot,
            phase: "legacy-load",
            telemetryOperationID: telemetryOperationID
        )
        return snapshot
    }

    public func replaceWorkflowSnapshot(_ snapshot: WorkflowSnapshot) async throws {
        let telemetryOperationID = Self.telemetryOperationID()
        try validateSnapshot(
            snapshot,
            phase: "replace-input",
            telemetryOperationID: telemetryOperationID
        )
        try ensureDirectories()
        var securedSnapshot = snapshot.sanitizingEphemeralRuntimeState()
        let preparedCredentials = try prepareRelayCredentials(in: snapshot.relayEndpoints)
        securedSnapshot.relayEndpoints = preparedCredentials.endpoints

        let currentSnapshot = try await loadWorkflowSnapshot()
        let existingPointer = try loadSnapshotPointer()
        let previousActiveID: String
        var previousRollbackIDs: [String]

        if let existingPointer {
            previousActiveID = existingPointer.activeSnapshotID
            previousRollbackIDs = existingPointer.rollbackSnapshotIDs
        } else {
            previousActiveID = try stageSnapshot(
                currentSnapshot,
                telemetryOperationID: telemetryOperationID
            )
            previousRollbackIDs = []
        }

        let stagedSnapshotID: String
        do {
            stagedSnapshotID = try stageSnapshot(
                securedSnapshot,
                telemetryOperationID: telemetryOperationID
            )
        } catch {
            if existingPointer == nil {
                try? FileManager.default.removeItem(at: paths.workflowSnapshotDirectory(for: previousActiveID))
            }
            throw error
        }
        let rollbackIDs = Self.boundedUniqueSnapshotIDs(
            [previousActiveID] + previousRollbackIDs,
            excluding: stagedSnapshotID
        )
        let pointer = WorkflowSnapshotPointer(
            activeSnapshotID: stagedSnapshotID,
            rollbackSnapshotIDs: rollbackIDs
        )
        let journalReferences = try allPersistedRelayCredentialReferences().union(
            preparedCredentials.mutations.map(\.reference)
        )

        let activationStartedAt = DispatchTime.now().uptimeNanoseconds
        do {
            try writeRelayCredentialRecoveryJournal(references: journalReferences)
            try applyRelayCredentialMutations(preparedCredentials.mutations)
            try snapshotFailureInjector?(.activatePointer)
            let pointerByteCount = try writeSnapshotPointer(pointer)
            Self.logger.info(
                "operation=snapshot_activate correlation=\(telemetryOperationID, privacy: .public) result=success duration_ms=\(Self.elapsedMilliseconds(since: activationStartedAt), privacy: .public) bytes=\(pointerByteCount, privacy: .public) rollback_count=\(pointer.rollbackSnapshotIDs.count, privacy: .public)"
            )
        } catch let activationError {
            Self.logger.error(
                "operation=snapshot_activate correlation=\(telemetryOperationID, privacy: .public) result=failure duration_ms=\(Self.elapsedMilliseconds(since: activationStartedAt), privacy: .public)"
            )
            try? FileManager.default.removeItem(at: paths.workflowSnapshotDirectory(for: stagedSnapshotID))
            if existingPointer == nil {
                try? FileManager.default.removeItem(at: paths.workflowSnapshotDirectory(for: previousActiveID))
            }
            finishRelayCredentialRecoveryIfPossible()
            throw activationError
        }

        cachedLibrary = securedSnapshot.library
        cachedGraph = securedSnapshot.graphsByWorkflowID[securedSnapshot.library.activeWorkflowID]
        pruneUnreferencedSnapshots(keeping: Set([pointer.activeSnapshotID] + pointer.rollbackSnapshotIDs))
        finishRelayCredentialRecoveryIfPossible()
    }

    public func rollbackWorkflowSnapshot() async throws {
        let telemetryOperationID = Self.telemetryOperationID()
        guard let pointer = try loadSnapshotPointer(),
              let rollbackID = pointer.rollbackSnapshotIDs.first else {
            throw WorkflowSnapshotPersistenceError.noRollbackAvailable
        }

        let snapshot = try loadWorkflowSnapshot(
            from: paths.workflowSnapshotDirectory(for: rollbackID),
            expectedSnapshotID: rollbackID,
            telemetryPhase: "rollback",
            telemetryOperationID: telemetryOperationID
        )
        let remainingRollbackIDs = Array(pointer.rollbackSnapshotIDs.dropFirst())
        let nextPointer = WorkflowSnapshotPointer(
            activeSnapshotID: rollbackID,
            rollbackSnapshotIDs: Self.boundedUniqueSnapshotIDs(
                [pointer.activeSnapshotID] + remainingRollbackIDs,
                excluding: rollbackID
            )
        )
        let activationStartedAt = DispatchTime.now().uptimeNanoseconds
        do {
            try writeRelayCredentialRecoveryJournal(
                references: try allPersistedRelayCredentialReferences()
            )
            try snapshotFailureInjector?(.activatePointer)
            let pointerByteCount = try writeSnapshotPointer(nextPointer)
            Self.logger.info(
                "operation=snapshot_activate correlation=\(telemetryOperationID, privacy: .public) result=success mode=rollback duration_ms=\(Self.elapsedMilliseconds(since: activationStartedAt), privacy: .public) bytes=\(pointerByteCount, privacy: .public) rollback_count=\(nextPointer.rollbackSnapshotIDs.count, privacy: .public)"
            )
        } catch {
            Self.logger.error(
                "operation=snapshot_activate correlation=\(telemetryOperationID, privacy: .public) result=failure mode=rollback duration_ms=\(Self.elapsedMilliseconds(since: activationStartedAt), privacy: .public)"
            )
            finishRelayCredentialRecoveryIfPossible()
            throw error
        }

        cachedLibrary = snapshot.library
        cachedGraph = snapshot.graphsByWorkflowID[snapshot.library.activeWorkflowID]
        pruneUnreferencedSnapshots(keeping: Set([nextPointer.activeSnapshotID] + nextPointer.rollbackSnapshotIDs))
        finishRelayCredentialRecoveryIfPossible()
    }

    public func loadWorkflowEvents() async throws -> [WorkflowEvent] {
        try ensureDirectories()
        let url = try workflowEventsURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([WorkflowEvent].self, from: data)
    }

    public func saveWorkflowEvents(_ events: [WorkflowEvent]) async throws {
        try ensureDirectories()
        let recentEvents = Array(events.sorted { $0.createdAt > $1.createdAt }.prefix(200))
        let data = try encoder.encode(recentEvents)
        try data.write(to: workflowEventsURL(), options: [.atomic])
    }

    public func loadRelayEndpoints() async throws -> [AppServerRelayEndpoint] {
        try ensureDirectories()
        let url = try relayEndpointsURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        let endpoints = try decoder.decode([AppServerRelayEndpoint].self, from: data)
        let containsLegacyPlaintext = endpoints.contains { $0.bearerToken != nil }

        // Older releases wrote the token into this JSON file. Move it into
        // Keychain on first read and immediately sanitize the on-disk record.
        if containsLegacyPlaintext {
            let preparedCredentials = try prepareRelayCredentials(in: endpoints)
            let journalReferences = try allPersistedRelayCredentialReferences().union(
                preparedCredentials.mutations.map(\.reference)
            )
            do {
                try writeRelayCredentialRecoveryJournal(references: journalReferences)
                try applyRelayCredentialMutations(preparedCredentials.mutations)
                try encoder.encode(preparedCredentials.endpoints).write(to: url, options: [.atomic])
            } catch let migrationError {
                finishRelayCredentialRecoveryIfPossible()
                throw migrationError
            }
            finishRelayCredentialRecoveryIfPossible()
            return preparedCredentials.endpoints
        }
        return try resolveRelayCredentials(in: endpoints)
    }

    public func saveRelayEndpoints(_ endpoints: [AppServerRelayEndpoint]) async throws {
        try ensureDirectories()
        let url = try relayEndpointsURL()
        let preparedCredentials = try prepareRelayCredentials(in: endpoints)
        let journalReferences = try allPersistedRelayCredentialReferences().union(
            preparedCredentials.mutations.map(\.reference)
        )
        do {
            try writeRelayCredentialRecoveryJournal(references: journalReferences)
            try applyRelayCredentialMutations(preparedCredentials.mutations)
            try encoder.encode(preparedCredentials.endpoints).write(to: url, options: [.atomic])
        } catch let persistenceError {
            finishRelayCredentialRecoveryIfPossible()
            throw persistenceError
        }
        finishRelayCredentialRecoveryIfPossible()
    }

    public func loadTranscript(for threadRef: ThreadRef) async throws -> ThreadTranscript? {
        try ensureDirectories()
        let url = paths.transcriptReadURL(for: threadRef)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(ThreadTranscript.self, from: data)
    }

    public func saveTranscript(_ transcript: ThreadTranscript) async throws {
        try ensureDirectories()
        let data = try encoder.encode(transcript)
        try data.write(to: paths.transcriptURL(for: transcript.threadRef), options: [.atomic])
    }

    private func prepareRelayCredentials(
        in endpoints: [AppServerRelayEndpoint]
    ) throws -> PreparedRelayCredentials {
        var requestedCredentialsByReference: [String: String] = [:]
        var mutations: [RelayCredentialMutation] = []
        let securedEndpoints = try endpoints.map { endpoint in
            guard let credential = endpoint.bearerToken else { return endpoint }
            let baseReference = endpoint.credentialReference
                ?? AppServerRelayEndpoint.defaultCredentialReference(for: endpoint.id)
            if let existing = requestedCredentialsByReference[baseReference], existing != credential {
                throw AppServerRelayCredentialVaultError.conflictingCredentials(baseReference)
            }
            requestedCredentialsByReference[baseReference] = credential

            let existingCredential = try relayCredentialVault.load(reference: baseReference)
            let targetReference: String
            if existingCredential == credential {
                targetReference = baseReference
            } else if existingCredential == nil {
                targetReference = baseReference
            } else {
                targetReference = Self.versionedCredentialReference(for: endpoint.id)
            }

            if targetReference != baseReference || existingCredential != credential {
                mutations.append(
                    RelayCredentialMutation(
                        reference: targetReference,
                        previousCredential: try relayCredentialVault.load(reference: targetReference),
                        nextCredential: credential
                    )
                )
            }
            var secured = endpoint
            secured.credentialReference = targetReference
            return secured
        }
        return PreparedRelayCredentials(endpoints: securedEndpoints, mutations: mutations)
    }

    private static func versionedCredentialReference(for hostID: HostID) -> String {
        "\(AppServerRelayEndpoint.defaultCredentialReference(for: hostID)):v:\(UUID().uuidString.lowercased())"
    }

    private func applyRelayCredentialMutations(_ mutations: [RelayCredentialMutation]) throws {
        var applied: [RelayCredentialMutation] = []
        do {
            for mutation in mutations {
                if let nextCredential = mutation.nextCredential {
                    try relayCredentialVault.save(nextCredential, reference: mutation.reference)
                } else {
                    try relayCredentialVault.delete(reference: mutation.reference)
                }
                applied.append(mutation)
            }
        } catch let mutationError {
            do {
                try rollbackRelayCredentialMutations(applied)
            } catch {
                throw AppServerRelayCredentialVaultError.transactionRollbackFailed(
                    error.localizedDescription
                )
            }
            throw mutationError
        }
    }

    private func rollbackRelayCredentialMutations(_ mutations: [RelayCredentialMutation]) throws {
        for mutation in mutations.reversed() {
            if let previousCredential = mutation.previousCredential {
                try relayCredentialVault.save(previousCredential, reference: mutation.reference)
            } else {
                try relayCredentialVault.delete(reference: mutation.reference)
            }
        }
    }

    private func resolveRelayCredentials(
        in endpoints: [AppServerRelayEndpoint]
    ) throws -> [AppServerRelayEndpoint] {
        try endpoints.map { endpoint in
            if let legacyCredential = endpoint.bearerToken {
                let reference = endpoint.credentialReference
                    ?? AppServerRelayEndpoint.defaultCredentialReference(for: endpoint.id)
                try relayCredentialVault.save(legacyCredential, reference: reference)
                var migrated = endpoint
                migrated.credentialReference = reference
                return migrated
            }

            guard let reference = endpoint.credentialReference else { return endpoint }
            return endpoint.resolvingBearerToken(try relayCredentialVault.load(reference: reference))
        }
    }

    private func persistedRelayCredentialReferences(at url: URL) throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let endpoints = try decoder.decode(
            [AppServerRelayEndpoint].self,
            from: Data(contentsOf: url)
        )
        return Set(endpoints.compactMap(\.credentialReference))
    }

    private var relayCredentialRecoveryJournalURL: URL {
        paths.applicationSupportDirectory.appendingPathComponent("relay-credential-recovery.json")
    }

    private func writeRelayCredentialRecoveryJournal(references: Set<String>) throws {
        guard !references.isEmpty else {
            try? FileManager.default.removeItem(at: relayCredentialRecoveryJournalURL)
            return
        }
        let journal = RelayCredentialRecoveryJournal(references: references.sorted())
        try encoder.encode(journal).write(to: relayCredentialRecoveryJournalURL, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: relayCredentialRecoveryJournalURL.path
        )
        didRecoverRelayCredentialJournal = false
    }

    private func finishRelayCredentialRecoveryIfPossible() {
        do {
            try recoverRelayCredentialJournalIfNeeded(force: true)
        } catch {
            // Keep the owner-only journal so the next store operation or app
            // launch can deterministically finish cleanup.
            didRecoverRelayCredentialJournal = false
        }
    }

    private func recoverRelayCredentialJournalIfNeeded(force: Bool = false) throws {
        guard force || !didRecoverRelayCredentialJournal else { return }
        guard FileManager.default.fileExists(atPath: relayCredentialRecoveryJournalURL.path) else {
            didRecoverRelayCredentialJournal = true
            return
        }

        let journal = try decoder.decode(
            RelayCredentialRecoveryJournal.self,
            from: Data(contentsOf: relayCredentialRecoveryJournalURL)
        )
        let retainedReferences = try retainedRelayCredentialReferences()
        for reference in journal.references where !retainedReferences.contains(reference) {
            try relayCredentialVault.delete(reference: reference)
        }
        try FileManager.default.removeItem(at: relayCredentialRecoveryJournalURL)
        didRecoverRelayCredentialJournal = true
    }

    private func retainedRelayCredentialReferences() throws -> Set<String> {
        if let pointer = try loadSnapshotPointer() {
            return try Set([pointer.activeSnapshotID] + pointer.rollbackSnapshotIDs).reduce(into: Set<String>()) {
                result, snapshotID in
                let url = try relayEndpointsURL(root: paths.workflowSnapshotDirectory(for: snapshotID))
                result.formUnion(try persistedRelayCredentialReferences(at: url))
            }
        }
        return try persistedRelayCredentialReferences(
            at: paths.applicationSupportDirectory.appendingPathComponent("relay-endpoints.json")
        )
    }

    private func allPersistedRelayCredentialReferences() throws -> Set<String> {
        var references = try persistedRelayCredentialReferences(
            at: paths.applicationSupportDirectory.appendingPathComponent("relay-endpoints.json")
        )
        guard FileManager.default.fileExists(atPath: paths.workflowSnapshotsDirectory.path) else {
            return references
        }
        let entries = try FileManager.default.contentsOfDirectory(
            at: paths.workflowSnapshotsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                continue
            }
            let url = entry.appendingPathComponent("relay-endpoints.json")
            if let snapshotReferences = try? persistedRelayCredentialReferences(at: url) {
                references.formUnion(snapshotReferences)
            }
        }
        return references
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(
            at: paths.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: paths.workflowsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: paths.transcriptsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: paths.workflowSnapshotsDirectory,
            withIntermediateDirectories: true
        )
        try recoverRelayCredentialJournalIfNeeded()
    }

    private func writeCanvas(_ graph: AgentGraph, workflowID: String) throws {
        try ensureDirectories()
        var durableGraph = graph
        durableGraph.pendingAttentionRequests = []
        durableGraph.runtimeDiagnostics = []
        let data = try encoder.encode(durableGraph)
        try data.write(to: workflowCanvasURL(for: workflowID), options: [.atomic])
    }

    private func ensureWorkflowLibrary() throws -> WorkflowLibrarySnapshot {
        if let cachedLibrary {
            return cachedLibrary
        }

        try ensureDirectories()

        let libraryURL = try workflowLibraryURL()
        if FileManager.default.fileExists(atPath: libraryURL.path) {
            let data = try Data(contentsOf: libraryURL)
            var library = try decoder.decode(WorkflowLibrarySnapshot.self, from: data)
            if library.workflows.isEmpty {
                library = try createInitialLibrary()
            } else {
                try library.validateWorkflowIDs()
            }
            if !library.workflows.contains(where: { $0.id == library.activeWorkflowID }) {
                library.activeWorkflowID = library.workflows[0].id
                try writeLibrary(library)
            }
            cachedLibrary = library
            return library
        }

        if try loadSnapshotPointer() != nil {
            throw CocoaError(.fileReadCorruptFile)
        }

        let library = try createInitialLibrary()
        cachedLibrary = library
        return library
    }

    private func createInitialLibrary() throws -> WorkflowLibrarySnapshot {
        let now = Date()
        let workflow = WorkflowRecord(id: "main", name: "Main Workflow", createdAt: now, updatedAt: now)
        let library = WorkflowLibrarySnapshot(activeWorkflowID: workflow.id, workflows: [workflow])

        let stateRoot = try activeStateRoot()
        let legacyCanvasURL = stateRoot == paths.applicationSupportDirectory ? paths.canvasURL : stateRoot.appendingPathComponent("canvas.json")

        if FileManager.default.fileExists(atPath: legacyCanvasURL.path) {
            let canvasURL = try workflowCanvasURL(for: workflow.id)
            if !FileManager.default.fileExists(atPath: canvasURL.path) {
                try FileManager.default.copyItem(
                    at: legacyCanvasURL,
                    to: canvasURL
                )
            }
        } else {
            let graph = AgentGraph.starter(
                localHostName: ProcessInfo.processInfo.hostName,
                codexPath: LocalCodexDiscovery.findCodexExecutable()
            )
            try writeCanvas(graph, workflowID: workflow.id)
        }

        try writeLibrary(library)
        return library
    }

    private func writeLibrary(_ library: WorkflowLibrarySnapshot) throws {
        try ensureDirectories()
        let data = try encoder.encode(library)
        try data.write(to: workflowLibraryURL(), options: [.atomic])
    }

    private func updateActiveWorkflowTimestamp() throws {
        var library = try ensureWorkflowLibrary()
        guard let index = library.workflows.firstIndex(where: { $0.id == library.activeWorkflowID }) else {
            return
        }
        library.workflows[index].updatedAt = Date()
        try writeLibrary(library)
        cachedLibrary = library
    }

    private func activeStateRoot() throws -> URL {
        guard let pointer = try loadSnapshotPointer() else {
            return paths.applicationSupportDirectory
        }
        return paths.workflowSnapshotDirectory(for: pointer.activeSnapshotID)
    }

    private func workflowLibraryURL(root: URL? = nil) throws -> URL {
        let root = try root ?? activeStateRoot()
        return root
            .appendingPathComponent("workflows", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    private func workflowCanvasURL(for workflowID: String, root: URL? = nil) throws -> URL {
        let root = try root ?? activeStateRoot()
        return root
            .appendingPathComponent("workflows", isDirectory: true)
            .appendingPathComponent("\(ApplicationPaths.safeFileComponent(workflowID)).json")
    }

    private func legacyWorkflowCanvasURL(for workflowID: String, root: URL? = nil) throws -> URL {
        let root = try root ?? activeStateRoot()
        return root
            .appendingPathComponent("workflows", isDirectory: true)
            .appendingPathComponent("\(ApplicationPaths.legacySafeFileComponent(workflowID)).json")
    }

    private func workflowCanvasReadURL(for workflowID: String, root: URL? = nil) throws -> URL {
        let primary = try workflowCanvasURL(for: workflowID, root: root)
        if FileManager.default.fileExists(atPath: primary.path) {
            return primary
        }
        let legacy = try legacyWorkflowCanvasURL(for: workflowID, root: root)
        if legacy != primary, FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }
        return primary
    }

    private func workflowEventsURL(root: URL? = nil) throws -> URL {
        let root = try root ?? activeStateRoot()
        return root.appendingPathComponent("workflow-events.json")
    }

    private func relayEndpointsURL(root: URL? = nil) throws -> URL {
        let root = try root ?? activeStateRoot()
        return root.appendingPathComponent("relay-endpoints.json")
    }

    private func loadSnapshotPointer() throws -> WorkflowSnapshotPointer? {
        guard FileManager.default.fileExists(atPath: paths.workflowSnapshotPointerURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: paths.workflowSnapshotPointerURL)
        let pointer = try decoder.decode(WorkflowSnapshotPointer.self, from: data)
        try pointer.validate()
        return pointer
    }

    @discardableResult
    private func writeSnapshotPointer(_ pointer: WorkflowSnapshotPointer) throws -> Int {
        try pointer.validate()
        let data = try encoder.encode(pointer)
        try data.write(to: paths.workflowSnapshotPointerURL, options: [.atomic])
        return data.count
    }

    private func stageSnapshot(
        _ snapshot: WorkflowSnapshot,
        telemetryOperationID: String
    ) throws -> String {
        let snapshot = snapshot.sanitizingEphemeralRuntimeState()
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var stagedByteCount = 0
        var didSucceed = false
        defer {
            if didSucceed {
                Self.logger.info(
                    "operation=snapshot_stage correlation=\(telemetryOperationID, privacy: .public) result=success duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) bytes=\(stagedByteCount, privacy: .public) workflows=\(snapshot.library.workflows.count, privacy: .public)"
                )
            } else {
                Self.logger.error(
                    "operation=snapshot_stage correlation=\(telemetryOperationID, privacy: .public) result=failure duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) bytes=\(stagedByteCount, privacy: .public) workflows=\(snapshot.library.workflows.count, privacy: .public)"
                )
            }
        }

        try validateSnapshot(
            snapshot,
            phase: "stage-input",
            telemetryOperationID: telemetryOperationID
        )

        let snapshotID = UUID().uuidString
        let stagingURL = paths.workflowSnapshotsDirectory
            .appendingPathComponent(".staging-\(snapshotID)", isDirectory: true)
        let finalURL = paths.workflowSnapshotDirectory(for: snapshotID)
        let workflowsURL = stagingURL.appendingPathComponent("workflows", isDirectory: true)

        try FileManager.default.createDirectory(at: workflowsURL, withIntermediateDirectories: true)
        do {
            try snapshotFailureInjector?(.metadata)
            let metadata = WorkflowSnapshotMetadata(snapshotID: snapshotID)
            let metadataData = try encoder.encode(metadata)
            stagedByteCount += metadataData.count
            try metadataData.write(
                to: stagingURL.appendingPathComponent("metadata.json"),
                options: [.atomic]
            )

            try snapshotFailureInjector?(.library)
            let libraryData = try encoder.encode(snapshot.library)
            stagedByteCount += libraryData.count
            try libraryData.write(
                to: workflowsURL.appendingPathComponent("library.json"),
                options: [.atomic]
            )

            for workflow in snapshot.library.workflows {
                let graph = try snapshot.graphsByWorkflowID[workflow.id].requiredWorkflowGraph(workflow.id)
                try snapshotFailureInjector?(.workflowGraph(workflow.id))
                let graphData = try encoder.encode(graph)
                stagedByteCount += graphData.count
                try graphData.write(
                    to: workflowsURL.appendingPathComponent(
                        "\(ApplicationPaths.safeFileComponent(workflow.id)).json"
                    ),
                    options: [.atomic]
                )
            }

            try snapshotFailureInjector?(.workflowEvents)
            let recentEvents = Array(snapshot.workflowEvents.sorted { $0.createdAt > $1.createdAt }.prefix(200))
            let eventsData = try encoder.encode(recentEvents)
            stagedByteCount += eventsData.count
            try eventsData.write(
                to: stagingURL.appendingPathComponent("workflow-events.json"),
                options: [.atomic]
            )

            try snapshotFailureInjector?(.relayEndpoints)
            let endpointsData = try encoder.encode(snapshot.relayEndpoints)
            stagedByteCount += endpointsData.count
            try endpointsData.write(
                to: stagingURL.appendingPathComponent("relay-endpoints.json"),
                options: [.atomic]
            )

            _ = try loadWorkflowSnapshot(
                from: stagingURL,
                expectedSnapshotID: snapshotID,
                telemetryPhase: "staged-validation",
                telemetryOperationID: telemetryOperationID
            )
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)
            didSucceed = true
            return snapshotID
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    private func loadWorkflowSnapshot(
        from root: URL,
        expectedSnapshotID: String? = nil,
        telemetryPhase: String,
        telemetryOperationID: String
    ) throws -> WorkflowSnapshot {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var loadedByteCount = 0
        var loadedWorkflowCount = 0
        var didSucceed = false
        defer {
            if didSucceed {
                Self.logger.info(
                    "operation=snapshot_load correlation=\(telemetryOperationID, privacy: .public) result=success phase=\(telemetryPhase, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) bytes=\(loadedByteCount, privacy: .public) workflows=\(loadedWorkflowCount, privacy: .public)"
                )
            } else {
                Self.logger.error(
                    "operation=snapshot_load correlation=\(telemetryOperationID, privacy: .public) result=failure phase=\(telemetryPhase, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) bytes=\(loadedByteCount, privacy: .public) workflows=\(loadedWorkflowCount, privacy: .public)"
                )
            }
        }

        if let expectedSnapshotID {
            let metadataURL = root.appendingPathComponent("metadata.json")
            let metadataData = try Data(contentsOf: metadataURL)
            loadedByteCount += metadataData.count
            let metadata = try decoder.decode(
                WorkflowSnapshotMetadata.self,
                from: metadataData
            )
            try metadata.validate(expectedSnapshotID: expectedSnapshotID)
        }

        let libraryData = try Data(contentsOf: try workflowLibraryURL(root: root))
        loadedByteCount += libraryData.count
        let library = try decoder.decode(
            WorkflowLibrarySnapshot.self,
            from: libraryData
        )
        try library.validateWorkflowIDs()
        loadedWorkflowCount = library.workflows.count

        var graphsByWorkflowID: [String: AgentGraph] = [:]
        for workflow in library.workflows {
            let graphURL = try workflowCanvasReadURL(for: workflow.id, root: root)
            guard FileManager.default.fileExists(atPath: graphURL.path) else {
                throw WorkflowSnapshotIntegrityError.missingWorkflowGraph(workflow.id)
            }
            let graphData = try Data(contentsOf: graphURL)
            loadedByteCount += graphData.count
            graphsByWorkflowID[workflow.id] = try decoder.decode(
                AgentGraph.self,
                from: graphData
            )
        }

        let eventsURL = try workflowEventsURL(root: root)
        let workflowEvents: [WorkflowEvent]
        if FileManager.default.fileExists(atPath: eventsURL.path) {
            let eventsData = try Data(contentsOf: eventsURL)
            loadedByteCount += eventsData.count
            workflowEvents = try decoder.decode([WorkflowEvent].self, from: eventsData)
        } else {
            workflowEvents = []
        }

        let endpointsURL = try relayEndpointsURL(root: root)
        let relayEndpoints: [AppServerRelayEndpoint]
        if FileManager.default.fileExists(atPath: endpointsURL.path) {
            let endpointsData = try Data(contentsOf: endpointsURL)
            loadedByteCount += endpointsData.count
            relayEndpoints = try decoder.decode([AppServerRelayEndpoint].self, from: endpointsData)
        } else {
            relayEndpoints = []
        }

        let snapshot = WorkflowSnapshot(
            library: library,
            graphsByWorkflowID: graphsByWorkflowID,
            workflowEvents: workflowEvents,
            relayEndpoints: relayEndpoints
        )
        try validateSnapshot(
            snapshot,
            phase: "\(telemetryPhase)-output",
            telemetryOperationID: telemetryOperationID
        )
        didSucceed = true
        return snapshot
    }

    private static func boundedUniqueSnapshotIDs(
        _ ids: [String],
        excluding excludedID: String
    ) -> [String] {
        var seen = Set([excludedID])
        return ids.filter { seen.insert($0).inserted }
            .prefix(maximumRollbackSnapshots)
            .map(\.self)
    }

    private func pruneUnreferencedSnapshots(keeping retainedIDs: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: paths.workflowSnapshotsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents where url.lastPathComponent != paths.workflowSnapshotPointerURL.lastPathComponent {
            guard retainedIDs.contains(url.lastPathComponent) == false else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func validateSnapshot(
        _ snapshot: WorkflowSnapshot,
        phase: String,
        telemetryOperationID: String
    ) throws {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        var didSucceed = false
        defer {
            if didSucceed {
                Self.logger.info(
                    "operation=snapshot_validate correlation=\(telemetryOperationID, privacy: .public) result=success phase=\(phase, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) workflows=\(snapshot.library.workflows.count, privacy: .public)"
                )
            } else {
                Self.logger.error(
                    "operation=snapshot_validate correlation=\(telemetryOperationID, privacy: .public) result=failure phase=\(phase, privacy: .public) duration_ms=\(Self.elapsedMilliseconds(since: startedAt), privacy: .public) workflows=\(snapshot.library.workflows.count, privacy: .public)"
                )
            }
        }
        try snapshot.validateForActivation()
        didSucceed = true
    }

    private static func elapsedMilliseconds(since startedAt: UInt64) -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds &- startedAt) / 1_000_000
    }

    private static func telemetryOperationID() -> String {
        UUID().uuidString.lowercased()
    }

    private static func telemetryName(for patch: CanvasPatch) -> String {
        switch patch {
        case .replace:
            return "replace"
        case .upsertNode:
            return "upsert_node"
        case .removeNode:
            return "remove_node"
        case .moveNode:
            return "move_node"
        case .updateViewport:
            return "update_viewport"
        case .upsertManualEdge:
            return "upsert_manual_edge"
        case .removeManualEdge:
            return "remove_manual_edge"
        case .upsertMessageRoute:
            return "upsert_message_route"
        }
    }

    private func sanitizedWorkflowName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

private extension Optional where Wrapped == AgentGraph {
    func requiredWorkflowGraph(_ workflowID: String) throws -> AgentGraph {
        guard let graph = self else {
            throw WorkflowSnapshotIntegrityError.missingWorkflowGraph(workflowID)
        }
        return graph
    }
}

public enum LocalCodexDiscovery {
    public static func findManagedCodexExecutable() -> String? {
        #if os(macOS)
        let standalone = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/packages/standalone/current/codex")
        return FileManager.default.isExecutableFile(atPath: standalone.path) ? standalone.path : nil
        #else
        return nil
        #endif
    }

    public static func findCodexExecutable() -> String? {
        #if os(macOS)
        if let managedExecutable = findManagedCodexExecutable() {
            return managedExecutable
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", "codex"]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path?.isEmpty == false ? path : nil
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
