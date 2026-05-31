import Foundation

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
        transcriptsDirectory.appendingPathComponent("\(Self.transcriptFileComponent(hostID: threadRef.hostID.rawValue, threadID: threadRef.threadID)).json")
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
    private let paths: ApplicationPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var cachedGraph: AgentGraph?
    private var cachedLibrary: WorkflowLibrarySnapshot?

    public init(paths: ApplicationPaths) {
        self.paths = paths
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadCanvas() async throws -> AgentGraph {
        if let cachedGraph {
            return cachedGraph
        }

        let library = try ensureWorkflowLibrary()
        let workflowID = library.activeWorkflowID

        let url = paths.workflowCanvasReadURL(for: workflowID)
        guard FileManager.default.fileExists(atPath: url.path) else {
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
        var graph = try await loadCanvas()

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

        let library = try ensureWorkflowLibrary()
        try writeCanvas(graph, workflowID: library.activeWorkflowID)
        try updateActiveWorkflowTimestamp()
        cachedGraph = graph
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
        var library = try ensureWorkflowLibrary()
        let workflow = WorkflowRecord(name: sanitizedWorkflowName(name, fallback: "New Workflow"))
        let graph = graph ?? AgentGraph.starter(
            localHostName: ProcessInfo.processInfo.hostName,
            codexPath: LocalCodexDiscovery.findCodexExecutable()
        )

        library.workflows.append(workflow)
        library.activeWorkflowID = workflow.id
        try writeCanvas(graph, workflowID: workflow.id)
        try writeLibrary(library)
        cachedLibrary = library
        cachedGraph = graph
        return workflow
    }

    @discardableResult
    public func duplicateActiveWorkflow(name: String) async throws -> WorkflowRecord {
        let graph = try await loadCanvas()
        return try await createWorkflow(name: name, graph: graph)
    }

    public func selectWorkflow(id: String) async throws {
        var library = try ensureWorkflowLibrary()
        guard library.workflows.contains(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        library.activeWorkflowID = id
        try writeLibrary(library)
        cachedLibrary = library
        cachedGraph = nil
    }

    @discardableResult
    public func renameWorkflow(id: String, name: String) async throws -> WorkflowRecord {
        var library = try ensureWorkflowLibrary()
        guard let index = library.workflows.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        library.workflows[index].name = sanitizedWorkflowName(name, fallback: library.workflows[index].name)
        library.workflows[index].updatedAt = Date()
        try writeLibrary(library)
        cachedLibrary = library
        return library.workflows[index]
    }

    public func deleteWorkflow(id: String) async throws -> WorkflowRecord {
        var library = try ensureWorkflowLibrary()
        guard library.workflows.count > 1 else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let index = library.workflows.firstIndex(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let removed = library.workflows.remove(at: index)
        try? FileManager.default.removeItem(at: paths.workflowCanvasURL(for: id))
        let legacyURL = paths.legacyWorkflowCanvasURL(for: id)
        if legacyURL != paths.workflowCanvasURL(for: id) {
            try? FileManager.default.removeItem(at: legacyURL)
        }

        if library.activeWorkflowID == id {
            library.activeWorkflowID = library.workflows[max(0, min(index, library.workflows.count - 1))].id
            cachedGraph = nil
        }

        try writeLibrary(library)
        cachedLibrary = library
        return removed
    }

    public func loadWorkflowSnapshot() async throws -> WorkflowSnapshot {
        let library = try ensureWorkflowLibrary()
        try library.validateWorkflowIDs()
        var graphsByWorkflowID: [String: AgentGraph] = [:]

        for workflow in library.workflows {
            let url = paths.workflowCanvasReadURL(for: workflow.id)
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
        try snapshot.validateForActivation()
        return snapshot
    }

    public func replaceWorkflowSnapshot(_ snapshot: WorkflowSnapshot) async throws {
        try snapshot.validateForActivation()

        try ensureDirectories()

        for workflow in snapshot.library.workflows {
            let graph = try snapshot.graphsByWorkflowID[workflow.id].requiredWorkflowGraph(workflow.id)
            try writeCanvas(graph, workflowID: workflow.id)
        }

        try writeLibrary(snapshot.library)
        try await saveWorkflowEvents(snapshot.workflowEvents)
        try await saveRelayEndpoints(snapshot.relayEndpoints)

        cachedLibrary = snapshot.library
        cachedGraph = snapshot.graphsByWorkflowID[snapshot.library.activeWorkflowID]
    }

    public func loadWorkflowEvents() async throws -> [WorkflowEvent] {
        try ensureDirectories()
        guard FileManager.default.fileExists(atPath: paths.workflowEventsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: paths.workflowEventsURL)
        return try decoder.decode([WorkflowEvent].self, from: data)
    }

    public func saveWorkflowEvents(_ events: [WorkflowEvent]) async throws {
        try ensureDirectories()
        let recentEvents = Array(events.sorted { $0.createdAt > $1.createdAt }.prefix(200))
        let data = try encoder.encode(recentEvents)
        try data.write(to: paths.workflowEventsURL, options: [.atomic])
    }

    public func loadRelayEndpoints() async throws -> [AppServerRelayEndpoint] {
        try ensureDirectories()
        guard FileManager.default.fileExists(atPath: paths.relayEndpointsURL.path) else {
            return []
        }
        let data = try Data(contentsOf: paths.relayEndpointsURL)
        return try decoder.decode([AppServerRelayEndpoint].self, from: data)
    }

    public func saveRelayEndpoints(_ endpoints: [AppServerRelayEndpoint]) async throws {
        try ensureDirectories()
        let data = try encoder.encode(endpoints)
        try data.write(to: paths.relayEndpointsURL, options: [.atomic])
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
    }

    private func writeCanvas(_ graph: AgentGraph, workflowID: String) throws {
        try ensureDirectories()
        let data = try encoder.encode(graph)
        try data.write(to: paths.workflowCanvasURL(for: workflowID), options: [.atomic])
    }

    private func ensureWorkflowLibrary() throws -> WorkflowLibrarySnapshot {
        if let cachedLibrary {
            return cachedLibrary
        }

        try ensureDirectories()

        if FileManager.default.fileExists(atPath: paths.workflowLibraryURL.path) {
            let data = try Data(contentsOf: paths.workflowLibraryURL)
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

        let library = try createInitialLibrary()
        cachedLibrary = library
        return library
    }

    private func createInitialLibrary() throws -> WorkflowLibrarySnapshot {
        let now = Date()
        let workflow = WorkflowRecord(id: "main", name: "Main Workflow", createdAt: now, updatedAt: now)
        let library = WorkflowLibrarySnapshot(activeWorkflowID: workflow.id, workflows: [workflow])

        if FileManager.default.fileExists(atPath: paths.canvasURL.path) {
            if !FileManager.default.fileExists(atPath: paths.workflowCanvasURL(for: workflow.id).path) {
                try FileManager.default.copyItem(
                    at: paths.canvasURL,
                    to: paths.workflowCanvasURL(for: workflow.id)
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
        try data.write(to: paths.workflowLibraryURL, options: [.atomic])
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
    public static func findCodexExecutable() -> String? {
        #if os(macOS)
        let standalone = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/packages/standalone/current/codex")
        if FileManager.default.isExecutableFile(atPath: standalone.path) {
            return standalone.path
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
