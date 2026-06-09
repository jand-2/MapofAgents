using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class SemanticEdgeResolverTests
{
    [TestMethod]
    public void ResolvesMachineFolderAndMostSpecificFolderThreadEdges()
    {
        var graph = GraphWith(
            Machine("machine", "host-a"),
            Folder("root", "host-a", @"C:\Users\example"),
            Folder("repo", "host-a", @"C:\Users\example\Repo"),
            Thread("thread", "host-a", @"c:\users\example\repo\src"));

        var edges = SemanticEdgeResolver.ResolveEdges(graph);

        AssertEdge(edges, "machine", "root", EdgeKinds.MachineFolder);
        AssertEdge(edges, "machine", "repo", EdgeKinds.MachineFolder);
        AssertEdge(edges, "repo", "thread", EdgeKinds.FolderThread);
        AssertNoEdge(edges, "machine", "thread", EdgeKinds.MachineThread);
    }

    [TestMethod]
    public void ResolvesMachineThreadWhenNoFolderMatches()
    {
        var graph = GraphWith(
            Machine("machine", "host-a"),
            Folder("repo", "host-a", @"C:\Users\example\Repo"),
            Thread("thread", "host-a", @"D:\scratch"));

        var edges = SemanticEdgeResolver.ResolveEdges(graph);

        AssertEdge(edges, "machine", "repo", EdgeKinds.MachineFolder);
        AssertEdge(edges, "machine", "thread", EdgeKinds.MachineThread);
        AssertNoEdge(edges, "repo", "thread", EdgeKinds.FolderThread);
    }

    [TestMethod]
    public void SkipsSubagentThreadsLikeMacSemanticResolver()
    {
        var graph = GraphWith(
            Machine("machine", "host-a"),
            Folder("repo", "host-a", "/Users/example/repo"),
            Thread("agent", "host-a", "/Users/example/repo", ThreadKinds.Subagent));

        var edges = SemanticEdgeResolver.ResolveEdges(graph);

        AssertEdge(edges, "machine", "repo", EdgeKinds.MachineFolder);
        AssertNoEdge(edges, "repo", "agent", EdgeKinds.FolderThread);
        AssertNoEdge(edges, "machine", "agent", EdgeKinds.MachineThread);
    }

    [TestMethod]
    public void DeduplicatesEdgesAlreadyStoredInWindowsManualEdges()
    {
        var graph = GraphWith(
            Machine("machine", "host-a"),
            Folder("repo", "host-a", @"C:\Users\example\Repo"),
            Thread("thread", "host-a", @"C:\Users\example\Repo"));
        graph.ManualEdges["existing-folder-thread"] = new CanvasEdge
        {
            Id = "existing-folder-thread",
            Source = "repo",
            Target = "thread",
            Kind = EdgeKinds.FolderThread,
            IsManual = false
        };

        var semanticEdges = SemanticEdgeResolver.ResolveEdges(graph);
        var allEdges = SemanticEdgeResolver.AllEdges(graph);

        AssertNoEdge(semanticEdges, "repo", "thread", EdgeKinds.FolderThread);
        Assert.AreEqual(1, allEdges.Count(edge =>
            edge.Source == "repo" &&
            edge.Target == "thread" &&
            edge.Kind == EdgeKinds.FolderThread));
    }

    private static AgentGraph GraphWith(params CanvasNode[] nodes)
    {
        var graph = new AgentGraph();
        foreach (var node in nodes)
        {
            graph.Nodes[node.Id] = node;
        }

        return graph;
    }

    private static CanvasNode Machine(string id, string hostId)
    {
        return new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.Machine,
            Title = id,
            Metadata = new NodeMetadata
            {
                HostID = hostId,
                Platform = HostPlatforms.Windows
            }
        };
    }

    private static CanvasNode Folder(string id, string hostId, string path)
    {
        return new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.Folder,
            Title = id,
            Metadata = new NodeMetadata
            {
                HostID = hostId,
                Platform = HostPlatforms.Windows,
                FolderPath = path
            }
        };
    }

    private static CanvasNode Thread(
        string id,
        string hostId,
        string cwd,
        string threadKind = ThreadKinds.Thread)
    {
        return new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.CodexThread,
            Title = id,
            Metadata = new NodeMetadata
            {
                HostID = hostId,
                Platform = HostPlatforms.Windows,
                ThreadKind = threadKind,
                ThreadRef = new ThreadRef
                {
                    HostID = hostId,
                    ThreadID = id,
                    Cwd = cwd,
                    Name = id
                }
            }
        };
    }

    private static void AssertEdge(
        IReadOnlyList<CanvasEdge> edges,
        string source,
        string target,
        string kind)
    {
        Assert.IsTrue(
            edges.Any(edge => edge.Source == source && edge.Target == target && edge.Kind == kind),
            $"Expected {kind} edge from {source} to {target}.");
    }

    private static void AssertNoEdge(
        IReadOnlyList<CanvasEdge> edges,
        string source,
        string target,
        string kind)
    {
        Assert.IsFalse(
            edges.Any(edge => edge.Source == source && edge.Target == target && edge.Kind == kind),
            $"Did not expect {kind} edge from {source} to {target}.");
    }
}
