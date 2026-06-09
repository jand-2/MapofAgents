using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class GraphNodeLinkActionPresentationTests
{
    [TestMethod]
    public void DrawStateMatchesMacDottedTriangleConnectionAction()
    {
        var presentation = GraphNodeLinkActionPresentation.Resolve(GraphNodeLinkActionPresentation.DrawState);

        Assert.AreEqual("point.3.connected.trianglepath.dotted", presentation.MacSymbolName);
        Assert.AreEqual("\uE8F3", presentation.Glyph);
        Assert.AreEqual("Draw connection", presentation.Label);
        Assert.AreEqual(GraphNodeLinkActionPresentation.DottedTrianglePathIconKind, presentation.IconKind);
    }

    [TestMethod]
    public void ActiveStatesMatchMacCircleActions()
    {
        var cancel = GraphNodeLinkActionPresentation.Resolve(GraphNodeLinkActionPresentation.CancelState);
        var complete = GraphNodeLinkActionPresentation.Resolve(GraphNodeLinkActionPresentation.CompleteState);

        Assert.AreEqual("xmark.circle", cancel.MacSymbolName);
        Assert.AreEqual("\uE711", cancel.Glyph);
        Assert.AreEqual("Cancel connection", cancel.Label);
        Assert.AreEqual(GraphNodeLinkActionPresentation.FluentGlyphIconKind, cancel.IconKind);
        Assert.AreEqual("checkmark.circle", complete.MacSymbolName);
        Assert.AreEqual("\uE73E", complete.Glyph);
        Assert.AreEqual("Complete connection", complete.Label);
        Assert.AreEqual(GraphNodeLinkActionPresentation.FluentGlyphIconKind, complete.IconKind);
    }

    [TestMethod]
    public void WebConfigExposesMacActiveTreatment()
    {
        var config = GraphNodeLinkActionPresentation.WebConfig();

        Assert.AreEqual(GraphNodeLinkActionPresentation.DrawLabel, config.Draw.Label);
        Assert.AreEqual(GraphNodeLinkActionPresentation.DottedTrianglePathIconKind, config.Draw.IconKind);
        Assert.AreEqual(GraphNodeLinkActionPresentation.CancelLabel, config.Cancel.Label);
        Assert.AreEqual(GraphNodeLinkActionPresentation.CompleteLabel, config.Complete.Label);
        Assert.AreEqual("#30D158", config.ActiveHex);
        Assert.AreEqual(1.3, config.ActiveBorderWidth, 0.001);
        Assert.AreEqual(999, config.ActiveBorderRadius);
    }
}
