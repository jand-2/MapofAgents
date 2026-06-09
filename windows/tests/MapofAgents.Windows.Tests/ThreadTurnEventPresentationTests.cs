using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadTurnEventPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacTurnHeaderTitlesGlyphsAndTints()
    {
        var running = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            Status = ThreadRunStatuses.Running,
            StartedAt = LocalTimestamp(2026, 6, 7, 21, 30, 10)
        });
        var needsInput = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            Status = ThreadRunStatuses.NeedsInput,
            StartedAt = LocalTimestamp(2026, 6, 7, 21, 30, 10)
        });
        var failed = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            Status = ThreadRunStatuses.Failed,
            StartedAt = LocalTimestamp(2026, 6, 7, 21, 30, 10)
        });

        Assert.AreEqual("Turn running", running.HeaderTitle);
        Assert.AreEqual("\uE895", running.WindowsGlyph);
        Assert.AreEqual(ThreadStatusPresentation.BlueHex, running.ForegroundHex);
        Assert.AreEqual("Turn needs you", needsInput.HeaderTitle);
        Assert.AreEqual("\uE7BA", needsInput.WindowsGlyph);
        Assert.AreEqual(ThreadStatusPresentation.OrangeHex, needsInput.ForegroundHex);
        Assert.AreEqual("Turn failed", failed.HeaderTitle);
        Assert.AreEqual("\uE711", failed.WindowsGlyph);
        Assert.AreEqual(ThreadStatusPresentation.RedHex, failed.ForegroundHex);
    }

    [TestMethod]
    public void DetailIncludesMacVisibleStartTimestampDurationCompletionAndError()
    {
        var presentation = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            Status = ThreadRunStatuses.Complete,
            ItemsView = ThreadTurnItemsViews.Summary,
            StartedAt = LocalTimestamp(2026, 6, 7, 21, 30, 10),
            CompletedAt = LocalTimestamp(2026, 6, 7, 21, 30, 12),
            DurationMilliseconds = 2500,
            Error = "Tool output truncated."
        });

        StringAssert.Contains(presentation.Detail, "summary");
        StringAssert.Contains(presentation.Detail, "Started");
        StringAssert.Contains(presentation.Detail, "Jun 7");
        StringAssert.Contains(presentation.Detail, "9:30:10 PM");
        StringAssert.Contains(presentation.Detail, "2.5s");
        StringAssert.Contains(presentation.Detail, "Completed 9:30:12 PM");
        StringAssert.Contains(presentation.Detail, "Tool output truncated.");
    }

    [TestMethod]
    public void TurnHeadersUseMacPlainHeaderMetrics()
    {
        var presentation = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            Status = ThreadRunStatuses.Complete,
            StartedAt = LocalTimestamp(2026, 6, 7, 21, 30, 10)
        });

        Assert.AreEqual("#00FFFFFF", presentation.HeaderBackgroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.HeaderBorderHex);
        Assert.AreEqual("#8F9BAA", presentation.HeaderDetailForegroundHex);
        Assert.AreEqual(8, presentation.HeaderHorizontalPadding, 0.001);
        Assert.AreEqual(0, presentation.HeaderVerticalPadding, 0.001);
        Assert.AreEqual(0, presentation.HeaderCornerRadius, 0.001);
        Assert.AreEqual(5, presentation.HeaderContentSpacing, 0.001);
        Assert.AreEqual(6, presentation.HeaderStatusIconSpacing, 0.001);
        Assert.AreEqual(11, presentation.HeaderStatusIconFontSize, 0.001);
        Assert.AreEqual(11, presentation.HeaderDetailFontSize, 0.001);
        Assert.IsTrue(double.IsPositiveInfinity(presentation.HeaderMaxWidth));
    }

    [TestMethod]
    public void DurationTextMatchesMacMillisecondAndSecondThresholds()
    {
        Assert.AreEqual(
            "450 ms",
            ThreadTurnEventPresentation.DurationText(new LocalThreadTurn
            {
                StartedAt = LocalTimestamp(2026, 6, 7, 21, 30, 10),
                DurationMilliseconds = 450
            }));
        Assert.AreEqual(
            "1.2s",
            ThreadTurnEventPresentation.DurationText(new LocalThreadTurn
            {
                StartedAt = LocalTimestamp(2026, 6, 7, 21, 30, 10),
                DurationMilliseconds = 1200
            }));
    }

    [TestMethod]
    public void EmptyTurnDetailsMatchMacPlaceholders()
    {
        var notLoaded = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            ItemsView = ThreadTurnItemsViews.NotLoaded
        });
        var summary = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            ItemsView = ThreadTurnItemsViews.Summary
        });
        var running = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            Status = ThreadRunStatuses.Running,
            ItemsView = ThreadTurnItemsViews.Full
        });

        Assert.AreEqual(
            "Turn items are not loaded yet.",
            notLoaded.EmptyDetail);
        Assert.AreEqual(
            "Only summary details are loaded for this turn.",
            summary.EmptyDetail);
        Assert.AreEqual(
            "Turn is running; no message items have arrived yet.",
            running.EmptyDetail);
        Assert.AreEqual("Turn details", notLoaded.EmptyTitle);
        Assert.AreEqual("\uE8EF", notLoaded.EmptyWindowsGlyph);
        Assert.AreEqual("\uE9D5", running.EmptyWindowsGlyph);
    }

    [TestMethod]
    public void EmptyTurnDetailsUseMacCompactStripMetrics()
    {
        var presentation = ThreadTurnEventPresentation.Resolve(new LocalThreadTurn
        {
            ItemsView = ThreadTurnItemsViews.Full
        });

        Assert.AreEqual("#14A7B0BF", presentation.EmptyBackgroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.EmptyBorderHex);
        Assert.AreEqual(TranscriptCategoryPresentation.SecondaryHex, presentation.EmptyForegroundHex);
        Assert.AreEqual(10, presentation.EmptyPadding, 0.001);
        Assert.AreEqual(8, presentation.EmptyCornerRadius, 0.001);
        Assert.AreEqual(8, presentation.EmptyContentSpacing, 0.001);
        Assert.AreEqual(12, presentation.EmptyIconFontSize, 0.001);
        Assert.AreEqual(12, presentation.EmptyTextFontSize, 0.001);
        Assert.IsTrue(double.IsPositiveInfinity(presentation.EmptyMaxWidth));
    }

    private static DateTimeOffset LocalTimestamp(
        int year,
        int month,
        int day,
        int hour,
        int minute,
        int second)
    {
        var local = new DateTime(year, month, day, hour, minute, second, DateTimeKind.Unspecified);
        return new DateTimeOffset(local, TimeZoneInfo.Local.GetUtcOffset(local));
    }
}
