using System.Diagnostics;
using System.Globalization;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

namespace MapofAgents.Core;

public sealed class LocalAppServerException(string message, Exception? innerException = null)
    : Exception(message, innerException);

public sealed record LocalAppServerStartResult(
    AppServerEndpoint Endpoint,
    AppServerInitializeResult InitializeResult,
    int Port,
    string TokenFilePath);

public static class LocalAppServerService
{
    public const int PreferredWindowsPort = 14_500;
    public const int FallbackPort = 18_945;
    private const string LocalAppServerDirectoryName = "local-app-server";
    private static readonly TimeSpan InitializeTimeout = TimeSpan.FromSeconds(25);

    public static IReadOnlyList<int> PortCandidates { get; } = [PreferredWindowsPort, FallbackPort];

    public static async Task<LocalAppServerStartResult> StartOrConnectAsync(
        string applicationDataDirectory,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(applicationDataDirectory))
        {
            throw new LocalAppServerException("Application data directory is required.");
        }

        var supportDirectory = Path.Combine(
            ApplicationSupportFolder.EnsureExists(applicationDataDirectory),
            LocalAppServerDirectoryName);
        Directory.CreateDirectory(supportDirectory);

        Exception? lastError = null;
        foreach (var port in PortCandidates)
        {
            var paths = LocalAppServerPaths.For(supportDirectory, port);
            var launchedServer = false;
            try
            {
                var hadTrackedServer = HasTrackedServer(paths);
                if (await TryConnectTrackedServerAsync(paths, cancellationToken).ConfigureAwait(false) is { } tracked)
                {
                    return tracked;
                }

                if (hadTrackedServer)
                {
                    await ReclaimTrackedServerAsync(paths, cancellationToken).ConfigureAwait(false);
                }

                if (await IsPortListeningAsync(port, cancellationToken).ConfigureAwait(false))
                {
                    lastError = new LocalAppServerException(
                        $"Port {port} is already in use by an untracked or unauthenticated App Server.");
                    continue;
                }

                var token = GenerateToken();
                await File.WriteAllTextAsync(paths.TokenPath, token, cancellationToken).ConfigureAwait(false);
                var process = StartCodexAppServer(port, paths);
                launchedServer = true;
                await File.WriteAllTextAsync(paths.PidPath, process.Id.ToString(), cancellationToken).ConfigureAwait(false);

                var endpoint = EndpointFor(port, token);
                var initialize = await WaitForInitializeAsync(endpoint, cancellationToken).ConfigureAwait(false);
                return new LocalAppServerStartResult(endpoint, initialize, port, paths.TokenPath);
            }
            catch (Exception exception) when (exception is not OperationCanceledException)
            {
                lastError = exception;
                if (launchedServer)
                {
                    break;
                }
            }
        }

        throw new LocalAppServerException(
            lastError is null
                ? "Could not start a local Codex App Server."
                : CodexRemoteTunnelService.RedactSensitiveDiagnosticText(lastError.Message),
            lastError);
    }

    private static async Task<LocalAppServerStartResult?> TryConnectTrackedServerAsync(
        LocalAppServerPaths paths,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(paths.TokenPath))
        {
            return null;
        }

        var token = (await File.ReadAllTextAsync(paths.TokenPath, cancellationToken).ConfigureAwait(false)).Trim();
        if (string.IsNullOrWhiteSpace(token))
        {
            return null;
        }

        var endpoint = EndpointFor(paths.Port, token);
        try
        {
            var initialize = await new AppServerClient().InitializeAsync(endpoint, cancellationToken).ConfigureAwait(false);
            return new LocalAppServerStartResult(endpoint, initialize, paths.Port, paths.TokenPath);
        }
        catch (Exception exception) when (exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            return null;
        }
    }

    private static bool HasTrackedServer(LocalAppServerPaths paths)
    {
        return File.Exists(paths.PidPath) || File.Exists(paths.TokenPath);
    }

    private static async Task ReclaimTrackedServerAsync(
        LocalAppServerPaths paths,
        CancellationToken cancellationToken)
    {
        await StopTrackedProcessAsync(paths, cancellationToken).ConfigureAwait(false);
        await StopManagedListenerProcessesAsync(paths, cancellationToken).ConfigureAwait(false);
        await WaitForPortToCloseAsync(paths.Port, cancellationToken).ConfigureAwait(false);
        DeleteTrackedFiles(paths);
    }

    private static async Task StopTrackedProcessAsync(
        LocalAppServerPaths paths,
        CancellationToken cancellationToken)
    {
        if (!File.Exists(paths.PidPath))
        {
            return;
        }

        var pidText = (await File.ReadAllTextAsync(paths.PidPath, cancellationToken).ConfigureAwait(false)).Trim();
        if (!int.TryParse(pidText, CultureInfo.InvariantCulture, out var pid) || pid <= 0)
        {
            return;
        }

        if (RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            await RunTaskKillAsync(pid, cancellationToken).ConfigureAwait(false);
            return;
        }

        try
        {
            Process.GetProcessById(pid).Kill(entireProcessTree: true);
        }
        catch
        {
            // A missing or already-exited tracked process is fine; stale files are removed below.
        }
    }

    private static async Task RunTaskKillAsync(int pid, CancellationToken cancellationToken)
    {
        var startInfo = new ProcessStartInfo("taskkill.exe")
        {
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false
        };
        startInfo.ArgumentList.Add("/PID");
        startInfo.ArgumentList.Add(pid.ToString(CultureInfo.InvariantCulture));
        startInfo.ArgumentList.Add("/T");
        startInfo.ArgumentList.Add("/F");

        try
        {
            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return;
            }

            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            // If taskkill is unavailable or the process is already gone, startup will validate the port next.
        }
    }

    private static async Task StopManagedListenerProcessesAsync(
        LocalAppServerPaths paths,
        CancellationToken cancellationToken)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
        {
            return;
        }

        var processIds = await FindManagedListenerProcessIdsAsync(paths, cancellationToken).ConfigureAwait(false);
        foreach (var pid in processIds.Distinct())
        {
            await RunTaskKillAsync(pid, cancellationToken).ConfigureAwait(false);
        }
    }

    private static async Task<IReadOnlyList<int>> FindManagedListenerProcessIdsAsync(
        LocalAppServerPaths paths,
        CancellationToken cancellationToken)
    {
        const string script = """
$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$tokenPath = [Environment]::GetEnvironmentVariable('MAPOFAGENTS_LOCAL_TOKEN_PATH', 'Process')
$portText = [Environment]::GetEnvironmentVariable('MAPOFAGENTS_LOCAL_PORT', 'Process')
if ([string]::IsNullOrWhiteSpace($tokenPath) -or [string]::IsNullOrWhiteSpace($portText)) {
    exit 0
}

$lines = netstat -ano -p TCP | Select-String (':' + $portText + ' ')
foreach ($line in $lines) {
    $text = ($line.Line -replace '\s+', ' ').Trim()
    if (-not $text.Contains(' LISTENING ')) {
        continue
    }

    $parts = $text -split ' '
    $listenerPidText = $parts[$parts.Length - 1]
    $process = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $listenerPidText)
    $commandLine = $process.CommandLine -as [string]
    if (-not $commandLine) {
        continue
    }

    $usesManagedTokenPath = $commandLine.IndexOf($tokenPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
    $isAppServer = $commandLine.IndexOf('app-server', [StringComparison]::OrdinalIgnoreCase) -ge 0
    if ($usesManagedTokenPath -and $isAppServer) {
        Write-Output $listenerPidText
    }
}
""";

        var startInfo = new ProcessStartInfo("powershell.exe")
        {
            CreateNoWindow = true,
            RedirectStandardError = true,
            RedirectStandardOutput = true,
            UseShellExecute = false
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(script);
        startInfo.Environment["MAPOFAGENTS_LOCAL_TOKEN_PATH"] = paths.TokenPath;
        startInfo.Environment["MAPOFAGENTS_LOCAL_PORT"] = paths.Port.ToString(CultureInfo.InvariantCulture);

        try
        {
            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return [];
            }

            var outputTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
            var errorTask = process.StandardError.ReadToEndAsync(cancellationToken);
            await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
            _ = await errorTask.ConfigureAwait(false);

            var output = await outputTask.ConfigureAwait(false);
            return output
                .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                .Select(line => int.TryParse(line, NumberStyles.Integer, CultureInfo.InvariantCulture, out var pid) ? pid : 0)
                .Where(pid => pid > 0)
                .ToArray();
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            return [];
        }
    }

    private static async Task WaitForPortToCloseAsync(int port, CancellationToken cancellationToken)
    {
        var deadline = DateTimeOffset.UtcNow + TimeSpan.FromSeconds(2);
        while (DateTimeOffset.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (!await IsPortListeningAsync(port, cancellationToken).ConfigureAwait(false))
            {
                return;
            }

            await Task.Delay(150, cancellationToken).ConfigureAwait(false);
        }
    }

    private static void DeleteTrackedFiles(LocalAppServerPaths paths)
    {
        DeleteFileIfExists(paths.PidPath);
        DeleteFileIfExists(paths.TokenPath);
    }

    private static void DeleteFileIfExists(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch
        {
            // The next startup attempt will surface any remaining file or port issue.
        }
    }

    private static AppServerEndpoint EndpointFor(int port, string token)
    {
        return new AppServerEndpoint(
            "Local Codex App Server",
            new Uri($"ws://127.0.0.1:{port}"),
            token);
    }

    private static Process StartCodexAppServer(
        int port,
        LocalAppServerPaths paths)
    {
        var codexCommand = FindExecutableOnPath("codex")
            ?? throw new LocalAppServerException("codex was not found on PATH.");
        var startInfo = CreateCodexStartInfo(
            codexCommand,
            [
                "app-server",
                "--listen",
                $"ws://127.0.0.1:{port}",
                "--ws-auth",
                "capability-token",
                "--ws-token-file",
                paths.TokenPath
            ]);
        startInfo.CreateNoWindow = true;
        startInfo.UseShellExecute = false;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;

        try
        {
            return Process.Start(startInfo)
                ?? throw new LocalAppServerException("codex app-server did not start.");
        }
        catch (Exception exception) when (exception is not LocalAppServerException)
        {
            var redacted = CodexRemoteTunnelService.RedactSensitiveDiagnosticText(exception.Message);
            throw new LocalAppServerException($"Could not launch codex app-server: {redacted}", exception);
        }
    }

    private static ProcessStartInfo CreateCodexStartInfo(string codexCommand, IReadOnlyList<string> arguments)
    {
        var extension = Path.GetExtension(codexCommand);
        if (extension.Equals(".cmd", StringComparison.OrdinalIgnoreCase) ||
            extension.Equals(".bat", StringComparison.OrdinalIgnoreCase))
        {
            var startInfo = new ProcessStartInfo("cmd.exe");
            startInfo.ArgumentList.Add("/c");
            startInfo.ArgumentList.Add(codexCommand);
            foreach (var argument in arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }

            return startInfo;
        }

        if (extension.Equals(".ps1", StringComparison.OrdinalIgnoreCase))
        {
            var startInfo = new ProcessStartInfo("powershell.exe");
            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(codexCommand);
            foreach (var argument in arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }

            return startInfo;
        }

        var processStartInfo = new ProcessStartInfo(codexCommand);
        foreach (var argument in arguments)
        {
            processStartInfo.ArgumentList.Add(argument);
        }

        return processStartInfo;
    }

    private static async Task<AppServerInitializeResult> WaitForInitializeAsync(
        AppServerEndpoint endpoint,
        CancellationToken cancellationToken)
    {
        var deadline = DateTimeOffset.UtcNow + InitializeTimeout;
        Exception? lastError = null;
        while (DateTimeOffset.UtcNow < deadline)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var attemptTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                attemptTimeout.CancelAfter(TimeSpan.FromSeconds(2));
                return await new AppServerClient().InitializeAsync(endpoint, attemptTimeout.Token).ConfigureAwait(false);
            }
            catch (Exception exception) when (exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
            {
                lastError = exception;
                await Task.Delay(350, cancellationToken).ConfigureAwait(false);
            }
        }

        throw new LocalAppServerException(
            lastError is null
                ? $"Local Codex App Server did not answer initialize on {endpoint.Url}."
                : $"Local Codex App Server did not answer initialize on {endpoint.Url}: {lastError.Message}",
            lastError);
    }

    private static async Task<bool> IsPortListeningAsync(int port, CancellationToken cancellationToken)
    {
        try
        {
            using var client = new TcpClient();
            var connectTask = client.ConnectAsync("127.0.0.1", port, cancellationToken).AsTask();
            var completed = await Task.WhenAny(connectTask, Task.Delay(300, cancellationToken)).ConfigureAwait(false);
            if (completed != connectTask)
            {
                return false;
            }

            await connectTask.ConfigureAwait(false);
            return client.Connected;
        }
        catch
        {
            return false;
        }
    }

    private static string GenerateToken()
    {
        return Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
    }

    private static string? FindExecutableOnPath(string executableName)
    {
        var paths = (Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var extensions = RuntimeInformation.IsOSPlatform(OSPlatform.Windows)
            ? (Environment.GetEnvironmentVariable("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD;.PS1")
                .Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            : [""];

        foreach (var path in paths)
        {
            foreach (var extension in extensions)
            {
                var candidate = Path.Combine(path, executableName + extension);
                if (File.Exists(candidate))
                {
                    return candidate;
                }
            }
        }

        return null;
    }

    private sealed record LocalAppServerPaths(
        int Port,
        string PidPath,
        string TokenPath)
    {
        public static LocalAppServerPaths For(string supportDirectory, int port)
        {
            return new LocalAppServerPaths(
                port,
                Path.Combine(supportDirectory, $"mapofagents-codex-app-server-{port}.pid"),
                Path.Combine(supportDirectory, $"mapofagents-codex-app-server-{port}.token"));
        }
    }
}
