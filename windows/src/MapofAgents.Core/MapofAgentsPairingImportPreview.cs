namespace MapofAgents.Core;

public sealed record MapofAgentsPairingEndpointImportPreview(
    string Id,
    string Kind,
    string Label,
    string Url,
    bool IsPreferred);

public sealed record MapofAgentsPairingImportPreview(
    string HostName,
    DateTimeOffset? ExpiresAt,
    IReadOnlyList<MapofAgentsPairingEndpointImportPreview> Endpoints)
{
    public MapofAgentsPairingEndpointImportPreview? PreferredEndpoint =>
        Endpoints.FirstOrDefault(endpoint => endpoint.IsPreferred);

    public static MapofAgentsPairingImportPreview FromPayload(MapofAgentsPairingPayload payload)
    {
        payload.ValidateForImport();
        var endpoints = payload.PreferredEndpoints();
        if (endpoints.Count == 0)
        {
            throw new MapofAgentsPairingException(
                "No pairing endpoint satisfies the Windows App Server security requirements.");
        }

        var preferredID = endpoints[0].Id;
        return new MapofAgentsPairingImportPreview(
            string.IsNullOrWhiteSpace(payload.Name) ? "Paired Codex App Server" : payload.Name.Trim(),
            payload.ExpiresAt,
            endpoints
                .Take(4)
                .Select(endpoint => new MapofAgentsPairingEndpointImportPreview(
                    endpoint.Id,
                    endpoint.Kind,
                    string.IsNullOrWhiteSpace(endpoint.Label) ? EndpointKindLabel(endpoint.Kind) : endpoint.Label,
                    endpoint.Url,
                    string.Equals(endpoint.Id, preferredID, StringComparison.Ordinal)))
                .ToList());
    }

    private static string EndpointKindLabel(string? kind)
    {
        return kind?.Trim().ToLowerInvariant() switch
        {
            "tailnet" => "Tailnet",
            "local" => "Local",
            "manual" => "Manual",
            _ => "Endpoint"
        };
    }
}
