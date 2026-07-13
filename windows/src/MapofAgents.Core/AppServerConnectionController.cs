namespace MapofAgents.Core;

public sealed record AppServerConnectionRequest(
    string EndpointText,
    string? EndpointName,
    string? BearerToken,
    AppServerEndpointTrust Trust = AppServerEndpointTrust.Standard);

public enum AppServerConnectionOutcomeKind
{
    Invalid,
    Connected,
    Failed
}

public sealed record AppServerConnectionOutcome(
    AppServerConnectionOutcomeKind Kind,
    string Message,
    AppServerEndpoint? Endpoint = null,
    AppServerInitializeResult? InitializeResult = null)
{
    public bool IsConnected => Kind == AppServerConnectionOutcomeKind.Connected;
}

public sealed record AppServerConnectionPreparation(
    AppServerEndpoint? Endpoint,
    string? ErrorMessage)
{
    public bool IsValid => Endpoint is not null && string.IsNullOrWhiteSpace(ErrorMessage);
}

/// <summary>
/// Owns validation and the single-flight App Server initialize handshake.
/// Presentation code supplies a request and applies the resulting connection
/// to its graph only while its own lifetime lease remains current.
/// </summary>
public sealed class AppServerConnectionController
{
    private const string DefaultEndpointName = "Codex App Server";
    private readonly object _gate = new();
    private readonly Func<AppServerEndpoint, CancellationToken, Task<AppServerInitializeResult>> _initialize;
    private Task<AppServerConnectionOutcome>? _activeConnection;

    public AppServerConnectionController(
        Func<AppServerEndpoint, CancellationToken, Task<AppServerInitializeResult>>? initialize = null)
    {
        _initialize = initialize ?? ((endpoint, cancellationToken) =>
            new AppServerClient().InitializeAsync(endpoint, cancellationToken));
    }

    public Task<AppServerConnectionOutcome> ConnectAsync(
        AppServerConnectionRequest request,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        return ConnectAsync(Prepare(request), cancellationToken);
    }

    public AppServerConnectionPreparation Prepare(AppServerConnectionRequest request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var endpointText = request.EndpointText?.Trim() ?? "";
        if (!Uri.TryCreate(endpointText, UriKind.Absolute, out var endpointUri))
        {
            return new AppServerConnectionPreparation(
                null,
                "Enter an absolute ws:// or wss:// endpoint.");
        }

        var bearerToken = string.IsNullOrWhiteSpace(request.BearerToken)
            ? null
            : request.BearerToken.Trim();
        var validation = AppServerEndpointValidator.Validate(endpointUri, bearerToken, request.Trust);
        if (!validation.IsValid)
        {
            return new AppServerConnectionPreparation(
                null,
                validation.Message ?? "Endpoint validation failed.");
        }

        var endpointName = string.IsNullOrWhiteSpace(request.EndpointName)
            ? DefaultEndpointName
            : request.EndpointName.Trim();
        return new AppServerConnectionPreparation(
            new AppServerEndpoint(endpointName, endpointUri, bearerToken, request.Trust),
            null);
    }

    public Task<AppServerConnectionOutcome> ConnectAsync(
        AppServerConnectionPreparation preparation,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(preparation);
        if (!preparation.IsValid)
        {
            return Task.FromResult(new AppServerConnectionOutcome(
                AppServerConnectionOutcomeKind.Invalid,
                preparation.ErrorMessage ?? "Endpoint validation failed."));
        }

        lock (_gate)
        {
            if (_activeConnection is { IsCompleted: false })
            {
                return _activeConnection;
            }

            _activeConnection = ConnectCoreAsync(preparation.Endpoint!, cancellationToken);
            return _activeConnection;
        }
    }

    private async Task<AppServerConnectionOutcome> ConnectCoreAsync(
        AppServerEndpoint endpoint,
        CancellationToken cancellationToken)
    {
        try
        {
            var initialize = await _initialize(endpoint, cancellationToken).ConfigureAwait(false);
            return new AppServerConnectionOutcome(
                AppServerConnectionOutcomeKind.Connected,
                $"Connected to {initialize.HostName}.",
                endpoint,
                initialize);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            return new AppServerConnectionOutcome(
                AppServerConnectionOutcomeKind.Failed,
                exception.Message,
                endpoint);
        }
    }
}
