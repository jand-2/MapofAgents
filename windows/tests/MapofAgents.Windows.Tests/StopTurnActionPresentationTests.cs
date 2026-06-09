using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class StopTurnActionPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacRedStopTurnTreatment()
    {
        var presentation = StopTurnActionPresentation.Resolve();

        Assert.AreEqual("stop.fill", presentation.ActiveMacSymbolName);
        Assert.AreEqual("stop.circle", presentation.StoppingMacSymbolName);
        Assert.AreEqual("\uE71A", presentation.WindowsGlyph);
        Assert.AreEqual("#FF453A", presentation.ForegroundHex);
        Assert.AreEqual("#1AFF453A", presentation.BackgroundHex);
        Assert.AreEqual("#44FF453A", presentation.BorderHex);
        Assert.AreEqual("Stop running turn", presentation.ToolTip);
        Assert.AreEqual("Stop running turn", presentation.AccessibilityName);
    }

    [TestMethod]
    public void AvailabilityShowsActiveButtonWhenHeaderStatusIsRunning()
    {
        var availability = StopTurnActionPresentation.Availability(
            ThreadRunStatuses.Running,
            canStopTurn: true,
            isStoppingTurn: false);

        Assert.IsTrue(availability.IsVisible);
        Assert.IsTrue(availability.IsButtonEnabled);
        Assert.IsTrue(availability.CanInvoke);
        Assert.AreEqual(StopTurnActionPresentation.AvailableOpacity, availability.Opacity);
        Assert.AreEqual(StopTurnActionPresentation.ToolTip, availability.ToolTip);
        Assert.AreEqual("", availability.AccessibilityHint);
        Assert.IsNull(availability.UnavailableReason);
    }

    [TestMethod]
    public void AvailabilityKeepsUnavailableRunningHeaderClickableWithReason()
    {
        var availability = StopTurnActionPresentation.Availability(
            ThreadRunStatuses.Running,
            canStopTurn: false,
            isStoppingTurn: false);

        Assert.IsTrue(availability.IsVisible);
        Assert.IsTrue(availability.IsButtonEnabled);
        Assert.IsFalse(availability.CanInvoke);
        Assert.AreEqual(StopTurnActionPresentation.UnavailableOpacity, availability.Opacity);
        Assert.AreEqual(StopTurnActionPresentation.NotRunningOrDisconnectedReason, availability.ToolTip);
        Assert.AreEqual(StopTurnActionPresentation.NotRunningOrDisconnectedReason, availability.AccessibilityHint);
        Assert.AreEqual(StopTurnActionPresentation.NotRunningOrDisconnectedReason, availability.UnavailableReason);
    }

    [TestMethod]
    public void AvailabilityKeepsStoppingTurnVisibleWithStoppingAccessibility()
    {
        var availability = StopTurnActionPresentation.Availability(
            ThreadRunStatuses.Idle,
            canStopTurn: false,
            isStoppingTurn: true);

        Assert.IsTrue(availability.IsVisible);
        Assert.IsTrue(availability.IsButtonEnabled);
        Assert.IsFalse(availability.CanInvoke);
        Assert.IsTrue(availability.IsStoppingTurn);
        Assert.AreEqual(StopTurnActionPresentation.UnavailableOpacity, availability.Opacity);
        Assert.AreEqual(StopTurnActionPresentation.AlreadyStoppingReason, availability.ToolTip);
        Assert.AreEqual(StopTurnActionPresentation.StoppingAccessibilityName, availability.AccessibilityName);
        Assert.AreEqual(StopTurnActionPresentation.AlreadyStoppingReason, availability.AccessibilityHint);
    }

    [TestMethod]
    public void AvailabilityHidesIdleThreadWithoutStopCapability()
    {
        var availability = StopTurnActionPresentation.Availability(
            ThreadRunStatuses.Idle,
            canStopTurn: false,
            isStoppingTurn: false);

        Assert.IsFalse(availability.IsVisible);
        Assert.IsFalse(availability.IsButtonEnabled);
        Assert.IsFalse(availability.CanInvoke);
        Assert.AreEqual(StopTurnActionPresentation.AvailableOpacity, availability.Opacity);
    }
}
