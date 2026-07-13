using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MentionCatalogSessionTests
{
    [TestMethod]
    public async Task ConcurrentRequestsForContextShareOneRefresh()
    {
        var release = new TaskCompletionSource<IReadOnlyList<MentionCatalogCandidate>>(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var calls = 0;
        using var session = new MentionCatalogSession((_, _) =>
        {
            Interlocked.Increment(ref calls);
            return release.Task;
        });
        var context = Context("host|cwd");

        var first = session.EnsureRefreshedAsync(context);
        var second = session.EnsureRefreshedAsync(context);

        Assert.AreSame(first, second);
        Assert.AreEqual(1, calls);
        release.SetResult([Candidate("file:b", "@b"), Candidate("file:a", "@a")]);
        await first;
        CollectionAssert.AreEqual(
            new[] { "@a", "@b", "$mapofagents-workflow-bridge" },
            session.Candidates(context).Select(candidate => candidate.Title).ToArray());
    }

    [TestMethod]
    public async Task FailurePublishesSafeBridgeFallback()
    {
        using var session = new MentionCatalogSession((_, _) =>
            throw new InvalidOperationException("catalog unavailable"));
        var context = Context("host|failed");
        var changedKeys = new List<string>();
        session.CatalogChanged += (_, eventArgs) => changedKeys.Add(eventArgs.CacheKey);

        await session.EnsureRefreshedAsync(context);

        Assert.AreEqual(1, session.Candidates(context).Count);
        Assert.AreEqual(MentionCatalog.WorkflowBridgeCandidate, session.Candidates(context)[0]);
        CollectionAssert.AreEqual(new[] { context.CacheKey }, changedKeys);
    }

    [TestMethod]
    public async Task DisposingSessionCancelsActiveRefresh()
    {
        var cancellationObserved = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var session = new MentionCatalogSession(async (_, cancellationToken) =>
        {
            try
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
                return [];
            }
            finally
            {
                cancellationObserved.TrySetResult();
            }
        });
        var refresh = session.EnsureRefreshedAsync(Context("host|slow"));

        session.Dispose();

        await cancellationObserved.Task.WaitAsync(TimeSpan.FromSeconds(1));
        await Assert.ThrowsExceptionAsync<TaskCanceledException>(async () => await refresh);
    }

    [TestMethod]
    public async Task InvalidatingContextCancelsRefreshAndAllowsReplacement()
    {
        var firstStarted = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        var attempts = 0;
        using var session = new MentionCatalogSession(async (_, cancellationToken) =>
        {
            if (Interlocked.Increment(ref attempts) == 1)
            {
                firstStarted.SetResult();
                await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            }

            return [Candidate("file:ready", "@ready")];
        });
        var context = Context("host|replace");
        var first = session.EnsureRefreshedAsync(context);
        await firstStarted.Task;

        session.Invalidate(context.CacheKey);
        var replacement = session.EnsureRefreshedAsync(context);

        await Assert.ThrowsExceptionAsync<TaskCanceledException>(async () => await first);
        await replacement;
        Assert.IsTrue(session.Candidates(context).Any(candidate => candidate.Title == "@ready"));
    }

    [TestMethod]
    public async Task AbandonedConsumerContextCancelsScanUnlessAnotherConsumerUsesIt()
    {
        var started = new TaskCompletionSource(
            TaskCreationOptions.RunContinuationsAsynchronously);
        using var session = new MentionCatalogSession(async (_, cancellationToken) =>
        {
            started.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return [];
        });
        var context = Context("host|shared");
        session.ActivateContext("new-thread", context);
        session.ActivateContext("thread-popover", context);
        var refresh = session.EnsureRefreshedAsync(context);
        await started.Task;

        session.ActivateContext("new-thread", null);
        Assert.IsFalse(refresh.IsCanceled);
        session.ActivateContext("thread-popover", null);

        await Assert.ThrowsExceptionAsync<TaskCanceledException>(async () => await refresh);
    }

    [TestMethod]
    public void LocalFileScanHonorsPreCanceledToken()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        Assert.ThrowsException<OperationCanceledException>(() =>
            MentionCatalog.LocalFileMentionCandidates(
                Path.GetTempPath(),
                cancellationToken: cancellation.Token));
    }

    private static MentionCatalogContext Context(string key)
    {
        return new MentionCatalogContext(key, null, IncludeLocalFiles: false, Endpoint: null);
    }

    private static MentionCatalogCandidate Candidate(string id, string title)
    {
        return new MentionCatalogCandidate(id, MentionCatalog.KindFile, '@', title, title, title, title);
    }
}
