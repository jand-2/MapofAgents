import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func accessTokenExpiryPolicyClampsExpiredTokensAndRejectsStaleConnections() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(
        AppServerAccessTokenExpiryPolicy.delay(
            until: now.addingTimeInterval(45),
            now: now
        ) == 45
    )
    #expect(
        AppServerAccessTokenExpiryPolicy.delay(
            until: now.addingTimeInterval(-1),
            now: now
        ) == 0
    )

    let current = AppServerConnectionID()
    let stale = AppServerConnectionID()
    #expect(
        AppServerAccessTokenExpiryPolicy.applies(
            expectedConnectionID: current,
            currentConnectionID: current
        )
    )
    #expect(
        !AppServerAccessTokenExpiryPolicy.applies(
            expectedConnectionID: stale,
            currentConnectionID: current
        )
    )
}

@Test
func relayEndpointCanBeRecoveredFromConnectedMachine() throws {
    let machine = SupervisorMachine(
        id: HostID(rawValue: "codex-remote-windows"),
        name: "Windows",
        endpointDescription: "ws://127.0.0.1:54064",
        status: .connected,
        platform: .windows
    )

    let endpoint = try #require(AppServerRelayEndpoint(machine: machine))

    #expect(endpoint.id == machine.id)
    #expect(endpoint.name == "Windows")
    #expect(endpoint.url.absoluteString == "ws://127.0.0.1:54064")
}

@Test
func relayEndpointRecoveryRequiresConnectedWebSocketMachine() {
    let failedMachine = SupervisorMachine(
        id: HostID(rawValue: "failed"),
        name: "Failed",
        endpointDescription: "ws://127.0.0.1:54064",
        status: .failed
    )
    let sshMachine = SupervisorMachine(
        id: HostID(rawValue: "ssh"),
        name: "SSH",
        endpointDescription: "User@windows.example.ts.net",
        status: .connected
    )

    #expect(AppServerRelayEndpoint(machine: failedMachine) == nil)
    #expect(AppServerRelayEndpoint(machine: sshMachine) == nil)
}

@Test
func relayCanStopForEndpointReplacementWithoutDisconnectingMachine() async throws {
    let supervisor = WorkflowSupervisor()
    let hostID = HostID(rawValue: "paired-mac")
    await supervisor.upsertMachine(
        SupervisorMachine(
            id: hostID,
            name: "Paired Mac",
            endpointDescription: "ws://192.0.2.10:18945",
            status: .connected
        )
    )
    let endpoint = AppServerRelayEndpoint(
        id: hostID,
        name: "Paired Mac",
        url: try #require(URL(string: "ws://192.0.2.10:18945"))
    )
    let relay = AppServerWebSocketWorkflowRelay(endpoint: endpoint, supervisor: supervisor)

    await relay.stop(markDisconnected: false)
    #expect(await supervisor.machineSnapshot().first { $0.id == hostID }?.status == .connected)

    await relay.stop()
    #expect(await supervisor.machineSnapshot().first { $0.id == hostID }?.status == .disconnected)
}

@Test
func relayStopForEndpointReplacementDoesNotNotifyDisconnected() async throws {
    let supervisor = WorkflowSupervisor()
    let hostID = HostID(rawValue: "paired-mac")
    let endpoint = AppServerRelayEndpoint(
        id: hostID,
        name: "Paired Mac",
        url: try #require(URL(string: "ws://192.0.2.10:18945"))
    )
    let recorder = HostIDRecorder()
    let relay = AppServerWebSocketWorkflowRelay(
        endpoint: endpoint,
        supervisor: supervisor,
        onDisconnected: { hostID in
            recorder.append(hostID)
        }
    )

    await relay.stop(markDisconnected: false)
    #expect(recorder.recorded.isEmpty)

    await relay.stop()
    #expect(recorder.recorded == [hostID])
}

@Test
@MainActor
func disconnectCancelsPendingCodexRemoteRecovery() async {
    let store = WorkflowSupervisorStore()
    let hostID = HostID(rawValue: "codex-remote-windows")

    await store.scheduleCodexRemoteRecovery(hostID: hostID, reason: "Route dropped during test.")
    #expect(store.hasPendingCodexRemoteRecovery(for: hostID))
    #expect(store.hasActiveCodexRemoteRecovery(for: hostID))

    await store.disconnect(hostID)
    #expect(!store.hasPendingCodexRemoteRecovery(for: hostID))
    #expect(!store.hasActiveCodexRemoteRecovery(for: hostID))
}

@Test
func codexRemotePortHintsPreferWindowsAppServerPort() {
    let windowsRemote = CodexDesktopRemote(
        id: HostID(rawValue: "codex-remote-windows"),
        displayName: "Windows DESKTOP-EXAMPLE",
        hostID: "remote-ssh-codex-managed:Windows%20DESKTOP-EXAMPLE",
        hostname: "User@windows.example.ts.net",
        source: "codex-managed"
    )

    #expect(CodexRemoteTunnelService.remoteAppServerPortCandidates(for: windowsRemote) == [14_500, 18_945])
}

@Test
func codexRemoteFolderBrowserSupportsConnectableWindowsRemotes() {
    let windowsRemote = CodexDesktopRemote(
        id: HostID(rawValue: "codex-remote-windows"),
        displayName: "Windows DESKTOP-EXAMPLE",
        hostID: "remote-ssh-codex-managed:Windows%20DESKTOP-EXAMPLE",
        hostname: "User@windows.example.ts.net",
        source: "codex-managed"
    )
    let disconnectedRemote = CodexDesktopRemote(
        id: HostID(rawValue: "codex-remote-discovered"),
        displayName: "windows-erp",
        hostID: "remote-ssh-discovered:windows-erp",
        source: "discovered"
    )

    #expect(CodexRemoteTunnelService.canBrowseRemoteFolders(for: windowsRemote))
    #expect(CodexRemoteTunnelService.canBrowseRemoteFolders(for: disconnectedRemote) == false)
}

@Test
func codexRemoteFolderListingParsesJSONEnvelope() throws {
    let output = """
    PowerShell banner text
    {"path":"C:\\\\Users\\\\Example","parent":"C:\\\\Users","entries":[{"name":"Desktop","path":"C:\\\\Users\\\\Example\\\\Desktop"},{"name":"Documents","path":"C:\\\\Users\\\\Example\\\\Documents"}]}
    """

    let listing = try CodexRemoteTunnelService.remoteFolderListing(from: output)

    #expect(listing.path == "C:\\Users\\Example")
    #expect(listing.parentPath == "C:\\Users")
    #expect(listing.entries.map(\.name) == ["Desktop", "Documents"])
    #expect(listing.entries.first?.path == "C:\\Users\\Example\\Desktop")
}

@Test
func codexRemoteDebugReportRedactsTokensButKeepsDiagnosticShape() {
    let remote = CodexDesktopRemote(
        id: HostID(rawValue: "codex-remote-windows-example"),
        displayName: "Windows DESKTOP-EXAMPLE",
        hostID: "remote-ssh-codex-managed:Windows%20DESKTOP-EXAMPLE",
        hostname: "User@windows.example.ts.net",
        identityPath: "/Users/example/.ssh/codex_example",
        sshPort: 22,
        source: "codex-managed"
    )
    let steps = [
        RuntimeDiagnosticStep(
            id: "remote-token",
            title: "Token file found and valid",
            status: .passed,
            detail: "token:abcdef1234567890",
            evidence: "codex app-server --ws-token-file C:\\Temp\\mapofagents-codex-app-server-14500.token"
        ),
        RuntimeDiagnosticStep(
            id: "websocket-initialize",
            title: "WebSocket initialize passed",
            status: .failed,
            detail: "Bearer abcdef1234567890 was rejected",
            evidence: "initialize response fields: codexHome, platformFamily"
        ),
    ]

    let report = CodexRemoteTunnelService.debugReport(
        for: remote,
        steps: steps,
        generatedAt: Date(timeIntervalSince1970: 0)
    )

    #expect(report.contains("sshTarget: User@windows.example.ts.net"))
    #expect(report.contains("appServerPortCandidates: 14500, 18945"))
    #expect(report.contains("WebSocket initialize passed"))
    #expect(report.contains("token:<redacted>"))
    #expect(report.contains("Bearer <redacted>"))
    #expect(!report.contains("abcdef1234567890"))
    #expect(!report.contains("mapofagents-codex-app-server-14500.token"))
}

@Test
func remoteStartCommandRequiresAuthenticatedAppServerToken() throws {
    let linuxRemote = CodexDesktopRemote(
        id: HostID(rawValue: "linux"),
        displayName: "Linux",
        hostID: "linux",
        hostname: "linux.example.test",
        source: "test"
    )
    let windowsRemote = CodexDesktopRemote(
        id: HostID(rawValue: "windows"),
        displayName: "Windows",
        hostID: "windows",
        hostname: "User@windows.example.test",
        source: "test"
    )

    let linuxCommand = CodexRemoteTunnelService.remoteStartAppServerCommand(remote: linuxRemote, remotePort: 18_945)
    let windowsCommand = try decodedPowerShellScript(
        from: CodexRemoteTunnelService.remoteStartAppServerCommand(remote: windowsRemote, remotePort: 14_500)
    )

    for command in [linuxCommand, windowsCommand] {
        #expect(command.contains("--ws-auth"))
        #expect(command.contains("capability-token"))
        #expect(command.contains("--ws-token-file"))
        #expect(command.contains("token:"))
    }

    #expect(linuxCommand.contains("unauthenticated App Server"))
    #expect(!windowsCommand.contains("Find-MapofAgentsTrackedAppServerToken"))
    #expect(windowsCommand.contains("Port $port is already in use by an untracked or unauthenticated App Server."))
    #expect(CodexRemoteTunnelService.remoteStartAppServerCommand(remote: windowsRemote, remotePort: 14_500).count < 8_000)
}

@Test
func remoteAuthenticatedTokenProbeRequiresTrackedAuthenticatedProcess() throws {
    let remote = CodexDesktopRemote(
        id: HostID(rawValue: "linux"),
        displayName: "Linux",
        hostID: "linux",
        hostname: "linux.example.test",
        source: "test"
    )

    let command = CodexRemoteTunnelService.remoteAuthenticatedAppServerTokenCommand(remote: remote, remotePort: 18_945)

    #expect(command.contains("mapofagents-codex-app-server-${port}.token"))
    #expect(command.contains("--ws-auth"))
    #expect(command.contains("capability-token"))
    #expect(command.contains("token:"))
}

@Test
func remoteAuthenticatedTokenProbeAcceptsWindowsAppDataLocalServer() throws {
    let remote = CodexDesktopRemote(
        id: HostID(rawValue: "windows"),
        displayName: "Windows",
        hostID: "windows",
        hostname: "User@windows.example.test",
        source: "test"
    )

    let command = try decodedPowerShellScript(
        from: CodexRemoteTunnelService.remoteAuthenticatedAppServerTokenCommand(remote: remote, remotePort: 14_500)
    )

    #expect(command.contains("Find-MapofAgentsTrackedAppServerToken"))
    #expect(command.contains("$roots += $env:TEMP"))
    #expect(command.contains("MapofAgents\\local-app-server"))
    #expect(command.contains("[regex]::Escape($tokenPath)"))
    #expect(command.contains("Write-Output \"token:$token\""))
}

@Test
func powershellCLIXMLOutputIsCleanedForDisplay() {
    let progressOnly = """
    #< CLIXML
    ready
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><Obj S="progress" RefId="0"><MS><PR N="Record"><AV>Preparing modules for first use.</AV></PR></MS></Obj></Objs>
    """

    #expect(CodexRemoteTunnelService.cleanedSSHOutputForDisplay(progressOnly) == "ready")

    let error = """
    #< CLIXML
    <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><S S="Error">Port 14500 is already in use_x000D__x000A_Restart MapofAgents on Windows</S></Objs>
    """

    #expect(
        CodexRemoteTunnelService.cleanedSSHOutputForDisplay(error)
            == "Port 14500 is already in use\nRestart MapofAgents on Windows"
    )
}

@Test
func macLanHelperDefaultsToLoopbackAndRequiresExplicitInsecureOptIn() throws {
    let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let scriptURL = repoRoot.appendingPathComponent("script/start_mac_lan_app_server.sh")
    let script = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(script.contains(#"HOST="${MAPOFAGENTS_MAC_LAN_HOST:-127.0.0.1}""#))
    #expect(script.contains("MAPOFAGENTS_ALLOW_INSECURE_LAN"))
    #expect(script.contains("Refusing to expose a bearer-token Codex App Server over cleartext"))
    #expect(script.contains("refusing to reuse an existing listener with an unknown token policy"))
    #expect(script.contains("/usr/bin/openssl rand -hex 32 >"))
    #expect(script.contains("if [[ ! -s") == false)
}

@Test
func hostRegistryReusesExplicitStableHostIDAcrossEndpointAliases() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-host-registry-tests-\(UUID().uuidString)", isDirectory: true)
    let registryURL = directory.appendingPathComponent("host-registry.json")
    let registry = HostRegistry(url: registryURL)
    let firstURL = try #require(URL(string: "ws://paired-a.example.test:18945"))
    let secondURL = try #require(URL(string: "ws://paired-b.example.test:18945"))
    let pairedMacID = HostID(rawValue: "paired-mac")

    let firstID = await registry.hostID(explicitID: pairedMacID, name: "Mac mini", endpointURL: firstURL)
    let secondID = await registry.hostID(explicitID: pairedMacID, name: "Mac mini", endpointURL: secondURL)

    #expect(firstID == secondID)

    let restoredRegistry = HostRegistry(url: registryURL)
    let restoredID = await restoredRegistry.hostID(explicitID: nil, name: "", endpointURL: secondURL)
    #expect(restoredID == pairedMacID)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func hostRegistryDoesNotCollapseDistinctMachinesWithSameDisplayName() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-host-registry-tests-\(UUID().uuidString)", isDirectory: true)
    let registryURL = directory.appendingPathComponent("host-registry.json")
    let registry = HostRegistry(url: registryURL)
    let firstURL = try #require(URL(string: "ws://lab-a.example.test:18945"))
    let secondURL = try #require(URL(string: "ws://lab-b.example.test:18945"))

    let firstID = await registry.hostID(explicitID: nil, name: "Mac mini", endpointURL: firstURL)
    let secondID = await registry.hostID(explicitID: nil, name: "Mac mini", endpointURL: secondURL)

    #expect(firstID != secondID)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func hostRegistryDoesNotMergeSameHostnameDifferentPortsWithoutExplicitID() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-host-registry-tests-\(UUID().uuidString)", isDirectory: true)
    let registryURL = directory.appendingPathComponent("host-registry.json")
    let registry = HostRegistry(url: registryURL)
    let firstURL = try #require(URL(string: "ws://same-host.example.test:18945"))
    let secondURL = try #require(URL(string: "ws://same-host.example.test:14500"))

    let firstID = await registry.hostID(explicitID: nil, name: "Mac mini", endpointURL: firstURL)
    let secondID = await registry.hostID(explicitID: nil, name: "Mac mini", endpointURL: secondURL)

    #expect(firstID != secondID)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func hostRegistryAvoidsLongEndpointIDCollisions() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("mapofagents-host-registry-tests-\(UUID().uuidString)", isDirectory: true)
    let registryURL = directory.appendingPathComponent("host-registry.json")
    let registry = HostRegistry(url: registryURL)
    let commonPathPrefix = String(repeating: "very-long-path-component-", count: 5)
    let firstURL = try #require(URL(string: "ws://same.example.test:18945/\(commonPathPrefix)a"))
    let secondURL = try #require(URL(string: "ws://same.example.test:18945/\(commonPathPrefix)b"))

    let firstID = await registry.hostID(explicitID: nil, name: "Mac mini", endpointURL: firstURL)
    let secondID = await registry.hostID(explicitID: nil, name: "Mac mini", endpointURL: secondURL)

    #expect(firstID != secondID)

    try? FileManager.default.removeItem(at: directory)
}

@Test
func remoteRestartStopCommandOnlyTargetsTrackedAppServerPids() {
    let remote = CodexDesktopRemote(
        id: HostID(rawValue: "linux"),
        displayName: "Linux",
        hostID: "linux",
        hostname: "linux.example.test",
        source: "test"
    )

    let command = CodexRemoteTunnelService.remoteStopAppServerCommand(remote: remote, ports: [18_945])

    #expect(command.contains("mapofagents-codex-app-server-${port}.pid"))
    #expect(command.contains("lsof -tiTCP:$port"))
    #expect(command.contains("kill $pids") == false)
    #expect(command.contains("fuser -k") == false)
    #expect(command.contains("untracked process"))
    #expect(command.contains("exit 64") == false)

    let windowsRemote = CodexDesktopRemote(
        id: HostID(rawValue: "windows"),
        displayName: "Windows",
        hostID: "windows",
        hostname: "windows.example.test",
        source: "test"
    )
    let windowsCommand = CodexRemoteTunnelService.remoteStopAppServerCommand(remote: windowsRemote, ports: [14_500])
    let windowsScript = try? decodedPowerShellScript(from: windowsCommand)
    #expect(windowsScript?.contains("Write-Warning \"Port $port is in use by an untracked process") == true)
    #expect(windowsScript?.contains("throw \"Port $port is in use by an untracked process") == false)
}

private func decodedPowerShellScript(from command: String) throws -> String {
    let prefix = "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand "
    let encoded = command.replacingOccurrences(of: prefix, with: "")
    let data = try #require(Data(base64Encoded: encoded))
    return try #require(String(data: data, encoding: .utf16LittleEndian))
}

private final class HostIDRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [HostID] = []

    var recorded: [HostID] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }

    func append(_ hostID: HostID) {
        lock.lock()
        defer { lock.unlock() }
        values.append(hostID)
    }
}
