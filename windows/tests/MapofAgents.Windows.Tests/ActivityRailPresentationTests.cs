using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ActivityRailPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacWorkflowActivityRailMetrics()
    {
        var presentation = ActivityRailPresentation.Resolve();

        Assert.AreEqual(320, presentation.Width);
        Assert.AreEqual(12, presentation.Padding);
        Assert.IsTrue(double.IsPositiveInfinity(presentation.MaxHeight));
        Assert.AreEqual(10, presentation.SurfaceSpacing);
        Assert.AreEqual(10, presentation.ContentSpacing);
        Assert.AreEqual(11, presentation.CountFontSize);
        Assert.AreEqual(12, presentation.EmptyFontSize);
        Assert.AreEqual(8, presentation.EmptyVerticalPadding);
        Assert.AreEqual(260, presentation.ListMaxHeight);
        Assert.AreEqual(4, presentation.RowSpacing);
        Assert.AreEqual("No workflow activity yet.", presentation.EmptyMessage);
    }

    [TestMethod]
    public void ResolveMatchesMacWorkflowActivityRowMetrics()
    {
        var presentation = ActivityRailPresentation.Resolve();

        Assert.AreEqual(8, presentation.RowHorizontalPadding);
        Assert.AreEqual(6, presentation.RowVerticalPadding);
        Assert.AreEqual(8, presentation.RowColumnSpacing);
        Assert.AreEqual(16, presentation.RowIconColumnWidth);
        Assert.AreEqual(13, presentation.RowIconFontSize);
        Assert.AreEqual(2, presentation.RowContentSpacing);
        Assert.AreEqual(12, presentation.RowTitleFontSize);
        Assert.AreEqual(11, presentation.RowDetailFontSize);
        Assert.AreEqual(2, presentation.RowDetailMaxLines);
    }
}
