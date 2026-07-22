import Foundation
@testable import MapofAgentsCore
import Testing

@Test
func codexRuntimeVersionParserPreservesPrereleaseIdentifiers() {
    #expect(CodexRuntimeUpdateService.parseVersion(from: "codex-cli 0.144.1") == "0.144.1")
    #expect(
        CodexRuntimeUpdateService.parseVersion(from: "codex-cli 0.145.0-alpha.4")
            == "0.145.0-alpha.4"
    )
    #expect(CodexRuntimeUpdateService.parseVersion(from: "not a version") == nil)
}

@Test
func unknownRunningCodexRuntimeRequiresRestartWhenAnInstalledVersionExists() {
    #expect(CodexRuntimeVersionStatus(installedVersion: "0.144.1", runningVersion: nil).needsRestart)
    #expect(!CodexRuntimeVersionStatus(installedVersion: nil, runningVersion: nil).needsRestart)
}

@Test
func codexRuntimeVersionUsesLiveInitializeUserAgentShape() {
    let initializeResult: JSONValue = .object([
        "userAgent": .string("codex_cli_rs/0.144.1 (Mac OS 26.0; arm64)"),
        "platformFamily": .string("macOS"),
    ])

    #expect(CodexRuntimeStore.runtimeVersion(fromInitializeResult: initializeResult) == "0.144.1")
}

@Test
func codexRuntimeUpdaterUsesOfficialUpdateAndRediscoversExecutable() async throws {
    let probe = RuntimeUpdateCommandProbe(
        installedVersion: "0.142.0",
        updateVersion: "0.144.1",
        initialPath: "/tmp/codex-old",
        updatedPath: "/tmp/codex-new"
    )
    let service = CodexRuntimeUpdateService(
        resolveExecutable: { probe.executableURL },
        runCommand: probe.run
    )

    let result = try await service.applyUpdate()

    #expect(result.previousVersion == "0.142.0")
    #expect(result.installedVersion == "0.144.1")
    #expect(result.didUpdate)
    #expect(probe.updateCallCount == 1)
    #expect(
        probe.calls == [
            RuntimeUpdateCommandProbe.Call(path: "/tmp/codex-old", arguments: ["--version"], timeout: 10),
            RuntimeUpdateCommandProbe.Call(path: "/tmp/codex-old", arguments: ["update"], timeout: 300),
            RuntimeUpdateCommandProbe.Call(path: "/tmp/codex-new", arguments: ["--version"], timeout: 10),
        ]
    )
}

@Test
func unchangedCodexRuntimeSkipsRestartDecision() async throws {
    let probe = RuntimeUpdateCommandProbe(
        installedVersion: "0.144.1",
        updateVersion: "0.144.1"
    )
    let service = CodexRuntimeUpdateService(
        resolveExecutable: { probe.executableURL },
        runCommand: probe.run
    )

    let result = try await service.applyUpdate()

    #expect(!result.didUpdate)
    #expect(!probe.calls.contains { $0.arguments.contains("restart") })
}

@Test
func simultaneousCodexRuntimeUpdatesShareOneOfficialUpdate() async throws {
    let probe = RuntimeUpdateCommandProbe(
        installedVersion: "0.142.0",
        updateVersion: "0.144.1",
        updateDelay: .milliseconds(50)
    )
    let service = CodexRuntimeUpdateService(
        resolveExecutable: { probe.executableURL },
        runCommand: probe.run
    )

    async let first = service.applyUpdate()
    async let second = service.applyUpdate()
    let results = try await [first, second]

    #expect(results[0] == results[1])
    #expect(probe.updateCallCount == 1)
}

@Test
func failedCodexRuntimeUpdateDoesNotAttemptRestart() async {
    let probe = RuntimeUpdateCommandProbe(
        installedVersion: "0.142.0",
        updateVersion: "0.144.1",
        updateExitCode: 7
    )
    let service = CodexRuntimeUpdateService(
        resolveExecutable: { probe.executableURL },
        runCommand: probe.run
    )

    await #expect(throws: CodexRuntimeUpdateError.updateFailed(exitCode: 7)) {
        try await service.applyUpdate()
    }
    #expect(!probe.calls.contains { $0.arguments.contains("restart") })
}

@Test
func daemonRestartIsVerifiedAgainstInstalledVersion() async throws {
    let probe = RuntimeUpdateCommandProbe(
        installedVersion: "0.144.1",
        updateVersion: "0.144.1",
        runningVersion: "0.142.0"
    )
    let service = CodexRuntimeUpdateService(
        resolveExecutable: { probe.executableURL },
        runCommand: probe.run
    )

    let status = try await service.restartDaemonAndVerify()

    #expect(status.installedVersion == "0.144.1")
    #expect(status.runningVersion == "0.144.1")
    #expect(probe.restartCallCount == 1)
    #expect(
        probe.calls.first(where: { $0.arguments == ["app-server", "daemon", "restart"] })?.timeout
            == 120
    )
}

@MainActor
@Test
func activeRuntimeWorkBlocksUpdaterUntilTurnCompletes() {
    let store = CodexRuntimeStore()
    let started = WorkflowEvent(
        id: "turn-started",
        kind: .turnStarted,
        hostID: store.localHost.id,
        threadID: "thread-1",
        method: "turn/started",
        summary: "Turn started"
    )
    let completed = WorkflowEvent(
        id: "turn-completed",
        kind: .turnCompleted,
        hostID: store.localHost.id,
        threadID: "thread-1",
        method: "turn/completed",
        summary: "Turn completed"
    )

    store.recordWorkflowEvent(started)
    #expect(store.activeRuntimeWorkCount == 1)
    #expect(!store.beginRuntimeMaintenance())

    store.recordWorkflowEvent(completed)
    #expect(store.activeRuntimeWorkCount == 0)
    #expect(store.beginRuntimeMaintenance())
    #expect(store.isRuntimeMaintenanceInProgress)
    store.endRuntimeMaintenance()
    #expect(!store.isRuntimeMaintenanceInProgress)
}

@MainActor
@Test
func runtimeMaintenanceRejectsNewLocalWritesBeforeConnecting() async {
    let store = CodexRuntimeStore()
    #expect(store.beginRuntimeMaintenance())
    defer { store.endRuntimeMaintenance() }

    do {
        try await store.archiveThread(ThreadRef(
            hostID: store.localHost.id,
            threadID: "thread-1",
            cwd: "/Users/example/project"
        ))
        Issue.record("A local write should not start during runtime maintenance")
    } catch {
        #expect(error.localizedDescription.contains("being updated"))
    }
}

private final class RuntimeUpdateCommandProbe: @unchecked Sendable {
    struct Call: Sendable, Hashable {
        var path: String
        var arguments: [String]
        var timeout: TimeInterval
    }

    private let lock = NSLock()
    private var installedVersion: String
    private let updateVersion: String
    private var runningVersion: String
    private var path: String
    private let updatedPath: String
    private let updateExitCode: Int32
    private let updateDelay: Duration?
    private var recordedCalls: [Call] = []
    private var recordedUpdateCalls = 0
    private var recordedRestartCalls = 0

    init(
        installedVersion: String,
        updateVersion: String,
        runningVersion: String? = nil,
        initialPath: String = "/tmp/codex",
        updatedPath: String? = nil,
        updateExitCode: Int32 = 0,
        updateDelay: Duration? = nil
    ) {
        self.installedVersion = installedVersion
        self.updateVersion = updateVersion
        self.runningVersion = runningVersion ?? installedVersion
        self.path = initialPath
        self.updatedPath = updatedPath ?? initialPath
        self.updateExitCode = updateExitCode
        self.updateDelay = updateDelay
    }

    var executableURL: URL {
        lock.withLock { URL(fileURLWithPath: path) }
    }

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    var updateCallCount: Int {
        lock.withLock { recordedUpdateCalls }
    }

    var restartCallCount: Int {
        lock.withLock { recordedRestartCalls }
    }

    func run(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> BoundedProcessResult {
        _ = timeout
        lock.withLock {
            recordedCalls.append(Call(path: executableURL.path, arguments: arguments, timeout: timeout))
        }

        if arguments == ["update"] {
            if let updateDelay {
                try await Task.sleep(for: updateDelay)
            }
            lock.withLock {
                recordedUpdateCalls += 1
                if updateExitCode == 0 {
                    installedVersion = updateVersion
                    path = updatedPath
                }
            }
            return result(status: updateExitCode)
        }

        if arguments == ["app-server", "daemon", "restart"] {
            lock.withLock {
                recordedRestartCalls += 1
                runningVersion = installedVersion
            }
            return result()
        }

        if arguments == ["app-server", "daemon", "version"] {
            let payload = lock.withLock {
                "{\"status\":\"running\",\"appServerVersion\":\"\(runningVersion)\"}"
            }
            return result(stdout: payload)
        }

        if arguments == ["--version"] {
            return result(stdout: lock.withLock { "codex-cli \(installedVersion)" })
        }

        return result(status: 64)
    }

    private func result(
        status: Int32 = 0,
        stdout: String = "",
        stderr: String = ""
    ) -> BoundedProcessResult {
        BoundedProcessResult(
            terminationStatus: status,
            stdout: BoundedProcessOutput(data: Data(stdout.utf8)),
            stderr: BoundedProcessOutput(data: Data(stderr.utf8))
        )
    }
}
