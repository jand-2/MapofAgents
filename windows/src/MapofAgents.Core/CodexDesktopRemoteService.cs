using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public sealed class CodexDesktopRemote
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("displayName")]
    public string DisplayName { get; set; } = "";

    [JsonPropertyName("hostID")]
    public string HostID { get; set; } = "";

    [JsonPropertyName("hostname")]
    public string? Hostname { get; set; }

    [JsonPropertyName("identityPath")]
    public string? IdentityPath { get; set; }

    [JsonPropertyName("sshPort")]
    public int? SshPort { get; set; }

    [JsonPropertyName("source")]
    public string Source { get; set; } = "codex-desktop";

    public string Platform => HostPlatformResolver.Resolve(DisplayName);

    public bool IsConnectable => !string.IsNullOrWhiteSpace(Hostname);

    public string DisplayAddress => Hostname ?? HostID;
}

public sealed class CodexDesktopRemoteException : Exception
{
    public CodexDesktopRemoteException(string message)
        : base(message)
    {
    }
}

public static class CodexDesktopRemoteService
{
    private const string StateOverrideVariable = "MAPOFAGENTS_CODEX_DESKTOP_STATE_PATH";

    public static async Task<IReadOnlyList<CodexDesktopRemote>> DiscoverAsync(CancellationToken cancellationToken = default)
    {
        var statePath = DefaultStatePath();
        if (string.IsNullOrWhiteSpace(statePath) || !File.Exists(statePath))
        {
            throw new CodexDesktopRemoteException("Codex Desktop remote state was not found.");
        }

        try
        {
            var json = await File.ReadAllTextAsync(statePath, cancellationToken).ConfigureAwait(false);
            return RemotesFromJson(json);
        }
        catch (JsonException exception)
        {
            throw new CodexDesktopRemoteException($"Codex Desktop remote state could not be read: {exception.Message}");
        }
        catch (IOException exception)
        {
            throw new CodexDesktopRemoteException($"Codex Desktop remote state could not be read: {exception.Message}");
        }
        catch (UnauthorizedAccessException exception)
        {
            throw new CodexDesktopRemoteException($"Codex Desktop remote state could not be read: {exception.Message}");
        }
    }

    public static IReadOnlyList<CodexDesktopRemote> RemotesFromJson(string json)
    {
        var state = JsonSerializer.Deserialize<CodexDesktopState>(json, MapofAgentsJson.Options);
        return (state?.ManagedRemoteConnections ?? [])
            .Select(RemoteFromConnection)
            .Where(remote => remote is not null)
            .Cast<CodexDesktopRemote>()
            .OrderByDescending(remote => remote.IsConnectable)
            .ThenBy(remote => remote.DisplayName, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public static bool IsValidSSHTarget(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Trim() != value)
        {
            return false;
        }

        if (value.StartsWith('-') ||
            value.Any(char.IsWhiteSpace) ||
            value.Any(char.IsControl) ||
            value.Contains('/') ||
            value.Contains('\\'))
        {
            return false;
        }

        var parts = value.Split('@', 2);
        var host = parts.Length == 2 ? parts[1] : parts[0];
        if (parts.Length == 2 &&
            (string.IsNullOrWhiteSpace(parts[0]) ||
             !parts[0].All(character => char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or '-')))
        {
            return false;
        }

        return !string.IsNullOrWhiteSpace(host) &&
            host.All(character => char.IsAsciiLetterOrDigit(character) || character is '.' or '-' or ':' or '[' or ']' or '_' or '%');
    }

    private static CodexDesktopRemote? RemoteFromConnection(CodexDesktopManagedRemoteConnection connection)
    {
        var hostID = NonEmpty(connection.HostID);
        if (hostID is null)
        {
            return null;
        }

        var displayName = NonEmpty(connection.DisplayName) ??
            NonEmpty(connection.Alias) ??
            NonEmpty(connection.Hostname) ??
            hostID;
        return new CodexDesktopRemote
        {
            Id = MachineID(hostID),
            DisplayName = displayName,
            HostID = hostID,
            Hostname = IsValidSSHTarget(connection.Hostname) ? connection.Hostname : null,
            IdentityPath = NonEmpty(connection.Identity),
            SshPort = connection.SshPort,
            Source = NonEmpty(connection.Source) ?? "codex-desktop"
        };
    }

    private static string? DefaultStatePath()
    {
        var overridePath = Environment.GetEnvironmentVariable(StateOverrideVariable);
        if (!string.IsNullOrWhiteSpace(overridePath))
        {
            return overridePath;
        }

        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return string.IsNullOrWhiteSpace(home)
            ? null
            : Path.Combine(home, ".codex", ".codex-global-state.json");
    }

    private static string MachineID(string raw)
    {
        var compact = new string(raw
            .ToLowerInvariant()
            .Select(character => char.IsLetterOrDigit(character) ? character : '-')
            .ToArray())
            .Trim('-');
        return string.IsNullOrWhiteSpace(compact) ? $"codex-remote-{Guid.NewGuid():N}" : $"codex-remote-{compact}";
    }

    private static string? NonEmpty(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
    }

    private sealed class CodexDesktopState
    {
        [JsonPropertyName("codex-managed-remote-connections")]
        public List<CodexDesktopManagedRemoteConnection>? ManagedRemoteConnections { get; set; }
    }

    private sealed class CodexDesktopManagedRemoteConnection
    {
        public string? Alias { get; set; }

        public string? DisplayName { get; set; }

        [JsonPropertyName("hostId")]
        public string? HostID { get; set; }

        public string? Hostname { get; set; }

        public string? Identity { get; set; }

        public string? Source { get; set; }

        public int? SshPort { get; set; }
    }
}
