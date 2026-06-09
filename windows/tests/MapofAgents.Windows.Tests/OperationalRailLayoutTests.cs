using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class OperationalRailLayoutTests
{
    [TestMethod]
    public void MeasureKeepsMacStyleRailLaneInsetsAndWidth()
    {
        var layout = OperationalRailLayout.Measure(1048, reserveThreadInboxDock: true);

        Assert.AreEqual(334, layout.Width);
        Assert.AreEqual(320, layout.ContentWidth);
        Assert.AreEqual(14, layout.ContentInset);
        Assert.AreEqual(58, layout.TopInset);
        Assert.AreEqual(14, layout.RightInset);
    }

    [TestMethod]
    public void MeasureReservesBottomRightInboxLane()
    {
        var layout = OperationalRailLayout.Measure(1048, reserveThreadInboxDock: true);

        Assert.AreEqual(
            ThreadInboxDockLayout.MinimumMaxHeight + OperationalRailLayout.EdgeInset + OperationalRailLayout.InterRailGap,
            layout.BottomInset);
        Assert.AreEqual(746, layout.MaxHeight);
    }

    [TestMethod]
    public void MeasureCanUseOnlyChromeBottomInsetWhenInboxIsNotReserved()
    {
        var layout = OperationalRailLayout.Measure(1048, reserveThreadInboxDock: false);

        Assert.AreEqual(OperationalRailLayout.EdgeInset, layout.BottomInset);
        Assert.AreEqual(976, layout.MaxHeight);
    }

    [TestMethod]
    public void MeasureForBottomInboxOverlayUsesMacIndependentTopRailHeight()
    {
        var layout = OperationalRailLayout.MeasureForBottomInboxOverlay(1048);

        Assert.AreEqual(334, layout.Width);
        Assert.AreEqual(320, layout.ContentWidth);
        Assert.AreEqual(14, layout.ContentInset);
        Assert.AreEqual(58, layout.TopInset);
        Assert.AreEqual(14, layout.RightInset);
        Assert.AreEqual(OperationalRailLayout.EdgeInset, layout.BottomInset);
        Assert.AreEqual(976, layout.MaxHeight);
    }

    [TestMethod]
    public void MeasureKeepsShortWindowsUsable()
    {
        var layout = OperationalRailLayout.Measure(360, reserveThreadInboxDock: true);

        Assert.AreEqual(OperationalRailLayout.MinimumMaxHeight, layout.MaxHeight);
    }
}
