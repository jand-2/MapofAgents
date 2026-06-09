using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarFeedbackButtonPresentationTests
{
    [TestMethod]
    public void AvailableButtonMatchesMacFeedbackButtonDefaultState()
    {
        var presentation = ToolbarFeedbackButtonPresentation.Resolve(
            unavailableReason: null,
            availableToolTip: "Create Codex thread");

        Assert.AreEqual(1.0, presentation.Opacity, 0.001);
        Assert.AreEqual("Create Codex thread", presentation.ToolTip);
        Assert.AreEqual("", presentation.AccessibilityHint);
        Assert.AreEqual("", presentation.AccessibilityValue);
    }

    [TestMethod]
    public void UnavailableButtonMatchesMacFeedbackButtonReasonState()
    {
        var presentation = ToolbarFeedbackButtonPresentation.Resolve(
            unavailableReason: " Add or connect a machine. ",
            availableToolTip: "Create Codex thread");

        Assert.AreEqual(0.48, presentation.Opacity, 0.001);
        Assert.AreEqual("Add or connect a machine.", presentation.ToolTip);
        Assert.AreEqual("Add or connect a machine.", presentation.AccessibilityHint);
        Assert.AreEqual("Unavailable: Add or connect a machine.", presentation.AccessibilityValue);
    }
}
