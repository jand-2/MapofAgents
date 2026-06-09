using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxPresentationTests
{
    [TestMethod]
    public void CompleteStatusUsesMacFinishedLabelAndGreenTreatment()
    {
        var presentation = ThreadInboxPresentation.Resolve(
            ThreadRunStatuses.Complete,
            isSubagent: false,
            pendingRequestCount: 0);

        Assert.AreEqual("finished", presentation.StatusText);
        Assert.AreEqual("\uE8F2", presentation.LeadingGlyph);
        Assert.AreEqual(ThreadInboxPresentation.LeadingThreadPairIcon, presentation.LeadingIconKind);
        Assert.AreEqual("bubble.left.and.bubble.right", presentation.LeadingMacSymbolName);
        Assert.IsTrue(presentation.LeadingUsesThreadPairIcon);
        Assert.AreEqual(ThreadInboxPresentation.GreenHex, presentation.LeadingHex);
        Assert.AreEqual(ThreadInboxPresentation.GreenHex, presentation.StatusHex);
        Assert.AreEqual("#1F30D158", presentation.StatusBackgroundHex);
        Assert.AreEqual(ThreadLiveStatePresentation.CheckmarkCircleIcon, presentation.LiveStateIconKind);
        Assert.AreEqual("Finished", presentation.LiveStateText);
        Assert.AreEqual("Finished", presentation.LiveStateTitle);
        Assert.AreEqual("", presentation.LiveStateDetail);
    }

    [TestMethod]
    public void NeedsInputUsesMacNeedsLabelAndOrangeTreatment()
    {
        var presentation = ThreadInboxPresentation.Resolve(
            ThreadRunStatuses.NeedsInput,
            isSubagent: false,
            pendingRequestCount: 0,
            liveDetail: "approval requested");

        Assert.AreEqual("needs", presentation.StatusText);
        Assert.AreEqual("\uE7BA", presentation.LeadingGlyph);
        Assert.AreEqual(ThreadInboxPresentation.LeadingNeedsInputIcon, presentation.LeadingIconKind);
        Assert.AreEqual("exclamationmark.bubble", presentation.LeadingMacSymbolName);
        Assert.IsFalse(presentation.LeadingUsesThreadPairIcon);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, presentation.LeadingHex);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, presentation.LiveStateHex);
        Assert.AreEqual(ThreadLiveStatePresentation.HandRaisedIcon, presentation.LiveStateIconKind);
        Assert.AreEqual("Waiting for input \u00B7 approval requested", presentation.LiveStateText);
        Assert.AreEqual("Waiting for input", presentation.LiveStateTitle);
        Assert.AreEqual("approval requested", presentation.LiveStateDetail);
    }

    [TestMethod]
    public void FailedStatusUsesMacRedTreatment()
    {
        var presentation = ThreadInboxPresentation.Resolve(
            ThreadRunStatuses.Failed,
            isSubagent: false,
            pendingRequestCount: 0);

        Assert.AreEqual("failed", presentation.StatusText);
        Assert.AreEqual(ThreadInboxPresentation.LeadingFailedIcon, presentation.LeadingIconKind);
        Assert.AreEqual("xmark.octagon", presentation.LeadingMacSymbolName);
        Assert.IsFalse(presentation.LeadingUsesThreadPairIcon);
        Assert.AreEqual(ThreadInboxPresentation.RedHex, presentation.LeadingHex);
        Assert.AreEqual(ThreadInboxPresentation.RedHex, presentation.StatusHex);
        Assert.AreEqual("#1FFF453A", presentation.StatusBackgroundHex);
        Assert.AreEqual(ThreadInboxPresentation.RedHex, presentation.LiveStateHex);
    }

    [TestMethod]
    public void PendingApprovalDoesNotReplaceThreadLeadingIcon()
    {
        var presentation = ThreadInboxPresentation.Resolve(
            ThreadRunStatuses.Idle,
            isSubagent: true,
            pendingRequestCount: 2,
            liveDetail: "sandbox approval");

        Assert.AreEqual("idle", presentation.StatusText);
        Assert.AreEqual("\uE716", presentation.LeadingGlyph);
        Assert.AreEqual(ThreadInboxPresentation.LeadingSubagentGlyphIcon, presentation.LeadingIconKind);
        Assert.AreEqual("person.2", presentation.LeadingMacSymbolName);
        Assert.IsFalse(presentation.LeadingUsesThreadPairIcon);
        Assert.AreEqual(ThreadInboxPresentation.PurpleHex, presentation.LeadingHex);
        Assert.AreEqual("Waiting for approval \u00B7 sandbox approval", presentation.LiveStateText);
        Assert.AreEqual("Waiting for approval", presentation.LiveStateTitle);
        Assert.AreEqual("sandbox approval", presentation.LiveStateDetail);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, presentation.LiveStateHex);
    }

    [TestMethod]
    public void IdleLiveStateUsesMacSecondaryTreatment()
    {
        var presentation = ThreadInboxPresentation.Resolve(
            ThreadRunStatuses.Idle,
            isSubagent: false,
            pendingRequestCount: 0);

        Assert.AreEqual("Idle", presentation.LiveStateTitle);
        Assert.AreEqual(ThreadLiveStatePresentation.ClockIcon, presentation.LiveStateIconKind);
        Assert.AreEqual(ThreadLiveStatePresentation.SecondaryHex, presentation.LiveStateHex);
    }

    [TestMethod]
    public void RunningUsesMacRowLeadingCycleIcon()
    {
        var presentation = ThreadInboxPresentation.Resolve(
            ThreadRunStatuses.Running,
            isSubagent: false,
            pendingRequestCount: 0);

        Assert.AreEqual(ThreadInboxPresentation.LeadingRunningIcon, presentation.LeadingIconKind);
        Assert.AreEqual("arrow.triangle.2.circlepath", presentation.LeadingMacSymbolName);
        Assert.AreEqual(18, ThreadInboxPresentation.LeadingStatusIconWidth);
        Assert.AreEqual(18, ThreadInboxPresentation.LeadingStatusIconHeight);
        Assert.AreEqual(1.25, ThreadInboxPresentation.LeadingStatusIconStrokeThickness);
    }
}
