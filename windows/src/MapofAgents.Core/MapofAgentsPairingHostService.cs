using System.ComponentModel;
using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace MapofAgents.Core;

public sealed record MapofAgentsPairingHostSession(
    MapofAgentsPairingPayload Payload,
    string PairingUrl,
    DateTimeOffset ExpiresAt,
    bool MayRequireWindowsNetworkAccessApproval);

public sealed class MapofAgentsPairingHostService
{
    public const int DefaultPort = 18_945;
    public static readonly TimeSpan PairingSessionDuration = TimeSpan.FromMinutes(30);

    private const string SignedBearerIssuer = "mapofagents";
    private const string SignedBearerAudience = "codex-app-server";
    private const string SignedBearerSubject = "mapofagents-pairing";
    private const int SignedBearerClockSkewSeconds = 5;
    private static readonly TimeSpan ReadyProbeTimeout = TimeSpan.FromSeconds(2);

    private readonly string _supportDirectory;
    private Process? _hostProcess;
    private CancellationTokenSource? _expirationCancellation;

    public MapofAgentsPairingHostService(string? supportDirectory = null)
    {
        _supportDirectory = string.IsNullOrWhiteSpace(supportDirectory)
            ? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "MapofAgents")
            : supportDirectory;
    }

    public async Task<MapofAgentsPairingHostSession> BeginPairingSessionAsync(
        int port = DefaultPort,
        TimeSpan? duration = null,
        CancellationToken cancellationToken = default)
    {
        StopPairingSession(port);
        var expiresAt = DateTimeOffset.UtcNow.Add(duration ?? PairingSessionDuration);
        var session = RotateToken(expiresAt);
        StartHostServer(port);

        for (var attempt = 0; attempt < 12; attempt++)
        {
            await Task.Delay(250, cancellationToken).ConfigureAwait(false);
            if (HostProcessExitSummary() is { } exitSummary)
            {
                ExpirePairingSessionIfCurrentToken(session.Token, port);
                throw new MapofAgentsPairingException($"Could not start the mapofagents Windows host server: {exitSummary} {RecentLogSnippet()}");
            }

            if (await IsHostServerReadyAsync(port, cancellationToken).ConfigureAwait(false))
            {
                var payload = MakePayload(port, session.Token, expiresAt);
                SchedulePairingExpiration(session.Token, port, expiresAt);
                return new MapofAgentsPairingHostSession(
                    payload,
                    payload.PairingUrl(),
                    expiresAt,
                    MayRequireNetworkAccessApproval(ListenerUrl(port), OperatingSystem.IsWindows()));
            }
        }

        var failureDetail = HostServerFailureDetail();
        ExpirePairingSessionIfCurrentToken(session.Token, port);
        throw new MapofAgentsPairingException($"Could not start the mapofagents Windows host server: {failureDetail}");
    }

    public void StopPairingSession(int port = DefaultPort)
    {
        _expirationCancellation?.Cancel();
        _expirationCancellation?.Dispose();
        _expirationCancellation = null;
        StopHostServer(port);
        TryDelete(TokenPath);
        TryDelete(SharedSecretPath);
    }

    public static string SignedBearerToken(
        string secret,
        DateTimeOffset expiresAt,
        DateTimeOffset? issuedAt = null)
    {
        var issued = issuedAt ?? DateTimeOffset.UtcNow;
        var header = new SortedDictionary<string, object>
        {
            ["alg"] = "HS256",
            ["typ"] = "JWT"
        };
        var payload = new SortedDictionary<string, object>
        {
            ["aud"] = SignedBearerAudience,
            ["exp"] = CeilingUnixSeconds(expiresAt),
            ["iat"] = issued.ToUnixTimeSeconds(),
            ["iss"] = SignedBearerIssuer,
            ["nbf"] = issued.AddSeconds(-SignedBearerClockSkewSeconds).ToUnixTimeSeconds(),
            ["sub"] = SignedBearerSubject
        };

        var signingInput = $"{Base64UrlJson(header)}.{Base64UrlJson(payload)}";
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var signature = hmac.ComputeHash(Encoding.UTF8.GetBytes(signingInput));
        return $"{signingInput}.{Base64UrlEncode(signature)}";
    }

    public static DateTimeOffset? SignedBearerExpiration(string token)
    {
        var parts = token.Split('.');
        if (parts.Length != 3)
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(Base64UrlDecode(parts[1]));
            if (!document.RootElement.TryGetProperty("exp", out var expiration) ||
                !expiration.TryGetInt64(out var unixSeconds))
            {
                return null;
            }

            return DateTimeOffset.FromUnixTimeSeconds(unixSeconds);
        }
        catch (JsonException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    public static IReadOnlyList<MapofAgentsPairingEndpoint> EndpointCandidatesFromTailscaleStatusJson(
        string json,
        int port = DefaultPort)
    {
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("Self", out var self))
        {
            return [];
        }

        var hosts = new List<string>();
        if (self.TryGetProperty("DNSName", out var dnsName) &&
            dnsName.ValueKind == JsonValueKind.String &&
            !string.IsNullOrWhiteSpace(dnsName.GetString()))
        {
            hosts.Add(dnsName.GetString()!);
        }

        if (self.TryGetProperty("TailscaleIPs", out var addresses) &&
            addresses.ValueKind == JsonValueKind.Array)
        {
            hosts.AddRange(addresses
                .EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.String)
                .Select(item => item.GetString()!)
                .Where(address => !string.IsNullOrWhiteSpace(address)));
        }

        return StableUnique(hosts)
            .Select(host => Endpoint("tailnet", host, host, port))
            .Where(endpoint => endpoint is not null)
            .Cast<MapofAgentsPairingEndpoint>()
            .ToList();
    }

    public static Uri ReadyzUrl(int port = DefaultPort)
    {
        return new Uri($"http://127.0.0.1:{port}/readyz");
    }

    public static Uri ListenerUrl(int port = DefaultPort)
    {
        return new Uri(ListenerUrlString(port));
    }

    public static bool MayRequireNetworkAccessApproval(Uri listenerUrl, bool isWindows)
    {
        if (!isWindows)
        {
            return false;
        }

        var host = listenerUrl.Host.Trim('[', ']').ToLowerInvariant();
        return listenerUrl.Scheme.Equals("ws", StringComparison.OrdinalIgnoreCase) &&
            host is not ("localhost" or "127.0.0.1" or "::1");
    }

    public static string ListenerUrlString(int port = DefaultPort)
    {
        return $"ws://0.0.0.0:{port}";
    }

    private MapofAgentsPairingPayload MakePayload(int port, string token, DateTimeOffset expiresAt)
    {
        var hostName = Environment.MachineName;
        return new MapofAgentsPairingPayload
        {
            HostID = PersistentHostID(hostName),
            Name = string.IsNullOrWhiteSpace(hostName) ? "Windows PC" : hostName,
            Endpoints = EndpointCandidates(port).ToList(),
            BearerToken = token,
            CreatedAt = DateTimeOffset.UtcNow,
            ExpiresAt = expiresAt,
            MapofAgentsSupportDirectory = _supportDirectory
        };
    }

    private IReadOnlyList<MapofAgentsPairingEndpoint> EndpointCandidates(int port)
    {
        var endpoints = new List<MapofAgentsPairingEndpoint>();
        endpoints.AddRange(TailnetEndpointCandidates(port));

        var machineName = Environment.MachineName;
        var localHosts = new[]
        {
            string.IsNullOrWhiteSpace(machineName) ? null : $"{machineName}.local",
            string.IsNullOrWhiteSpace(machineName) ? null : machineName
        };
        endpoints.AddRange(localHosts
            .Where(host => !string.IsNullOrWhiteSpace(host))
            .Select(host => Endpoint("local", host!, host!, port))
            .Where(endpoint => endpoint is not null)
            .Cast<MapofAgentsPairingEndpoint>());

        return endpoints
            .GroupBy(endpoint => endpoint.Url, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .ToList();
    }

    private IEnumerable<MapofAgentsPairingEndpoint> TailnetEndpointCandidates(int port)
    {
        try
        {
            var tailscale = TailscaleExecutablePath();
            if (tailscale is null)
            {
                return [];
            }

            using var process = new Process
            {
                StartInfo = new ProcessStartInfo
                {
                    FileName = tailscale,
                    ArgumentList = { "status", "--json" },
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    StandardOutputEncoding = Encoding.UTF8,
                    StandardErrorEncoding = Encoding.UTF8,
                    UseShellExecute = false,
                    CreateNoWindow = true
                }
            };

            process.Start();
            var stdout = process.StandardOutput.ReadToEnd();
            if (!process.WaitForExit(3000))
            {
                process.Kill(entireProcessTree: true);
                return [];
            }

            return process.ExitCode == 0
                ? EndpointCandidatesFromTailscaleStatusJson(stdout, port)
                : [];
        }
        catch (Exception exception) when (exception is InvalidOperationException or IOException)
        {
            return [];
        }
    }

    private PairingAuthSession RotateToken(DateTimeOffset expiresAt)
    {
        Directory.CreateDirectory(_supportDirectory);
        var secret = GenerateSecret();
        var token = SignedBearerToken(secret, expiresAt);
        File.WriteAllText(SharedSecretPath, secret, Encoding.UTF8);
        File.WriteAllText(TokenPath, token, Encoding.UTF8);
        return new PairingAuthSession(token, expiresAt);
    }

    private async Task<bool> IsHostServerReadyAsync(
        int port,
        CancellationToken cancellationToken)
    {
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(ReadyProbeTimeout);
            using var client = new HttpClient { Timeout = ReadyProbeTimeout };
            using var response = await client
                .GetAsync(ReadyzUrl(port), timeout.Token)
                .ConfigureAwait(false);
            return response.IsSuccessStatusCode;
        }
        catch (Exception exception) when (
            exception is OperationCanceledException or HttpRequestException or IOException)
        {
            return false;
        }
    }

    private void StartHostServer(int port)
    {
        var codexPath = CodexExecutablePath();
        if (codexPath is null)
        {
            throw new MapofAgentsPairingException("Could not find the codex executable needed to host iPhone pairing.");
        }

        Directory.CreateDirectory(_supportDirectory);
        File.WriteAllText(LogPath, "", Encoding.UTF8);
        AppendLogLine($"starting codex app-server on ws://0.0.0.0:{port} using {codexPath}");

        var appServerArgs = new[]
        {
            "app-server",
            "--listen",
            ListenerUrlString(port),
            "--ws-auth",
            "signed-bearer-token",
            "--ws-shared-secret-file",
            SharedSecretPath,
            "--ws-issuer",
            SignedBearerIssuer,
            "--ws-audience",
            SignedBearerAudience,
            "--ws-max-clock-skew-seconds",
            SignedBearerClockSkewSeconds.ToString()
        };
        var startInfo = ProcessStartInfoForCodex(codexPath, appServerArgs);
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;
        startInfo.StandardOutputEncoding = Encoding.UTF8;
        startInfo.StandardErrorEncoding = Encoding.UTF8;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;

        _hostProcess = new Process
        {
            StartInfo = startInfo,
            EnableRaisingEvents = true
        };
        _hostProcess.OutputDataReceived += (_, eventArgs) => AppendLogLine(eventArgs.Data);
        _hostProcess.ErrorDataReceived += (_, eventArgs) => AppendLogLine(eventArgs.Data);
        _hostProcess.Exited += (_, _) =>
        {
            try
            {
                AppendLogLine($"codex app-server exited with code {_hostProcess?.ExitCode}");
            }
            catch (InvalidOperationException)
            {
            }
        };
        _hostProcess.Start();
        _hostProcess.BeginOutputReadLine();
        _hostProcess.BeginErrorReadLine();
        File.WriteAllText(PidPath, _hostProcess.Id.ToString(), Encoding.UTF8);
    }

    private void StopHostServer(int port)
    {
        if (_hostProcess is { HasExited: false })
        {
            try
            {
                _hostProcess.Kill(entireProcessTree: true);
            }
            catch (Exception exception) when (exception is InvalidOperationException or Win32Exception)
            {
            }
        }

        _hostProcess?.Dispose();
        _hostProcess = null;

        if (File.Exists(PidPath) &&
            int.TryParse(File.ReadAllText(PidPath).Trim(), out var pid))
        {
            try
            {
                var process = Process.GetProcessById(pid);
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                }
            }
            catch (Exception exception) when (exception is ArgumentException or InvalidOperationException or Win32Exception)
            {
            }
        }

        TryDelete(PidPath);
    }

    private string HostServerFailureDetail()
    {
        var exitSummary = HostProcessExitSummary();
        var logSnippet = RecentLogSnippet();
        return string.IsNullOrWhiteSpace(exitSummary)
            ? logSnippet
            : $"{exitSummary} {logSnippet}".Trim();
    }

    private string? HostProcessExitSummary()
    {
        try
        {
            if (_hostProcess is { HasExited: true })
            {
                return $"The process exited with code {_hostProcess.ExitCode}.";
            }
        }
        catch (InvalidOperationException)
        {
        }

        return null;
    }

    private void SchedulePairingExpiration(string token, int port, DateTimeOffset expiresAt)
    {
        _expirationCancellation?.Cancel();
        _expirationCancellation?.Dispose();
        _expirationCancellation = new CancellationTokenSource();
        var cancellationToken = _expirationCancellation.Token;
        _ = Task.Run(async () =>
        {
            var delay = expiresAt - DateTimeOffset.UtcNow;
            if (delay > TimeSpan.Zero)
            {
                await Task.Delay(delay, cancellationToken).ConfigureAwait(false);
            }

            if (!cancellationToken.IsCancellationRequested)
            {
                ExpirePairingSessionIfCurrentToken(token, port);
            }
        }, cancellationToken);
    }

    private void ExpirePairingSessionIfCurrentToken(string token, int port)
    {
        if (!string.Equals(CurrentToken(), token, StringComparison.Ordinal))
        {
            return;
        }

        StopHostServer(port);
        TryDelete(TokenPath);
        TryDelete(SharedSecretPath);
    }

    private string? CurrentToken()
    {
        return File.Exists(TokenPath)
            ? File.ReadAllText(TokenPath, Encoding.UTF8).Trim()
            : null;
    }

    private string PersistentHostID(string hostName)
    {
        Directory.CreateDirectory(_supportDirectory);
        var path = Path.Combine(_supportDirectory, "pairing-host-id.txt");
        if (File.Exists(path))
        {
            var existing = File.ReadAllText(path, Encoding.UTF8).Trim();
            if (!string.IsNullOrWhiteSpace(existing))
            {
                return existing;
            }
        }

        var id = $"paired-windows-{SafeIdentifier(hostName)}";
        File.WriteAllText(path, id, Encoding.UTF8);
        return id;
    }

    private string RecentLogSnippet()
    {
        if (!File.Exists(LogPath))
        {
            return "The process did not become ready.";
        }

        var text = File.ReadAllText(LogPath, Encoding.UTF8);
        if (string.IsNullOrWhiteSpace(text))
        {
            return "The process did not become ready.";
        }

        return text.Length <= 1200 ? text.Trim() : text[^1200..].Trim();
    }

    private string TokenPath => Path.Combine(_supportDirectory, "windows-lan-app-server.token");

    private string SharedSecretPath => Path.Combine(_supportDirectory, "windows-lan-app-server.shared-secret");

    private string LogPath => Path.Combine(_supportDirectory, "windows-lan-app-server.log");

    private string PidPath => Path.Combine(_supportDirectory, "windows-lan-app-server.pid");

    private static ProcessStartInfo ProcessStartInfoForCodex(string codexPath, IReadOnlyList<string> appServerArgs)
    {
        var extension = Path.GetExtension(codexPath).ToLowerInvariant();
        var useCmdShell = extension is ".cmd" or ".bat" ||
            (string.IsNullOrEmpty(extension) && OperatingSystem.IsWindows());
        var startInfo = extension switch
        {
            ".ps1" => new ProcessStartInfo("powershell.exe"),
            ".cmd" or ".bat" => new ProcessStartInfo("cmd.exe"),
            _ when useCmdShell => new ProcessStartInfo("cmd.exe"),
            _ => new ProcessStartInfo(codexPath)
        };

        if (extension == ".ps1")
        {
            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-File");
            startInfo.ArgumentList.Add(codexPath);
            foreach (var argument in appServerArgs)
            {
                startInfo.ArgumentList.Add(argument);
            }
        }
        else if (useCmdShell)
        {
            startInfo.ArgumentList.Add("/d");
            startInfo.ArgumentList.Add("/s");
            startInfo.ArgumentList.Add("/c");
            startInfo.ArgumentList.Add(CmdCommandLine(codexPath, appServerArgs));
        }
        else
        {
            foreach (var argument in appServerArgs)
            {
                startInfo.ArgumentList.Add(argument);
            }
        }

        return startInfo;
    }

    private static string CmdCommandLine(string command, IReadOnlyList<string> arguments)
    {
        return string.Join(
            " ",
            new[] { command }
                .Concat(arguments)
                .Select(QuoteCmdArgument));
    }

    private static string QuoteCmdArgument(string argument)
    {
        if (argument.Length == 0)
        {
            return "\"\"";
        }

        var needsQuotes = argument.Any(character =>
            char.IsWhiteSpace(character) ||
            character is '"' or '&' or '(' or ')' or '[' or ']' or '{' or '}' or '^' or '=' or ';' or '!' or '\'' or '+' or ',' or '`' or '~');
        if (!needsQuotes)
        {
            return argument;
        }

        return $"\"{argument.Replace("\"", "\\\"")}\"";
    }

    private static MapofAgentsPairingEndpoint? Endpoint(string kind, string host, string label, int port)
    {
        var cleaned = host.Trim().Trim('.');
        if (string.IsNullOrWhiteSpace(cleaned))
        {
            return null;
        }

        var formattedHost = cleaned.Contains(':') && !cleaned.StartsWith('[')
            ? $"[{cleaned}]"
            : cleaned;
        return new MapofAgentsPairingEndpoint
        {
            Id = $"{kind}-{SafeIdentifier(cleaned)}",
            Kind = kind,
            Label = string.IsNullOrWhiteSpace(label) ? cleaned : label.Trim().Trim('.'),
            Url = $"ws://{formattedHost}:{port}"
        };
    }

    private static IReadOnlyList<string> StableUnique(IEnumerable<string?> values)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<string>();
        foreach (var value in values)
        {
            var cleaned = value?.Trim().Trim('.');
            if (!string.IsNullOrWhiteSpace(cleaned) && seen.Add(cleaned))
            {
                result.Add(cleaned);
            }
        }

        return result;
    }

    private static string? CodexExecutablePath()
    {
        var candidates = PathEntries()
            .SelectMany(path => new[]
            {
                Path.Combine(path, "codex.exe"),
                Path.Combine(path, "codex.cmd"),
                Path.Combine(path, "codex.bat"),
                Path.Combine(path, "codex.ps1"),
                Path.Combine(path, "codex")
            })
            .Append("codex")
            .ToList();

        return candidates.FirstOrDefault(File.Exists) ?? "codex";
    }

    private static string? TailscaleExecutablePath()
    {
        var candidates = PathEntries()
            .SelectMany(path => new[]
            {
                Path.Combine(path, "tailscale.exe"),
                Path.Combine(path, "tailscale")
            })
            .Concat(new[]
            {
                @"C:\Program Files\Tailscale\tailscale.exe",
                @"C:\Program Files (x86)\Tailscale\tailscale.exe"
            });
        return candidates.FirstOrDefault(File.Exists);
    }

    private static IEnumerable<string> PathEntries()
    {
        return (Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
            .Where(path => !string.IsNullOrWhiteSpace(path));
    }

    private static string GenerateSecret()
    {
        var bytes = RandomNumberGenerator.GetBytes(32);
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private static string SafeIdentifier(string value)
    {
        var builder = new StringBuilder();
        foreach (var character in value.ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(character))
            {
                builder.Append(character);
            }
            else if (builder.Length == 0 || builder[^1] != '-')
            {
                builder.Append('-');
            }
        }

        return builder.ToString().Trim('-');
    }

    private void AppendLogLine(string? line)
    {
        if (line is null)
        {
            return;
        }

        try
        {
            File.AppendAllText(LogPath, $"{line}{Environment.NewLine}", Encoding.UTF8);
        }
        catch (IOException)
        {
        }
    }

    private static long CeilingUnixSeconds(DateTimeOffset date)
    {
        return (long)Math.Ceiling(date.ToUnixTimeMilliseconds() / 1000.0);
    }

    private static string Base64UrlJson(object value)
    {
        return Base64UrlEncode(JsonSerializer.SerializeToUtf8Bytes(value, MapofAgentsJson.Options));
    }

    private static string Base64UrlEncode(byte[] value)
    {
        return Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static byte[] Base64UrlDecode(string value)
    {
        var normalized = value.Trim().Replace('-', '+').Replace('_', '/');
        var padding = normalized.Length % 4;
        if (padding > 0)
        {
            normalized = normalized.PadRight(normalized.Length + (4 - padding), '=');
        }

        return Convert.FromBase64String(normalized);
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private sealed record PairingAuthSession(string Token, DateTimeOffset ExpiresAt);
}
