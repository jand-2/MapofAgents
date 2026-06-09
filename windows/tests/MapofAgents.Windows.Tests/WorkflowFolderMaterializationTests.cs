using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class WorkflowFolderMaterializationTests
{
    [TestMethod]
    public void MaterializeWorkflowFolderRootCreatesFolderUnderMachine()
    {
        var graph = AgentGraph.CreateStarter("DESKTOP-EXAMPLE");
        graph.Nodes["remote-windows-machine"] = new CanvasNode
        {
            Id = "remote-windows-machine",
            Kind = NodeKinds.Machine,
            Title = "Windows Desktop",
            Subtitle = "windows - example-host.local",
            Position = new CanvasPoint(120, 100),
            Size = CanvasSize.Machine,
            Metadata = new NodeMetadata
            {
                HostID = "remote-windows",
                Platform = HostPlatforms.Windows,
                HostStatus = HostStatuses.Connected
            },
            ZIndex = 3
        };

        var folderID = graph.MaterializeWorkflowFolderRoot(
            @"C:\Users\Example\Desktop",
            "remote-windows",
            "Desktop");

        Assert.IsFalse(string.IsNullOrWhiteSpace(folderID));
        var folder = graph.Nodes[folderID!];
        Assert.AreEqual(NodeKinds.Folder, folder.Kind);
        Assert.AreEqual("Desktop", folder.Title);
        Assert.AreEqual(@"C:\Users\Example\Desktop", folder.Subtitle);
        Assert.AreEqual("remote-windows", folder.Metadata.HostID);
        Assert.AreEqual(HostPlatforms.Windows, folder.Metadata.Platform);
        Assert.AreEqual(@"C:\Users\Example\Desktop", folder.Metadata.FolderPath);
        Assert.AreEqual(false, folder.Metadata.HasManualPosition);
        Assert.AreEqual(4, folder.ZIndex);

        var semanticEdges = SemanticEdgeResolver.ResolveEdges(graph);
        Assert.IsTrue(semanticEdges.Any(edge =>
            edge.Kind == EdgeKinds.MachineFolder &&
            edge.Source == "remote-windows-machine" &&
            edge.Target == folderID));
    }

    [TestMethod]
    public void MaterializeWorkflowFolderRootIgnoresDescendantFolders()
    {
        var graph = AgentGraph.CreateStarter("DESKTOP-EXAMPLE");

        var rootID = graph.MaterializeWorkflowFolderRoot(
            "/Users/example/projects/root",
            LocalHostIdentity.CanonicalHostID,
            "root");
        var descendantID = graph.MaterializeWorkflowFolderRoot(
            "/Users/example/projects/root/subproject",
            LocalHostIdentity.CanonicalHostID,
            "subproject");

        var folders = graph.Nodes.Values
            .Where(node =>
                node.Kind == NodeKinds.Folder &&
                node.Metadata.HostID == LocalHostIdentity.CanonicalHostID)
            .ToList();
        Assert.IsNotNull(rootID);
        Assert.IsNull(descendantID);
        Assert.AreEqual(1, folders.Count);
        Assert.AreEqual(rootID, folders[0].Id);
        Assert.AreEqual("/Users/example/projects/root", folders[0].Metadata.FolderPath);
    }

    [TestMethod]
    public void MaterializeWorkflowFolderRootUpdatesExistingWindowsFolderPath()
    {
        var graph = AgentGraph.CreateStarter("DESKTOP-EXAMPLE");

        var firstID = graph.MaterializeWorkflowFolderRoot(
            @"C:\Users\Example\Desktop\",
            LocalHostIdentity.CanonicalHostID,
            "Desktop");
        var secondID = graph.MaterializeWorkflowFolderRoot(
            "c:/users/example/desktop",
            LocalHostIdentity.CanonicalHostID,
            "Desktop");

        var folders = graph.Nodes.Values
            .Where(node => node.Kind == NodeKinds.Folder)
            .ToList();
        Assert.IsNotNull(firstID);
        Assert.AreEqual(firstID, secondID);
        Assert.AreEqual(1, folders.Count);
        Assert.AreEqual("c:/users/example/desktop", folders[0].Subtitle);
        Assert.AreEqual("c:/users/example/desktop", folders[0].Metadata.FolderPath);
    }
}
