using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptSessionStoreTests
{
    [TestMethod]
    public void AllowsOnlyOneLoadPerThreadAndReleasesItWhenLeaseEnds()
    {
        using var store = new TranscriptSessionStore();

        Assert.IsTrue(store.TryBeginLoad(
            "thread-1",
            appendOlder: false,
            hasCachedTranscript: false,
            Timeout.InfiniteTimeSpan,
            out var first));
        Assert.IsFalse(store.TryBeginLoad(
            "thread-1",
            appendOlder: false,
            hasCachedTranscript: false,
            Timeout.InfiniteTimeSpan,
            out var duplicate));
        Assert.IsNull(duplicate);
        Assert.AreEqual(TranscriptLoadPhase.ConnectingHost, store.Snapshot("thread-1").LoadPhase);

        first!.Dispose();

        Assert.IsTrue(store.TryBeginLoad(
            "thread-1",
            appendOlder: false,
            hasCachedTranscript: true,
            Timeout.InfiniteTimeSpan,
            out var next));
        Assert.AreEqual(TranscriptLoadPhase.Refreshing, store.Snapshot("thread-1").LoadPhase);
        next!.Dispose();
    }

    [TestMethod]
    public void CompletedLoadPublishesCursorAndAllowsOneOlderLoad()
    {
        using var store = new TranscriptSessionStore();
        Assert.IsTrue(store.TryBeginLoad(
            "thread-1",
            appendOlder: false,
            hasCachedTranscript: false,
            Timeout.InfiniteTimeSpan,
            out var initial));
        initial!.SetPhase(TranscriptLoadPhase.HydratingArtifacts);
        initial.Complete("cursor-2");
        initial.Dispose();

        var completed = store.Snapshot("thread-1");
        Assert.IsTrue(completed.HasLoaded);
        Assert.IsTrue(completed.HasAutoLoadAttempted);
        Assert.IsTrue(completed.HasOlderPage);
        Assert.AreEqual("cursor-2", completed.NextCursor);

        Assert.IsTrue(store.TryBeginLoad(
            "thread-1",
            appendOlder: true,
            hasCachedTranscript: true,
            Timeout.InfiniteTimeSpan,
            out var older));
        Assert.AreEqual("cursor-2", older!.StartingCursor);
        Assert.IsTrue(store.Snapshot("thread-1").IsLoadingOlder);
        older.Complete(null);
        older.Dispose();

        Assert.IsFalse(store.Snapshot("thread-1").HasOlderPage);
        Assert.IsFalse(store.TryBeginLoad(
            "thread-1",
            appendOlder: true,
            hasCachedTranscript: true,
            Timeout.InfiniteTimeSpan,
            out _));
    }

    [TestMethod]
    public void RemovingThreadCancelsItsActiveLoad()
    {
        using var store = new TranscriptSessionStore();
        Assert.IsTrue(store.TryBeginLoad(
            "thread-1",
            appendOlder: false,
            hasCachedTranscript: false,
            Timeout.InfiniteTimeSpan,
            out var load));

        store.Remove("thread-1");

        Assert.IsTrue(load!.CancellationToken.IsCancellationRequested);
        Assert.IsFalse(store.Snapshot("thread-1").IsLoading);
        load.Dispose();
    }

    [TestMethod]
    public void DisposingStoreCancelsEveryActiveThreadLoad()
    {
        var store = new TranscriptSessionStore();
        Assert.IsTrue(store.TryBeginLoad(
            "thread-1",
            appendOlder: false,
            hasCachedTranscript: false,
            Timeout.InfiniteTimeSpan,
            out var first));
        Assert.IsTrue(store.TryBeginLoad(
            "thread-2",
            appendOlder: false,
            hasCachedTranscript: false,
            Timeout.InfiniteTimeSpan,
            out var second));

        store.Dispose();

        Assert.IsTrue(first!.CancellationToken.IsCancellationRequested);
        Assert.IsTrue(second!.CancellationToken.IsCancellationRequested);
        first.Dispose();
        second.Dispose();
    }

    [TestMethod]
    public void AutoLoadReservationPreventsDuplicateQueueing()
    {
        using var store = new TranscriptSessionStore();

        Assert.IsTrue(store.TryReserveAutoLoad("thread-1"));
        Assert.IsFalse(store.TryReserveAutoLoad("thread-1"));
    }

    [TestMethod]
    public void FailureKeepsErrorButEndsLoadingState()
    {
        using var store = new TranscriptSessionStore();
        Assert.IsTrue(store.TryBeginLoad(
            "thread-1",
            appendOlder: false,
            hasCachedTranscript: false,
            Timeout.InfiniteTimeSpan,
            out var load));

        load!.Fail(" host unavailable ");

        var snapshot = store.Snapshot("thread-1");
        Assert.IsFalse(snapshot.IsLoading);
        Assert.AreEqual("host unavailable", snapshot.Error);
        load.Dispose();
    }
}
