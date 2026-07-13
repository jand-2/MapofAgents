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
    let supervisorStore: WorkflowSupervisorStore
    let threadCatalogStore: ThreadCatalogStore
    let workflowLibrary: WorkflowLibraryCoordinator
    let threadCreation: ThreadCreationCoordinator
    let bootstrapErrorMessage: String?

    private(set) var pairingHostError: String?
    private(set) var isStarted = false

    @ObservationIgnored private let services: MapofAgentsAppSessionServices
    @ObservationIgnored private var pairingHostSupervisionTask: Task<Void, Never>?
    @ObservationIgnored private var hookEventBridgeTask: Task<Void, Never>?
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
        self.supervisorStore = WorkflowSupervisorStore()
        self.threadCatalogStore = ThreadCatalogStore()
        self.workflowLibrary = WorkflowLibraryCoordinator(repository: repository)
        self.threadCreation = ThreadCreationCoordinator()
        self.bootstrapErrorMessage = bootstrapErrorMessage
        self.services = services

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
        isStarted = true
        supervisorStore.start()
        startWorkflowHookEventBridge()

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

    func stop(terminateRuntime: Bool = true) {
        guard isStarted || pairingHostSupervisionTask != nil || hookEventBridgeTask != nil else {
            return
        }
        isStarted = false
        pairingHostSupervisionTask?.cancel()
        pairingHostSupervisionTask = nil
        hookEventBridgeTask?.cancel()
        hookEventBridgeTask = nil
        if terminateRuntime {
            services.terminatePairingHostRuntime()
        }
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
#endif
