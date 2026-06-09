using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineFolderActionPolicyTests
{
    [TestMethod]
    public void LocalDisconnectedMachineCanUseProjectFolderPicker()
    {
        var machine = Machine(HostStatuses.Disconnected);

        Assert.IsTrue(MachineFolderActionPolicy.CanChooseProjectFolder(machine, isLocalHost: true, hasRemoteBrowser: false));
        Assert.IsTrue(MachineFolderActionPolicy.CanAddFolderFromMachine(machine, isLocalHost: true, hasRemoteBrowser: false));
        Assert.IsNull(MachineFolderActionPolicy.UnavailableReason(machine, isLocalHost: true, hasRemoteBrowser: false));
    }

    [TestMethod]
    public void BrowsableRemoteMachineCanUseProjectFolderPickerBeforeConnection()
    {
        var machine = Machine(HostStatuses.Disconnected);

        Assert.IsTrue(MachineFolderActionPolicy.CanChooseProjectFolder(machine, isLocalHost: false, hasRemoteBrowser: true));
        Assert.IsTrue(MachineFolderActionPolicy.CanAddFolderFromMachine(machine, isLocalHost: false, hasRemoteBrowser: true));
        Assert.IsNull(MachineFolderActionPolicy.UnavailableReason(machine, isLocalHost: false, hasRemoteBrowser: true));
    }

    [TestMethod]
    public void ConnectedRemoteMachineCanAddProjectFolderManually()
    {
        var machine = Machine(HostStatuses.Connected);

        Assert.IsFalse(MachineFolderActionPolicy.CanChooseProjectFolder(machine, isLocalHost: false, hasRemoteBrowser: false));
        Assert.IsTrue(MachineFolderActionPolicy.CanAddFolderFromMachine(machine, isLocalHost: false, hasRemoteBrowser: false));
        Assert.IsNull(MachineFolderActionPolicy.UnavailableReason(machine, isLocalHost: false, hasRemoteBrowser: false));
    }

    [TestMethod]
    public void DisconnectedRemoteMachineWithoutBrowserNeedsConnection()
    {
        var machine = Machine(HostStatuses.Disconnected);

        Assert.IsFalse(MachineFolderActionPolicy.CanChooseProjectFolder(machine, isLocalHost: false, hasRemoteBrowser: false));
        Assert.IsFalse(MachineFolderActionPolicy.CanAddFolderFromMachine(machine, isLocalHost: false, hasRemoteBrowser: false));
        Assert.AreEqual(
            "Connect this machine before adding a project folder.",
            MachineFolderActionPolicy.UnavailableReason(machine, isLocalHost: false, hasRemoteBrowser: false));
    }

    private static CanvasNode Machine(string status)
    {
        return new CanvasNode
        {
            Kind = NodeKinds.Machine,
            Metadata = new NodeMetadata
            {
                HostStatus = status
            }
        };
    }
}
