using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ActivitySurfaceHeaderPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacActivityRailAndNotificationSymbols()
    {
        var presentation = ActivitySurfaceHeaderPresentation.Resolve();

        Assert.AreEqual("waveform.path.ecg", presentation.RailMacSymbolName);
        Assert.AreEqual("bell.badge", presentation.NotificationMacSymbolName);
        Assert.AreEqual("#A7B0BF", presentation.StrokeHex);
        Assert.AreEqual("#A7B0BF", presentation.BadgeHex);
        Assert.AreEqual(17, presentation.RailIconWidth);
        Assert.AreEqual(16, presentation.RailIconHeight);
        Assert.AreEqual(1.25, presentation.RailStrokeThickness);
        Assert.AreEqual(16, presentation.BellIconWidth);
        Assert.AreEqual(15, presentation.BellIconHeight);
        Assert.AreEqual(1.1, presentation.BellStrokeThickness);
        Assert.AreEqual(5, presentation.BadgeSize);
        Assert.IsTrue(presentation.BadgeX > presentation.BellIconWidth / 2);
        Assert.IsTrue(presentation.BadgeY < presentation.BellIconHeight / 2);
        Assert.AreEqual("Workflow activity", presentation.RailAccessibilityName);
        Assert.AreEqual("Activity", presentation.HistoryAccessibilityName);
        Assert.AreEqual("Notification preferences", presentation.PreferencesAccessibilityName);
    }
}
