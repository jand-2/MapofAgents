using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class WindowStartupPlacementTests
{
    [TestMethod]
    public void CenterInWorkAreaUsesPreferredSizeWhenItFits()
    {
        var bounds = WindowStartupPlacement.CenterInWorkArea(
            workAreaX: 0,
            workAreaY: 0,
            workAreaWidth: 1920,
            workAreaHeight: 1040,
            preferredWidth: WindowStartupPlacement.PreferredWidth,
            preferredHeight: WindowStartupPlacement.PreferredHeight);

        Assert.AreEqual(new WindowStartupBounds(270, 90, 1380, 860), bounds);
    }

    [TestMethod]
    public void CenterInWorkAreaClampsToSmallWorkArea()
    {
        var bounds = WindowStartupPlacement.CenterInWorkArea(
            workAreaX: 12,
            workAreaY: 34,
            workAreaWidth: 1024,
            workAreaHeight: 720,
            preferredWidth: WindowStartupPlacement.PreferredWidth,
            preferredHeight: WindowStartupPlacement.PreferredHeight);

        Assert.AreEqual(new WindowStartupBounds(12, 34, 1024, 720), bounds);
    }

    [TestMethod]
    public void CenterInWorkAreaHonorsOffsetWorkArea()
    {
        var bounds = WindowStartupPlacement.CenterInWorkArea(
            workAreaX: -1600,
            workAreaY: 20,
            workAreaWidth: 1600,
            workAreaHeight: 900,
            preferredWidth: 1200,
            preferredHeight: 700);

        Assert.AreEqual(new WindowStartupBounds(-1400, 120, 1200, 700), bounds);
    }

    [TestMethod]
    public void MinimumTrackSizeUsesMacWindowMinimumAtDefaultDpi()
    {
        var size = WindowStartupPlacement.MinimumTrackSizeForDpi(WindowStartupPlacement.DefaultDpi);

        Assert.AreEqual(980, size.Width);
        Assert.AreEqual(640, size.Height);
    }

    [TestMethod]
    public void MinimumTrackSizeScalesForPerMonitorDpi()
    {
        var size = WindowStartupPlacement.MinimumTrackSizeForDpi(144);

        Assert.AreEqual(1470, size.Width);
        Assert.AreEqual(960, size.Height);
    }

    [TestMethod]
    public void MinimumTrackSizeFallsBackToDefaultDpiWhenUnavailable()
    {
        var size = WindowStartupPlacement.MinimumTrackSizeForDpi(0);

        Assert.AreEqual(980, size.Width);
        Assert.AreEqual(640, size.Height);
    }
}
