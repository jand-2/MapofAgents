namespace MapofAgents.Core;

public sealed record MentionCatalogContext(
    string CacheKey,
    string? Cwd,
    bool IncludeLocalFiles,
    AppServerEndpoint? Endpoint);

public sealed class MentionCatalogChangedEventArgs(string cacheKey) : EventArgs
{
    public string CacheKey { get; } = cacheKey;
}

/// <summary>
/// Owns mention-catalog caching and refresh lifetimes across composer surfaces.
/// Concurrent requests for the same context share one refresh, and disposal
/// cancels file scans and remote catalog requests.
/// </summary>
public sealed class MentionCatalogSession : IDisposable
{
    private readonly object _gate = new();
    private readonly Dictionary<string, IReadOnlyList<MentionCatalogCandidate>> _catalogs =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, RefreshOperation> _refreshes =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _activeContextsByConsumer =
        new(StringComparer.Ordinal);
    private readonly CancellationTokenSource _lifetime = new();
    private readonly Func<MentionCatalogContext, CancellationToken, Task<IReadOnlyList<MentionCatalogCandidate>>> _loader;
    private bool _isDisposed;

    public MentionCatalogSession(
        Func<MentionCatalogContext, CancellationToken, Task<IReadOnlyList<MentionCatalogCandidate>>>? loader = null)
    {
        _loader = loader ?? LoadCatalogAsync;
    }

    public event EventHandler<MentionCatalogChangedEventArgs>? CatalogChanged;

    public IReadOnlyList<MentionCatalogCandidate> Candidates(MentionCatalogContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        lock (_gate)
        {
            return _catalogs.TryGetValue(context.CacheKey, out var candidates)
                ? candidates
                : [MentionCatalog.WorkflowBridgeCandidate];
        }
    }

    public Task EnsureRefreshedAsync(MentionCatalogContext context)
    {
        ArgumentNullException.ThrowIfNull(context);

        RefreshOperation operation;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_isDisposed, this);
            if (_catalogs.ContainsKey(context.CacheKey))
            {
                return Task.CompletedTask;
            }

            if (_refreshes.TryGetValue(context.CacheKey, out var existing))
            {
                return existing.Completion.Task;
            }

            operation = new RefreshOperation(
                CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token),
                new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously));
            _refreshes[context.CacheKey] = operation;
        }

        _ = RunRefreshAsync(context, operation);
        return operation.Completion.Task;
    }

    public void ActivateContext(string consumerId, MentionCatalogContext? context)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(consumerId);

        RefreshOperation? abandonedRefresh = null;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_isDisposed, this);
            _activeContextsByConsumer.TryGetValue(consumerId, out var previousCacheKey);
            if (context is null)
            {
                _activeContextsByConsumer.Remove(consumerId);
            }
            else
            {
                _activeContextsByConsumer[consumerId] = context.CacheKey;
            }

            if (!string.IsNullOrWhiteSpace(previousCacheKey) &&
                !string.Equals(previousCacheKey, context?.CacheKey, StringComparison.OrdinalIgnoreCase) &&
                !_activeContextsByConsumer.Values.Contains(previousCacheKey, StringComparer.OrdinalIgnoreCase) &&
                _refreshes.Remove(previousCacheKey, out var refresh))
            {
                abandonedRefresh = refresh;
            }
        }

        SafeCancel(abandonedRefresh?.Cancellation);
    }

    public void Invalidate(string cacheKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(cacheKey);

        RefreshOperation? operation = null;
        lock (_gate)
        {
            _catalogs.Remove(cacheKey);
            if (_refreshes.Remove(cacheKey, out var active))
            {
                operation = active;
            }
        }

        SafeCancel(operation?.Cancellation);
    }

    public void Dispose()
    {
        List<RefreshOperation> operations;
        lock (_gate)
        {
            if (_isDisposed)
            {
                return;
            }

            _isDisposed = true;
            operations = _refreshes.Values.ToList();
            _refreshes.Clear();
            _catalogs.Clear();
            _activeContextsByConsumer.Clear();
            CatalogChanged = null;
        }

        _lifetime.Cancel();
        foreach (var operation in operations)
        {
            SafeCancel(operation.Cancellation);
        }
        _lifetime.Dispose();
    }

    private async Task RunRefreshAsync(MentionCatalogContext context, RefreshOperation operation)
    {
        var changed = false;
        var canceled = false;
        var cancellationToken = operation.Cancellation.Token;
        try
        {
            var loaded = await _loader(context, cancellationToken).ConfigureAwait(false);
            var candidates = MentionCatalog.UniqueCandidates(
                    new[] { MentionCatalog.WorkflowBridgeCandidate }.Concat(loaded))
                .OrderBy(candidate => MentionCatalog.SortPriority(candidate.Kind))
                .ThenBy(candidate => candidate.Title, StringComparer.OrdinalIgnoreCase)
                .ToList();
            lock (_gate)
            {
                if (!_isDisposed && IsCurrentOperation(context.CacheKey, operation))
                {
                    _catalogs[context.CacheKey] = candidates;
                    changed = true;
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
            canceled = true;
        }
        catch
        {
            lock (_gate)
            {
                if (!_isDisposed && IsCurrentOperation(context.CacheKey, operation))
                {
                    _catalogs[context.CacheKey] = [MentionCatalog.WorkflowBridgeCandidate];
                    changed = true;
                }
            }
        }
        finally
        {
            lock (_gate)
            {
                if (IsCurrentOperation(context.CacheKey, operation))
                {
                    _refreshes.Remove(context.CacheKey);
                }
            }

            operation.Cancellation.Dispose();
        }

        if (changed)
        {
            try
            {
                CatalogChanged?.Invoke(this, new MentionCatalogChangedEventArgs(context.CacheKey));
            }
            catch
            {
                // Catalog consumers must not break refresh task completion.
            }
        }

        if (canceled)
        {
            operation.Completion.TrySetCanceled(cancellationToken);
        }
        else
        {
            operation.Completion.TrySetResult();
        }
    }

    private bool IsCurrentOperation(string cacheKey, RefreshOperation operation)
    {
        return _refreshes.TryGetValue(cacheKey, out var current) && ReferenceEquals(current, operation);
    }

    private static void SafeCancel(CancellationTokenSource? cancellation)
    {
        try
        {
            cancellation?.Cancel();
        }
        catch (ObjectDisposedException)
        {
            // The refresh completed between state removal and cancellation.
        }
    }

    private static async Task<IReadOnlyList<MentionCatalogCandidate>> LoadCatalogAsync(
        MentionCatalogContext context,
        CancellationToken cancellationToken)
    {
        var candidates = new List<MentionCatalogCandidate>();
        if (context.IncludeLocalFiles && !string.IsNullOrWhiteSpace(context.Cwd))
        {
            var cwd = context.Cwd;
            candidates.AddRange(await Task.Run(
                () => MentionCatalog.LocalFileMentionCandidates(cwd, cancellationToken: cancellationToken),
                cancellationToken).ConfigureAwait(false));
        }

        if (context.Endpoint is not null)
        {
            candidates.AddRange(await new AppServerClient()
                .ListMentionCandidatesAsync(
                    context.Endpoint,
                    context.Cwd,
                    cancellationToken: cancellationToken)
                .ConfigureAwait(false));
        }

        return candidates;
    }

    private sealed record RefreshOperation(
        CancellationTokenSource Cancellation,
        TaskCompletionSource Completion);
}
