using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class LoadOlderMessagesActionPresentationTests
{
    [TestMethod]
    public void HiddenWhenThereIsNoOlderCursor()
    {
        var presentation = LoadOlderMessagesActionPresentation.Resolve(
            hasOlderCursor: false,
            isLoadingOlder: false);

        Assert.IsFalse(presentation.IsVisible);
        Assert.IsFalse(presentation.IsButtonEnabled);
        Assert.AreEqual("Show older messages", presentation.ButtonText);
        Assert.IsFalse(presentation.ShowsIdleIcon);
        Assert.IsNull(presentation.UnavailableReason);
    }

    [TestMethod]
    public void AvailableCursorMatchesMacPlainFeedbackButton()
    {
        var presentation = LoadOlderMessagesActionPresentation.Resolve(
            hasOlderCursor: true,
            isLoadingOlder: false);

        Assert.IsTrue(presentation.IsVisible);
        Assert.IsTrue(presentation.IsButtonEnabled);
        Assert.AreEqual(1.0, presentation.Opacity, 0.001);
        Assert.IsFalse(presentation.ShowsProgress);
        Assert.IsFalse(presentation.ShowsIdleIcon);
        Assert.AreEqual("Show older messages", presentation.ButtonText);
        Assert.AreEqual("Show older messages", presentation.ToolTip);
        Assert.AreEqual("", presentation.AccessibilityHint);
        Assert.AreEqual(28, presentation.ButtonMinHeight, 0.001);
        Assert.AreEqual(7, presentation.ButtonHorizontalPadding, 0.001);
        Assert.AreEqual(3, presentation.ButtonVerticalPadding, 0.001);
        Assert.AreEqual(6, presentation.ContentSpacing, 0.001);
        Assert.AreEqual(14, presentation.ProgressRingSize, 0.001);
        Assert.AreEqual(11, presentation.IdleIconFontSize, 0.001);
        Assert.AreEqual(12, presentation.TextFontSize, 0.001);
    }

    [TestMethod]
    public void LoadingOlderStaysClickableDimmedAndExplainsTheWait()
    {
        var presentation = LoadOlderMessagesActionPresentation.Resolve(
            hasOlderCursor: true,
            isLoadingOlder: true);

        Assert.IsTrue(presentation.IsVisible);
        Assert.IsTrue(presentation.IsButtonEnabled);
        Assert.AreEqual(0.48, presentation.Opacity, 0.001);
        Assert.IsTrue(presentation.ShowsProgress);
        Assert.IsFalse(presentation.ShowsIdleIcon);
        Assert.AreEqual("Loading older messages", presentation.ButtonText);
        Assert.AreEqual("Older messages are already loading.", presentation.ToolTip);
        Assert.AreEqual("Older messages are already loading.", presentation.AccessibilityHint);
        Assert.AreEqual("Older messages are already loading.", presentation.UnavailableReason);
    }
}
