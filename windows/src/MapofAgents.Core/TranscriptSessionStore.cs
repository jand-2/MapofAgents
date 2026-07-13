namespace MapofAgents.Core;

public readonly record struct TranscriptSessionSnapshot(
    bool IsLoading,
    bool IsLoadingOlder,
    bool HasLoaded,
    bool HasAutoLoadAttempted,
    string? NextCursor,
    string? Error,
    TranscriptLoadPhase LoadPhase)
{
    public bool HasOlderPage => !string.IsNullOrWhiteSpace(NextCursor);

    public TranscriptLoadPhase EffectiveLoadPhase(bool hasCachedTranscript)
    {
        return LoadPhase == TranscriptLoadPhase.Idle
            ? TranscriptLoadPhasePresentation.InitialPhase(IsLoadingOlder, hasCachedTranscript)
            : LoadPhase;
    }
}

/// <summary>
/// Owns the lifecycle of transcript loads independently of any UI surface.
/// A thread can have only one active load, and removing or disposing the store
/// cancels the corresponding operation.
/// </summary>
public sealed class TranscriptSessionStore : IDisposable
{
    private readonly object _gate = new();
    private readonly Dictionary<string, SessionState> _sessions = new(StringComparer.Ordinal);
    private bool _isDisposed;

    public TranscriptSessionSnapshot Snapshot(string threadId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(threadId);

        lock (_gate)
        {
            return _sessions.TryGetValue(threadId, out var state)
                ? state.Snapshot()
                : default;
        }
    }

    public bool TryBeginLoad(
        string threadId,
        bool appendOlder,
        bool hasCachedTranscript,
        TimeSpan timeout,
        out TranscriptLoadLease? lease)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(threadId);
        if (timeout != Timeout.InfiniteTimeSpan && timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout), "The transcript timeout must be positive or infinite.");
        }

        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_isDisposed, this);
            var state = GetOrCreateState(threadId);
            if (state.ActiveCancellation is not null ||
                (appendOlder && string.IsNullOrWhiteSpace(state.NextCursor)))
            {
                lease = null;
                return false;
            }

            var cancellation = new CancellationTokenSource();
            if (timeout != Timeout.InfiniteTimeSpan)
            {
                cancellation.CancelAfter(timeout);
            }

            state.Generation += 1;
            state.ActiveCancellation = cancellation;
            state.IsLoadingOlder = appendOlder;
            state.Error = null;
            state.LoadPhase = TranscriptLoadPhasePresentation.InitialPhase(
                appendOlder,
                hasCachedTranscript);
            lease = new TranscriptLoadLease(
                this,
                threadId,
                state.Generation,
                appendOlder ? state.NextCursor : null,
                cancellation.Token);
            return true;
        }
    }

    public bool TryReserveAutoLoad(string threadId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(threadId);

        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_isDisposed, this);
            var state = GetOrCreateState(threadId);
            if (state.HasAutoLoadAttempted || state.HasLoaded || state.ActiveCancellation is not null)
            {
                return false;
            }

            state.HasAutoLoadAttempted = true;
            return true;
        }
    }

    public void ClearError(string threadId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(threadId);

        lock (_gate)
        {
            if (_sessions.TryGetValue(threadId, out var state))
            {
                state.Error = null;
            }
        }
    }

    public void SetError(string threadId, string message)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(threadId);
        ArgumentException.ThrowIfNullOrWhiteSpace(message);

        CancellationTokenSource? cancellation;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_isDisposed, this);
            var state = GetOrCreateState(threadId);
            cancellation = EndActiveLoad(state);
            state.Error = message.Trim();
        }

        CancelAndDispose(cancellation);
    }

    public void Remove(string threadId)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(threadId);

        CancellationTokenSource? cancellation = null;
        lock (_gate)
        {
            if (_sessions.Remove(threadId, out var state))
            {
                cancellation = state.ActiveCancellation;
                state.ActiveCancellation = null;
            }
        }

        CancelAndDispose(cancellation);
    }

    public void Dispose()
    {
        List<CancellationTokenSource> cancellations;
        lock (_gate)
        {
            if (_isDisposed)
            {
                return;
            }

            _isDisposed = true;
            cancellations = _sessions.Values
                .Select(state => state.ActiveCancellation)
                .OfType<CancellationTokenSource>()
                .ToList();
            _sessions.Clear();
        }

        foreach (var cancellation in cancellations)
        {
            CancelAndDispose(cancellation);
        }
    }

    internal void SetLoadPhase(string threadId, long generation, TranscriptLoadPhase phase)
    {
        lock (_gate)
        {
            if (TryGetActiveState(threadId, generation, out var state))
            {
                state.LoadPhase = phase;
            }
        }
    }

    internal void Complete(string threadId, long generation, string? nextCursor)
    {
        lock (_gate)
        {
            if (!TryGetActiveState(threadId, generation, out var state))
            {
                return;
            }

            state.NextCursor = string.IsNullOrWhiteSpace(nextCursor) ? null : nextCursor;
            state.HasLoaded = true;
            state.HasAutoLoadAttempted = true;
            state.Error = null;
        }
    }

    internal void Fail(string threadId, long generation, string message)
    {
        CancellationTokenSource? cancellation = null;
        lock (_gate)
        {
            if (!TryGetActiveState(threadId, generation, out var state))
            {
                return;
            }

            state.Error = string.IsNullOrWhiteSpace(message)
                ? "Transcript loading failed."
                : message.Trim();
            cancellation = EndActiveLoad(state);
        }

        cancellation?.Dispose();
    }

    internal void End(string threadId, long generation)
    {
        CancellationTokenSource? cancellation = null;
        lock (_gate)
        {
            if (TryGetActiveState(threadId, generation, out var state))
            {
                cancellation = EndActiveLoad(state);
            }
        }

        cancellation?.Dispose();
    }

    private SessionState GetOrCreateState(string threadId)
    {
        if (!_sessions.TryGetValue(threadId, out var state))
        {
            state = new SessionState();
            _sessions[threadId] = state;
        }

        return state;
    }

    private bool TryGetActiveState(string threadId, long generation, out SessionState state)
    {
        return _sessions.TryGetValue(threadId, out state!) &&
            state.Generation == generation &&
            state.ActiveCancellation is not null;
    }

    private static CancellationTokenSource? EndActiveLoad(SessionState state)
    {
        var cancellation = state.ActiveCancellation;
        state.ActiveCancellation = null;
        state.IsLoadingOlder = false;
        state.LoadPhase = TranscriptLoadPhase.Idle;
        return cancellation;
    }

    private static void CancelAndDispose(CancellationTokenSource? cancellation)
    {
        if (cancellation is null)
        {
            return;
        }

        try
        {
            cancellation.Cancel();
        }
        catch (ObjectDisposedException)
        {
            // A lease may have completed concurrently.
        }
        finally
        {
            cancellation.Dispose();
        }
    }

    private sealed class SessionState
    {
        public long Generation { get; set; }
        public CancellationTokenSource? ActiveCancellation { get; set; }
        public bool IsLoadingOlder { get; set; }
        public bool HasLoaded { get; set; }
        public bool HasAutoLoadAttempted { get; set; }
        public string? NextCursor { get; set; }
        public string? Error { get; set; }
        public TranscriptLoadPhase LoadPhase { get; set; }

        public TranscriptSessionSnapshot Snapshot()
        {
            return new TranscriptSessionSnapshot(
                ActiveCancellation is not null,
                IsLoadingOlder,
                HasLoaded,
                HasAutoLoadAttempted,
                NextCursor,
                Error,
                LoadPhase);
        }
    }
}

public sealed class TranscriptLoadLease : IDisposable
{
    private TranscriptSessionStore? _owner;
    private readonly string _threadId;
    private readonly long _generation;

    internal TranscriptLoadLease(
        TranscriptSessionStore owner,
        string threadId,
        long generation,
        string? startingCursor,
        CancellationToken cancellationToken)
    {
        _owner = owner;
        _threadId = threadId;
        _generation = generation;
        StartingCursor = startingCursor;
        CancellationToken = cancellationToken;
    }

    public string? StartingCursor { get; }

    public CancellationToken CancellationToken { get; }

    public void SetPhase(TranscriptLoadPhase phase)
    {
        _owner?.SetLoadPhase(_threadId, _generation, phase);
    }

    public void Complete(string? nextCursor)
    {
        _owner?.Complete(_threadId, _generation, nextCursor);
    }

    public void Fail(string message)
    {
        _owner?.Fail(_threadId, _generation, message);
    }

    public void Dispose()
    {
        var owner = Interlocked.Exchange(ref _owner, null);
        owner?.End(_threadId, _generation);
    }
}
