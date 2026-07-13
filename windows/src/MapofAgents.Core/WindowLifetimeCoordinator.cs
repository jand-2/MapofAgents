namespace MapofAgents.Core;

public readonly record struct WindowLifetimeLease(
    long Generation,
    CancellationToken CancellationToken);

/// <summary>
/// Coordinates a window's background producers and late UI callbacks. A
/// producer is registered before its delegate can start, so shutdown can
/// cancel and await every accepted producer before UI-owned stores are
/// disposed.
/// </summary>
public sealed class WindowLifetimeCoordinator : IDisposable
{
    private readonly object _gate = new();
    private readonly CancellationTokenSource _lifetimeCancellation = new();
    private readonly HashSet<Task> _producerTasks = [];
    private readonly List<Exception> _producerFaults = [];
    private Task<IReadOnlyList<Exception>>? _shutdownTask;
    private long _generation = 1;
    private bool _isShuttingDown;
    private bool _isDisposed;

    public bool IsShuttingDown
    {
        get
        {
            lock (_gate)
            {
                return _isShuttingDown;
            }
        }
    }

    public bool TryCapture(out WindowLifetimeLease lease)
    {
        lock (_gate)
        {
            if (_isShuttingDown || _isDisposed)
            {
                lease = default;
                return false;
            }

            lease = new WindowLifetimeLease(_generation, _lifetimeCancellation.Token);
            return true;
        }
    }

    public bool IsCurrent(WindowLifetimeLease lease)
    {
        lock (_gate)
        {
            return !_isShuttingDown &&
                !_isDisposed &&
                lease.Generation == _generation &&
                !lease.CancellationToken.IsCancellationRequested;
        }
    }

    public bool TryRunTracked(
        Func<WindowLifetimeLease, Task> producer,
        out Task task)
    {
        ArgumentNullException.ThrowIfNull(producer);

        TaskCompletionSource completion;
        WindowLifetimeLease lease;
        lock (_gate)
        {
            if (_isShuttingDown || _isDisposed)
            {
                task = Task.CompletedTask;
                return false;
            }

            lease = new WindowLifetimeLease(_generation, _lifetimeCancellation.Token);
            completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            task = completion.Task;
            _producerTasks.Add(task);
        }

        _ = ExecuteProducerAsync(producer, lease, completion);
        return true;
    }

    public bool TryDispatch(
        WindowLifetimeLease lease,
        Func<Action, bool> dispatcher,
        Action callback)
    {
        ArgumentNullException.ThrowIfNull(dispatcher);
        ArgumentNullException.ThrowIfNull(callback);
        if (!IsCurrent(lease))
        {
            return false;
        }

        return dispatcher(() =>
        {
            if (IsCurrent(lease))
            {
                callback();
            }
        });
    }

    public Task<IReadOnlyList<Exception>> ShutdownAsync()
    {
        TaskCompletionSource<IReadOnlyList<Exception>> completion;
        Task[] producers;
        lock (_gate)
        {
            if (_shutdownTask is not null)
            {
                return _shutdownTask;
            }

            _isShuttingDown = true;
            _generation += 1;
            producers = _producerTasks.ToArray();
            completion = new TaskCompletionSource<IReadOnlyList<Exception>>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            _shutdownTask = completion.Task;
        }

        try
        {
            _lifetimeCancellation.Cancel();
        }
        catch (ObjectDisposedException)
        {
            // Disposal raced an idempotent shutdown request.
        }

        _ = CompleteShutdownAsync(producers, completion);
        return completion.Task;
    }

    public void Dispose()
    {
        Task<IReadOnlyList<Exception>> shutdown;
        lock (_gate)
        {
            if (_isDisposed)
            {
                return;
            }

            _isDisposed = true;
        }

        shutdown = ShutdownAsync();
        if (shutdown.IsCompleted)
        {
            _lifetimeCancellation.Dispose();
            return;
        }

        _ = shutdown.ContinueWith(
            _ => _lifetimeCancellation.Dispose(),
            CancellationToken.None,
            TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }

    private async Task ExecuteProducerAsync(
        Func<WindowLifetimeLease, Task> producer,
        WindowLifetimeLease lease,
        TaskCompletionSource completion)
    {
        try
        {
            await producer(lease).ConfigureAwait(false);
            completion.TrySetResult();
        }
        catch (OperationCanceledException) when (lease.CancellationToken.IsCancellationRequested)
        {
            completion.TrySetCanceled(lease.CancellationToken);
        }
        catch (Exception exception)
        {
            lock (_gate)
            {
                _producerFaults.Add(exception);
            }

            completion.TrySetException(exception);
        }
        finally
        {
            _ = completion.Task.Exception;
            lock (_gate)
            {
                _producerTasks.Remove(completion.Task);
            }
        }
    }

    private async Task CompleteShutdownAsync(
        IReadOnlyList<Task> producers,
        TaskCompletionSource<IReadOnlyList<Exception>> completion)
    {
        foreach (var producer in producers)
        {
            try
            {
                await producer.ConfigureAwait(false);
            }
            catch
            {
                // ExecuteProducerAsync records faults; cancellation is expected.
            }
        }

        IReadOnlyList<Exception> faults;
        lock (_gate)
        {
            faults = _producerFaults.ToArray();
        }

        completion.TrySetResult(faults);
    }
}
