import Foundation

#if os(macOS)
import Darwin
#endif

public enum CodexRemoteTunnelError: LocalizedError, Sendable {
    case notConnectable
    case invalidSSHTarget(String)
    case noOpenPort
    case unsupportedPlatform
    case tunnelFailed(String)
    case diagnosticFailure(String, [RuntimeDiagnosticStep])

    public var errorDescription: String? {
        switch self {
        case .notConnectable:
            return "This Codex remote is missing an SSH target."
        case .invalidSSHTarget(let target):
            return "The SSH target is not valid: \(target)"
        case .noOpenPort:
            return "Could not find an open local port for the SSH tunnel."
        case .unsupportedPlatform:
            return "Codex remote tunnels are only available on macOS in this build."
        case .tunnelFailed(let message):
            return message.isEmpty ? "Could not start the SSH tunnel." : message
        case .diagnosticFailure(let message, _):
            return message.isEmpty ? "Could not start the SSH tunnel." : message
        }
    }

    public var diagnosticSteps: [RuntimeDiagnosticStep] {
        switch self {
        case .diagnosticFailure(_, let steps):
            return steps
        case .notConnectable, .invalidSSHTarget, .noOpenPort, .unsupportedPlatform, .tunnelFailed:
            return []
        }
    }
}

@MainActor
public final class CodexRemoteTunnel: @unchecked Sendable {
    public let endpoint: AppServerRelayEndpoint

    #if os(macOS)
    private let tunnelProcess: Process
    #endif

    #if os(macOS)
    init(endpoint: AppServerRelayEndpoint, tunnelProcess: Process) {
        self.endpoint = endpoint
        self.tunnelProcess = tunnelProcess
    }
    #else
    init(endpoint: AppServerRelayEndpoint) {
        self.endpoint = endpoint
    }
    #endif

    public func stop() {
        #if os(macOS)
        if tunnelProcess.isRunning {
            tunnelProcess.terminate()
        }
        #endif
    }
}

public struct CodexRemoteTunnelStartResult {
    public var tunnel: CodexRemoteTunnel
    public var diagnostics: [RuntimeDiagnosticStep]

    public init(tunnel: CodexRemoteTunnel, diagnostics: [RuntimeDiagnosticStep]) {
        self.tunnel = tunnel
        self.diagnostics = diagnostics
    }
}

public enum CodexRemoteTunnelService {
    private struct RemoteAppServerSession {
        var port: Int
        var bearerToken: String
    }

    public static func remoteAppServerPortCandidates(for remote: CodexDesktopRemote) -> [Int] {
        switch remote.platform {
        case .windows:
            return [14_500, 18_945]
        case .macOS, .iOS, .iPadOS, .linux, .unknown:
            return [18_945, 14_500]
        }
    }

    public static func debugReport(
        for remote: CodexDesktopRemote,
        steps: [RuntimeDiagnosticStep],
        generatedAt: Date = Date()
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let lines = [
            "MapofAgents Remote Diagnostics",
            "generatedAt: \(formatter.string(from: generatedAt))",
            "remoteName: \(remote.displayName)",
            "remoteID: \(remote.id.rawValue)",
            "platform: \(remote.platform.rawValue)",
            "sshTarget: \(remote.hostname ?? "missing")",
            "sshPort: \(remote.sshPort.map(String.init) ?? "default")",
            "identity: \(remote.identityPath?.isEmpty == false ? "configured" : "not configured")",
            "appServerPortCandidates: \(remoteAppServerPortCandidates(for: remote).map(String.init).joined(separator: ", "))",
            "",
            "Steps:",
        ] + steps.map { step in
            let status = step.status.rawValue
            let detail = step.detail.isEmpty ? "no detail" : redactSensitiveDiagnosticText(step.detail)
            let evidence = step.evidence.isEmpty ? "no evidence" : redactSensitiveDiagnosticText(step.evidence)
            return "- [\(status)] \(step.title)\n  detail: \(detail)\n  evidence: \(evidence)"
        }
        return redactSensitiveDiagnosticText(lines.joined(separator: "\n"))
    }

    public static func pendingConnectionDiagnosticSteps(for remote: CodexDesktopRemote) -> [RuntimeDiagnosticStep] {
        [
            RuntimeDiagnosticStep(
                id: "ssh-reachable",
                title: "SSH reachable",
                status: .running,
                detail: remote.hostname ?? remote.hostID,
                evidence: "ssh -o BatchMode=yes <ssh-target> echo mapofagents-ssh-ok"
            ),
            RuntimeDiagnosticStep(id: "ssh-key", title: "SSH key accepted"),
            RuntimeDiagnosticStep(id: "codex", title: "Codex CLI found"),
            RuntimeDiagnosticStep(id: "app-server-command", title: "App Server command available"),
            RuntimeDiagnosticStep(id: "remote-listener", title: "Remote listener found or started"),
            RuntimeDiagnosticStep(id: "remote-token", title: "Token file found and valid"),
            RuntimeDiagnosticStep(id: "ssh-tunnel", title: "SSH tunnel opened"),
            RuntimeDiagnosticStep(id: "local-readyz", title: "Local tunnel /readyz passed"),
            RuntimeDiagnosticStep(id: "websocket-initialize", title: "WebSocket initialize passed"),
            RuntimeDiagnosticStep(id: "relay-handshake", title: "Relay handshake connected"),
        ]
    }

    public static func redactSensitiveDiagnosticText(_ value: String) -> String {
        var redacted = value
        let replacements: [(String, String)] = [
            (#"token:[A-Za-z0-9._~+/=-]{8,}"#, "token:<redacted>"),
            (#"Bearer\s+[A-Za-z0-9._~+/=-]{8,}"#, "Bearer <redacted>"),
            (#"--ws-token-file\s+("[^"]+"|'[^']+'|\S+)"#, "--ws-token-file <token-file>"),
            (#"mapofagents-codex-app-server-[0-9]+\.token"#, "mapofagents-codex-app-server-<port>.token"),
        ]
        for (pattern, replacement) in replacements {
            redacted = redacted.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        return redacted
    }

    public static func diagnose(
        remote: CodexDesktopRemote,
        onDiagnosticsUpdate: (@Sendable ([RuntimeDiagnosticStep]) async -> Void)? = nil
    ) async -> [RuntimeDiagnosticStep] {
        #if os(macOS)
        guard remote.hostname?.isEmpty == false else {
            return [
                RuntimeDiagnosticStep(
                    id: "ssh-target",
                    title: "SSH target",
                    status: .failed,
                    detail: "Missing SSH hostname"
                ),
            ]
        }

        do {
            let result = try await startTunnelWithDiagnostics(for: remote, onDiagnosticsUpdate: onDiagnosticsUpdate)
            await result.tunnel.stop()
            return result.diagnostics + [
                RuntimeDiagnosticStep(
                    id: "relay-handshake",
                    title: "Relay handshake connected",
                    status: .pending,
                    detail: "Use Connect to attach the workflow relay.",
                    evidence: "diagnose verified transport only"
                ),
            ]
        } catch let error as CodexRemoteTunnelError {
            if !error.diagnosticSteps.isEmpty {
                return error.diagnosticSteps
            }
            return [
                RuntimeDiagnosticStep(
                    id: "remote-diagnostic",
                    title: "Remote diagnostic",
                    status: .failed,
                    detail: error.localizedDescription,
                    action: .restartAppServer
                ),
            ]
        } catch {
            return [
                RuntimeDiagnosticStep(
                    id: "remote-diagnostic",
                    title: "Remote diagnostic",
                    status: .failed,
                    detail: error.localizedDescription
                ),
            ]
        }
        #else
        return [
            RuntimeDiagnosticStep(
                id: "platform",
                title: "Remote diagnostic",
                status: .failed,
                detail: CodexRemoteTunnelError.unsupportedPlatform.localizedDescription
            ),
        ]
        #endif
    }

    public static func startTunnel(for remote: CodexDesktopRemote) async throws -> CodexRemoteTunnel {
        try await startTunnelWithDiagnostics(for: remote).tunnel
    }

    public static func startTunnelWithDiagnostics(
        for remote: CodexDesktopRemote,
        onDiagnosticsUpdate: (@Sendable ([RuntimeDiagnosticStep]) async -> Void)? = nil
    ) async throws -> CodexRemoteTunnelStartResult {
        #if os(macOS)
        guard let hostname = remote.hostname, !hostname.isEmpty else {
            throw CodexRemoteTunnelError.notConnectable
        }

        var steps: [RuntimeDiagnosticStep] = []

        func publish() async {
            guard let onDiagnosticsUpdate else { return }
            await onDiagnosticsUpdate(steps)
        }

        func appendStep(_ step: RuntimeDiagnosticStep) async {
            steps.append(step)
            await publish()
        }

        func appendSteps(_ newSteps: [RuntimeDiagnosticStep]) async {
            steps.append(contentsOf: newSteps)
            await publish()
        }

        func fail(_ message: String, appending step: RuntimeDiagnosticStep? = nil) async throws -> Never {
            if let step {
                steps.append(step)
                await publish()
            }
            throw CodexRemoteTunnelError.diagnosticFailure(message, steps)
        }

        do {
            _ = try await runSSHCommand(
                remote: remote,
                hostname: hostname,
                remoteCommand: "echo mapofagents-ssh-ok",
                timeout: 6
            )
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "ssh-reachable",
                    title: "SSH reachable",
                    status: .passed,
                    detail: hostname,
                    evidence: "ssh -o BatchMode=yes \(hostname) echo mapofagents-ssh-ok"
                )
            )
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "ssh-key",
                    title: "SSH key accepted",
                    status: .passed,
                    detail: "BatchMode authentication succeeded",
                    evidence: remote.identityPath?.isEmpty == false ? "identity: configured" : "identity: SSH config/default"
                )
            )
        } catch {
            try await fail(
                error.localizedDescription,
                appending: RuntimeDiagnosticStep(
                    id: "ssh-reachable",
                    title: "SSH reachable",
                    status: .failed,
                    detail: error.localizedDescription,
                    evidence: "ssh -o BatchMode=yes \(hostname) echo mapofagents-ssh-ok"
                )
            )
        }

        let remoteCodexVersion: String
        do {
            let output = try await runSSHCommand(
                remote: remote,
                hostname: hostname,
                remoteCommand: "codex --version",
                timeout: 8
            )
            remoteCodexVersion = output.trimmedForDisplay
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "codex",
                    title: "Codex CLI found",
                    status: .passed,
                    detail: remoteCodexVersion,
                    evidence: "codex --version"
                )
            )
        } catch {
            try await fail(
                error.localizedDescription,
                appending: RuntimeDiagnosticStep(
                    id: "codex",
                    title: "Codex CLI found",
                    status: .failed,
                    detail: error.localizedDescription,
                    evidence: "codex --version",
                    action: .installCodexCLI
                )
            )
        }

        if let localVersion = await localCodexVersion(),
           Self.codexVersion(localVersion, isNewerThan: remoteCodexVersion) {
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "codex-update",
                    title: "Codex update",
                    status: .warning,
                    detail: "remote \(Self.versionNumber(from: remoteCodexVersion) ?? remoteCodexVersion); local \(Self.versionNumber(from: localVersion) ?? localVersion)",
                    evidence: "local codex --version compared with remote codex --version",
                    action: .updateCodexCLI
                )
            )
        }

        do {
            _ = try await runSSHCommand(
                remote: remote,
                hostname: hostname,
                remoteCommand: "codex app-server --help",
                timeout: 8
            )
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "app-server-command",
                    title: "App Server command available",
                    status: .passed,
                    detail: "codex app-server available",
                    evidence: "codex app-server --help"
                )
            )
        } catch {
            try await fail(
                error.localizedDescription,
                appending: RuntimeDiagnosticStep(
                    id: "app-server-command",
                    title: "App Server command available",
                    status: .failed,
                    detail: error.localizedDescription,
                    evidence: "codex app-server --help",
                    action: .updateCodexCLI
                )
            )
        }

        let localPort = try openLocalPort()
        let remoteSession: RemoteAppServerSession
        do {
            remoteSession = try await ensureRemoteAppServer(remote: remote, hostname: hostname)
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "remote-listener",
                    title: "Remote listener found or started",
                    status: .passed,
                    detail: "authenticated on 127.0.0.1:\(remoteSession.port)",
                    evidence: "remote ports: \(remotePortCandidates(for: remote).map(String.init).joined(separator: ", "))"
                )
            )
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "remote-token",
                    title: "Token file found and valid",
                    status: .passed,
                    detail: "token length \(remoteSession.bearerToken.count)",
                    evidence: "tracked pid/token files matched authenticated app-server command line"
                )
            )
        } catch {
            try await fail(
                error.localizedDescription,
                appending: RuntimeDiagnosticStep(
                    id: "remote-listener",
                    title: "Remote listener found or started",
                    status: .failed,
                    detail: error.localizedDescription,
                    evidence: "try ports: \(remotePortCandidates(for: remote).map(String.init).joined(separator: ", "))",
                    action: .restartAppServer
                )
            )
        }

        let tunnelProcess: Process
        do {
            tunnelProcess = try startForwardingTunnel(
                remote: remote,
                hostname: hostname,
                localPort: localPort,
                remotePort: remoteSession.port
            )
            await appendStep(
                RuntimeDiagnosticStep(
                    id: "ssh-tunnel",
                    title: "SSH tunnel opened",
                    status: .passed,
                    detail: "127.0.0.1:\(localPort) -> 127.0.0.1:\(remoteSession.port)",
                    evidence: "ssh -N -L 127.0.0.1:\(localPort):127.0.0.1:\(remoteSession.port) \(hostname)"
                )
            )
        } catch {
            try await fail(
                error.localizedDescription,
                appending: RuntimeDiagnosticStep(
                    id: "ssh-tunnel",
                    title: "SSH tunnel opened",
                    status: .failed,
                    detail: error.localizedDescription,
                    evidence: "ssh -N -L 127.0.0.1:\(localPort):127.0.0.1:\(remoteSession.port) \(hostname)"
                )
            )
        }

        let localProbe = await localAppServerProbeSteps(
            localPort: localPort,
            bearerToken: remoteSession.bearerToken,
            timeout: 4
        )
        await appendSteps(localProbe.steps)
        guard localProbe.succeeded else {
            tunnelProcess.terminate()
            throw CodexRemoteTunnelError.diagnosticFailure(localProbe.failureMessage, steps)
        }

        let endpoint = AppServerRelayEndpoint(
            id: remote.id,
            name: remote.displayName,
            url: URL(string: "ws://127.0.0.1:\(localPort)")!,
            bearerToken: remoteSession.bearerToken
        )
        let tunnel = await CodexRemoteTunnel(endpoint: endpoint, tunnelProcess: tunnelProcess)
        return CodexRemoteTunnelStartResult(tunnel: tunnel, diagnostics: steps)
        #else
        throw CodexRemoteTunnelError.unsupportedPlatform
        #endif
    }

    public static func installCodexCLI(on remote: CodexDesktopRemote) async throws {
        #if os(macOS)
        let hostname = try sshHostname(for: remote)
        let command: String
        if remote.platform == .windows {
            command = windowsPowerShellCommand(
                """
                $ErrorActionPreference = 'Stop'
                if (Get-Command codex -ErrorAction SilentlyContinue) {
                    codex --version
                    exit 0
                }
                if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
                    throw 'npm is required to install Codex CLI. Install Node.js/npm on the remote machine, then try again.'
                }
                npm install -g @openai/codex
                codex --version
                """
            )
        } else {
            command = "sh -lc 'if command -v codex >/dev/null 2>&1; then codex --version; exit 0; fi; if ! command -v npm >/dev/null 2>&1; then echo \"npm is required to install Codex CLI. Install Node.js/npm on the remote machine, then try again.\" >&2; exit 127; fi; npm install -g @openai/codex && codex --version'"
        }

        _ = try await runSSHCommand(remote: remote, hostname: hostname, remoteCommand: command, timeout: 180)
        #else
        throw CodexRemoteTunnelError.unsupportedPlatform
        #endif
    }

    public static func updateCodexCLI(on remote: CodexDesktopRemote) async throws {
        #if os(macOS)
        let hostname = try sshHostname(for: remote)
        let command: String
        if remote.platform == .windows {
            command = windowsPowerShellCommand(
                """
                $ErrorActionPreference = 'Stop'
                if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
                    throw 'Codex CLI is not installed.'
                }
                codex update
                if ($LASTEXITCODE -ne 0) {
                    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
                        throw 'codex update failed and npm is not available for fallback.'
                    }
                    npm install -g @openai/codex
                }
                codex --version
                """
            )
        } else {
            command = "sh -lc 'if ! command -v codex >/dev/null 2>&1; then echo \"Codex CLI is not installed.\" >&2; exit 127; fi; if codex update; then codex --version; exit 0; fi; if command -v npm >/dev/null 2>&1; then npm install -g @openai/codex && codex --version; else exit 1; fi'"
        }

        _ = try await runSSHCommand(remote: remote, hostname: hostname, remoteCommand: command, timeout: 180)
        #else
        throw CodexRemoteTunnelError.unsupportedPlatform
        #endif
    }

    @discardableResult
    public static func startAppServer(on remote: CodexDesktopRemote) async throws -> Int {
        #if os(macOS)
        let hostname = try sshHostname(for: remote)
        return try await ensureRemoteAppServer(remote: remote, hostname: hostname).port
        #else
        throw CodexRemoteTunnelError.unsupportedPlatform
        #endif
    }

    @discardableResult
    public static func restartAppServer(on remote: CodexDesktopRemote) async throws -> Int {
        #if os(macOS)
        let hostname = try sshHostname(for: remote)
        try await stopRemoteAppServer(remote: remote, hostname: hostname)
        guard let preferredPort = remotePortCandidates(for: remote).first else {
            throw CodexRemoteTunnelError.tunnelFailed("No remote App Server port candidates are configured.")
        }
        let session = try await startRemoteAppServer(remote: remote, remotePort: preferredPort)
        guard await waitForRemoteAppServer(remote: remote, hostname: hostname, remotePort: session.port, timeout: 12) else {
            throw CodexRemoteTunnelError.tunnelFailed(
                "Remote Codex App Server did not restart on 127.0.0.1:\(session.port)."
            )
        }
        return session.port
        #else
        throw CodexRemoteTunnelError.unsupportedPlatform
        #endif
    }

    public static func loadRemoteRolloutTranscript(
        on remote: CodexDesktopRemote,
        path: String,
        threadRef: ThreadRef
    ) async throws -> ThreadTranscript {
        let data = try await loadRemoteFileData(on: remote, path: path)
        return ThreadTranscriptParser.transcript(
            fromRolloutData: data,
            threadRef: threadRef
        )
    }

    public static func loadRemoteFileData(
        on remote: CodexDesktopRemote,
        path: String
    ) async throws -> Data {
        #if os(macOS)
        let hostname = try sshHostname(for: remote)
        let command = remoteReadFileCommand(remote: remote, path: path)
        let output = try await runSSHCommand(
            remote: remote,
            hostname: hostname,
            remoteCommand: command,
            timeout: 20,
            maxOutputBytes: 20 * 1_024 * 1_024
        )
        let compactBase64 = output.filter { !$0.isWhitespace }
        guard let data = Data(base64Encoded: String(compactBase64)) else {
            throw CodexRemoteTunnelError.tunnelFailed("Remote file could not be decoded.")
        }
        return data
        #else
        throw CodexRemoteTunnelError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private static func sshHostname(for remote: CodexDesktopRemote) throws -> String {
        guard let hostname = remote.hostname?.trimmingCharacters(in: .whitespacesAndNewlines), !hostname.isEmpty else {
            throw CodexRemoteTunnelError.notConnectable
        }
        guard CodexDesktopRemoteService.isValidSSHTarget(hostname) else {
            throw CodexRemoteTunnelError.invalidSSHTarget(hostname)
        }
        return hostname
    }

    private static func ensureRemoteAppServer(remote: CodexDesktopRemote, hostname: String) async throws -> RemoteAppServerSession {
        if let readySession = await firstAuthenticatedRemoteSession(remote: remote, hostname: hostname) {
            return readySession
        }

        let candidatePorts = remotePortCandidates(for: remote)
        guard !candidatePorts.isEmpty else {
            throw CodexRemoteTunnelError.tunnelFailed("No remote App Server port candidates are configured.")
        }

        var lastError: Error?
        for remotePort in candidatePorts {
            do {
                let session = try await startRemoteAppServer(remote: remote, remotePort: remotePort)
                guard await waitForRemoteAppServer(remote: remote, hostname: hostname, remotePort: session.port, timeout: 12) else {
                    throw CodexRemoteTunnelError.tunnelFailed(
                        "Remote Codex App Server did not start on 127.0.0.1:\(session.port)."
                    )
                }
                return session
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
        throw CodexRemoteTunnelError.tunnelFailed("Could not start an authenticated remote Codex App Server.")
    }

    private static func startRemoteAppServer(remote: CodexDesktopRemote, remotePort: Int) async throws -> RemoteAppServerSession {
        guard let hostname = remote.hostname else {
            throw CodexRemoteTunnelError.notConnectable
        }

        let command = remoteStartAppServerCommand(remote: remote, remotePort: remotePort)

        let output = try await runSSHCommand(remote: remote, hostname: hostname, remoteCommand: command, timeout: 8)
        guard let token = bearerToken(fromCommandOutput: output) else {
            throw CodexRemoteTunnelError.tunnelFailed("Remote Codex App Server did not return an authentication token.")
        }
        return RemoteAppServerSession(port: remotePort, bearerToken: token)
    }

    static func remoteStartAppServerCommand(remote: CodexDesktopRemote, remotePort: Int) -> String {
        if remote.platform == .windows {
            return windowsPowerShellCommand(
                """
                $ErrorActionPreference = 'Stop'
                $port = \(remotePort)
                $target = "ws://127.0.0.1:$port"
                $pidPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.pid"
                $tokenPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.token"
                $stdoutPath = Join-Path $env:TEMP "codex-app-server-$port.out.log"
                $stderrPath = Join-Path $env:TEMP "codex-app-server-$port.err.log"
                $existing = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $port -State Listen -ErrorAction SilentlyContinue
                if ($existing) {
                    if ((Test-Path $pidPath) -and (Test-Path $tokenPath)) {
                        $trackedPid = (Get-Content $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                        if ($trackedPid -match '^\\d+$') {
                            $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $trackedPid" -ErrorAction SilentlyContinue
                            if ($processInfo -and
                                $processInfo.CommandLine -match 'codex' -and
                                $processInfo.CommandLine -match 'app-server' -and
                                $processInfo.CommandLine -match [regex]::Escape("127.0.0.1:$port") -and
                                $processInfo.CommandLine -match '--ws-auth' -and
                                $processInfo.CommandLine -match 'capability-token' -and
                                $processInfo.CommandLine -match [regex]::Escape($tokenPath)) {
                                $existingToken = (Get-Content $tokenPath -ErrorAction Stop | Select-Object -First 1).Trim()
                                if ($existingToken) {
                                    Write-Output "token:$existingToken"
                                    exit 0
                                }
                            }
                        }
                    }
                    throw "Port $port is already in use by an untracked or unauthenticated App Server."
                }

                $bytes = New-Object 'Byte[]' 32
                [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
                $token = -join ($bytes | ForEach-Object { $_.ToString('x2') })
                Set-Content -Path $tokenPath -Value $token -Encoding ascii
                $codex = (Get-Command codex -ErrorAction Stop).Source
                $appServerArgs = @('app-server','--listen',$target,'--ws-auth','capability-token','--ws-token-file',$tokenPath)
                if ($codex -like '*.ps1') {
                    $process = Start-Process -PassThru -WindowStyle Hidden -FilePath powershell -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$codex) + $appServerArgs)
                } elseif ($codex -like '*.cmd' -or $codex -like '*.bat') {
                    $process = Start-Process -PassThru -WindowStyle Hidden -FilePath cmd.exe -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ArgumentList (@('/c',$codex) + $appServerArgs)
                } else {
                    $process = Start-Process -PassThru -WindowStyle Hidden -FilePath $codex -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -ArgumentList $appServerArgs
                }
                Set-Content -Path $pidPath -Value $process.Id -Encoding ascii
                Write-Output "token:$token"
                """
            )
        }

        let script = """
        port=\(remotePort)
        tokenfile="/tmp/mapofagents-codex-app-server-${port}.token"
        pidfile="/tmp/mapofagents-codex-app-server-${port}.pid"
        logfile="/tmp/codex-app-server-${port}.log"

        if command -v lsof >/dev/null 2>&1 && [ -n "$(lsof -tiTCP:${port} -sTCP:LISTEN 2>/dev/null || true)" ]; then
          if [ -f "$pidfile" ] && [ -s "$tokenfile" ]; then
            pid="$(head -n 1 "$pidfile" | tr -dc '0-9')"
            if [ -n "$pid" ]; then
              command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
              case "$command_line" in
                *codex*"app-server"*"127.0.0.1:${port}"*"--ws-auth"*"capability-token"*"--ws-token-file"*"$tokenfile"*)
                  printf 'token:%s\\n' "$(head -n 1 "$tokenfile" | tr -d '[:space:]')"
                  exit 0
                  ;;
              esac
            fi
          fi
          echo "Port $port is already in use by an untracked or unauthenticated App Server." >&2
          exit 64
        fi

        umask 077
        token="$( (command -v openssl >/dev/null 2>&1 && openssl rand -hex 32) || (od -An -N32 -tx1 /dev/urandom | tr -d ' \\n') )"
        if [ -z "$token" ]; then
          echo "Could not generate an App Server token." >&2
          exit 65
        fi
        printf '%s\\n' "$token" > "$tokenfile"
        nohup codex app-server --listen "ws://127.0.0.1:${port}" --ws-auth capability-token --ws-token-file "$tokenfile" >"$logfile" 2>&1 </dev/null &
        echo $! > "$pidfile"
        printf 'token:%s\\n' "$token"
        """
        return "sh -lc \(shellSingleQuoted(script))"
    }

    private static func stopRemoteAppServer(remote: CodexDesktopRemote, hostname: String) async throws {
        let ports = remotePortCandidates(for: remote)
        let command = remoteStopAppServerCommand(remote: remote, ports: ports)

        _ = try await runSSHCommand(remote: remote, hostname: hostname, remoteCommand: command, timeout: 8)
        try? await Task.sleep(for: .milliseconds(600))
    }

    static func remoteStopAppServerCommand(remote: CodexDesktopRemote, ports: [Int]) -> String {
        if remote.platform == .windows {
            let portList = ports.map(String.init).joined(separator: ",")
            return windowsPowerShellCommand(
                """
                $ErrorActionPreference = 'Stop'
                $ports = @(\(portList))
                foreach ($port in $ports) {
                    $pidPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.pid"
                    $tokenPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.token"
                    $stopped = $false
                    if (Test-Path $pidPath) {
                        $trackedPid = (Get-Content $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                        if ($trackedPid -match '^\\d+$') {
                            $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $trackedPid" -ErrorAction SilentlyContinue
                            if ($processInfo -and $processInfo.CommandLine -match 'codex' -and $processInfo.CommandLine -match 'app-server' -and $processInfo.CommandLine -match [regex]::Escape("127.0.0.1:$port")) {
                                Stop-Process -Id ([int]$trackedPid) -Force -ErrorAction SilentlyContinue
                                $stopped = $true
                            }
                        }
                        Remove-Item $pidPath -Force -ErrorAction SilentlyContinue
                    }
                    Remove-Item $tokenPath -Force -ErrorAction SilentlyContinue
                    if (-not $stopped) {
                        $existing = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $port -State Listen -ErrorAction SilentlyContinue
                        if ($existing) {
                            throw "Port $port is in use by an untracked process; mapofagents will not stop it."
                        }
                    }
                }
                Write-Output 'stopped'
                """
            )
        }

        let portList = ports.map(String.init).joined(separator: " ")
        let script = """
        for port in \(portList); do
          pidfile="/tmp/mapofagents-codex-app-server-${port}.pid"
          tokenfile="/tmp/mapofagents-codex-app-server-${port}.token"
          stopped=0
          if [ -f "$pidfile" ]; then
            pid="$(head -n 1 "$pidfile" | tr -dc '0-9')"
            if [ -n "$pid" ]; then
              command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
              case "$command_line" in
                *codex*"app-server"*"127.0.0.1:${port}"*|*codex*"app-server"*"ws://127.0.0.1:${port}"*)
                  kill "$pid" 2>/dev/null || true
                  stopped=1
                  ;;
              esac
            fi
            rm -f "$pidfile" "$tokenfile"
          else
            rm -f "$tokenfile"
          fi
          if [ "$stopped" -eq 0 ]; then
            if command -v lsof >/dev/null 2>&1 && [ -n "$(lsof -tiTCP:$port -sTCP:LISTEN 2>/dev/null || true)" ]; then
              echo "Port $port is in use by an untracked process; mapofagents will not stop it." >&2
              exit 64
            fi
          fi
        done
        echo stopped
        """
        return "sh -lc \(shellSingleQuoted(script))"
    }

    private static func firstAuthenticatedRemoteSession(remote: CodexDesktopRemote, hostname: String) async -> RemoteAppServerSession? {
        for port in remotePortCandidates(for: remote) {
            guard
                let token = await remoteAuthenticatedAppServerToken(remote: remote, hostname: hostname, remotePort: port),
                await isRemoteAppServerReady(remote: remote, hostname: hostname, remotePort: port)
            else {
                continue
            }
            return RemoteAppServerSession(port: port, bearerToken: token)
        }
        return nil
    }

    private static func remoteAuthenticatedAppServerToken(
        remote: CodexDesktopRemote,
        hostname: String,
        remotePort: Int
    ) async -> String? {
        let command = remoteAuthenticatedAppServerTokenCommand(remote: remote, remotePort: remotePort)
        guard let output = try? await runSSHCommand(
            remote: remote,
            hostname: hostname,
            remoteCommand: command,
            timeout: 5
        ) else {
            return nil
        }
        return bearerToken(fromCommandOutput: output)
    }

    static func remoteAuthenticatedAppServerTokenCommand(remote: CodexDesktopRemote, remotePort: Int) -> String {
        if remote.platform == .windows {
            return windowsPowerShellCommand(
                """
                $ErrorActionPreference = 'Stop'
                $port = \(remotePort)
                $pidPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.pid"
                $tokenPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.token"
                if (-not ((Test-Path $pidPath) -and (Test-Path $tokenPath))) {
                    exit 7
                }
                $trackedPid = (Get-Content $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                if ($trackedPid -notmatch '^\\d+$') {
                    exit 7
                }
                $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $trackedPid" -ErrorAction SilentlyContinue
                if (-not $processInfo) {
                    exit 7
                }
                if ($processInfo.CommandLine -notmatch 'codex' -or
                    $processInfo.CommandLine -notmatch 'app-server' -or
                    $processInfo.CommandLine -notmatch [regex]::Escape("127.0.0.1:$port") -or
                    $processInfo.CommandLine -notmatch '--ws-auth' -or
                    $processInfo.CommandLine -notmatch 'capability-token' -or
                    $processInfo.CommandLine -notmatch [regex]::Escape($tokenPath)) {
                    exit 7
                }
                $token = (Get-Content $tokenPath -ErrorAction Stop | Select-Object -First 1).Trim()
                if (-not $token) {
                    exit 7
                }
                Write-Output "token:$token"
                """
            )
        }

        let script = """
        port=\(remotePort)
        tokenfile="/tmp/mapofagents-codex-app-server-${port}.token"
        pidfile="/tmp/mapofagents-codex-app-server-${port}.pid"
        [ -f "$pidfile" ] && [ -s "$tokenfile" ] || exit 7
        pid="$(head -n 1 "$pidfile" | tr -dc '0-9')"
        [ -n "$pid" ] || exit 7
        command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
        case "$command_line" in
          *codex*"app-server"*"127.0.0.1:${port}"*"--ws-auth"*"capability-token"*"--ws-token-file"*"$tokenfile"*)
            printf 'token:%s\\n' "$(head -n 1 "$tokenfile" | tr -d '[:space:]')"
            ;;
          *)
            exit 7
            ;;
        esac
        """
        return "sh -lc \(shellSingleQuoted(script))"
    }

    private static func waitForRemoteAppServer(
        remote: CodexDesktopRemote,
        hostname: String,
        remotePort: Int,
        timeout: TimeInterval
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isRemoteAppServerReady(remote: remote, hostname: hostname, remotePort: remotePort) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(400))
        }
        return false
    }

    private static func isRemoteAppServerReady(
        remote: CodexDesktopRemote,
        hostname: String,
        remotePort: Int
    ) async -> Bool {
        let command: String
        if remote.platform == .windows {
            command = windowsPowerShellCommand(
                """
                try {
                    $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri 'http://127.0.0.1:\(remotePort)/readyz'
                    if ($response.StatusCode -eq 200) {
                        Write-Output 'ready'
                        exit 0
                    }
                    exit 7
                } catch {
                    exit 7
                }
                """
            )
        } else {
            command = "sh -lc 'curl -fsS --max-time 2 http://127.0.0.1:\(remotePort)/readyz >/dev/null'"
        }

        do {
            _ = try await runSSHCommand(remote: remote, hostname: hostname, remoteCommand: command, timeout: 5)
            return true
        } catch {
            return false
        }
    }

    private static func waitForLocalAppServer(localPort: Int, bearerToken: String, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isLocalAppServerReady(localPort: localPort, bearerToken: bearerToken) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    private struct LocalAppServerProbe {
        var succeeded: Bool
        var failureMessage: String
        var steps: [RuntimeDiagnosticStep]
    }

    private static func localAppServerProbeSteps(
        localPort: Int,
        bearerToken: String,
        timeout: TimeInterval
    ) async -> LocalAppServerProbe {
        let readyURL = URL(string: "http://127.0.0.1:\(localPort)/readyz")!
        let webSocketURL = URL(string: "ws://127.0.0.1:\(localPort)")!
        var steps: [RuntimeDiagnosticStep] = []

        do {
            var request = URLRequest(url: readyURL)
            request.timeoutInterval = min(timeout, 2)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CodexRemoteTunnelError.tunnelFailed("No HTTP response from /readyz.")
            }
            guard httpResponse.statusCode == 200 else {
                throw CodexRemoteTunnelError.tunnelFailed("/readyz returned HTTP \(httpResponse.statusCode).")
            }
            steps.append(
                RuntimeDiagnosticStep(
                    id: "local-readyz",
                    title: "Local tunnel /readyz passed",
                    status: .passed,
                    detail: "HTTP 200 on 127.0.0.1:\(localPort)",
                    evidence: "GET \(readyURL.absoluteString)"
                )
            )
        } catch {
            let message = error.localizedDescription
            steps.append(
                RuntimeDiagnosticStep(
                    id: "local-readyz",
                    title: "Local tunnel /readyz passed",
                    status: .failed,
                    detail: message,
                    evidence: "GET \(readyURL.absoluteString)",
                    action: .restartAppServer
                )
            )
            return LocalAppServerProbe(
                succeeded: false,
                failureMessage: "SSH tunnel opened, but /readyz failed on 127.0.0.1:\(localPort): \(message)",
                steps: steps
            )
        }

        do {
            let verification = try await AppServerEndpointVerifier.verifyDetailed(
                url: webSocketURL,
                bearerToken: bearerToken,
                timeout: min(timeout, 3)
            )
            let keys = AppServerEndpointVerifier.initializeResultKeys(verification.initializeResult)
            steps.append(
                RuntimeDiagnosticStep(
                    id: "websocket-initialize",
                    title: "WebSocket initialize passed",
                    status: .passed,
                    detail: keys.isEmpty ? "initialize response accepted" : "fields: \(keys.joined(separator: ", "))",
                    evidence: "initialize over \(webSocketURL.absoluteString) with bearer token"
                )
            )
            return LocalAppServerProbe(succeeded: true, failureMessage: "", steps: steps)
        } catch let error as AppServerEndpointVerificationError {
            let message = error.localizedDescription
            steps.append(
                RuntimeDiagnosticStep(
                    id: "websocket-initialize",
                    title: "WebSocket initialize passed",
                    status: .failed,
                    detail: message,
                    evidence: "initialize over \(webSocketURL.absoluteString) with bearer token",
                    action: .restartAppServer
                )
            )
            return LocalAppServerProbe(
                succeeded: false,
                failureMessage: "Codex App Server answered /readyz, but WebSocket initialize failed on 127.0.0.1:\(localPort): \(message)",
                steps: steps
            )
        } catch {
            let message = error.localizedDescription
            steps.append(
                RuntimeDiagnosticStep(
                    id: "websocket-initialize",
                    title: "WebSocket initialize passed",
                    status: .failed,
                    detail: message,
                    evidence: "initialize over \(webSocketURL.absoluteString) with bearer token",
                    action: .restartAppServer
                )
            )
            return LocalAppServerProbe(
                succeeded: false,
                failureMessage: "Codex App Server answered /readyz, but WebSocket initialize failed on 127.0.0.1:\(localPort): \(message)",
                steps: steps
            )
        }
    }

    private static func isLocalAppServerReady(localPort: Int, bearerToken: String) async -> Bool {
        guard let url = URL(string: "ws://127.0.0.1:\(localPort)") else {
            return false
        }

        do {
            _ = try await AppServerEndpointVerifier.verify(url: url, bearerToken: bearerToken, timeout: 2)
            return true
        } catch {
            return false
        }
    }

    private static func startForwardingTunnel(
        remote: CodexDesktopRemote,
        hostname: String,
        localPort: Int,
        remotePort: Int
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = try sshBaseArguments(for: remote, hostname: hostname) + [
            "-N",
            "-L",
            "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)",
            "--",
            hostname,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw CodexRemoteTunnelError.tunnelFailed(error.localizedDescription)
        }

        Thread.sleep(forTimeInterval: 0.45)
        if !process.isRunning {
            throw CodexRemoteTunnelError.tunnelFailed("SSH tunnel process exited before forwarding started.")
        }

        return process
    }

    private static func runSSHCommand(
        remote: CodexDesktopRemote,
        hostname: String,
        remoteCommand: String,
        timeout: TimeInterval,
        maxOutputBytes: Int = 1_048_576
    ) async throws -> String {
        let arguments = try sshBaseArguments(for: remote, hostname: hostname) + [
            "--",
            hostname,
            remoteCommand,
        ]
        let result = try await BoundedProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/ssh"),
            arguments: arguments,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )

        if result.terminationStatus == -1 {
            throw CodexRemoteTunnelError.tunnelFailed("Timed out waiting for the remote SSH command.")
        }

        guard result.terminationStatus == 0 else {
            throw CodexRemoteTunnelError.tunnelFailed(
                result.stderr.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return result.stdout.stringValue
    }

    private static func sshBaseArguments(for remote: CodexDesktopRemote, hostname: String) throws -> [String] {
        guard CodexDesktopRemoteService.isValidSSHTarget(hostname) else {
            throw CodexRemoteTunnelError.invalidSSHTarget(hostname)
        }
        var arguments = [
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=yes",
        ]

        let identityPath = (try? CodexRemoteIdentityStore.preparedIdentityPath(for: remote))
            ?? remote.identityPath
        if let identityPath, !identityPath.isEmpty {
            arguments += ["-i", identityPath]
        }

        if let sshPort = remote.sshPort {
            guard (1...65_535).contains(sshPort) else {
                throw CodexRemoteTunnelError.invalidSSHTarget("\(hostname):\(sshPort)")
            }
            arguments += ["-p", String(sshPort)]
        }

        return arguments
    }

    private static func remotePortCandidates(for remote: CodexDesktopRemote) -> [Int] {
        remoteAppServerPortCandidates(for: remote)
    }

    private static func remoteReadFileCommand(remote: CodexDesktopRemote, path: String) -> String {
        if remote.platform == .windows {
            return windowsPowerShellCommand(
                """
                $ErrorActionPreference = 'Stop'
                $path = '\(path.replacingOccurrences(of: "'", with: "''"))'
                $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $memory = New-Object System.IO.MemoryStream
                try {
                    $stream.CopyTo($memory)
                    [Convert]::ToBase64String($memory.ToArray())
                } finally {
                    $memory.Dispose()
                    $stream.Dispose()
                }
                """
            )
        }

        return "sh -lc \(shellSingleQuoted("base64 < \(shellSingleQuoted(path))"))"
    }

    private static func bearerToken(fromCommandOutput output: String) -> String? {
        output
            .split(whereSeparator: \.isNewline)
            .lazy
            .compactMap { line -> String? in
                let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.hasPrefix("token:") else { return nil }
                let token = String(text.dropFirst("token:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard token.count >= 32, token.allSatisfy({ !$0.isWhitespace }) else {
                    return nil
                }
                return token
            }
            .first
    }

    private static func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    private static func windowsPowerShellCommand(_ script: String) -> String {
        let data = script.data(using: .utf16LittleEndian) ?? Data()
        return "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand \(data.base64EncodedString())"
    }

    private static func localCodexVersion() async -> String? {
        try? await Task.detached(priority: .utility) {
            let result = try await BoundedProcessRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["codex", "--version"],
                timeout: 4
            )
            guard result.terminationStatus == 0 else { return nil }
            let output = result.stdout.stringValue
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? nil : output
        }.value
    }

    private static func codexVersion(_ lhs: String, isNewerThan rhs: String) -> Bool {
        guard let lhs = semanticVersionComponents(from: lhs),
              let rhs = semanticVersionComponents(from: rhs) else {
            return false
        }

        return lhs.lexicographicallyPrecedes(rhs) == false && lhs != rhs
    }

    private static func semanticVersionComponents(from value: String) -> [Int]? {
        guard let version = versionNumber(from: value) else {
            return nil
        }

        let components = version
            .split(separator: ".")
            .map { Int($0) ?? 0 }
        guard !components.isEmpty else { return nil }
        return Array((components + Array(repeating: 0, count: max(0, 3 - components.count))).prefix(3))
    }

    private static func versionNumber(from value: String) -> String? {
        let pattern = #"\d+(?:\.\d+){1,3}"#
        guard let range = value.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }

    private static func openLocalPort() throws -> Int {
        for _ in 0..<20 {
            let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard socketDescriptor >= 0 else { continue }
            defer { close(socketDescriptor) }

            var value: Int32 = 1
            setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = 0
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let bindResult = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            guard bindResult == 0 else { continue }

            var boundAddress = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    getsockname(socketDescriptor, sockaddrPointer, &length)
                }
            }
            guard nameResult == 0 else { continue }

            return Int(UInt16(bigEndian: boundAddress.sin_port))
        }

        throw CodexRemoteTunnelError.noOpenPort
    }
    #endif
}

private extension String {
    var trimmedForDisplay: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 90 else { return trimmed }
        return String(trimmed.prefix(87)) + "..."
    }
}
