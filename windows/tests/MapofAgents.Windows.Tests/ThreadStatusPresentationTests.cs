using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadStatusPresentationTests
{
    [TestMethod]
    public void NeedsInputUsesMacOrangeThreadHeaderTreatment()
    {
        var presentation = ThreadStatusPresentation.Resolve(ThreadRunStatuses.NeedsInput);

        Assert.AreEqual("needs input", presentation.Text);
        Assert.AreEqual("\uE7BA", presentation.Glyph);
        Assert.AreEqual(ThreadStatusPresentation.ExclamationBubbleIcon, presentation.IconKind);
        Assert.AreEqual("exclamationmark.bubble", presentation.MacSymbolName);
        Assert.AreEqual(ThreadStatusPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual("#1CFF9F0A", presentation.BackgroundHex);
        Assert.AreEqual(ThreadStatusPresentation.BorderlessHex, presentation.BorderHex);
        Assert.AreEqual(0, presentation.BorderThickness, 0.001);
    }

    [TestMethod]
    public void FailedUsesMacRedThreadHeaderTreatment()
    {
        var presentation = ThreadStatusPresentation.Resolve(ThreadRunStatuses.Failed);

        Assert.AreEqual("failed", presentation.Text);
        Assert.AreEqual("\uE711", presentation.Glyph);
        Assert.AreEqual(ThreadStatusPresentation.XmarkOctagonIcon, presentation.IconKind);
        Assert.AreEqual("xmark.octagon", presentation.MacSymbolName);
        Assert.AreEqual(ThreadStatusPresentation.RedHex, presentation.ForegroundHex);
        Assert.AreEqual("#1CFF453A", presentation.BackgroundHex);
        Assert.AreEqual(ThreadStatusPresentation.BorderlessHex, presentation.BorderHex);
        Assert.AreEqual(0, presentation.BorderThickness, 0.001);
    }

    [TestMethod]
    public void CompleteKeepsGreenCompleteLabel()
    {
        var presentation = ThreadStatusPresentation.Resolve(ThreadRunStatuses.Complete);

        Assert.AreEqual("complete", presentation.Text);
        Assert.AreEqual("\uE73E", presentation.Glyph);
        Assert.AreEqual(ThreadStatusPresentation.CheckmarkCircleIcon, presentation.IconKind);
        Assert.AreEqual("checkmark.circle", presentation.MacSymbolName);
        Assert.AreEqual(ThreadStatusPresentation.GreenHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void UnreadOverridesRunStatus()
    {
        var presentation = ThreadStatusPresentation.Resolve(
            ThreadRunStatuses.Complete,
            isUnread: true);

        Assert.AreEqual("unread", presentation.Text);
        Assert.AreEqual("\uEA3A", presentation.Glyph);
        Assert.AreEqual(ThreadStatusPresentation.CircleFillIcon, presentation.IconKind);
        Assert.AreEqual("circle.fill", presentation.MacSymbolName);
        Assert.AreEqual(ThreadStatusPresentation.BlueHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void RunningStatusStaysRunningBecauseArchiveStateIsNotPartOfMacHeaderPill()
    {
        var presentation = ThreadStatusPresentation.Resolve(ThreadRunStatuses.Running);

        Assert.AreEqual("running", presentation.Text);
        Assert.AreEqual("\uE895", presentation.Glyph);
        Assert.AreEqual(ThreadStatusPresentation.ArrowTriangleCirclePathIcon, presentation.IconKind);
        Assert.AreEqual("arrow.triangle.2.circlepath", presentation.MacSymbolName);
        Assert.AreEqual(ThreadStatusPresentation.BlueHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void PillMetricsMatchMacBorderlessCapsule()
    {
        var presentation = ThreadStatusPresentation.Resolve(ThreadRunStatuses.Running);

        Assert.AreEqual(ThreadStatusPresentation.BorderlessHex, presentation.BorderHex);
        Assert.AreEqual(0, presentation.BorderThickness, 0.001);
        Assert.AreEqual(8, presentation.HorizontalPadding, 0.001);
        Assert.AreEqual(4, presentation.VerticalPadding, 0.001);
        Assert.AreEqual(10, presentation.CornerRadius, 0.001);
        Assert.AreEqual(0, presentation.MinWidth, 0.001);
        Assert.AreEqual(11, presentation.IconFontSize, 0.001);
        Assert.AreEqual(11, presentation.IconWidth, 0.001);
        Assert.AreEqual(11, presentation.IconHeight, 0.001);
        Assert.AreEqual(1.25, presentation.IconStrokeThickness, 0.001);
        Assert.AreEqual(11, presentation.TextFontSize, 0.001);
    }

    [TestMethod]
    public void IdleAndUnknownUseMacCircleSymbol()
    {
        var idle = ThreadStatusPresentation.Resolve(ThreadRunStatuses.Idle);
        var unknown = ThreadStatusPresentation.Resolve(ThreadRunStatuses.Unknown);

        Assert.AreEqual(ThreadStatusPresentation.CircleIcon, idle.IconKind);
        Assert.AreEqual("circle", idle.MacSymbolName);
        Assert.AreEqual(ThreadStatusPresentation.CircleIcon, unknown.IconKind);
        Assert.AreEqual("circle", unknown.MacSymbolName);
    }
}
