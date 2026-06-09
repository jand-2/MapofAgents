using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public sealed class MapofAgentsPairingException : Exception
{
    public MapofAgentsPairingException(string message)
        : base(message)
    {
    }
}

public sealed class MapofAgentsPairingEndpoint
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = "";

    [JsonPropertyName("url")]
    public string Url { get; set; } = "";

    [JsonPropertyName("label")]
    public string Label { get; set; } = "";
}

public sealed class MapofAgentsPairingPayload
{
    public const string UrlScheme = "mapofagents";
    public const string UrlHost = "pair";

    [JsonPropertyName("version")]
    public int Version { get; set; } = 1;

    [JsonPropertyName("hostID")]
    public string HostID { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("endpoints")]
    public List<MapofAgentsPairingEndpoint> Endpoints { get; set; } = [];

    [JsonPropertyName("bearerToken")]
    public string BearerToken { get; set; } = "";

    [JsonPropertyName("createdAt")]
    public DateTimeOffset? CreatedAt { get; set; }

    [JsonPropertyName("expiresAt")]
    public DateTimeOffset? ExpiresAt { get; set; }

    [JsonPropertyName("mapofagentsSupportDirectory")]
    public string? MapofAgentsSupportDirectory { get; set; }

    public bool IsExpired => ExpiresAt is not null && ExpiresAt.Value < DateTimeOffset.UtcNow;

    public string PairingUrl()
    {
        var json = JsonSerializer.Serialize(this, MapofAgentsJson.Options);
        return $"{UrlScheme}://{UrlHost}?payload={Base64UrlEncode(Encoding.UTF8.GetBytes(json))}";
    }

    public static MapofAgentsPairingPayload Decode(string value)
    {
        var encodedPayload = EncodedPayload(value);
        var json = Encoding.UTF8.GetString(Base64UrlDecode(encodedPayload));
        try
        {
            return JsonSerializer.Deserialize<MapofAgentsPairingPayload>(json, MapofAgentsJson.Options)
                ?? throw new MapofAgentsPairingException("This pairing payload is empty.");
        }
        catch (JsonException exception)
        {
            throw new MapofAgentsPairingException($"This pairing payload is unreadable: {exception.Message}");
        }
    }

    public void ValidateForImport()
    {
        if (ExpiresAt is null)
        {
            throw new MapofAgentsPairingException("This pairing payload is missing its expiration time.");
        }

        if (IsExpired)
        {
            throw new MapofAgentsPairingException("This pairing payload has expired.");
        }

        if (Endpoints.Count == 0)
        {
            throw new MapofAgentsPairingException("This pairing payload does not include a WebSocket endpoint.");
        }

        if (string.IsNullOrWhiteSpace(BearerToken))
        {
            throw new MapofAgentsPairingException("This pairing payload does not include a bearer token.");
        }
    }

    public MapofAgentsPairingEndpoint? PreferredEndpoint()
    {
        return PreferredEndpoints().FirstOrDefault();
    }

    public IReadOnlyList<MapofAgentsPairingEndpoint> PreferredEndpoints()
    {
        var token = BearerToken.Trim();
        return Endpoints
            .Select((endpoint, index) => new { Endpoint = endpoint, Index = index })
            .Where(endpoint =>
                Uri.TryCreate(endpoint.Endpoint.Url, UriKind.Absolute, out var url) &&
                AppServerEndpointValidator.Validate(
                    url,
                    token,
                    AppServerEndpointTrust.SignedPairingPayload).IsValid)
            .OrderBy(endpoint => EndpointPriority(endpoint.Endpoint.Kind))
            .ThenBy(endpoint => endpoint.Index)
            .Select(endpoint => endpoint.Endpoint)
            .ToList();
    }

    private static int EndpointPriority(string? kind)
    {
        return kind?.Trim().ToLowerInvariant() switch
        {
            "tailnet" => 0,
            "local" => 1,
            "manual" => 2,
            _ => 3
        };
    }

    private static string EncodedPayload(string value)
    {
        var trimmed = value.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            throw new MapofAgentsPairingException("Paste a mapofagents pairing payload before importing.");
        }

        if (Uri.TryCreate(trimmed, UriKind.Absolute, out var uri) &&
            string.Equals(uri.Scheme, UrlScheme, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(uri.Host, UrlHost, StringComparison.OrdinalIgnoreCase))
        {
            var payload = QueryValue(uri.Query, "payload");
            if (!string.IsNullOrWhiteSpace(payload))
            {
                return payload;
            }
        }

        var markerIndex = trimmed.IndexOf("payload=", StringComparison.OrdinalIgnoreCase);
        if (markerIndex >= 0)
        {
            var payload = trimmed[(markerIndex + "payload=".Length)..];
            var ampersand = payload.IndexOf('&');
            if (ampersand >= 0)
            {
                payload = payload[..ampersand];
            }

            return Uri.UnescapeDataString(payload);
        }

        return trimmed;
    }

    private static string? QueryValue(string query, string name)
    {
        var trimmed = query.TrimStart('?');
        foreach (var part in trimmed.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var pieces = part.Split('=', 2);
            if (pieces.Length == 2 &&
                string.Equals(Uri.UnescapeDataString(pieces[0]), name, StringComparison.OrdinalIgnoreCase))
            {
                return Uri.UnescapeDataString(pieces[1]);
            }
        }

        return null;
    }

    private static byte[] Base64UrlDecode(string value)
    {
        var normalized = value.Trim().Replace('-', '+').Replace('_', '/');
        var padding = normalized.Length % 4;
        if (padding > 0)
        {
            normalized = normalized.PadRight(normalized.Length + (4 - padding), '=');
        }

        try
        {
            return Convert.FromBase64String(normalized);
        }
        catch (FormatException exception)
        {
            throw new MapofAgentsPairingException($"This pairing code is not valid: {exception.Message}");
        }
    }

    private static string Base64UrlEncode(byte[] value)
    {
        return Convert.ToBase64String(value)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }
}
