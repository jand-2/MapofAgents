using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarActivityPresentationTests
{
    [TestMethod]
    public void UsesMacBellBadgeTreatment()
    {
        var presentation = ToolbarActivityPresentation.Resolve();

        Assert.AreEqual("bell.badge", presentation.MacSymbolName);
        Assert.AreEqual("#D7DCE5", presentation.StrokeHex);
        Assert.AreEqual("#D7DCE5", presentation.BadgeHex);
        Assert.AreEqual("Show recent notifications", presentation.ToolTip);
        Assert.AreEqual(16, presentation.IconWidth);
        Assert.AreEqual(15, presentation.IconHeight);
        Assert.AreEqual(1.1, presentation.StrokeThickness);
        Assert.AreEqual(5, presentation.BadgeSize);
        Assert.IsTrue(presentation.BadgeX > presentation.IconWidth / 2);
        Assert.IsTrue(presentation.BadgeY < presentation.IconHeight / 2);
        Assert.AreEqual("Activity", presentation.AccessibilityName);
    }
}
