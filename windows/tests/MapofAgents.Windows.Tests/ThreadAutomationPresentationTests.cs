using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadAutomationPresentationTests
{
    [TestMethod]
    public void ActiveAutomationUsesMacAlarmFillTreatment()
    {
        var presentation = ThreadAutomationPresentation.Resolve(Automation("ACTIVE"));

        Assert.IsTrue(presentation.IsVisible);
        Assert.IsTrue(presentation.IsActive);
        Assert.AreEqual(ThreadAutomationPresentation.WindowsGlyph, presentation.WindowsGlyph);
        Assert.AreEqual("alarm.fill", presentation.MacSymbolName);
        Assert.AreEqual(ThreadAutomationPresentation.ActiveForegroundHex, presentation.ForegroundHex);
        Assert.AreEqual("Example automation is active", presentation.ToolTip);
        Assert.AreEqual("Thread automation", presentation.AccessibilityName);
    }

    [TestMethod]
    public void PausedAutomationUsesSecondaryAlarmTreatment()
    {
        var presentation = ThreadAutomationPresentation.Resolve(Automation("PAUSED"));

        Assert.IsTrue(presentation.IsVisible);
        Assert.IsFalse(presentation.IsActive);
        Assert.AreEqual("alarm", presentation.MacSymbolName);
        Assert.AreEqual(ThreadAutomationPresentation.InactiveForegroundHex, presentation.ForegroundHex);
        Assert.AreEqual("Example automation is paused", presentation.AccessibilityValue);
    }

    [TestMethod]
    public void MissingAutomationIsHidden()
    {
        var presentation = ThreadAutomationPresentation.Resolve(null);

        Assert.IsFalse(presentation.IsVisible);
        Assert.AreEqual(ThreadAutomationPresentation.HiddenToolTip, presentation.ToolTip);
    }

    private static CodexAutomationSummary Automation(string status)
    {
        return new CodexAutomationSummary(
            "example",
            "heartbeat",
            "Example",
            "",
            status,
            "FREQ=HOURLY;INTERVAL=1",
            "thread-123",
            null,
            null,
            null,
            null,
            null,
            null,
            "");
    }
}
