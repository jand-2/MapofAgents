using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxRowActionPresentationTests
{
    [TestMethod]
    public void UnreadRowsUseMacEnvelopeOpenAndArchiveBox()
    {
        var presentation = ThreadInboxRowActionPresentation.Resolve(
            unread: true,
            archived: false,
            title: "Build parity");

        Assert.AreEqual("Add to canvas", presentation.AddToCanvasToolTip);
        Assert.AreEqual("Add Build parity to canvas", presentation.AddToCanvasAccessibilityLabel);
        Assert.AreEqual(ThreadInboxRowActionPresentation.EnvelopeOpenIcon, presentation.MarkReadIconKind);
        Assert.AreEqual("Mark read", presentation.MarkReadLabel);
        Assert.AreEqual("Mark Build parity read", presentation.MarkReadAccessibilityLabel);
        Assert.AreEqual(ThreadInboxRowActionPresentation.ArchiveBoxIcon, presentation.ArchiveIconKind);
        Assert.AreEqual("Archive", presentation.ArchiveLabel);
        Assert.AreEqual("Archive Build parity", presentation.ArchiveAccessibilityLabel);
        Assert.IsTrue(presentation.ShowsArchiveAction);
    }

    [TestMethod]
    public void ReadRowsUseMacEnvelopeBadgeAndArchiveBox()
    {
        var read = ThreadInboxRowActionPresentation.Resolve(
            unread: false,
            archived: false,
            title: "Review transcript");

        Assert.AreEqual(ThreadInboxRowActionPresentation.EnvelopeBadgeIcon, read.MarkReadIconKind);
        Assert.AreEqual("Mark unread", read.MarkReadLabel);
        Assert.AreEqual("Mark Review transcript unread", read.MarkReadAccessibilityLabel);
        Assert.AreEqual(ThreadInboxRowActionPresentation.ArchiveBoxIcon, read.ArchiveIconKind);
        Assert.AreEqual("Archive", read.ArchiveLabel);
        Assert.AreEqual("Archive Review transcript", read.ArchiveAccessibilityLabel);
        Assert.IsTrue(read.ShowsArchiveAction);
    }

    [TestMethod]
    public void ArchivedRowsHideArchiveActionLikeMacRows()
    {
        var archived = ThreadInboxRowActionPresentation.Resolve(
            unread: false,
            archived: true,
            title: "Finished thread");

        Assert.AreEqual(ThreadInboxRowActionPresentation.EnvelopeBadgeIcon, archived.MarkReadIconKind);
        Assert.AreEqual("Mark unread", archived.MarkReadLabel);
        Assert.AreEqual("Mark Finished thread unread", archived.MarkReadAccessibilityLabel);
        Assert.AreEqual(ThreadInboxRowActionPresentation.ArchiveBoxIcon, archived.ArchiveIconKind);
        Assert.AreEqual("Archive", archived.ArchiveLabel);
        Assert.AreEqual("Archive Finished thread", archived.ArchiveAccessibilityLabel);
        Assert.IsFalse(archived.ShowsArchiveAction);
    }

    [TestMethod]
    public void BlankTitlesUseGenericThreadAccessibilityTarget()
    {
        var presentation = ThreadInboxRowActionPresentation.Resolve(
            unread: true,
            archived: false,
            title: " ");

        Assert.AreEqual("Add thread to canvas", presentation.AddToCanvasAccessibilityLabel);
        Assert.AreEqual("Mark thread read", presentation.MarkReadAccessibilityLabel);
        Assert.AreEqual("Archive thread", presentation.ArchiveAccessibilityLabel);
    }

    [TestMethod]
    public void RowActionsUseMacPlainIconFrameMetrics()
    {
        var presentation = ThreadInboxRowActionPresentation.Resolve(
            unread: true,
            archived: false,
            title: "Build parity");

        Assert.AreEqual(18, presentation.ActionButtonSize);
        Assert.AreEqual(ThreadInboxPresentation.SecondaryHex, presentation.ActionIconHex);
        Assert.AreEqual(1.1, presentation.AddToCanvasStrokeThickness, 0.001);
        Assert.AreEqual(0.72, presentation.AddToCanvasBackLayerOpacity, 0.001);
        Assert.AreEqual(1.15, presentation.MarkReadStrokeThickness, 0.001);
        Assert.AreEqual(4, presentation.MarkReadBadgeSize);
        Assert.AreEqual(1.15, presentation.ArchiveStrokeThickness, 0.001);
    }
}
