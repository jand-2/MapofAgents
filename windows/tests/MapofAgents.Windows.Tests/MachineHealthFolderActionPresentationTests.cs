using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineHealthFolderActionPresentationTests
{
    [TestMethod]
    public void LocalMachineHidesTheRemoteFolderAction()
    {
        var presentation = MachineHealthFolderActionPresentation.Resolve(
            isLocal: true,
            HostStatuses.Connected,
            hasRemoteBrowser: false);

        Assert.IsFalse(presentation.IsVisible);
        Assert.IsFalse(presentation.CanInvoke);
        Assert.AreEqual("Use Folder to add a local project.", presentation.ToolTip);
        Assert.AreEqual(1.0, presentation.Opacity, 0.001);
    }

    [TestMethod]
    public void DisconnectedRemoteStaysClickableButDimmedForFeedback()
    {
        var presentation = MachineHealthFolderActionPresentation.Resolve(
            isLocal: false,
            HostStatuses.Disconnected,
            hasRemoteBrowser: false);

        Assert.IsTrue(presentation.IsVisible);
        Assert.IsFalse(presentation.CanInvoke);
        Assert.AreEqual("Connect this machine before adding a folder.", presentation.ToolTip);
        Assert.AreEqual(0.48, presentation.Opacity, 0.001);
        Assert.AreEqual("folder.badge.plus", presentation.MacSymbolName);
    }

    [TestMethod]
    public void ConnectedRemoteWithoutBrowserUsesMacAddFolderCopy()
    {
        var presentation = MachineHealthFolderActionPresentation.Resolve(
            isLocal: false,
            HostStatuses.Connected,
            hasRemoteBrowser: false);

        Assert.IsTrue(presentation.IsVisible);
        Assert.IsTrue(presentation.CanInvoke);
        Assert.AreEqual("Add folder", presentation.ToolTip);
        Assert.AreEqual(1.0, presentation.Opacity, 0.001);
        Assert.AreEqual("folder.badge.plus", presentation.MacSymbolName);
    }

    [TestMethod]
    public void BrowsableRemoteUsesMacBrowseFolderCopy()
    {
        var presentation = MachineHealthFolderActionPresentation.Resolve(
            isLocal: false,
            HostStatuses.Connected,
            hasRemoteBrowser: true);

        Assert.IsTrue(presentation.IsVisible);
        Assert.IsTrue(presentation.CanInvoke);
        Assert.AreEqual("Browse project folders", presentation.ToolTip);
        Assert.AreEqual("folder", presentation.MacSymbolName);
    }
}
