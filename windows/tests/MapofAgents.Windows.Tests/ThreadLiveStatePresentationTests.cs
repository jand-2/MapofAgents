using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadLiveStatePresentationTests
{
    [TestMethod]
    public void RunningWithDetailUsesMacLiveStateSeparator()
    {
        var presentation = ThreadLiveStatePresentation.Resolve(
            ThreadRunStatuses.Running,
            detail: "checking transcript rows");

        Assert.AreEqual("\uE895", presentation.Glyph);
        Assert.AreEqual(ThreadLiveStatePresentation.ArrowTriangleCirclePathIcon, presentation.IconKind);
        Assert.AreEqual("arrow.triangle.2.circlepath", presentation.MacSymbolName);
        Assert.AreEqual("Working \u00B7 checking transcript rows", presentation.Text);
        Assert.AreEqual("Working", presentation.Title);
        Assert.AreEqual("checking transcript rows", presentation.Detail);
        Assert.AreEqual(ThreadLiveStatePresentation.BlueHex, presentation.ForegroundHex);
        Assert.AreEqual(14, presentation.IconWidth);
        Assert.AreEqual(12, presentation.IconHeight);
        Assert.AreEqual(1.1, presentation.StrokeThickness);
    }

    [TestMethod]
    public void PendingApprovalOverridesRunStatus()
    {
        var presentation = ThreadLiveStatePresentation.Resolve(
            ThreadRunStatuses.Complete,
            pendingRequestCount: 1,
            detail: "sandbox approval");

        Assert.AreEqual("\uE7BA", presentation.Glyph);
        Assert.AreEqual(ThreadLiveStatePresentation.HandRaisedIcon, presentation.IconKind);
        Assert.AreEqual("hand.raised", presentation.MacSymbolName);
        Assert.AreEqual("Waiting for approval \u00B7 sandbox approval", presentation.Text);
        Assert.AreEqual("Waiting for approval", presentation.Title);
        Assert.AreEqual("sandbox approval", presentation.Detail);
        Assert.AreEqual(ThreadLiveStatePresentation.OrangeHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void DuplicateDetailDoesNotRepeatTitle()
    {
        var presentation = ThreadLiveStatePresentation.Resolve(
            ThreadRunStatuses.NeedsInput,
            detail: "Waiting for input");

        Assert.AreEqual("Waiting for input", presentation.Text);
        Assert.AreEqual(ThreadLiveStatePresentation.HandRaisedIcon, presentation.IconKind);
        Assert.AreEqual("hand.raised", presentation.MacSymbolName);
        Assert.AreEqual("Waiting for input", presentation.Title);
        Assert.AreEqual("", presentation.Detail);
        Assert.AreEqual(ThreadLiveStatePresentation.OrangeHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void IdleUsesMacSecondaryClockTreatment()
    {
        var presentation = ThreadLiveStatePresentation.Resolve(ThreadRunStatuses.Idle);

        Assert.AreEqual("\uE823", presentation.Glyph);
        Assert.AreEqual(ThreadLiveStatePresentation.ClockIcon, presentation.IconKind);
        Assert.AreEqual("clock", presentation.MacSymbolName);
        Assert.AreEqual("Idle", presentation.Text);
        Assert.AreEqual("Idle", presentation.Title);
        Assert.AreEqual("", presentation.Detail);
        Assert.AreEqual(ThreadLiveStatePresentation.SecondaryHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void CompleteAndFailedUseMacCircleAndOctagonIcons()
    {
        var complete = ThreadLiveStatePresentation.Resolve(ThreadRunStatuses.Complete);
        var failed = ThreadLiveStatePresentation.Resolve(ThreadRunStatuses.Failed);

        Assert.AreEqual(ThreadLiveStatePresentation.CheckmarkCircleIcon, complete.IconKind);
        Assert.AreEqual("checkmark.circle", complete.MacSymbolName);
        Assert.AreEqual(ThreadLiveStatePresentation.XmarkOctagonIcon, failed.IconKind);
        Assert.AreEqual("xmark.octagon", failed.MacSymbolName);
    }
}
