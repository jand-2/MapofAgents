using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class SelectionInspectorLayoutTests
{
    [TestMethod]
    public void NodeInspectorMatchesMacRightRailCardMetrics()
    {
        var layout = SelectionInspectorLayout.ForNode();

        Assert.AreEqual(310, layout.Width);
        Assert.AreEqual(86, layout.TopInset);
        Assert.AreEqual(14, layout.RightInset);
        Assert.AreEqual(12, layout.Padding);
        Assert.AreEqual(8, layout.CornerRadius);
        Assert.AreEqual(18, layout.ShadowTranslationZ);
    }

    [TestMethod]
    public void EdgeInspectorUsesMacLineEditorWidthInTheSameRailLane()
    {
        var layout = SelectionInspectorLayout.ForEdge();

        Assert.AreEqual(300, layout.Width);
        Assert.AreEqual(SelectionInspectorLayout.TopInset, layout.TopInset);
        Assert.AreEqual(SelectionInspectorLayout.RightInset, layout.RightInset);
        Assert.AreEqual(SelectionInspectorLayout.Padding, layout.Padding);
        Assert.AreEqual(SelectionInspectorLayout.CornerRadius, layout.CornerRadius);
    }

    [TestMethod]
    public void HeaderAndIconMetricsMatchMacInspectorSurface()
    {
        var layout = SelectionInspectorLayout.ForNode();

        Assert.AreEqual(8, layout.HeaderSpacing);
        Assert.AreEqual(10, layout.ContentSpacing);
        Assert.AreEqual(22, layout.IconSize);
        Assert.AreEqual(6, layout.IconCornerRadius);
    }
}
