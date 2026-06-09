using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class CommandFeedbackLayoutTests
{
    [TestMethod]
    public void UsesMacCommandBarFeedbackGeometry()
    {
        var layout = CommandFeedbackLayout.Measure();

        Assert.AreEqual(240, layout.Width);
        Assert.AreEqual(14, layout.LeftInset);
        Assert.AreEqual(76, layout.TopInset);
    }

    [TestMethod]
    public void UsesMacControlFeedbackBubbleVisualMetrics()
    {
        var layout = CommandFeedbackLayout.Measure();

        Assert.AreEqual(10, layout.HorizontalPadding);
        Assert.AreEqual(7, layout.VerticalPadding);
        Assert.AreEqual(8, layout.CornerRadius);
        Assert.AreEqual(1, layout.BorderThickness);
        Assert.AreEqual(12, layout.TextFontSize);
        Assert.AreEqual(16, layout.TextLineHeight);
        Assert.AreEqual(3, layout.TextMaxLines);
        Assert.AreEqual(18, layout.ShadowTranslationZ);
    }

    [TestMethod]
    public void CentersAnchoredFeedbackAboveControl()
    {
        var layout = CommandFeedbackLayout.MeasureAnchored(
            anchorLeft: 160,
            anchorTop: 70,
            anchorWidth: 80,
            anchorHeight: 30,
            rootWidth: 1000);

        Assert.AreEqual(240, layout.Width);
        Assert.AreEqual(80, layout.LeftInset);
        Assert.AreEqual(28, layout.TopInset);
    }

    [TestMethod]
    public void ClampsAnchoredFeedbackInsideRootEdges()
    {
        var leftLayout = CommandFeedbackLayout.MeasureAnchored(
            anchorLeft: 20,
            anchorTop: 20,
            anchorWidth: 60,
            anchorHeight: 30,
            rootWidth: 300);
        var rightLayout = CommandFeedbackLayout.MeasureAnchored(
            anchorLeft: 260,
            anchorTop: 70,
            anchorWidth: 60,
            anchorHeight: 30,
            rootWidth: 300);

        Assert.AreEqual(14, leftLayout.LeftInset);
        Assert.AreEqual(58, leftLayout.TopInset);
        Assert.AreEqual(46, rightLayout.LeftInset);
    }
}
