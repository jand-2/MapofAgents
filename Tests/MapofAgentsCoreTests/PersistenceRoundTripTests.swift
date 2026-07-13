import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func localStorePersistsCanvasPatches() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))

    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 10, y: 20),
        size: .folder,
        metadata: NodeMetadata(hostID: HostID(rawValue: "local"), folderPath: "/tmp/project")
    )

    _ = try await store.applyCanvasPatch(.upsertNode(folder))
    let graph = try await store.loadCanvas()

    #expect(graph.nodes[folder.id]?.title == "Project")
    #expect(graph.nodes[folder.id]?.metadata.folderPath == "/tmp/project")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func localStoreKeepsWorkflowCanvasesSeparate() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))

    let mainFolder = CanvasNode(
        id: NodeID(rawValue: "main-folder"),
        kind: .folder,
        title: "Main Project",
        position: CanvasPoint(x: 10, y: 20),
        size: .folder,
        metadata: NodeMetadata(hostID: HostID(rawValue: "local"), folderPath: "/tmp/main")
    )
    _ = try await store.applyCanvasPatch(.upsertNode(mainFolder))
    let mainWorkflowID = try await store.activeWorkflowID()

    let secondWorkflow = try await store.createWorkflow(name: "Second Workflow")
    let secondFolder = CanvasNode(
        id: NodeID(rawValue: "second-folder"),
        kind: .folder,
        title: "Second Project",
        position: CanvasPoint(x: 30, y: 40),
        size: .folder,
        metadata: NodeMetadata(hostID: HostID(rawValue: "local"), folderPath: "/tmp/second")
    )
    _ = try await store.applyCanvasPatch(.upsertNode(secondFolder))

    var graph = try await store.loadCanvas()
    #expect(graph.nodes[secondFolder.id] != nil)
    #expect(graph.nodes[mainFolder.id] == nil)

    try await store.selectWorkflow(id: mainWorkflowID)
    graph = try await store.loadCanvas()
    #expect(graph.nodes[mainFolder.id] != nil)
    #expect(graph.nodes[secondFolder.id] == nil)

    try await store.selectWorkflow(id: secondWorkflow.id)
    graph = try await store.loadCanvas()
    #expect(graph.nodes[secondFolder.id] != nil)
    #expect(graph.nodes[mainFolder.id] == nil)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func localStoreDuplicatesAndDeletesWorkflows() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-workflow-delete-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))

    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 10, y: 20),
        size: .folder,
        metadata: NodeMetadata(hostID: HostID(rawValue: "local"), folderPath: "/tmp/project")
    )
    _ = try await store.applyCanvasPatch(.upsertNode(folder))

    let mainWorkflowID = try await store.activeWorkflowID()
    _ = try await store.renameWorkflow(id: mainWorkflowID, name: "Renamed Main")
    let copy = try await store.duplicateActiveWorkflow(name: "Project Copy")
    var workflows = try await store.loadWorkflows()
    #expect(workflows.map(\.name).contains("Renamed Main"))
    #expect(workflows.map(\.name).contains("Project Copy"))

    var graph = try await store.loadCanvas()
    #expect(graph.nodes[folder.id]?.title == "Project")

    _ = try await store.deleteWorkflow(id: copy.id)
    workflows = try await store.loadWorkflows()
    #expect(workflows.count == 1)
    #expect(try await store.activeWorkflowID() != copy.id)

    graph = try await store.loadCanvas()
    #expect(graph.nodes[folder.id]?.title == "Project")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func localStoreMigratesLegacyCanvasIntoMainWorkflow() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-workflow-migration-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let folder = CanvasNode(
        id: NodeID(rawValue: "legacy-folder"),
        kind: .folder,
        title: "Legacy Project",
        position: CanvasPoint(x: 10, y: 20),
        size: .folder,
        metadata: NodeMetadata(hostID: HostID(rawValue: "local"), folderPath: "/tmp/legacy")
    )
    var legacyGraph = AgentGraph()
    legacyGraph.upsertNode(folder)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(legacyGraph)
    try data.write(to: paths.canvasURL, options: [.atomic])

    let store = LocalControlRoomStore(paths: paths)
    let graph = try await store.loadCanvas()
    let workflows = try await store.loadWorkflows()

    #expect(graph.nodes[folder.id]?.title == "Legacy Project")
    #expect(workflows.count == 1)
    #expect(workflows.first?.name == "Main Workflow")
    #expect(FileManager.default.fileExists(atPath: paths.workflowCanvasURL(for: "main").path))

    try? FileManager.default.removeItem(at: directory)
}

@Test
func localStoreReplacesWorkflowSnapshot() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-import-tests-\(UUID().uuidString)", isDirectory: true)
    let vault = TestRelayCredentialVault()
    let store = LocalControlRoomStore(
        paths: ApplicationPaths(applicationSupportDirectory: directory),
        relayCredentialVault: vault
    )

    let workflow = WorkflowRecord(id: "remote-main", name: "Remote Main")
    let folder = CanvasNode(
        id: NodeID(rawValue: "folder"),
        kind: .folder,
        title: "Project",
        position: CanvasPoint(x: 10, y: 20),
        size: .folder,
        metadata: NodeMetadata(hostID: HostID(rawValue: "local"), folderPath: "/tmp/project")
    )
    var graph = AgentGraph()
    graph.upsertNode(folder)

    let snapshot = WorkflowSnapshot(
        library: WorkflowLibrarySnapshot(activeWorkflowID: workflow.id, workflows: [workflow]),
        graphsByWorkflowID: [workflow.id: graph],
        workflowEvents: [
            WorkflowEvent(
                id: "event-1",
                kind: .turnCompleted,
                hostID: HostID(rawValue: "local"),
                threadID: "thread-1",
                method: "turn/completed",
                summary: "Turn completed"
            ),
        ],
        relayEndpoints: [
            AppServerRelayEndpoint(
                id: HostID(rawValue: "relay"),
                name: "Relay",
                url: try #require(URL(string: "ws://mac.lan:18945")),
                bearerToken: "secret"
            ),
        ]
    )

    try await store.replaceWorkflowSnapshot(snapshot)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let pointer = try decoder.decode(
        WorkflowSnapshotPointer.self,
        from: Data(contentsOf: directory.appendingPathComponent("workflow-snapshots/current.json"))
    )
    let relayEndpointJSON = try String(
        contentsOf: directory
            .appendingPathComponent("workflow-snapshots")
            .appendingPathComponent(pointer.activeSnapshotID)
            .appendingPathComponent("relay-endpoints.json"),
        encoding: .utf8
    )

    #expect(try await store.activeWorkflowID() == workflow.id)
    #expect(try await store.loadWorkflows() == [workflow])
    #expect(try await store.loadCanvas().nodes[folder.id]?.title == "Project")
    #expect(try await store.loadWorkflowEvents().map(\.id) == ["event-1"])
    #expect(relayEndpointJSON.contains("secret") == false)
    #expect(try await store.loadRelayEndpoints().first?.bearerToken == "secret")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func localStoreRejectsSnapshotMissingNonActiveGraphWithoutOverwriting() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-missing-graph-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let existingFolder = CanvasNode(
        id: NodeID(rawValue: "existing-folder"),
        kind: .folder,
        title: "Existing",
        position: CanvasPoint(x: 10, y: 20),
        size: .folder
    )
    _ = try await store.applyCanvasPatch(.upsertNode(existingFolder))

    let activeWorkflow = WorkflowRecord(id: "active", name: "Active")
    let missingWorkflow = WorkflowRecord(id: "missing", name: "Missing")
    var replacementGraph = AgentGraph()
    replacementGraph.upsertNode(
        CanvasNode(
            id: NodeID(rawValue: "replacement-folder"),
            kind: .folder,
            title: "Replacement",
            position: CanvasPoint(x: 30, y: 40),
            size: .folder
        )
    )
    let snapshot = WorkflowSnapshot(
        library: WorkflowLibrarySnapshot(activeWorkflowID: activeWorkflow.id, workflows: [activeWorkflow, missingWorkflow]),
        graphsByWorkflowID: [activeWorkflow.id: replacementGraph]
    )

    var integrityError: WorkflowSnapshotIntegrityError?
    do {
        try await store.replaceWorkflowSnapshot(snapshot)
    } catch let error as WorkflowSnapshotIntegrityError {
        integrityError = error
    }

    #expect(integrityError == .missingWorkflowGraph(missingWorkflow.id))
    let graph = try await store.loadCanvas()
    #expect(graph.nodes[existingFolder.id]?.title == "Existing")
    #expect(graph.nodes[NodeID(rawValue: "replacement-folder")] == nil)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func localStoreRejectsDuplicateWorkflowIDsWithoutOverwriting() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-duplicate-workflow-tests-\(UUID().uuidString)", isDirectory: true)
    let store = LocalControlRoomStore(paths: ApplicationPaths(applicationSupportDirectory: directory))
    let existingFolder = CanvasNode(
        id: NodeID(rawValue: "existing-folder"),
        kind: .folder,
        title: "Existing",
        position: CanvasPoint(x: 10, y: 20),
        size: .folder
    )
    _ = try await store.applyCanvasPatch(.upsertNode(existingFolder))

    let duplicateA = WorkflowRecord(id: "duplicate", name: "Duplicate A")
    let duplicateB = WorkflowRecord(id: "duplicate", name: "Duplicate B")
    let snapshot = WorkflowSnapshot(
        library: WorkflowLibrarySnapshot(activeWorkflowID: duplicateA.id, workflows: [duplicateA, duplicateB]),
        graphsByWorkflowID: [duplicateA.id: AgentGraph(title: "Replacement")]
    )

    var integrityError: WorkflowSnapshotIntegrityError?
    do {
        try await store.replaceWorkflowSnapshot(snapshot)
    } catch let error as WorkflowSnapshotIntegrityError {
        integrityError = error
    }

    #expect(integrityError == .duplicateWorkflowID("duplicate"))
    let graph = try await store.loadCanvas()
    #expect(graph.nodes[existingFolder.id]?.title == "Existing")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func snapshotImportFailureBeforePointerSwitchLeavesLiveStateUntouched() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-atomicity-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    let originalStore = LocalControlRoomStore(paths: paths)
    try await originalStore.replaceWorkflowSnapshot(testWorkflowSnapshot(id: "original", title: "Original"))

    let pointerDataBefore = try Data(contentsOf: paths.workflowSnapshotPointerURL)
    let failingStore = LocalControlRoomStore(
        paths: paths,
        snapshotFailureInjector: { step in
            if step == .workflowGraph("replacement") {
                throw SnapshotInjectionError.injected
            }
        }
    )

    var didThrowInjectedFailure = false
    do {
        try await failingStore.replaceWorkflowSnapshot(
            testWorkflowSnapshot(id: "replacement", title: "Replacement")
        )
    } catch SnapshotInjectionError.injected {
        didThrowInjectedFailure = true
    }

    #expect(didThrowInjectedFailure)
    #expect(try Data(contentsOf: paths.workflowSnapshotPointerURL) == pointerDataBefore)
    #expect(try await failingStore.loadCanvas().title == "Original")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func snapshotPointerWriteFailureLeavesLegacyStateAndNoStagedVersions() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-pointer-failure-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacyEncoder = JSONEncoder()
    legacyEncoder.dateEncodingStrategy = .iso8601
    try legacyEncoder.encode(AgentGraph(title: "Legacy Live")).write(
        to: paths.canvasURL,
        options: [.atomic]
    )

    let failingStore = LocalControlRoomStore(
        paths: paths,
        snapshotFailureInjector: { step in
            if step == .activatePointer {
                throw SnapshotInjectionError.injected
            }
        }
    )
    var didThrowInjectedFailure = false
    do {
        try await failingStore.replaceWorkflowSnapshot(
            testWorkflowSnapshot(id: "replacement", title: "Replacement")
        )
    } catch SnapshotInjectionError.injected {
        didThrowInjectedFailure = true
    }

    #expect(didThrowInjectedFailure)
    #expect(FileManager.default.fileExists(atPath: paths.workflowSnapshotPointerURL.path) == false)
    #expect(try await failingStore.loadCanvas().title == "Legacy Live")
    let snapshotDirectoryContents = try FileManager.default.contentsOfDirectory(
        at: paths.workflowSnapshotsDirectory,
        includingPropertiesForKeys: nil
    )
    #expect(snapshotDirectoryContents.isEmpty)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func snapshotPointerFailureRollsBackRelayCredentialMutation() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-credential-rollback-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    let vault = TestRelayCredentialVault()
    let endpointURL = try #require(URL(string: "wss://mac.example.test/app-server"))
    var original = testWorkflowSnapshot(id: "original", title: "Original")
    original.relayEndpoints = [
        AppServerRelayEndpoint(
            id: HostID(rawValue: "paired-mac"),
            name: "Paired Mac",
            url: endpointURL,
            bearerToken: "original-credential"
        ),
    ]
    let originalStore = LocalControlRoomStore(paths: paths, relayCredentialVault: vault)
    try await originalStore.replaceWorkflowSnapshot(original)
    let pointerDataBefore = try Data(contentsOf: paths.workflowSnapshotPointerURL)

    var replacement = testWorkflowSnapshot(id: "replacement", title: "Replacement")
    replacement.relayEndpoints = [
        AppServerRelayEndpoint(
            id: HostID(rawValue: "paired-mac"),
            name: "Paired Mac",
            url: endpointURL,
            bearerToken: "replacement-credential"
        ),
    ]
    let failingStore = LocalControlRoomStore(
        paths: paths,
        relayCredentialVault: vault,
        snapshotFailureInjector: { step in
            if step == .activatePointer {
                throw SnapshotInjectionError.injected
            }
        }
    )

    await #expect(throws: SnapshotInjectionError.self) {
        try await failingStore.replaceWorkflowSnapshot(replacement)
    }

    #expect(try Data(contentsOf: paths.workflowSnapshotPointerURL) == pointerDataBefore)
    #expect(vault.credential(for: "relay:paired-mac") == "original-credential")
    #expect(try await failingStore.loadCanvas().title == "Original")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func workflowSnapshotRollbackRestoresVersionedRelayCredential() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-credential-version-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    let vault = TestRelayCredentialVault()
    let store = LocalControlRoomStore(paths: paths, relayCredentialVault: vault)
    let endpointURL = try #require(URL(string: "wss://mac.example.test/app-server"))

    var first = testWorkflowSnapshot(id: "first", title: "First")
    first.relayEndpoints = [
        AppServerRelayEndpoint(
            id: HostID(rawValue: "paired-mac"),
            name: "Paired Mac",
            url: endpointURL,
            bearerToken: "first-credential"
        ),
    ]
    try await store.replaceWorkflowSnapshot(first)
    let firstReference = try #require(
        try await store.loadRelayEndpoints().first?.credentialReference
    )

    var second = testWorkflowSnapshot(id: "second", title: "Second")
    second.relayEndpoints = [
        AppServerRelayEndpoint(
            id: HostID(rawValue: "paired-mac"),
            name: "Paired Mac",
            url: endpointURL,
            bearerToken: "second-credential",
            credentialReference: firstReference
        ),
    ]
    try await store.replaceWorkflowSnapshot(second)
    let secondEndpoint = try #require(try await store.loadRelayEndpoints().first)
    #expect(secondEndpoint.bearerToken == "second-credential")
    #expect(secondEndpoint.credentialReference != firstReference)

    try await store.rollbackWorkflowSnapshot()
    let restoredEndpoint = try #require(try await store.loadRelayEndpoints().first)
    #expect(restoredEndpoint.credentialReference == firstReference)
    #expect(restoredEndpoint.bearerToken == "first-credential")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func relayCredentialRecoveryJournalRemovesPrePointerCrashCredential() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-relay-crash-recovery-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    let vault = TestRelayCredentialVault()
    let setupStore = LocalControlRoomStore(paths: paths, relayCredentialVault: vault)
    try await setupStore.replaceWorkflowSnapshot(testWorkflowSnapshot(id: "active", title: "Active"))

    let orphanedReference = "relay:paired-mac:v:interrupted-before-pointer"
    try vault.save("orphaned-credential", reference: orphanedReference)
    try Data("{\"references\":[\"\(orphanedReference)\"]}".utf8).write(
        to: directory.appendingPathComponent("relay-credential-recovery.json"),
        options: [.atomic]
    )

    let recoveredStore = LocalControlRoomStore(paths: paths, relayCredentialVault: vault)
    _ = try await recoveredStore.loadCanvas()

    #expect(vault.credential(for: orphanedReference) == nil)
    #expect(FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("relay-credential-recovery.json").path
    ) == false)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func workflowSnapshotRollbackAtomicallyRestoresPreviousVersion() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-rollback-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    let store = LocalControlRoomStore(paths: paths)

    try await store.replaceWorkflowSnapshot(testWorkflowSnapshot(id: "first", title: "First"))
    try await store.replaceWorkflowSnapshot(testWorkflowSnapshot(id: "second", title: "Second"))
    #expect(try await store.loadCanvas().title == "Second")

    try await store.rollbackWorkflowSnapshot()
    #expect(try await store.activeWorkflowID() == "first")
    #expect(try await store.loadCanvas().title == "First")

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let pointer = try decoder.decode(
        WorkflowSnapshotPointer.self,
        from: Data(contentsOf: paths.workflowSnapshotPointerURL)
    )
    #expect(pointer.rollbackSnapshotIDs.count <= 2)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func corruptRollbackSnapshotDoesNotChangeActivePointer() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-snapshot-corrupt-rollback-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    let store = LocalControlRoomStore(paths: paths)

    try await store.replaceWorkflowSnapshot(testWorkflowSnapshot(id: "first", title: "First"))
    try await store.replaceWorkflowSnapshot(testWorkflowSnapshot(id: "second", title: "Second"))

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let pointerDataBefore = try Data(contentsOf: paths.workflowSnapshotPointerURL)
    let pointer = try decoder.decode(WorkflowSnapshotPointer.self, from: pointerDataBefore)
    let rollbackID = try #require(pointer.rollbackSnapshotIDs.first)
    try Data("{not-json".utf8).write(
        to: paths.workflowSnapshotDirectory(for: rollbackID).appendingPathComponent("metadata.json"),
        options: [.atomic]
    )

    var rejectedCorruption = false
    do {
        try await store.rollbackWorkflowSnapshot()
    } catch is DecodingError {
        rejectedCorruption = true
    }

    #expect(rejectedCorruption)
    #expect(try Data(contentsOf: paths.workflowSnapshotPointerURL) == pointerDataBefore)
    #expect(try await store.loadCanvas().title == "Second")

    try? FileManager.default.removeItem(at: directory)
}

@Test
func persistenceFileComponentsAvoidWorkflowAndTranscriptCollisions() {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-filename-collision-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    let slashWorkflow = paths.workflowCanvasURL(for: "a/b")
    let underscoreWorkflow = paths.workflowCanvasURL(for: "a_b")
    let firstThread = ThreadRef(hostID: HostID(rawValue: "a/b"), threadID: "c", cwd: "/tmp")
    let secondThread = ThreadRef(hostID: HostID(rawValue: "a_b"), threadID: "c", cwd: "/tmp")
    let thirdThread = ThreadRef(hostID: HostID(rawValue: "a"), threadID: "b__c", cwd: "/tmp")
    let fourthThread = ThreadRef(hostID: HostID(rawValue: "a__b"), threadID: "c", cwd: "/tmp")

    #expect(slashWorkflow != underscoreWorkflow)
    #expect(slashWorkflow.lastPathComponent.hasPrefix("~b64_"))
    #expect(paths.transcriptURL(for: firstThread) != paths.transcriptURL(for: secondThread))
    #expect(paths.transcriptURL(for: thirdThread) != paths.transcriptURL(for: fourthThread))
}

@Test
func localStoreLoadsLegacySanitizedWorkflowCanvasFilename() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-legacy-workflow-filename-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = ApplicationPaths(applicationSupportDirectory: directory)
    try FileManager.default.createDirectory(at: paths.workflowsDirectory, withIntermediateDirectories: true)
    let workflowID = "a/b"
    let library = WorkflowLibrarySnapshot(
        activeWorkflowID: workflowID,
        workflows: [WorkflowRecord(id: workflowID, name: "Legacy")]
    )
    let graph = AgentGraph(title: "Legacy Graph")
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(library).write(to: paths.workflowLibraryURL, options: [.atomic])
    try encoder.encode(graph).write(to: paths.legacyWorkflowCanvasURL(for: workflowID), options: [.atomic])

    let store = LocalControlRoomStore(paths: paths)
    let restored = try await store.loadCanvas()

    #expect(restored.title == "Legacy Graph")
    #expect(paths.workflowCanvasURL(for: workflowID) != paths.legacyWorkflowCanvasURL(for: workflowID))

    try? FileManager.default.removeItem(at: directory)
}

@Test
func workflowSnapshotRewritesMacLocalHostForIPhone() throws {
    let macHostID = HostID(rawValue: "relay-ws-mac-lan-18945")
    let machine = CanvasNode(
        id: NodeID(rawValue: "local-machine"),
        kind: .machine,
        title: "Mac",
        subtitle: "macOS - local",
        position: CanvasPoint(x: 10, y: 10),
        size: .machine,
        metadata: NodeMetadata(hostID: HostID(rawValue: "local"), platform: .macOS, hostStatus: .connected)
    )
    let thread = CanvasNode(
        id: NodeID(rawValue: "thread"),
        kind: .codexThread,
        title: "Thread",
        position: CanvasPoint(x: 100, y: 100),
        size: .thread,
        metadata: NodeMetadata(
            hostID: HostID(rawValue: "local"),
            platform: .macOS,
            threadRef: ThreadRef(
                hostID: HostID(rawValue: "local"),
                threadID: "thread-1",
                cwd: "/tmp/project"
            )
        )
    )
    var graph = AgentGraph()
    graph.upsertNode(machine)
    graph.upsertNode(thread)
    graph.upsertMessageRoute(
        MessageRoute(
            id: "route-1",
            sourceHostID: HostID(rawValue: "local"),
            sourceThreadID: "thread-1",
            targetHostID: HostID(rawValue: "local"),
            targetThreadID: "thread-2",
            snippet: "handoff"
        )
    )

    let snapshot = WorkflowSnapshot(
        library: WorkflowLibrarySnapshot(activeWorkflowID: "main", workflows: [WorkflowRecord(id: "main", name: "Main")]),
        graphsByWorkflowID: ["main": graph],
        workflowEvents: [
            WorkflowEvent(
                kind: .turnStarted,
                hostID: HostID(rawValue: "local"),
                threadID: "thread-1",
                method: "turn/started",
                summary: "Turn started"
            ),
        ]
    )

    let rewritten = snapshot.replacingLocalHost(with: macHostID, machineName: "mac-host.lan")
    let rewrittenGraph = try #require(rewritten.graphsByWorkflowID["main"])

    #expect(rewrittenGraph.nodes[machine.id]?.title == "mac-host.lan")
    #expect(rewrittenGraph.nodes[machine.id]?.metadata.hostID == macHostID)
    #expect(rewrittenGraph.nodes[thread.id]?.metadata.hostID == macHostID)
    #expect(rewrittenGraph.nodes[thread.id]?.metadata.threadRef?.hostID == macHostID)
    #expect(rewrittenGraph.messageRoutes["route-1"]?.sourceHostID == macHostID)
    #expect(rewrittenGraph.messageRoutes["route-1"]?.targetHostID == macHostID)
    #expect(rewritten.workflowEvents.first?.hostID == macHostID)
}

private enum SnapshotInjectionError: Error {
    case injected
}

private func testWorkflowSnapshot(id: String, title: String) -> WorkflowSnapshot {
    let workflow = WorkflowRecord(id: id, name: title)
    return WorkflowSnapshot(
        library: WorkflowLibrarySnapshot(activeWorkflowID: id, workflows: [workflow]),
        graphsByWorkflowID: [id: AgentGraph(title: title)]
    )
}
