using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class GraphNodeStatusPresentationTests
{
    [TestMethod]
    public void ThreadNeedsInputKeepsMacRawNodeLabelAndOrangeTreatment()
    {
        var presentation = GraphNodeStatusPresentation.Thread(
            ThreadRunStatuses.NeedsInput,
            isUnread: false);

        Assert.AreEqual("needsInput", presentation.Label);
        Assert.AreEqual("\uE7BA", presentation.Glyph);
        Assert.AreEqual(GraphNodeStatusPresentation.ExclamationBubbleIcon, presentation.IconKind);
        Assert.AreEqual("exclamationmark.bubble", presentation.MacSymbolName);
        Assert.IsTrue(presentation.ShowsGlyph);
        Assert.AreEqual(GraphNodeStatusPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual("rgba(255, 159, 10, 0.10)", presentation.BackgroundCss);
        Assert.AreEqual("rgba(255, 159, 10, 0.18)", presentation.BorderCss);
    }

    [TestMethod]
    public void ThreadCompleteKeepsMacRawNodeLabelAndGreenTreatment()
    {
        var presentation = GraphNodeStatusPresentation.Thread(
            ThreadRunStatuses.Complete,
            isUnread: false);

        Assert.AreEqual("complete", presentation.Label);
        Assert.AreEqual("\uE73E", presentation.Glyph);
        Assert.AreEqual(GraphNodeStatusPresentation.CheckmarkCircleIcon, presentation.IconKind);
        Assert.AreEqual("checkmark.circle", presentation.MacSymbolName);
        Assert.IsTrue(presentation.ShowsGlyph);
        Assert.AreEqual(GraphNodeStatusPresentation.GreenHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void ThreadRunningAndFailedExposeMacSemanticIcons()
    {
        var running = GraphNodeStatusPresentation.Thread(
            ThreadRunStatuses.Running,
            isUnread: false);
        var failed = GraphNodeStatusPresentation.Thread(
            ThreadRunStatuses.Failed,
            isUnread: false);

        Assert.AreEqual(GraphNodeStatusPresentation.ArrowTriangleCirclePathIcon, running.IconKind);
        Assert.AreEqual("arrow.triangle.2.circlepath", running.MacSymbolName);
        Assert.AreEqual(GraphNodeStatusPresentation.XmarkOctagonIcon, failed.IconKind);
        Assert.AreEqual("xmark.octagon", failed.MacSymbolName);
    }

    [TestMethod]
    public void ThreadUnreadOverridesRunStatusLikeMacNodeView()
    {
        var presentation = GraphNodeStatusPresentation.Thread(
            ThreadRunStatuses.Complete,
            isUnread: true);

        Assert.AreEqual("unread", presentation.Label);
        Assert.AreEqual("\uEA3A", presentation.Glyph);
        Assert.AreEqual(GraphNodeStatusPresentation.CircleFillIcon, presentation.IconKind);
        Assert.AreEqual("circle.fill", presentation.MacSymbolName);
        Assert.IsTrue(presentation.ShowsGlyph);
        Assert.AreEqual(GraphNodeStatusPresentation.BlueHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void MachineDisconnectedUsesMacOfflineSecondaryPill()
    {
        var presentation = GraphNodeStatusPresentation.Machine(HostStatuses.Disconnected);

        Assert.AreEqual("offline", presentation.Label);
        Assert.AreEqual(GraphNodeStatusPresentation.CircleIcon, presentation.IconKind);
        Assert.AreEqual("circle", presentation.MacSymbolName);
        Assert.IsFalse(presentation.ShowsGlyph);
        Assert.AreEqual(GraphNodeStatusPresentation.SecondaryHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void WebPresentationMapIncludesRendererFallbackKeys()
    {
        var map = GraphNodeStatusPresentation.WebPresentationMap();

        Assert.IsTrue(map["machine"].ContainsKey(HostStatuses.Disconnected));
        Assert.IsTrue(map["folder"].ContainsKey("folder"));
        Assert.IsTrue(map["thread"].ContainsKey("unread"));
        Assert.IsTrue(map["thread"].ContainsKey(ThreadRunStatuses.Unknown));
        Assert.AreEqual(
            "needsInput",
            map["thread"][ThreadRunStatuses.NeedsInput].Label);
    }
}
