using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class WindowLifetimeCoordinatorTests
{
    [TestMethod]
    public async Task ShutdownCancelsAndAwaitsEveryAcceptedProducer()
    {
        using var coordinator = new WindowLifetimeCoordinator();
        var canceled = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Assert.IsTrue(coordinator.TryRunTracked(
            async lease =>
            {
                try
                {
                    await Task.Delay(Timeout.InfiniteTimeSpan, lease.CancellationToken);
                }
                finally
                {
                    canceled.TrySetResult();
                }
            },
            out var producer));

        var faults = await coordinator.ShutdownAsync();

        await canceled.Task.WaitAsync(TimeSpan.FromSeconds(1));
        Assert.IsTrue(producer.IsCanceled);
        Assert.AreEqual(0, faults.Count);
        Assert.IsTrue(coordinator.IsShuttingDown);
    }

    [TestMethod]
    public async Task CallbackQueuedBeforeShutdownIsRejectedWhenDispatcherRunsLate()
    {
        using var coordinator = new WindowLifetimeCoordinator();
        Assert.IsTrue(coordinator.TryCapture(out var lease));
        Action? queued = null;
        var callbackCount = 0;

        var accepted = coordinator.TryDispatch(
            lease,
            callback =>
            {
                queued = callback;
                return true;
            },
            () => callbackCount += 1);

        Assert.IsTrue(accepted);
        await coordinator.ShutdownAsync();
        queued!();
        Assert.AreEqual(0, callbackCount);
    }

    [TestMethod]
    public void CurrentCallbackRunsThroughFakeDispatcher()
    {
        using var coordinator = new WindowLifetimeCoordinator();
        Assert.IsTrue(coordinator.TryCapture(out var lease));
        var callbackCount = 0;

        var accepted = coordinator.TryDispatch(
            lease,
            callback =>
            {
                callback();
                return true;
            },
            () => callbackCount += 1);

        Assert.IsTrue(accepted);
        Assert.AreEqual(1, callbackCount);
    }

    [TestMethod]
    public async Task ShutdownRejectsNewProducersAndReportsObservedFaults()
    {
        using var coordinator = new WindowLifetimeCoordinator();
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        Assert.IsTrue(coordinator.TryRunTracked(
            async _ =>
            {
                await release.Task;
                throw new InvalidOperationException("producer failed");
            },
            out var producer));

        var shutdown = coordinator.ShutdownAsync();
        Assert.IsFalse(coordinator.TryRunTracked(_ => Task.CompletedTask, out var rejected));
        release.TrySetResult();
        var faults = await shutdown;

        await Assert.ThrowsExceptionAsync<InvalidOperationException>(async () => await producer);
        Assert.AreEqual(1, faults.Count);
        Assert.AreEqual("producer failed", faults[0].Message);
        Assert.AreSame(Task.CompletedTask, rejected);
    }
}
