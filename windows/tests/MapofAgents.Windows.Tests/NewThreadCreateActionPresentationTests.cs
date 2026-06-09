using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NewThreadCreateActionPresentationTests
{
    [TestMethod]
    public void AvailableTargetShowsMacReadyChipAndCreateAction()
    {
        var presentation = NewThreadCreateActionPresentation.Resolve(
            isCreating: false,
            unavailableReason: null);

        Assert.AreEqual("Ready for a new thread.", presentation.StatusText);
        Assert.IsTrue(presentation.IsButtonEnabled);
        Assert.AreEqual(1.0, presentation.ButtonOpacity, 0.001);
        Assert.AreEqual("Create thread", presentation.ToolTip);
    }

    [TestMethod]
    public void UnavailableTargetKeepsMacReadyChipAndClickableFeedbackAction()
    {
        var presentation = NewThreadCreateActionPresentation.Resolve(
            isCreating: false,
            unavailableReason: "Connect this machine before creating a chat.");

        Assert.AreEqual("Ready for a new thread.", presentation.StatusText);
        Assert.IsTrue(presentation.IsButtonEnabled);
        Assert.AreEqual(0.48, presentation.ButtonOpacity, 0.001);
        Assert.AreEqual("Connect this machine before creating a chat.", presentation.ToolTip);
    }

    [TestMethod]
    public void CreatingStateUsesMacCreatingChipWithoutDisablingFeedback()
    {
        var presentation = NewThreadCreateActionPresentation.Resolve(
            isCreating: true,
            unavailableReason: null);

        Assert.AreEqual("Creating the new thread...", presentation.StatusText);
        Assert.IsTrue(presentation.IsButtonEnabled);
        Assert.AreEqual(0.48, presentation.ButtonOpacity, 0.001);
        Assert.AreEqual("Creating this thread now.", presentation.ToolTip);
    }
}
