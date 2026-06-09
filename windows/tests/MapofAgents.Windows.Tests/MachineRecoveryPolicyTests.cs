using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineRecoveryPolicyTests
{
    [TestMethod]
    public void StarterLocalDisconnectedMachineDoesNotNeedRecovery()
    {
        var graph = AgentGraph.CreateStarter("Windows PC");
        var machine = graph.Nodes[LocalHostIdentity.LocalMachineNodeID];

        Assert.IsFalse(MachineRecoveryPolicy.NeedsRecovery(machine, isLocalHost: true));
    }

    [TestMethod]
    public void RemoteDisconnectedMachineWithoutSavedEndpointDoesNotNeedRecovery()
    {
        var machine = Machine("remote", HostStatuses.Disconnected);

        Assert.IsFalse(MachineRecoveryPolicy.NeedsRecovery(machine, isLocalHost: false));
    }

    [TestMethod]
    public void RemoteDisconnectedMachineWithSavedEndpointNeedsRecovery()
    {
        var machine = Machine("remote", HostStatuses.Disconnected);
        machine.Metadata.AppServerEndpointUrl = "ws://127.0.0.1:14500";

        Assert.IsTrue(MachineRecoveryPolicy.NeedsRecovery(machine, isLocalHost: false));
    }

    [TestMethod]
    public void ConnectingOrUnavailableMachinesNeedRecovery()
    {
        Assert.IsTrue(MachineRecoveryPolicy.NeedsRecovery(Machine("connecting", HostStatuses.Connecting), isLocalHost: false));
        Assert.IsTrue(MachineRecoveryPolicy.NeedsRecovery(Machine("failed", HostStatuses.Unavailable), isLocalHost: false));
    }

    [TestMethod]
    public void NonMachineNodesDoNotNeedRecovery()
    {
        var folder = new CanvasNode { Id = "folder", Kind = NodeKinds.Folder };

        Assert.IsFalse(MachineRecoveryPolicy.NeedsRecovery(folder, isLocalHost: false));
    }

    private static CanvasNode Machine(string id, string status)
    {
        return new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.Machine,
            Metadata = new NodeMetadata
            {
                HostID = id,
                HostStatus = status
            }
        };
    }
}
