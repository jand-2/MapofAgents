using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxSummaryPresentationTests
{
    [TestMethod]
    public void ActiveModeShowsOnlyThreadCount()
    {
        var summary = ThreadInboxSummaryPresentation.Resolve("active", threadCount: 2, requestCount: 3);

        Assert.AreEqual("2 threads", summary.ThreadSummaryText);
        Assert.IsFalse(summary.ThreadSummaryText.Contains("visible", StringComparison.OrdinalIgnoreCase));
        Assert.IsTrue(summary.ShowThreadSummary);
        Assert.AreEqual("3 requests", summary.AttentionSummaryText);
        Assert.IsFalse(summary.ShowAttentionSection);
        Assert.IsFalse(summary.ShowEmptyState);
        Assert.AreEqual(11, summary.SummaryFontSize);
        Assert.AreEqual(ThreadInboxPresentation.TertiaryHex, summary.SummaryForegroundHex);
        Assert.AreEqual("Normal", summary.SummaryFontWeight);
        Assert.AreEqual(360, summary.AttentionRequestListMaxHeight);
        Assert.AreEqual(360, summary.ThreadListMaxHeight);
    }

    [TestMethod]
    public void NeedsYouModeSeparatesRequestsFromAttentionThreadCount()
    {
        var summary = ThreadInboxSummaryPresentation.Resolve("needsYou", threadCount: 1, requestCount: 2);

        Assert.AreEqual("1 thread with attention", summary.ThreadSummaryText);
        Assert.IsTrue(summary.ShowThreadSummary);
        Assert.AreEqual("2 requests", summary.AttentionSummaryText);
        Assert.IsTrue(summary.ShowAttentionSection);
        Assert.IsFalse(summary.ShowEmptyState);
        Assert.AreEqual(360, summary.AttentionRequestListMaxHeight);
        Assert.AreEqual(300, summary.ThreadListMaxHeight);
    }

    [TestMethod]
    public void NeedsYouModeWithRequestsOnlyHidesThreadSummary()
    {
        var summary = ThreadInboxSummaryPresentation.Resolve("needsYou", threadCount: 0, requestCount: 1);

        Assert.AreEqual("0 threads with attention", summary.ThreadSummaryText);
        Assert.IsFalse(summary.ShowThreadSummary);
        Assert.AreEqual("1 request", summary.AttentionSummaryText);
        Assert.IsTrue(summary.ShowAttentionSection);
        Assert.IsFalse(summary.ShowEmptyState);
        Assert.AreEqual(360, summary.AttentionRequestListMaxHeight);
        Assert.AreEqual(300, summary.ThreadListMaxHeight);
    }

    [TestMethod]
    public void EmptyNeedsYouModeHidesBothSummaries()
    {
        var summary = ThreadInboxSummaryPresentation.Resolve("needsYou", threadCount: 0, requestCount: 0);

        Assert.AreEqual("0 threads with attention", summary.ThreadSummaryText);
        Assert.IsFalse(summary.ShowThreadSummary);
        Assert.AreEqual("0 requests", summary.AttentionSummaryText);
        Assert.IsFalse(summary.ShowAttentionSection);
        Assert.IsTrue(summary.ShowEmptyState);
    }

    [TestMethod]
    public void ActiveModeStillShowsEmptyStateWhenRequestsExist()
    {
        var summary = ThreadInboxSummaryPresentation.Resolve("active", threadCount: 0, requestCount: 1);

        Assert.AreEqual("0 threads", summary.ThreadSummaryText);
        Assert.IsFalse(summary.ShowThreadSummary);
        Assert.AreEqual("1 request", summary.AttentionSummaryText);
        Assert.IsFalse(summary.ShowAttentionSection);
        Assert.IsTrue(summary.ShowEmptyState);
    }
}
