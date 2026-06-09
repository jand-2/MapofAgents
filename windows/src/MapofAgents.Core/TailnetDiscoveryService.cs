using System.Diagnostics;
using System.ComponentModel;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public sealed class TailnetMachine
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("dnsName")]
    public string? DnsName { get; set; }

    [JsonPropertyName("addresses")]
    public List<string> Addresses { get; set; } = [];

    [JsonPropertyName("platform")]
    public string Platform { get; set; } = HostPlatforms.Unknown;

    [JsonPropertyName("isOnline")]
    public bool IsOnline { get; set; }

    [JsonPropertyName("lastSeenAt")]
    public DateTimeOffset? LastSeenAt { get; set; }

    public string DisplayAddress => DnsName ?? Addresses.FirstOrDefault() ?? "tailnet";

    public string? SuggestedWebSocketEndpoint(int port = 18_945)
    {
        var host = DnsName ?? Addresses.FirstOrDefault();
        if (string.IsNullOrWhiteSpace(host))
        {
            return null;
        }

        var formattedHost = host.Contains(':') && !host.StartsWith('[')
            ? $"[{host}]"
            : host;
        var scheme = DnsName is null ? "ws" : "wss";
        return $"{scheme}://{formattedHost}:{port}";
    }
}

public sealed class TailnetDiscoveryException : Exception
{
    public TailnetDiscoveryException(string message)
        : base(message)
    {
    }
}

public static class TailnetDiscoveryService
{
    public static async Task<IReadOnlyList<TailnetMachine>> DiscoverAsync(CancellationToken cancellationToken = default)
    {
        var executable = TailscaleExecutablePath();
        if (executable is null)
        {
            throw new TailnetDiscoveryException("Tailscale CLI not found.");
        }

        using var process = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = executable,
                ArgumentList = { "status", "--json" },
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        try
        {
            process.Start();
        }
        catch (Exception exception) when (exception is Win32Exception or InvalidOperationException)
        {
            throw new TailnetDiscoveryException(exception.Message);
        }

        var stdoutTask = process.StandardOutput.ReadToEndAsync(cancellationToken);
        var stderrTask = process.StandardError.ReadToEndAsync(cancellationToken);
        await process.WaitForExitAsync(cancellationToken).ConfigureAwait(false);
        var stdout = await stdoutTask.ConfigureAwait(false);
        var stderr = await stderrTask.ConfigureAwait(false);
        if (process.ExitCode != 0)
        {
            throw new TailnetDiscoveryException(
                string.IsNullOrWhiteSpace(stderr) ? "Tailscale discovery failed." : stderr.Trim());
        }

        return MachinesFromJson(stdout);
    }

    public static IReadOnlyList<TailnetMachine> MachinesFromJson(string json)
    {
        try
        {
            var status = JsonSerializer.Deserialize<TailscaleStatus>(json, MapofAgentsJson.Options);
            return (status?.Peers ?? [])
                .Select(pair => MachineFromPeer(pair.Value, pair.Key))
                .Where(machine => machine is not null)
                .Cast<TailnetMachine>()
                .OrderByDescending(machine => machine.IsOnline)
                .ThenBy(machine => machine.Name, StringComparer.OrdinalIgnoreCase)
                .ToList();
        }
        catch (JsonException exception)
        {
            throw new TailnetDiscoveryException($"Tailscale returned an unreadable status response: {exception.Message}");
        }
    }

    private static TailnetMachine? MachineFromPeer(TailscalePeer peer, string fallbackID)
    {
        var dnsName = TrimTailnetDNSName(peer.DnsName);
        var name = FirstNonEmpty(peer.HostName, dnsName, peer.TailscaleIPs?.FirstOrDefault(), fallbackID);
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        return new TailnetMachine
        {
            Id = MachineID(peer.ID ?? peer.PublicKey ?? dnsName ?? fallbackID),
            Name = name,
            DnsName = dnsName,
            Addresses = peer.TailscaleIPs ?? [],
            Platform = HostPlatformResolver.Resolve(peer.OS),
            IsOnline = peer.Online ?? peer.Active ?? false,
            LastSeenAt = ParseDate(peer.LastSeen)
        };
    }

    private static string MachineID(string raw)
    {
        var compact = new string(raw
            .ToLowerInvariant()
            .Select(character => char.IsLetterOrDigit(character) ? character : '-')
            .ToArray())
            .Trim('-');
        return string.IsNullOrWhiteSpace(compact) ? $"tailnet-{Guid.NewGuid():N}" : $"tailnet-{compact}";
    }

    private static DateTimeOffset? ParseDate(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) ||
            value.StartsWith("0001-01-01", StringComparison.Ordinal))
        {
            return null;
        }

        return DateTimeOffset.TryParse(
            value,
            CultureInfo.InvariantCulture,
            DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
            out var date)
            ? date
            : null;
    }

    private static string? FirstNonEmpty(params string?[] values)
    {
        return values
            .Select(value => value?.Trim())
            .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
    }

    private static string? TrimTailnetDNSName(string? value)
    {
        var trimmed = value?.Trim().Trim('.');
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private static string? TailscaleExecutablePath()
    {
        var pathCandidates = (Environment.GetEnvironmentVariable("PATH") ?? "")
            .Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(path => Path.Combine(path, "tailscale.exe"));
        var installCandidates = new[]
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Tailscale", "tailscale.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Tailscale", "tailscale.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Tailscale", "tailscale.exe")
        };

        return pathCandidates
            .Concat(installCandidates)
            .FirstOrDefault(File.Exists);
    }

    private sealed class TailscaleStatus
    {
        [JsonPropertyName("Peer")]
        public Dictionary<string, TailscalePeer>? Peers { get; set; }
    }

    private sealed class TailscalePeer
    {
        public string? ID { get; set; }

        public string? PublicKey { get; set; }

        public string? HostName { get; set; }

        public string? DnsName { get; set; }

        public string? OS { get; set; }

        public List<string>? TailscaleIPs { get; set; }

        public bool? Online { get; set; }

        public bool? Active { get; set; }

        public string? LastSeen { get; set; }
    }
}
