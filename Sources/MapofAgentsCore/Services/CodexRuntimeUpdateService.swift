import Foundation

public enum CodexRuntimeUpdatePhase: String, Sendable, Hashable {
    case idle
    case checking
    case updating
    case restarting
    case reconnecting
    case succeeded
    case failed

    public var isBusy: Bool {
        switch self {
        case .checking, .updating, .restarting, .reconnecting:
            return true
        case .idle, .succeeded, .failed:
            return false
        }
    }
}

public struct CodexRuntimeVersionStatus: Sendable, Hashable {
    public var installedVersion: String?
    public var runningVersion: String?
    public var daemonStatus: String?

    public init(
        installedVersion: String?,
        runningVersion: String?,
        daemonStatus: String? = nil
    ) {
        self.installedVersion = installedVersion
        self.runningVersion = runningVersion
        self.daemonStatus = daemonStatus
    }

    public var needsRestart: Bool {
        guard let installedVersion else { return false }
        guard let runningVersion else { return true }
        return installedVersion != runningVersion
    }
}

public struct CodexRuntimeUpdateResult: Sendable, Hashable {
    public var previousVersion: String
    public var installedVersion: String

    public init(previousVersion: String, installedVersion: String) {
        self.previousVersion = previousVersion
        self.installedVersion = installedVersion
    }

    public var didUpdate: Bool {
        previousVersion != installedVersion
    }
}

public enum CodexRuntimeUpdateError: Error, LocalizedError, Sendable, Equatable {
    case managedRuntimeNotInstalled
    case invalidVersionOutput
    case updateCommandFailed
    case updateFailed(exitCode: Int32)
    case daemonRestartCommandFailed
    case daemonRestartFailed(exitCode: Int32)
    case daemonRestartVerificationFailed(installed: String, running: String?)

    public var errorDescription: String? {
        switch self {
        case .managedRuntimeNotInstalled:
            return "The managed Codex runtime is not installed. Install Codex with the standalone installer first."
        case .invalidVersionOutput:
            return "The installed Codex version could not be verified."
        case .updateCommandFailed:
            return "The Codex updater could not be started. The existing runtime was left running."
        case .updateFailed(let exitCode):
            return "Codex could not be updated (exit code \(exitCode)). The existing runtime was left running."
        case .daemonRestartCommandFailed:
            return "Codex was installed, but the App Server restart command could not be started. Try the update again."
        case .daemonRestartFailed(let exitCode):
            return "Codex was installed, but App Server could not be restarted (exit code \(exitCode)). Try the update again."
        case .daemonRestartVerificationFailed(let installed, let running):
            if let running {
                return "Codex \(installed) is installed, but App Server is still running \(running). Try restarting the runtime."
            }
            return "Codex \(installed) is installed, but the restarted App Server version could not be verified."
        }
    }
}

public actor CodexRuntimeUpdateService {
    public typealias ExecutableResolver = @Sendable () -> URL?
    public typealias CommandRunner = @Sendable (
        _ executableURL: URL,
        _ arguments: [String],
        _ timeout: TimeInterval
    ) async throws -> BoundedProcessResult

    public static let live = CodexRuntimeUpdateService(
        resolveExecutable: {
            LocalCodexDiscovery.findManagedCodexExecutable().map(URL.init(fileURLWithPath:))
        },
        runCommand: { executableURL, arguments, timeout in
            try await BoundedProcessRunner.run(
                executableURL: executableURL,
                arguments: arguments,
                timeout: timeout,
                maxOutputBytes: 128 * 1_024
            )
        }
    )

    private let resolveExecutable: ExecutableResolver
    private let runCommand: CommandRunner
    private var activeUpdateTask: Task<CodexRuntimeUpdateResult, Error>?

    public init(
        resolveExecutable: @escaping ExecutableResolver,
        runCommand: @escaping CommandRunner
    ) {
        self.resolveExecutable = resolveExecutable
        self.runCommand = runCommand
    }

    public func versionStatus() async throws -> CodexRuntimeVersionStatus {
        guard let executableURL = resolveExecutable() else {
            throw CodexRuntimeUpdateError.managedRuntimeNotInstalled
        }
        return try await Self.readVersionStatus(executableURL: executableURL, runCommand: runCommand)
    }

    /// Runs Codex's official self-updater while the current daemon remains available.
    /// The caller should restart App Server when the installed and running
    /// versions differ or the running version cannot be verified.
    public func applyUpdate() async throws -> CodexRuntimeUpdateResult {
        if let activeUpdateTask {
            return try await activeUpdateTask.value
        }

        let resolveExecutable = self.resolveExecutable
        let runCommand = self.runCommand
        let task = Task {
            try await Self.performUpdate(
                resolveExecutable: resolveExecutable,
                runCommand: runCommand
            )
        }
        activeUpdateTask = task
        defer { activeUpdateTask = nil }
        return try await task.value
    }

    public func restartDaemonAndVerify() async throws -> CodexRuntimeVersionStatus {
        guard let executableURL = resolveExecutable() else {
            throw CodexRuntimeUpdateError.managedRuntimeNotInstalled
        }
        let result: BoundedProcessResult
        do {
            result = try await runCommand(
                executableURL,
                ["app-server", "daemon", "restart"],
                120
            )
        } catch {
            throw CodexRuntimeUpdateError.daemonRestartCommandFailed
        }
        guard result.terminationStatus == 0 else {
            throw CodexRuntimeUpdateError.daemonRestartFailed(exitCode: result.terminationStatus)
        }

        let status = try await Self.readVersionStatus(
            executableURL: executableURL,
            runCommand: runCommand
        )
        if let installedVersion = status.installedVersion,
           status.runningVersion != installedVersion {
            throw CodexRuntimeUpdateError.daemonRestartVerificationFailed(
                installed: installedVersion,
                running: status.runningVersion
            )
        }
        return status
    }

    public nonisolated static func parseVersion(from output: String) -> String? {
        let pattern = #"\b\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?\b"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = expression.firstMatch(in: output, range: range),
              let swiftRange = Range(match.range, in: output)
        else {
            return nil
        }
        return String(output[swiftRange])
    }

    private static func performUpdate(
        resolveExecutable: ExecutableResolver,
        runCommand: CommandRunner
    ) async throws -> CodexRuntimeUpdateResult {
        guard let previousExecutableURL = resolveExecutable() else {
            throw CodexRuntimeUpdateError.managedRuntimeNotInstalled
        }
        let previousVersion = try await installedVersion(
            executableURL: previousExecutableURL,
            runCommand: runCommand
        )

        let updateResult: BoundedProcessResult
        do {
            updateResult = try await runCommand(previousExecutableURL, ["update"], 5 * 60)
        } catch {
            throw CodexRuntimeUpdateError.updateCommandFailed
        }
        guard updateResult.terminationStatus == 0 else {
            throw CodexRuntimeUpdateError.updateFailed(exitCode: updateResult.terminationStatus)
        }

        guard let installedExecutableURL = resolveExecutable() else {
            throw CodexRuntimeUpdateError.managedRuntimeNotInstalled
        }
        let installedVersion = try await installedVersion(
            executableURL: installedExecutableURL,
            runCommand: runCommand
        )
        return CodexRuntimeUpdateResult(
            previousVersion: previousVersion,
            installedVersion: installedVersion
        )
    }

    private static func readVersionStatus(
        executableURL: URL,
        runCommand: CommandRunner
    ) async throws -> CodexRuntimeVersionStatus {
        let installedVersion = try await installedVersion(
            executableURL: executableURL,
            runCommand: runCommand
        )
        let daemonResult: BoundedProcessResult
        do {
            daemonResult = try await runCommand(
                executableURL,
                ["app-server", "daemon", "version"],
                10
            )
        } catch {
            return CodexRuntimeVersionStatus(
                installedVersion: installedVersion,
                runningVersion: nil
            )
        }
        guard daemonResult.terminationStatus == 0,
              let payload = daemonVersionPayload(from: daemonResult.stdout.stringValue)
        else {
            return CodexRuntimeVersionStatus(
                installedVersion: installedVersion,
                runningVersion: nil
            )
        }
        return CodexRuntimeVersionStatus(
            installedVersion: installedVersion,
            runningVersion: payload.appServerVersion,
            daemonStatus: payload.status
        )
    }

    private static func installedVersion(
        executableURL: URL,
        runCommand: CommandRunner
    ) async throws -> String {
        let result: BoundedProcessResult
        do {
            result = try await runCommand(executableURL, ["--version"], 10)
        } catch {
            throw CodexRuntimeUpdateError.invalidVersionOutput
        }
        guard result.terminationStatus == 0,
              let version = parseVersion(from: result.stdout.stringValue)
                    ?? parseVersion(from: result.stderr.stringValue)
        else {
            throw CodexRuntimeUpdateError.invalidVersionOutput
        }
        return version
    }

    private nonisolated static func daemonVersionPayload(from output: String) -> DaemonVersionPayload? {
        guard let start = output.firstIndex(of: "{"),
              let end = output.lastIndex(of: "}"),
              start <= end
        else {
            return nil
        }
        let json = String(output[start...end])
        return try? JSONDecoder().decode(DaemonVersionPayload.self, from: Data(json.utf8))
    }
}

private struct DaemonVersionPayload: Decodable, Sendable {
    var status: String?
    var appServerVersion: String?
}
