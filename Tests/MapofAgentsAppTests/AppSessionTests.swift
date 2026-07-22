#if os(macOS)
import Foundation
import MapofAgentsCore
import Testing
@testable import MapofAgentsApp

@MainActor
@Test
func appSessionStartsProcessServicesOnlyOnce() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-app-session-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let probe = AppSessionServiceProbe()
    let services = MapofAgentsAppSessionServices(
        hasActivePairedDevices: { true },
        migrateLegacyPersistentRoutes: {
            probe.recordMigration()
        },
        ensurePairingHostRunning: {
            probe.recordPairingHostCheck()
        },
        terminatePairingHostRuntime: {
            probe.recordTermination()
        },
        startHookBridge: { _, _ in
            probe.recordHookStart()
            return Task {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    probe.recordHookCancellation()
                }
            }
        },
        pairingSupervisionInterval: .seconds(60)
    )
    let session = MapofAgentsAppSession(
        paths: ApplicationPaths(applicationSupportDirectory: directory),
        services: services,
        observesApplicationTermination: false
    )
    let repository = session.repository
    let runtimeStore = session.runtimeStore

    await session.start()
    await session.start()
    session.ensurePairingHostSupervision()
    session.ensurePairingHostSupervision()
    await waitForAppSessionProbe { probe.pairingHostCheckCount == 1 }

    #expect(session.repository === repository)
    #expect(session.runtimeStore === runtimeStore)
    #expect(probe.hookStartCount == 1)
    #expect(probe.pairingHostCheckCount == 1)
    #expect(probe.migrationCount == 0)

    session.stop()
    session.stop()
    await waitForAppSessionProbe { probe.hookCancellationCount == 1 }
    #expect(probe.terminationCount == 1)
    #expect(probe.hookCancellationCount == 1)
}

@MainActor
@Test
func appSessionBlocksRuntimeUpdateWhileLocalWorkIsActive() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-update-session-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let updateService = CodexRuntimeUpdateService(
        resolveExecutable: { nil },
        runCommand: { _, _, _ in
            Issue.record("The updater must not run while local work is active")
            return BoundedProcessResult(
                terminationStatus: 1,
                stdout: BoundedProcessOutput(data: Data()),
                stderr: BoundedProcessOutput(data: Data())
            )
        }
    )
    let services = MapofAgentsAppSessionServices(
        hasActivePairedDevices: { false },
        migrateLegacyPersistentRoutes: {},
        ensurePairingHostRunning: {},
        terminatePairingHostRuntime: {},
        startHookBridge: { _, _ in Task {} },
        runtimeUpdateService: updateService,
        pairingSupervisionInterval: .seconds(60)
    )
    let session = MapofAgentsAppSession(
        paths: ApplicationPaths(applicationSupportDirectory: directory),
        services: services,
        observesApplicationTermination: false
    )
    await session.start()
    session.runtimeStore.recordWorkflowEvent(WorkflowEvent(
        id: "turn-started",
        kind: .turnStarted,
        hostID: session.runtimeStore.localHost.id,
        threadID: "thread-1",
        method: "turn/started",
        summary: "Turn started"
    ))

    session.updateCodexRuntime()

    #expect(session.runtimeUpdatePhase == .failed)
    #expect(session.runtimeUpdateMessage?.contains("active local thread") == true)
    session.stop()
}

@MainActor
@Test
func stoppingAppSessionDuringUpdatePreventsRuntimeRestartAndReconnect() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-cancel-update-session-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let probe = SuspendedRuntimeUpdateProbe()
    let updateService = CodexRuntimeUpdateService(
        resolveExecutable: { URL(fileURLWithPath: "/tmp/codex") },
        runCommand: probe.run
    )
    let services = MapofAgentsAppSessionServices(
        hasActivePairedDevices: { false },
        migrateLegacyPersistentRoutes: {},
        ensurePairingHostRunning: {},
        terminatePairingHostRuntime: {},
        startHookBridge: { _, _ in Task {} },
        runtimeUpdateService: updateService,
        pairingSupervisionInterval: .seconds(60)
    )
    let session = MapofAgentsAppSession(
        paths: ApplicationPaths(applicationSupportDirectory: directory),
        services: services,
        observesApplicationTermination: false
    )

    await session.start()
    session.updateCodexRuntime()
    await waitForAsyncAppSessionProbe { await probe.hasStartedUpdate }
    #expect(session.runtimeStore.isRuntimeMaintenanceInProgress)

    session.stop()
    await probe.releaseUpdate()
    await waitForAppSessionProbe { !session.runtimeStore.isRuntimeMaintenanceInProgress }

    #expect(await probe.restartCallCount == 0)
    #expect(session.runtimeStore.connectionState != .connected)
    #expect(session.runtimeUpdatePhase == .idle)
}

@Test
func runtimeUpdateRestartsWhenConnectedStdioVersionIsStaleOrUnknown() {
    let update = CodexRuntimeUpdateResult(
        previousVersion: "0.144.1",
        installedVersion: "0.144.1"
    )
    let daemonStatus = CodexRuntimeVersionStatus(
        installedVersion: "0.144.1",
        runningVersion: "0.144.1"
    )

    #expect(!MapofAgentsAppSession.shouldRestartCodexRuntime(
        update: update,
        daemonStatus: daemonStatus,
        connectionState: .connected,
        connectedRuntimeVersion: "0.144.1"
    ))
    #expect(MapofAgentsAppSession.shouldRestartCodexRuntime(
        update: update,
        daemonStatus: daemonStatus,
        connectionState: .connected,
        connectedRuntimeVersion: "0.142.0"
    ))
    #expect(MapofAgentsAppSession.shouldRestartCodexRuntime(
        update: update,
        daemonStatus: daemonStatus,
        connectionState: .connected,
        connectedRuntimeVersion: nil
    ))
}

@MainActor
@Test
func initialBootstrapPublishesCrossWorkflowMembershipsBeforeSupervisorThreads() async throws {
    let hostID = HostID(rawValue: "example-host")
    let sharedThread = ThreadRef(
        hostID: hostID,
        threadID: "thread-1",
        cwd: "/Users/example/project",
        name: "Shared thread"
    )
    let activeWorkflow = WorkflowRecord(id: "active", name: "Active")
    let otherWorkflow = WorkflowRecord(id: "other", name: "Other")
    let activeNode = CanvasNode(
        id: NodeID(rawValue: "active-node"),
        kind: .codexThread,
        title: "Active thread",
        position: .zero,
        size: .thread,
        metadata: NodeMetadata(threadRef: sharedThread)
    )
    let otherNode = CanvasNode(
        id: NodeID(rawValue: "other-node"),
        kind: .codexThread,
        title: "Other thread",
        position: .zero,
        size: .thread,
        metadata: NodeMetadata(threadRef: sharedThread)
    )
    let snapshot = WorkflowSnapshot(
        library: WorkflowLibrarySnapshot(
            activeWorkflowID: activeWorkflow.id,
            workflows: [activeWorkflow, otherWorkflow]
        ),
        graphsByWorkflowID: [
            activeWorkflow.id: AgentGraph(nodes: [activeNode.id: activeNode]),
            otherWorkflow.id: AgentGraph(nodes: [otherNode.id: otherNode]),
        ]
    )
    var steps: [String] = []
    var publishedMemberships: [String: [ThreadWorkflowMembership]] = [:]
    var supervisorObservedMemberships: [String: [ThreadWorkflowMembership]] = [:]

    try await RootWorkflowBootstrap.run(
        refreshWorkflowLibrary: { steps.append("library") },
        loadGraph: { steps.append("graph") },
        loadSnapshot: {
            steps.append("snapshot")
            return snapshot
        },
        activeWorkflowID: { activeWorkflow.id },
        workflowThreadRefs: { [sharedThread] },
        publishMemberships: {
            steps.append("memberships")
            publishedMemberships = $0
        },
        publishWorkflowThreads: { threadRefs in
            steps.append("threads")
            supervisorObservedMemberships = publishedMemberships
            #expect(threadRefs == [sharedThread])
        }
    )

    #expect(steps == ["library", "graph", "snapshot", "memberships", "threads"])
    #expect(publishedMemberships[sharedThread.qualifiedID]?.map(\.workflowID) == ["active", "other"])
    #expect(supervisorObservedMemberships == publishedMemberships)
}

private final class AppSessionServiceProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var hookStarts = 0
    private var hookCancellations = 0
    private var pairingHostChecks = 0
    private var migrations = 0
    private var terminations = 0

    var hookStartCount: Int { lock.withLock { hookStarts } }
    var hookCancellationCount: Int { lock.withLock { hookCancellations } }
    var pairingHostCheckCount: Int { lock.withLock { pairingHostChecks } }
    var migrationCount: Int { lock.withLock { migrations } }
    var terminationCount: Int { lock.withLock { terminations } }

    func recordHookStart() { lock.withLock { hookStarts += 1 } }
    func recordHookCancellation() { lock.withLock { hookCancellations += 1 } }
    func recordPairingHostCheck() { lock.withLock { pairingHostChecks += 1 } }
    func recordMigration() { lock.withLock { migrations += 1 } }
    func recordTermination() { lock.withLock { terminations += 1 } }
}

private actor SuspendedRuntimeUpdateProbe {
    private var installedVersion = "0.142.0"
    private var updateStarted = false
    private var releaseRequested = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var restartCalls = 0

    var hasStartedUpdate: Bool { updateStarted }
    var restartCallCount: Int { restartCalls }

    func releaseUpdate() {
        releaseRequested = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> BoundedProcessResult {
        _ = executableURL
        _ = timeout

        switch arguments {
        case ["--version"]:
            return result(stdout: "codex-cli \(installedVersion)")
        case ["update"]:
            updateStarted = true
            if !releaseRequested {
                await withCheckedContinuation { continuation in
                    releaseContinuation = continuation
                }
            }
            installedVersion = "0.144.1"
            return result()
        case ["app-server", "daemon", "restart"]:
            restartCalls += 1
            return result()
        case ["app-server", "daemon", "version"]:
            return result(stdout: "{\"status\":\"running\",\"appServerVersion\":\"\(installedVersion)\"}")
        default:
            return result(status: 64)
        }
    }

    private func result(status: Int32 = 0, stdout: String = "") -> BoundedProcessResult {
        BoundedProcessResult(
            terminationStatus: status,
            stdout: BoundedProcessOutput(data: Data(stdout.utf8)),
            stderr: BoundedProcessOutput(data: Data())
        )
    }
}

@MainActor
private func waitForAppSessionProbe(
    maximumYields: Int = 2_000,
    _ condition: () -> Bool
) async {
    for _ in 0..<maximumYields {
        if condition() {
            return
        }
        await Task.yield()
    }
}


@MainActor
private func waitForAsyncAppSessionProbe(
    maximumYields: Int = 2_000,
    _ condition: () async -> Bool
) async {
    for _ in 0..<maximumYields {
        if await condition() {
            return
        }
        await Task.yield()
    }
}
#endif
