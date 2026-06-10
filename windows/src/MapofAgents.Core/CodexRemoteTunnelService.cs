using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace MapofAgents.Core;

public sealed class CodexRemoteTunnel : IDisposable
{
    private readonly Process _tunnelProcess;

    public CodexRemoteTunnel(AppServerEndpoint endpoint, Process tunnelProcess)
    {
        Endpoint = endpoint;
        _tunnelProcess = tunnelProcess;
    }

    public AppServerEndpoint Endpoint { get; }

    public void Stop()
    {
        try
        {
            if (!_tunnelProcess.HasExited)
            {
                _tunnelProcess.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
        }
    }

    public void Dispose()
    {
        Stop();
        _tunnelProcess.Dispose();
    }
}

public sealed record CodexRemoteTunnelStartResult(
    CodexRemoteTunnel Tunnel,
    IReadOnlyList<RuntimeDiagnosticStep> Diagnostics);

public sealed record RemoteFolderEntry(string Name, string Path);

public sealed record RemoteFolderListing(string Path, string? ParentPath, IReadOnlyList<RemoteFolderEntry> Entries);

public sealed class CodexRemoteTunnelException : Exception
{
    public CodexRemoteTunnelException(string message, IReadOnlyList<RuntimeDiagnosticStep>? diagnosticSteps = null)
        : base(string.IsNullOrWhiteSpace(message) ? "Could not start the SSH tunnel." : message)
    {
        DiagnosticSteps = diagnosticSteps ?? [];
    }

    public IReadOnlyList<RuntimeDiagnosticStep> DiagnosticSteps { get; }
}

public static class RuntimeDiagnosticActions
{
    public const string InstallCodexCLI = "installCodexCLI";
    public const string UpdateCodexCLI = "updateCodexCLI";
    public const string StartAppServer = "startAppServer";
    public const string RestartAppServer = "restartAppServer";
}

public static class CodexRemoteTunnelService
{
    private const int MaxProcessOutputBytes = 1_048_576;

    public static IReadOnlyList<int> RemoteAppServerPortCandidates(CodexDesktopRemote remote)
    {
        return remote.Platform == HostPlatforms.Windows
            ? [14_500, 18_945]
            : [18_945, 14_500];
    }

    public static string DebugReport(
        CodexDesktopRemote remote,
        IReadOnlyList<RuntimeDiagnosticStep> steps,
        DateTimeOffset? generatedAt = null)
    {
        var timestamp = (generatedAt ?? DateTimeOffset.UtcNow)
            .ToUniversalTime()
            .ToString("O", CultureInfo.InvariantCulture);
        var lines = new List<string>
        {
            "MapofAgents Remote Diagnostics",
            $"generatedAt: {timestamp}",
            $"remoteName: {remote.DisplayName}",
            $"remoteID: {remote.Id}",
            $"platform: {remote.Platform}",
            $"sshTarget: {remote.Hostname ?? "missing"}",
            $"sshPort: {remote.SshPort?.ToString(CultureInfo.InvariantCulture) ?? "default"}",
            $"identity: {(!string.IsNullOrWhiteSpace(remote.IdentityPath) ? "configured" : "not configured")}",
            $"appServerPortCandidates: {string.Join(", ", RemoteAppServerPortCandidates(remote))}",
            "",
            "Steps:"
        };

        foreach (var step in steps)
        {
            var detail = string.IsNullOrWhiteSpace(step.Detail)
                ? "no detail"
                : RedactSensitiveDiagnosticText(step.Detail);
            var evidence = string.IsNullOrWhiteSpace(step.Evidence)
                ? "no evidence"
                : RedactSensitiveDiagnosticText(step.Evidence);
            lines.Add($"- [{step.Status}] {step.Title}");
            lines.Add($"  detail: {detail}");
            lines.Add($"  evidence: {evidence}");
        }

        return RedactSensitiveDiagnosticText(string.Join('\n', lines));
    }

    public static IReadOnlyList<RuntimeDiagnosticStep> PendingConnectionDiagnosticSteps(CodexDesktopRemote remote)
    {
        return
        [
            new RuntimeDiagnosticStep
            {
                Id = "ssh-reachable",
                Title = "SSH reachable",
                Status = RuntimeDiagnosticStatuses.Running,
                Detail = remote.Hostname ?? remote.HostID,
                Evidence = "ssh -o BatchMode=yes <ssh-target> echo mapofagents-ssh-ok"
            },
            new RuntimeDiagnosticStep { Id = "ssh-key", Title = "SSH key accepted" },
            new RuntimeDiagnosticStep { Id = "codex", Title = "Codex CLI found" },
            new RuntimeDiagnosticStep { Id = "app-server-command", Title = "App Server command available" },
            new RuntimeDiagnosticStep { Id = "remote-listener", Title = "Remote listener found or started" },
            new RuntimeDiagnosticStep { Id = "remote-token", Title = "Token file found and valid" },
            new RuntimeDiagnosticStep { Id = "ssh-tunnel", Title = "SSH tunnel opened" },
            new RuntimeDiagnosticStep { Id = "local-readyz", Title = "Local tunnel /readyz passed" },
            new RuntimeDiagnosticStep { Id = "websocket-initialize", Title = "WebSocket initialize passed" },
            new RuntimeDiagnosticStep { Id = "relay-handshake", Title = "Relay handshake connected" }
        ];
    }

    public static async Task<IReadOnlyList<RuntimeDiagnosticStep>> DiagnoseAsync(
        CodexDesktopRemote remote,
        Func<IReadOnlyList<RuntimeDiagnosticStep>, Task>? onDiagnosticsUpdate = null,
        CancellationToken cancellationToken = default)
    {
        if (!remote.IsConnectable)
        {
            return
            [
                new RuntimeDiagnosticStep
                {
                    Id = "ssh-target",
                    Title = "SSH target",
                    Status = RuntimeDiagnosticStatuses.Failed,
                    Detail = "Missing SSH hostname"
                }
            ];
        }

        try
        {
            var result = await StartTunnelWithDiagnosticsAsync(remote, onDiagnosticsUpdate, cancellationToken).ConfigureAwait(false);
            result.Tunnel.Stop();
            return result.Diagnostics
                .Concat(
                [
                    new RuntimeDiagnosticStep
                    {
                        Id = "relay-handshake",
                        Title = "Relay handshake connected",
                        Status = RuntimeDiagnosticStatuses.Pending,
                        Detail = "Use Connect to attach the workflow relay.",
                        Evidence = "diagnose verified transport only"
                    }
                ])
                .ToList();
        }
        catch (CodexRemoteTunnelException exception)
        {
            if (exception.DiagnosticSteps.Count > 0)
            {
                return exception.DiagnosticSteps;
            }

            return
            [
                new RuntimeDiagnosticStep
                {
                    Id = "remote-diagnostic",
                    Title = "Remote diagnostic",
                    Status = RuntimeDiagnosticStatuses.Failed,
                    Detail = exception.Message,
                    Action = RuntimeDiagnosticActions.RestartAppServer
                }
            ];
        }
        catch (Exception exception)
        {
            return
            [
                new RuntimeDiagnosticStep
                {
                    Id = "remote-diagnostic",
                    Title = "Remote diagnostic",
                    Status = RuntimeDiagnosticStatuses.Failed,
                    Detail = exception.Message
                }
            ];
        }
    }

    public static async Task<CodexRemoteTunnelStartResult> StartTunnelWithDiagnosticsAsync(
        CodexDesktopRemote remote,
        Func<IReadOnlyList<RuntimeDiagnosticStep>, Task>? onDiagnosticsUpdate = null,
        CancellationToken cancellationToken = default)
    {
        var hostname = SshHostname(remote);
        var steps = new List<RuntimeDiagnosticStep>();

        async Task PublishAsync()
        {
            if (onDiagnosticsUpdate is not null)
            {
                await onDiagnosticsUpdate(steps.ToList()).ConfigureAwait(false);
            }
        }

        async Task AppendStepAsync(RuntimeDiagnosticStep step)
        {
            steps.Add(step);
            await PublishAsync().ConfigureAwait(false);
        }

        async Task FailAsync(string message, RuntimeDiagnosticStep? step = null)
        {
            if (step is not null)
            {
                steps.Add(step);
                await PublishAsync().ConfigureAwait(false);
            }

            throw new CodexRemoteTunnelException(message, steps.ToList());
        }

        try
        {
            await RunSshCommandAsync(remote, hostname, "echo mapofagents-ssh-ok", TimeSpan.FromSeconds(6), cancellationToken)
                .ConfigureAwait(false);
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "ssh-reachable",
                Title = "SSH reachable",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = hostname,
                Evidence = $"ssh -o BatchMode=yes {hostname} echo mapofagents-ssh-ok"
            }).ConfigureAwait(false);
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "ssh-key",
                Title = "SSH key accepted",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = "BatchMode authentication succeeded",
                Evidence = string.IsNullOrWhiteSpace(remote.IdentityPath) ? "identity: SSH config/default" : "identity: configured"
            }).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            await FailAsync(exception.Message, new RuntimeDiagnosticStep
            {
                Id = "ssh-reachable",
                Title = "SSH reachable",
                Status = RuntimeDiagnosticStatuses.Failed,
                Detail = RedactSensitiveDiagnosticText(exception.Message),
                Evidence = $"ssh -o BatchMode=yes {hostname} echo mapofagents-ssh-ok"
            }).ConfigureAwait(false);
        }

        string remoteCodexVersion;
        try
        {
            remoteCodexVersion = (await RunSshCommandAsync(remote, hostname, "codex --version", TimeSpan.FromSeconds(8), cancellationToken)
                .ConfigureAwait(false)).TrimmedForDisplay();
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "codex",
                Title = "Codex CLI found",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = remoteCodexVersion,
                Evidence = "codex --version"
            }).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            await FailAsync(exception.Message, new RuntimeDiagnosticStep
            {
                Id = "codex",
                Title = "Codex CLI found",
                Status = RuntimeDiagnosticStatuses.Failed,
                Detail = RedactSensitiveDiagnosticText(exception.Message),
                Evidence = "codex --version",
                Action = RuntimeDiagnosticActions.InstallCodexCLI
            }).ConfigureAwait(false);
            return null!;
        }

        var localCodexVersion = await LocalCodexVersionAsync(cancellationToken).ConfigureAwait(false);
        if (!string.IsNullOrWhiteSpace(localCodexVersion) &&
            IsVersionNewer(localCodexVersion, remoteCodexVersion))
        {
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "codex-update",
                Title = "Codex update",
                Status = RuntimeDiagnosticStatuses.Warning,
                Detail = $"remote {VersionNumber(remoteCodexVersion) ?? remoteCodexVersion}; local {VersionNumber(localCodexVersion) ?? localCodexVersion}",
                Evidence = "local codex --version compared with remote codex --version",
                Action = RuntimeDiagnosticActions.UpdateCodexCLI
            }).ConfigureAwait(false);
        }

        try
        {
            await RunSshCommandAsync(remote, hostname, "codex app-server --help", TimeSpan.FromSeconds(8), cancellationToken)
                .ConfigureAwait(false);
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "app-server-command",
                Title = "App Server command available",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = "codex app-server available",
                Evidence = "codex app-server --help"
            }).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            await FailAsync(exception.Message, new RuntimeDiagnosticStep
            {
                Id = "app-server-command",
                Title = "App Server command available",
                Status = RuntimeDiagnosticStatuses.Failed,
                Detail = RedactSensitiveDiagnosticText(exception.Message),
                Evidence = "codex app-server --help",
                Action = RuntimeDiagnosticActions.UpdateCodexCLI
            }).ConfigureAwait(false);
            return null!;
        }

        var localPort = OpenLocalPort();
        RemoteAppServerSession remoteSession;
        try
        {
            remoteSession = await EnsureRemoteAppServerAsync(remote, hostname, cancellationToken).ConfigureAwait(false);
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "remote-listener",
                Title = "Remote listener found or started",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = $"authenticated on 127.0.0.1:{remoteSession.Port}",
                Evidence = $"remote ports: {string.Join(", ", RemoteAppServerPortCandidates(remote))}"
            }).ConfigureAwait(false);
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "remote-token",
                Title = "Token file found and valid",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = $"token length {remoteSession.BearerToken.Length}",
                Evidence = "tracked pid/token files matched authenticated app-server command line"
            }).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            await FailAsync(exception.Message, new RuntimeDiagnosticStep
            {
                Id = "remote-listener",
                Title = "Remote listener found or started",
                Status = RuntimeDiagnosticStatuses.Failed,
                Detail = RedactSensitiveDiagnosticText(exception.Message),
                Evidence = $"try ports: {string.Join(", ", RemoteAppServerPortCandidates(remote))}",
                Action = RuntimeDiagnosticActions.RestartAppServer
            }).ConfigureAwait(false);
            return null!;
        }

        Process tunnelProcess;
        try
        {
            tunnelProcess = StartForwardingTunnel(remote, hostname, localPort, remoteSession.Port);
            await AppendStepAsync(new RuntimeDiagnosticStep
            {
                Id = "ssh-tunnel",
                Title = "SSH tunnel opened",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = $"127.0.0.1:{localPort} -> 127.0.0.1:{remoteSession.Port}",
                Evidence = $"ssh -N -L 127.0.0.1:{localPort}:127.0.0.1:{remoteSession.Port} {hostname}"
            }).ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            await FailAsync(exception.Message, new RuntimeDiagnosticStep
            {
                Id = "ssh-tunnel",
                Title = "SSH tunnel opened",
                Status = RuntimeDiagnosticStatuses.Failed,
                Detail = RedactSensitiveDiagnosticText(exception.Message),
                Evidence = $"ssh -N -L 127.0.0.1:{localPort}:127.0.0.1:{remoteSession.Port} {hostname}"
            }).ConfigureAwait(false);
            return null!;
        }

        var localProbe = await LocalAppServerProbeAsync(localPort, remoteSession.BearerToken, TimeSpan.FromSeconds(4), cancellationToken)
            .ConfigureAwait(false);
        steps.AddRange(localProbe.Steps);
        await PublishAsync().ConfigureAwait(false);
        if (!localProbe.Succeeded)
        {
            KillProcess(tunnelProcess);
            throw new CodexRemoteTunnelException(localProbe.FailureMessage, steps.ToList());
        }

        var endpoint = new AppServerEndpoint(remote.DisplayName, new Uri($"ws://127.0.0.1:{localPort}"), remoteSession.BearerToken);
        return new CodexRemoteTunnelStartResult(new CodexRemoteTunnel(endpoint, tunnelProcess), steps);
    }

    public static bool CanBrowseRemoteFolders(CodexDesktopRemote remote)
    {
        return remote.IsConnectable &&
            remote.Platform is HostPlatforms.Windows or HostPlatforms.MacOS or HostPlatforms.Linux;
    }

    public static async Task<RemoteFolderListing> ListRemoteFoldersAsync(
        CodexDesktopRemote remote,
        string path,
        CancellationToken cancellationToken = default)
    {
        if (!CanBrowseRemoteFolders(remote))
        {
            throw new CodexRemoteTunnelException("Remote folder browsing is not available for this Codex remote.");
        }

        var hostname = SshHostname(remote);
        var command = RemoteListFoldersCommand(remote, string.IsNullOrWhiteSpace(path) ? "~" : path.Trim());
        var output = await RunSshCommandAsync(remote, hostname, command, TimeSpan.FromSeconds(12), cancellationToken)
            .ConfigureAwait(false);
        return RemoteFolderListingFromOutput(output);
    }

    public static RemoteFolderListing RemoteFolderListingFromOutput(string output)
    {
        var start = output.IndexOf('{');
        var end = output.LastIndexOf('}');
        if (start < 0 || end < start)
        {
            throw new CodexRemoteTunnelException("The remote folder listing response was empty.");
        }

        var payload = JsonSerializer.Deserialize<RemoteFolderListingPayload>(
            output[start..(end + 1)],
            MapofAgentsJson.Options);
        if (payload is null || string.IsNullOrWhiteSpace(payload.Path))
        {
            throw new CodexRemoteTunnelException("The remote folder listing response was unreadable.");
        }

        var entries = (payload.Entries ?? [])
            .Where(entry => !string.IsNullOrWhiteSpace(entry.Name) && !string.IsNullOrWhiteSpace(entry.Path))
            .Select(entry => new RemoteFolderEntry(entry.Name.Trim(), entry.Path.Trim()))
            .ToList();

        return new RemoteFolderListing(payload.Path.Trim(), payload.ParentPath?.Trim(), entries);
    }

    public static async Task InstallCodexCliAsync(CodexDesktopRemote remote, CancellationToken cancellationToken = default)
    {
        var hostname = SshHostname(remote);
        var command = remote.Platform == HostPlatforms.Windows
            ? WindowsPowerShellCommand(
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
                """)
            : "sh -lc 'if command -v codex >/dev/null 2>&1; then codex --version; exit 0; fi; if ! command -v npm >/dev/null 2>&1; then echo \"npm is required to install Codex CLI. Install Node.js/npm on the remote machine, then try again.\" >&2; exit 127; fi; npm install -g @openai/codex && codex --version'";
        await RunSshCommandAsync(remote, hostname, command, TimeSpan.FromSeconds(180), cancellationToken).ConfigureAwait(false);
    }

    public static async Task UpdateCodexCliAsync(CodexDesktopRemote remote, CancellationToken cancellationToken = default)
    {
        var hostname = SshHostname(remote);
        var command = remote.Platform == HostPlatforms.Windows
            ? WindowsPowerShellCommand(
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
                """)
            : "sh -lc 'if ! command -v codex >/dev/null 2>&1; then echo \"Codex CLI is not installed.\" >&2; exit 127; fi; if codex update; then codex --version; exit 0; fi; if command -v npm >/dev/null 2>&1; then npm install -g @openai/codex && codex --version; else exit 1; fi'";
        await RunSshCommandAsync(remote, hostname, command, TimeSpan.FromSeconds(180), cancellationToken).ConfigureAwait(false);
    }

    public static async Task<int> StartAppServerAsync(CodexDesktopRemote remote, CancellationToken cancellationToken = default)
    {
        var hostname = SshHostname(remote);
        return (await EnsureRemoteAppServerAsync(remote, hostname, cancellationToken).ConfigureAwait(false)).Port;
    }

    public static async Task<int> RestartAppServerAsync(CodexDesktopRemote remote, CancellationToken cancellationToken = default)
    {
        var hostname = SshHostname(remote);
        var readySession = await FirstAuthenticatedRemoteSessionAsync(remote, hostname, cancellationToken).ConfigureAwait(false);
        if (readySession is not null)
        {
            return readySession.Port;
        }

        await StopRemoteAppServerAsync(remote, hostname, cancellationToken).ConfigureAwait(false);
        var port = RemoteAppServerPortCandidates(remote).FirstOrDefault();
        if (port == 0)
        {
            throw new CodexRemoteTunnelException("No remote App Server port candidates are configured.");
        }

        var session = await StartRemoteAppServerAsync(remote, hostname, port, cancellationToken).ConfigureAwait(false);
        if (!await WaitForRemoteAppServerAsync(remote, hostname, session.Port, TimeSpan.FromSeconds(12), cancellationToken).ConfigureAwait(false))
        {
            throw new CodexRemoteTunnelException($"Remote Codex App Server did not restart on 127.0.0.1:{session.Port}.");
        }

        return session.Port;
    }

    public static string RedactSensitiveDiagnosticText(string value)
    {
        var redacted = value;
        redacted = Regex.Replace(redacted, @"token:[A-Za-z0-9._~+/=-]{8,}", "token:<redacted>");
        redacted = Regex.Replace(redacted, @"Bearer\s+[A-Za-z0-9._~+/=-]{8,}", "Bearer <redacted>", RegexOptions.IgnoreCase);
        redacted = Regex.Replace(redacted, @"--ws-token-file\s+(""[^""]+""|'[^']+'|\S+)", "--ws-token-file <token-file>");
        redacted = Regex.Replace(redacted, @"mapofagents-codex-app-server-[0-9]+\.token", "mapofagents-codex-app-server-<port>.token");
        redacted = Regex.Replace(
            redacted,
            @"(identity file\s+)(.+?)(\s+not accessible)",
            "$1<identity-file>$3",
            RegexOptions.IgnoreCase);
        return redacted;
    }

    private static string SshHostname(CodexDesktopRemote remote)
    {
        var hostname = remote.Hostname?.Trim();
        if (string.IsNullOrWhiteSpace(hostname))
        {
            throw new CodexRemoteTunnelException("This Codex remote is missing an SSH target.");
        }

        if (!CodexDesktopRemoteService.IsValidSSHTarget(hostname))
        {
            throw new CodexRemoteTunnelException($"The SSH target is not valid: {hostname}");
        }

        return hostname;
    }

    private static async Task<RemoteAppServerSession> EnsureRemoteAppServerAsync(
        CodexDesktopRemote remote,
        string hostname,
        CancellationToken cancellationToken)
    {
        var readySession = await FirstAuthenticatedRemoteSessionAsync(remote, hostname, cancellationToken).ConfigureAwait(false);
        if (readySession is not null)
        {
            return readySession;
        }

        Exception? lastError = null;
        foreach (var remotePort in RemoteAppServerPortCandidates(remote))
        {
            try
            {
                var session = await StartRemoteAppServerAsync(remote, hostname, remotePort, cancellationToken).ConfigureAwait(false);
                if (!await WaitForRemoteAppServerAsync(remote, hostname, session.Port, TimeSpan.FromSeconds(12), cancellationToken).ConfigureAwait(false))
                {
                    throw new CodexRemoteTunnelException($"Remote Codex App Server did not start on 127.0.0.1:{session.Port}.");
                }

                return session;
            }
            catch (Exception exception)
            {
                lastError = exception;
            }
        }

        throw lastError ?? new CodexRemoteTunnelException("Could not start an authenticated remote Codex App Server.");
    }

    private static async Task<RemoteAppServerSession> StartRemoteAppServerAsync(
        CodexDesktopRemote remote,
        string hostname,
        int remotePort,
        CancellationToken cancellationToken)
    {
        var output = await RunSshCommandAsync(
            remote,
            hostname,
            RemoteStartAppServerCommand(remote, remotePort),
            TimeSpan.FromSeconds(8),
            cancellationToken).ConfigureAwait(false);
        var token = BearerToken(output);
        if (token is null)
        {
            throw new CodexRemoteTunnelException("Remote Codex App Server did not return an authentication token.");
        }

        return new RemoteAppServerSession(remotePort, token);
    }

    private static async Task StopRemoteAppServerAsync(
        CodexDesktopRemote remote,
        string hostname,
        CancellationToken cancellationToken)
    {
        await RunSshCommandAsync(
            remote,
            hostname,
            RemoteStopAppServerCommand(remote),
            TimeSpan.FromSeconds(8),
            cancellationToken).ConfigureAwait(false);
        await Task.Delay(600, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<RemoteAppServerSession?> FirstAuthenticatedRemoteSessionAsync(
        CodexDesktopRemote remote,
        string hostname,
        CancellationToken cancellationToken)
    {
        foreach (var port in RemoteAppServerPortCandidates(remote))
        {
            var token = await RemoteAuthenticatedAppServerTokenAsync(remote, hostname, port, cancellationToken).ConfigureAwait(false);
            if (token is not null &&
                await IsRemoteAppServerReadyAsync(remote, hostname, port, cancellationToken).ConfigureAwait(false))
            {
                return new RemoteAppServerSession(port, token);
            }
        }

        return null;
    }

    private static async Task<string?> RemoteAuthenticatedAppServerTokenAsync(
        CodexDesktopRemote remote,
        string hostname,
        int remotePort,
        CancellationToken cancellationToken)
    {
        try
        {
            var output = await RunSshCommandAsync(
                remote,
                hostname,
                RemoteAuthenticatedAppServerTokenCommand(remote, remotePort),
                TimeSpan.FromSeconds(5),
                cancellationToken).ConfigureAwait(false);
            return BearerToken(output);
        }
        catch
        {
            return null;
        }
    }

    private static async Task<bool> WaitForRemoteAppServerAsync(
        CodexDesktopRemote remote,
        string hostname,
        int remotePort,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var deadline = DateTimeOffset.UtcNow + timeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            if (await IsRemoteAppServerReadyAsync(remote, hostname, remotePort, cancellationToken).ConfigureAwait(false))
            {
                return true;
            }

            await Task.Delay(400, cancellationToken).ConfigureAwait(false);
        }

        return false;
    }

    private static async Task<bool> IsRemoteAppServerReadyAsync(
        CodexDesktopRemote remote,
        string hostname,
        int remotePort,
        CancellationToken cancellationToken)
    {
        var command = remote.Platform == HostPlatforms.Windows
            ? WindowsPowerShellCommand(
                $$"""
                try {
                    $response = Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 -Uri 'http://127.0.0.1:{{remotePort}}/readyz'
                    if ($response.StatusCode -eq 200) {
                        Write-Output 'ready'
                        exit 0
                    }
                    exit 7
                } catch {
                    exit 7
                }
                """)
            : $"sh -lc 'curl -fsS --max-time 2 http://127.0.0.1:{remotePort}/readyz >/dev/null'";
        try
        {
            await RunSshCommandAsync(remote, hostname, command, TimeSpan.FromSeconds(5), cancellationToken).ConfigureAwait(false);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static async Task<LocalAppServerProbe> LocalAppServerProbeAsync(
        int localPort,
        string bearerToken,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var readyUrl = new Uri($"http://127.0.0.1:{localPort}/readyz");
        var webSocketUrl = new Uri($"ws://127.0.0.1:{localPort}");
        var steps = new List<RuntimeDiagnosticStep>();

        try
        {
            using var httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(Math.Min(timeout.TotalSeconds, 2)) };
            using var response = await httpClient.GetAsync(readyUrl, cancellationToken).ConfigureAwait(false);
            if (response.StatusCode != HttpStatusCode.OK)
            {
                throw new CodexRemoteTunnelException($"/readyz returned HTTP {(int)response.StatusCode}.");
            }

            steps.Add(new RuntimeDiagnosticStep
            {
                Id = "local-readyz",
                Title = "Local tunnel /readyz passed",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = $"HTTP 200 on 127.0.0.1:{localPort}",
                Evidence = $"GET {readyUrl}"
            });
        }
        catch (Exception exception)
        {
            var message = RedactSensitiveDiagnosticText(exception.Message);
            steps.Add(new RuntimeDiagnosticStep
            {
                Id = "local-readyz",
                Title = "Local tunnel /readyz passed",
                Status = RuntimeDiagnosticStatuses.Failed,
                Detail = message,
                Evidence = $"GET {readyUrl}",
                Action = RuntimeDiagnosticActions.RestartAppServer
            });
            return new LocalAppServerProbe(false, $"SSH tunnel opened, but /readyz failed on 127.0.0.1:{localPort}: {message}", steps);
        }

        try
        {
            using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeoutSource.CancelAfter(TimeSpan.FromSeconds(Math.Min(timeout.TotalSeconds, 3)));
            var initialize = await new AppServerClient().InitializeAsync(
                new AppServerEndpoint("Codex Remote", webSocketUrl, bearerToken),
                timeoutSource.Token).ConfigureAwait(false);
            var keys = InitializeResultKeys(initialize.RawJson);
            steps.Add(new RuntimeDiagnosticStep
            {
                Id = "websocket-initialize",
                Title = "WebSocket initialize passed",
                Status = RuntimeDiagnosticStatuses.Passed,
                Detail = keys.Count == 0 ? "initialize response accepted" : $"fields: {string.Join(", ", keys)}",
                Evidence = $"initialize over {webSocketUrl} with bearer token"
            });
            return new LocalAppServerProbe(true, "", steps);
        }
        catch (Exception exception)
        {
            var message = RedactSensitiveDiagnosticText(exception.Message);
            steps.Add(new RuntimeDiagnosticStep
            {
                Id = "websocket-initialize",
                Title = "WebSocket initialize passed",
                Status = RuntimeDiagnosticStatuses.Failed,
                Detail = message,
                Evidence = $"initialize over {webSocketUrl} with bearer token",
                Action = RuntimeDiagnosticActions.RestartAppServer
            });
            return new LocalAppServerProbe(
                false,
                $"Codex App Server answered /readyz, but WebSocket initialize failed on 127.0.0.1:{localPort}: {message}",
                steps);
        }
    }

    private static Process StartForwardingTunnel(CodexDesktopRemote remote, string hostname, int localPort, int remotePort)
    {
        var startInfo = new ProcessStartInfo("ssh")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        AddSshBaseArguments(startInfo, remote, hostname);
        startInfo.ArgumentList.Add("-N");
        startInfo.ArgumentList.Add("-L");
        startInfo.ArgumentList.Add($"127.0.0.1:{localPort}:127.0.0.1:{remotePort}");
        startInfo.ArgumentList.Add("--");
        startInfo.ArgumentList.Add(hostname);

        var process = Process.Start(startInfo);
        if (process is null)
        {
            throw new CodexRemoteTunnelException("Could not start the SSH tunnel.");
        }

        Thread.Sleep(450);
        if (process.HasExited)
        {
            var error = process.StandardError.ReadToEnd();
            process.Dispose();
            throw new CodexRemoteTunnelException(string.IsNullOrWhiteSpace(error)
                ? "SSH tunnel process exited before forwarding started."
                : error.Trim());
        }

        return process;
    }

    private static async Task<string> RunSshCommandAsync(
        CodexDesktopRemote remote,
        string hostname,
        string remoteCommand,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo("ssh")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        AddSshBaseArguments(startInfo, remote, hostname);
        startInfo.ArgumentList.Add("--");
        startInfo.ArgumentList.Add(hostname);
        startInfo.ArgumentList.Add(remoteCommand);

        using var process = Process.Start(startInfo) ?? throw new CodexRemoteTunnelException("Could not start ssh.");
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        var stdoutTask = process.StandardOutput.ReadToEndAsync(timeoutSource.Token);
        var stderrTask = process.StandardError.ReadToEndAsync(timeoutSource.Token);

        try
        {
            await process.WaitForExitAsync(timeoutSource.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            KillProcess(process);
            throw new CodexRemoteTunnelException("Timed out waiting for the remote SSH command.");
        }

        var stdout = CleanedSshOutputForDisplay(TruncateOutput(await stdoutTask.ConfigureAwait(false)));
        var stderr = CleanedSshOutputForDisplay(TruncateOutput(await stderrTask.ConfigureAwait(false)));
        if (process.ExitCode != 0)
        {
            var detail = !string.IsNullOrWhiteSpace(stderr)
                ? stderr
                : !string.IsNullOrWhiteSpace(stdout)
                    ? stdout
                    : $"Remote SSH command failed with exit code {process.ExitCode}.";
            throw new CodexRemoteTunnelException(RedactSensitiveDiagnosticText(detail));
        }

        return stdout;
    }

    private static void AddSshBaseArguments(ProcessStartInfo startInfo, CodexDesktopRemote remote, string hostname)
    {
        if (!CodexDesktopRemoteService.IsValidSSHTarget(hostname))
        {
            throw new CodexRemoteTunnelException($"The SSH target is not valid: {hostname}");
        }

        foreach (var argument in new[]
        {
            "-o", "ExitOnForwardFailure=yes",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "StrictHostKeyChecking=yes"
        })
        {
            startInfo.ArgumentList.Add(argument);
        }

        if (!string.IsNullOrWhiteSpace(remote.IdentityPath))
        {
            startInfo.ArgumentList.Add("-i");
            startInfo.ArgumentList.Add(remote.IdentityPath);
        }

        if (remote.SshPort is not null)
        {
            if (remote.SshPort is < 1 or > 65_535)
            {
                throw new CodexRemoteTunnelException($"The SSH target is not valid: {hostname}:{remote.SshPort}");
            }

            startInfo.ArgumentList.Add("-p");
            startInfo.ArgumentList.Add(remote.SshPort.Value.ToString());
        }
    }

    private static string RemoteStartAppServerCommand(CodexDesktopRemote remote, int remotePort)
    {
        if (remote.Platform == HostPlatforms.Windows)
        {
            return WindowsPowerShellCommand(
                $$"""
                $ErrorActionPreference = 'Stop'
                $port = {{remotePort}}
                $target = "ws://127.0.0.1:$port"
                $pidPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.pid"
                $tokenPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.token"
                $stdoutPath = Join-Path $env:TEMP "codex-app-server-$port.out.log"
                $stderrPath = Join-Path $env:TEMP "codex-app-server-$port.err.log"
                {{WindowsTrackedAppServerTokenFunction()}}
                $existing = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $port -State Listen -ErrorAction SilentlyContinue
                if ($existing) {
                    $existingToken = Find-MapofAgentsTrackedAppServerToken -Port $port
                    if (-not [string]::IsNullOrWhiteSpace($existingToken)) {
                        Write-Output "token:$existingToken"
                        exit 0
                    }
                    throw "Port $port is already in use by an app-server without a readable MapofAgents token. Restart MapofAgents on Windows or free the port."
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
                """);
        }

        var script = $$"""
        port={{remotePort}}
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
                  printf 'token:%s\n' "$(head -n 1 "$tokenfile" | tr -d '[:space:]')"
                  exit 0
                  ;;
              esac
            fi
          fi
          echo "Port $port is already in use by an untracked or unauthenticated App Server." >&2
          exit 64
        fi

        umask 077
        token="$( (command -v openssl >/dev/null 2>&1 && openssl rand -hex 32) || (od -An -N32 -tx1 /dev/urandom | tr -d ' \n') )"
        if [ -z "$token" ]; then
          echo "Could not generate an App Server token." >&2
          exit 65
        fi
        printf '%s\n' "$token" > "$tokenfile"
        nohup codex app-server --listen "ws://127.0.0.1:${port}" --ws-auth capability-token --ws-token-file "$tokenfile" >"$logfile" 2>&1 </dev/null &
        echo $! > "$pidfile"
        printf 'token:%s\n' "$token"
        """;
        return $"sh -lc {ShellSingleQuoted(script)}";
    }

    private static string RemoteListFoldersCommand(CodexDesktopRemote remote, string path)
    {
        if (remote.Platform == HostPlatforms.Windows)
        {
            return WindowsPowerShellCommand(
                $$"""
                $ErrorActionPreference = 'Stop'
                $rawPath = {{PowerShellSingleQuoted(path)}}
                if ([string]::IsNullOrWhiteSpace($rawPath) -or $rawPath -eq '~') {
                    $rawPath = [Environment]::GetFolderPath('UserProfile')
                }
                $resolvedPath = Resolve-Path -LiteralPath $rawPath -ErrorAction Stop | Select-Object -First 1
                $resolved = $resolvedPath.ProviderPath
                if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
                    throw "Not a directory: $rawPath"
                }
                $parent = Split-Path -Path $resolved -Parent
                if ([string]::IsNullOrWhiteSpace($parent)) {
                    $parent = $null
                }
                $entries = @(Get-ChildItem -LiteralPath $resolved -Directory -Force -ErrorAction SilentlyContinue |
                    Sort-Object Name |
                    Select-Object -First 300 |
                    ForEach-Object {
                        [pscustomobject]@{
                            name = $_.Name
                            path = $_.FullName
                        }
                    })
                [pscustomobject]@{
                    path = $resolved
                    parent = $parent
                    entries = @($entries)
                } | ConvertTo-Json -Depth 4 -Compress
                """);
        }

        var script =
            """
            import json
            import os
            import sys

            raw_path = (os.environ.get("MAPOFAGENTS_DIR") or "~").strip() or "~"
            resolved = os.path.abspath(os.path.expanduser(raw_path))
            if not os.path.isdir(resolved):
                print(f"Not a directory: {raw_path}", file=sys.stderr)
                raise SystemExit(64)

            entries = []
            try:
                names = sorted(os.listdir(resolved), key=lambda value: value.lower())
            except OSError as exc:
                print(str(exc), file=sys.stderr)
                raise SystemExit(65)

            for name in names:
                full_path = os.path.join(resolved, name)
                if os.path.isdir(full_path):
                    entries.append({"name": name, "path": full_path})
                if len(entries) >= 300:
                    break

            parent = os.path.dirname(resolved.rstrip(os.sep)) or None
            if parent == resolved:
                parent = None

            print(json.dumps(
                {"path": resolved, "parent": parent, "entries": entries},
                separators=(",", ":")))
            """;
        var command = $"MAPOFAGENTS_DIR={ShellSingleQuoted(path)} python3 - <<'PY'\n{script}\nPY";
        return $"sh -lc {ShellSingleQuoted(command)}";
    }

    private static string RemoteStopAppServerCommand(CodexDesktopRemote remote)
    {
        var ports = RemoteAppServerPortCandidates(remote).ToList();
        if (remote.Platform == HostPlatforms.Windows)
        {
            var portList = string.Join(",", ports);
            return WindowsPowerShellCommand(
                $$"""
                $ErrorActionPreference = 'Stop'
                $ports = @({{portList}})
                foreach ($port in $ports) {
                    $pidPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.pid"
                    $tokenPath = Join-Path $env:TEMP "mapofagents-codex-app-server-$port.token"
                    $stopped = $false
                    if (Test-Path $pidPath) {
                        $trackedPid = (Get-Content $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                        if ($trackedPid -match '^\d+$') {
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
                """);
        }

        var portListText = string.Join(" ", ports);
        var script = $$"""
        for port in {{portListText}}; do
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
        """;
        return $"sh -lc {ShellSingleQuoted(script)}";
    }

    private static string RemoteAuthenticatedAppServerTokenCommand(CodexDesktopRemote remote, int remotePort)
    {
        if (remote.Platform == HostPlatforms.Windows)
        {
            return WindowsPowerShellCommand(
                $$"""
                $ErrorActionPreference = 'Stop'
                $port = {{remotePort}}
                {{WindowsTrackedAppServerTokenFunction()}}
                $token = Find-MapofAgentsTrackedAppServerToken -Port $port
                if ([string]::IsNullOrWhiteSpace($token)) {
                    exit 7
                }
                Write-Output "token:$token"
                """);
        }

        var script = $$"""
        port={{remotePort}}
        tokenfile="/tmp/mapofagents-codex-app-server-${port}.token"
        pidfile="/tmp/mapofagents-codex-app-server-${port}.pid"
        [ -f "$pidfile" ] && [ -s "$tokenfile" ] || exit 7
        pid="$(head -n 1 "$pidfile" | tr -dc '0-9')"
        [ -n "$pid" ] || exit 7
        command_line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
        case "$command_line" in
          *codex*"app-server"*"127.0.0.1:${port}"*"--ws-auth"*"capability-token"*"--ws-token-file"*"$tokenfile"*)
            printf 'token:%s\n' "$(head -n 1 "$tokenfile" | tr -d '[:space:]')"
            ;;
          *)
            exit 7
            ;;
        esac
        """;
        return $"sh -lc {ShellSingleQuoted(script)}";
    }

    private static string? BearerToken(string output)
    {
        foreach (var line in output.Split('\n'))
        {
            var text = line.Trim();
            if (!text.StartsWith("token:", StringComparison.Ordinal))
            {
                continue;
            }

            var token = text["token:".Length..].Trim();
            if (token.Length >= 32 && !token.Any(char.IsWhiteSpace))
            {
                return token;
            }
        }

        return null;
    }

    private static int OpenLocalPort()
    {
        using var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        return ((IPEndPoint)listener.LocalEndpoint).Port;
    }

    public static string CleanedSshOutputForDisplay(string value)
    {
        var output = value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
        output = string.Join(
            '\n',
            output
                .Split('\n')
                .Where(line => !line.TrimStart().StartsWith("#< CLIXML", StringComparison.Ordinal)));

        var clixmlMessages = new List<string>();
        while (true)
        {
            var start = output.IndexOf("<Objs", StringComparison.Ordinal);
            if (start < 0)
            {
                break;
            }

            var end = output.IndexOf("</Objs>", start, StringComparison.Ordinal);
            if (end < 0)
            {
                break;
            }

            end += "</Objs>".Length;
            var block = output[start..end];
            clixmlMessages.AddRange(HumanMessagesFromClixml(block));
            output = output.Remove(start, end - start);
        }

        var humanOutput = string.Join(
                '\n',
                output
                    .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                    .Where(line => !string.IsNullOrWhiteSpace(line)))
            .Trim();
        var decodedMessages = clixmlMessages
            .Select(message => message.Trim())
            .Where(message => !string.IsNullOrWhiteSpace(message))
            .ToArray();

        if (string.IsNullOrWhiteSpace(humanOutput))
        {
            return string.Join('\n', decodedMessages);
        }

        return decodedMessages.Length == 0
            ? humanOutput
            : string.Join('\n', new[] { humanOutput }.Concat(decodedMessages));
    }

    private static IEnumerable<string> HumanMessagesFromClixml(string block)
    {
        foreach (var pattern in new[]
        {
            """<S S="(?:Error|Warning)">([\s\S]*?)</S>""",
            """<S N="Message">([\s\S]*?)</S>"""
        })
        {
            foreach (Match match in Regex.Matches(block, pattern))
            {
                if (match.Groups.Count > 1)
                {
                    yield return DecodePowerShellSerializedText(match.Groups[1].Value);
                }
            }
        }
    }

    private static string DecodePowerShellSerializedText(string value)
    {
        var decoded = WebUtility.HtmlDecode(value);
        decoded = Regex.Replace(
            decoded,
            "_x([0-9A-Fa-f]{4})_",
            match =>
            {
                var hex = match.Groups[1].Value;
                return int.TryParse(hex, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var scalar)
                    ? char.ConvertFromUtf32(scalar)
                    : match.Value;
            });
        return decoded
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
    }

    private static string WindowsTrackedAppServerTokenFunction()
    {
        return """
        function Find-MapofAgentsTrackedAppServerToken {
            param([int]$Port)
            $roots = @()
            if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
                $roots += $env:TEMP
            }
            if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
                $roots += (Join-Path $env:APPDATA 'MapofAgents\local-app-server')
            }

            foreach ($root in $roots) {
                $pidPath = Join-Path $root "mapofagents-codex-app-server-$Port.pid"
                $tokenPath = Join-Path $root "mapofagents-codex-app-server-$Port.token"
                if (-not ((Test-Path -LiteralPath $pidPath -PathType Leaf) -and (Test-Path -LiteralPath $tokenPath -PathType Leaf))) {
                    continue
                }

                $trackedPid = (Get-Content -LiteralPath $pidPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                if ($trackedPid -notmatch '^\d+$') {
                    continue
                }

                $processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $trackedPid" -ErrorAction SilentlyContinue
                if (-not $processInfo) {
                    continue
                }

                $commandLine = [string]$processInfo.CommandLine
                $matchesLoopbackPort = $commandLine -match [regex]::Escape("127.0.0.1:$Port") -or
                    $commandLine -match [regex]::Escape("ws://127.0.0.1:$Port")
                if ($commandLine -notmatch 'codex' -or
                    $commandLine -notmatch 'app-server' -or
                    -not $matchesLoopbackPort -or
                    $commandLine -notmatch '--ws-auth' -or
                    $commandLine -notmatch 'capability-token' -or
                    $commandLine -notmatch [regex]::Escape($tokenPath)) {
                    continue
                }

                $token = (Get-Content -LiteralPath $tokenPath -ErrorAction SilentlyContinue | Select-Object -First 1).Trim()
                if (-not [string]::IsNullOrWhiteSpace($token)) {
                    return $token
                }
            }
            return $null
        }
        """;
    }

    private static string WindowsPowerShellCommand(string script)
    {
        var bytes = Encoding.Unicode.GetBytes(script);
        return $"powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand {Convert.ToBase64String(bytes)}";
    }

    private static string PowerShellSingleQuoted(string value)
    {
        return $"'{value.Replace("'", "''", StringComparison.Ordinal)}'";
    }

    private static string ShellSingleQuoted(string value)
    {
        return $"'{value.Replace("'", "'\"'\"'", StringComparison.Ordinal)}'";
    }

    private static async Task<string?> LocalCodexVersionAsync(CancellationToken cancellationToken)
    {
        try
        {
            return (await RunProcessAsync("codex", ["--version"], TimeSpan.FromSeconds(4), cancellationToken).ConfigureAwait(false))
                .Stdout
                .TrimmedForDisplay();
        }
        catch
        {
            return null;
        }
    }

    private static async Task<ProcessRunResult> RunProcessAsync(
        string fileName,
        IEnumerable<string> arguments,
        TimeSpan timeout,
        CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo(fileName)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in arguments)
        {
            startInfo.ArgumentList.Add(argument);
        }

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException($"Could not start {fileName}.");
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        var stdoutTask = process.StandardOutput.ReadToEndAsync(timeoutSource.Token);
        var stderrTask = process.StandardError.ReadToEndAsync(timeoutSource.Token);
        try
        {
            await process.WaitForExitAsync(timeoutSource.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            KillProcess(process);
            throw;
        }

        return new ProcessRunResult(
            process.ExitCode,
            TruncateOutput(await stdoutTask.ConfigureAwait(false)),
            TruncateOutput(await stderrTask.ConfigureAwait(false)));
    }

    private static IReadOnlyList<string> InitializeResultKeys(string rawJson)
    {
        try
        {
            using var document = System.Text.Json.JsonDocument.Parse(rawJson);
            if (!document.RootElement.TryGetProperty("result", out var result) ||
                result.ValueKind != System.Text.Json.JsonValueKind.Object)
            {
                return [];
            }

            return result.EnumerateObject()
                .Select(property => property.Name)
                .Where(name => !string.IsNullOrWhiteSpace(name))
                .Take(8)
                .ToList();
        }
        catch
        {
            return [];
        }
    }

    private static bool IsVersionNewer(string lhs, string rhs)
    {
        var lhsComponents = SemanticVersionComponents(lhs);
        var rhsComponents = SemanticVersionComponents(rhs);
        if (lhsComponents is null || rhsComponents is null)
        {
            return false;
        }

        for (var index = 0; index < lhsComponents.Length; index++)
        {
            if (lhsComponents[index] > rhsComponents[index])
            {
                return true;
            }

            if (lhsComponents[index] < rhsComponents[index])
            {
                return false;
            }
        }

        return false;
    }

    private static int[]? SemanticVersionComponents(string value)
    {
        var version = VersionNumber(value);
        if (version is null)
        {
            return null;
        }

        var components = version
            .Split('.')
            .Select(part => int.TryParse(part, out var number) ? number : 0)
            .Concat([0, 0, 0])
            .Take(3)
            .ToArray();
        return components.Length == 0 ? null : components;
    }

    private static string? VersionNumber(string value)
    {
        var match = Regex.Match(value, @"\d+(?:\.\d+){1,3}");
        return match.Success ? match.Value : null;
    }

    private static string TruncateOutput(string value)
    {
        if (value.Length <= MaxProcessOutputBytes)
        {
            return value;
        }

        return value[..MaxProcessOutputBytes];
    }

    private static void KillProcess(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill(entireProcessTree: true);
            }
        }
        catch (InvalidOperationException)
        {
        }
    }

    private sealed record RemoteAppServerSession(int Port, string BearerToken);

    private sealed record LocalAppServerProbe(
        bool Succeeded,
        string FailureMessage,
        IReadOnlyList<RuntimeDiagnosticStep> Steps);

    private sealed record ProcessRunResult(int ExitCode, string Stdout, string Stderr);

    private sealed class RemoteFolderListingPayload
    {
        [JsonPropertyName("path")]
        public string Path { get; set; } = "";

        [JsonPropertyName("parent")]
        public string? ParentPath { get; set; }

        [JsonPropertyName("entries")]
        public List<RemoteFolderEntryPayload>? Entries { get; set; }
    }

    private sealed class RemoteFolderEntryPayload
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = "";

        [JsonPropertyName("path")]
        public string Path { get; set; } = "";
    }
}

internal static class CodexRemoteTunnelStringExtensions
{
    public static string TrimmedForDisplay(this string value)
    {
        var trimmed = value.Trim();
        return trimmed.Length <= 90 ? trimmed : $"{trimmed[..87]}...";
    }
}
