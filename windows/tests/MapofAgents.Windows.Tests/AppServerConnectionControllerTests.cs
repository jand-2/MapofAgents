using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AppServerConnectionControllerTests
{
    [TestMethod]
    public async Task InvalidEndpointNeverStartsHandshake()
    {
        var calls = 0;
        var controller = new AppServerConnectionController((_, _) =>
        {
            calls += 1;
            return Task.FromResult(InitializeResult());
        });

        var outcome = await controller.ConnectAsync(new AppServerConnectionRequest(
            "not a websocket",
            null,
            null));

        Assert.AreEqual(AppServerConnectionOutcomeKind.Invalid, outcome.Kind);
        Assert.AreEqual("Enter an absolute ws:// or wss:// endpoint.", outcome.Message);
        Assert.AreEqual(0, calls);
    }

    [TestMethod]
    public async Task ValidRequestIsNormalizedAndReturnsInitializeResult()
    {
        AppServerEndpoint? receivedEndpoint = null;
        var controller = new AppServerConnectionController((endpoint, _) =>
        {
            receivedEndpoint = endpoint;
            return Task.FromResult(InitializeResult());
        });

        var outcome = await controller.ConnectAsync(new AppServerConnectionRequest(
            " wss://example-host.local/app-server ",
            " Remote Codex ",
            " example-token "));

        Assert.IsTrue(outcome.IsConnected);
        Assert.AreEqual("Remote Codex", receivedEndpoint!.Name);
        Assert.AreEqual("wss://example-host.local/app-server", receivedEndpoint.Url.ToString().TrimEnd('/'));
        Assert.AreEqual("example-token", receivedEndpoint.BearerToken);
        Assert.AreEqual("example-host", outcome.InitializeResult!.HostName);
    }

    [TestMethod]
    public async Task ConcurrentHandlerInvocationsShareOneHandshake()
    {
        var release = new TaskCompletionSource<AppServerInitializeResult>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        var controller = new AppServerConnectionController((_, _) =>
        {
            Interlocked.Increment(ref calls);
            return release.Task;
        });
        var request = new AppServerConnectionRequest("ws://127.0.0.1:18945", null, null);

        var first = controller.ConnectAsync(request);
        var second = controller.ConnectAsync(request);

        Assert.AreSame(first, second);
        Assert.AreEqual(1, calls);
        release.SetResult(InitializeResult());
        await first;
    }

    [TestMethod]
    public async Task CancellationPropagatesInsteadOfBecomingConnectionFailure()
    {
        var controller = new AppServerConnectionController(async (_, cancellationToken) =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return InitializeResult();
        });
        using var cancellation = new CancellationTokenSource();
        var operation = controller.ConnectAsync(
            new AppServerConnectionRequest("ws://127.0.0.1:18945", null, null),
            cancellation.Token);

        cancellation.Cancel();

        await Assert.ThrowsExceptionAsync<TaskCanceledException>(async () => await operation);
    }

    [TestMethod]
    public async Task HandshakeFailureBecomesPresentationSafeOutcome()
    {
        var controller = new AppServerConnectionController((_, _) =>
            throw new IOException("host unavailable"));

        var outcome = await controller.ConnectAsync(
            new AppServerConnectionRequest("ws://127.0.0.1:18945", null, null));

        Assert.AreEqual(AppServerConnectionOutcomeKind.Failed, outcome.Kind);
        Assert.AreEqual("host unavailable", outcome.Message);
    }

    [TestMethod]
    public async Task WindowShutdownCancelsRealConnectionFlowAndRejectsLateApply()
    {
        using var coordinator = new WindowLifetimeCoordinator();
        var handshakeStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var controller = new AppServerConnectionController(async (_, cancellationToken) =>
        {
            handshakeStarted.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return InitializeResult();
        });
        var appliedConnections = 0;

        Assert.IsTrue(coordinator.TryRunTracked(
            async lease =>
            {
                var outcome = await controller.ConnectAsync(
                    new AppServerConnectionRequest("ws://127.0.0.1:18945", null, null),
                    lease.CancellationToken);
                if (coordinator.IsCurrent(lease) && outcome.IsConnected)
                {
                    appliedConnections += 1;
                }
            },
            out var handler));

        await handshakeStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
        var faults = await coordinator.ShutdownAsync();

        Assert.IsTrue(handler.IsCanceled);
        Assert.AreEqual(0, appliedConnections);
        Assert.AreEqual(0, faults.Count);
    }

    private static AppServerInitializeResult InitializeResult()
    {
        return new AppServerInitializeResult(
            "example-host",
            HostPlatforms.Windows,
            null,
            "{}");
    }
}
