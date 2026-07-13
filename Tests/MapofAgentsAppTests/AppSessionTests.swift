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
#endif
