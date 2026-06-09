using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TopNotificationLayoutTests
{
    [TestMethod]
    public void UsesMacTopTrailingNotificationCardGeometry()
    {
        var layout = TopNotificationLayout.Measure();

        Assert.AreEqual(360, layout.StackWidth);
        Assert.AreEqual(0, layout.LeftInset);
        Assert.AreEqual(14, layout.TopInset);
        Assert.AreEqual(14, layout.RightInset);
        Assert.AreEqual(0, layout.BottomInset);
        Assert.AreEqual(18, layout.CardShadowTranslation);
        Assert.AreEqual(18, layout.CardDismissButtonSize);
        Assert.AreEqual(11, layout.CardDismissIconFontSize);
    }

    [TestMethod]
    public void UsesMacTopTrailingActivityHistoryGeometry()
    {
        var layout = TopNotificationLayout.Measure();

        Assert.AreEqual(380, layout.HistoryWidth);
        Assert.AreEqual(0, layout.LeftInset);
        Assert.AreEqual(14, layout.TopInset);
        Assert.AreEqual(14, layout.RightInset);
        Assert.AreEqual(0, layout.BottomInset);
        Assert.AreEqual(18, layout.HistoryShadowTranslation);
    }
}
