using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class GraphNodeActionPresentationTests
{
    [TestMethod]
    public void BrowsableMachineUsesChooseProjectCopy()
    {
        var presentation = GraphNodeActionPresentation.FolderAction(
            canChooseProjectFolder: true,
            canAddFolderFromMachine: true);

        Assert.AreEqual("Choose project from this machine", presentation.ToolTip);
        Assert.AreEqual(string.Empty, presentation.CssClass);
        Assert.IsFalse(presentation.IsAriaDisabled);
        Assert.AreEqual(1.0, presentation.Opacity, 0.001);
    }

    [TestMethod]
    public void ConnectedMachineUsesManualAddCopy()
    {
        var presentation = GraphNodeActionPresentation.FolderAction(
            canChooseProjectFolder: false,
            canAddFolderFromMachine: true);

        Assert.AreEqual("Add project from this machine", presentation.ToolTip);
        Assert.AreEqual(string.Empty, presentation.CssClass);
        Assert.IsFalse(presentation.IsAriaDisabled);
        Assert.AreEqual(1.0, presentation.Opacity, 0.001);
    }

    [TestMethod]
    public void UnavailableMachineKeepsMacFeedbackOpacity()
    {
        var presentation = GraphNodeActionPresentation.FolderAction(
            canChooseProjectFolder: false,
            canAddFolderFromMachine: false);

        Assert.AreEqual("Connect this machine before adding a project folder.", presentation.ToolTip);
        Assert.AreEqual("unavailable", presentation.CssClass);
        Assert.IsTrue(presentation.IsAriaDisabled);
        Assert.AreEqual(0.48, presentation.Opacity, 0.001);
    }

    [TestMethod]
    public void WebConfigExposesTheSameMacFeedbackTreatment()
    {
        var config = GraphNodeActionPresentation.FolderActionWebConfig();

        Assert.AreEqual("Choose project from this machine", config.ChooseProjectToolTip);
        Assert.AreEqual("Add project from this machine", config.AddProjectToolTip);
        Assert.AreEqual("Connect this machine before adding a project folder.", config.UnavailableToolTip);
        Assert.AreEqual("unavailable", config.UnavailableCssClass);
        Assert.IsTrue(config.UnavailableAriaDisabled);
        Assert.AreEqual(1.0, config.AvailableOpacity, 0.001);
        Assert.AreEqual(0.48, config.UnavailableOpacity, 0.001);
    }
}
