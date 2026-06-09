using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxDockLayoutTests
{
    [TestMethod]
    public void MeasurePinsInboxToMacStyleBottomRightChromeInset()
    {
        var layout = ThreadInboxDockLayout.Measure(860);

        Assert.AreEqual(320, layout.Width);
        Assert.AreEqual(14, layout.RightInset);
        Assert.AreEqual(14, layout.BottomInset);
        Assert.AreEqual(ThreadInboxDockLayout.OverlayZIndex, layout.ZIndex);
    }

    [TestMethod]
    public void MeasureUsesMacInboxPanelShellMetrics()
    {
        var layout = ThreadInboxDockLayout.Measure(860);

        Assert.AreEqual(12, layout.Padding);
        Assert.AreEqual(8, layout.CornerRadius);
        Assert.AreEqual(1, layout.BorderThickness);
        Assert.AreEqual(10, layout.ShadowTranslationZ);
    }

    [TestMethod]
    public void MeasureReservesTopChromeClearance()
    {
        var layout = ThreadInboxDockLayout.Measure(860);

        Assert.AreEqual(748, layout.MaxHeight);
    }

    [TestMethod]
    public void MeasureKeepsInboxUsableInShortWindows()
    {
        var layout = ThreadInboxDockLayout.Measure(260);

        Assert.AreEqual(ThreadInboxDockLayout.MinimumMaxHeight, layout.MaxHeight);
    }
}
