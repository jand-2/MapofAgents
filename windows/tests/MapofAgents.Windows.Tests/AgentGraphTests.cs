using System.Text.Json;
using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AgentGraphTests
{
    [TestMethod]
    public void StarterGraphMatchesMacStarterShapeWithOnlyLocalMachine()
    {
        var graph = AgentGraph.CreateStarter("DESKTOP-EXAMPLE");

        Assert.AreEqual(1, graph.Nodes.Count);
        Assert.AreEqual(0, graph.ManualEdges.Count);
        Assert.AreEqual(CanvasLayoutCoordinateSpaces.Center, graph.LayoutCoordinateSpace);
        var machine = graph.Nodes[LocalHostIdentity.LocalMachineNodeID];
        Assert.AreEqual(NodeKinds.Machine, machine.Kind);
        Assert.AreEqual(LocalHostIdentity.CanonicalHostID, machine.Metadata.HostID);
        Assert.AreEqual(HostPlatforms.Windows, machine.Metadata.Platform);
        Assert.AreEqual($"{HostPlatforms.Windows} - local", machine.Subtitle);
        Assert.AreEqual(120, machine.Position.X);
        Assert.AreEqual(100, machine.Position.Y);
        Assert.IsFalse(graph.Nodes.Values.Any(node => node.Kind == NodeKinds.Folder));
    }

    [TestMethod]
    public void LocalHostIdentityAcceptsCanonicalAndLegacyWindowsIDs()
    {
        Assert.IsTrue(LocalHostIdentity.IsLocalHostID("local"));
        Assert.IsTrue(LocalHostIdentity.IsLocalHostID("local-windows"));
        Assert.IsTrue(LocalHostIdentity.IsLocalHostID("localhost"));
        Assert.IsTrue(LocalHostIdentity.IsLocalHostID("127.0.0.1"));
        Assert.IsTrue(LocalHostIdentity.IsLocalHostID("DESKTOP-EXAMPLE", "desktop-example"));
        Assert.IsTrue(LocalHostIdentity.IsLocalHostID(null));
        Assert.IsFalse(LocalHostIdentity.IsLocalHostID("remote-windows", "desktop-example"));
    }

    [TestMethod]
    public void GraphRoundTripsAsJson()
    {
        var graph = AgentGraph.CreateStarter("DESKTOP-EXAMPLE");
        var thread = new CanvasNode
        {
            Id = "thread-example",
            Kind = NodeKinds.CodexThread,
            Title = "Thread",
            Metadata = new NodeMetadata
            {
                ThreadKind = ThreadKinds.Subagent,
                InitialPrompt = "Start here",
                IsArchived = true,
                IsUnread = true,
                LocalTranscript = new List<LocalThreadMessage>
                {
                    new LocalThreadMessage
                    {
                        Role = "user",
                        Text = "Start here",
                        CreatedAt = DateTimeOffset.Parse("2026-06-03T00:00:00Z")
                    }
                }
            }
        };
        graph.Nodes[thread.Id] = thread;
        graph.RuntimeDiagnostics.Add(new RuntimeDiagnosticStep
        {
            Id = "codex",
            Title = "Find Codex executable",
            Status = RuntimeDiagnosticStatuses.Passed,
            Detail = "codex found",
            Evidence = "/usr/local/bin/codex",
            Action = "updateCodexCLI"
        });
        var json = JsonSerializer.Serialize(graph, MapofAgentsJson.Options);
        var decoded = JsonSerializer.Deserialize<AgentGraph>(json, MapofAgentsJson.Options);

        Assert.IsNotNull(decoded);
        Assert.AreEqual(graph.Nodes.Count, decoded.Nodes.Count);
        Assert.AreEqual("mapofagents", decoded.Title);
        Assert.AreEqual("Start here", decoded.Nodes["thread-example"].Metadata.InitialPrompt);
        Assert.AreEqual(ThreadKinds.Subagent, decoded.Nodes["thread-example"].Metadata.ThreadKind);
        Assert.IsTrue(decoded.Nodes["thread-example"].Metadata.IsArchived);
        Assert.IsTrue(decoded.Nodes["thread-example"].Metadata.IsUnread);
        Assert.AreEqual(1, decoded.Nodes["thread-example"].Metadata.LocalTranscript.Count);
        Assert.AreEqual(1, decoded.RuntimeDiagnostics.Count);
        Assert.AreEqual("codex", decoded.RuntimeDiagnostics[0].Id);
        Assert.AreEqual(RuntimeDiagnosticStatuses.Passed, decoded.RuntimeDiagnostics[0].Status);
        Assert.AreEqual("codex found", decoded.RuntimeDiagnostics[0].Detail);
        Assert.AreEqual("/usr/local/bin/codex", decoded.RuntimeDiagnostics[0].Evidence);
        Assert.AreEqual("updateCodexCLI", decoded.RuntimeDiagnostics[0].Action);
    }

    [TestMethod]
    public void MessageRouteReadsMacRouteFields()
    {
        var json = """
        {
          "workspaceID": "workflow-route-test",
          "title": "route parity",
          "nodes": {},
          "manualEdges": {},
          "messageRoutes": {
            "route-1": {
              "id": "route-1",
              "sourceHostID": "mac-host",
              "sourceThreadID": "source-thread",
              "sourceTurnID": "turn-1",
              "sourceItemID": "item-1",
              "targetHostID": "windows-host",
              "targetThreadID": "target-thread",
              "targetTurnID": "target-turn",
              "timestamp": "2026-06-03T12:34:56Z",
              "snippet": "handoff from Mac to Windows",
              "deliveryState": "pending",
              "eventIDs": ["event-1", "event-2"],
              "canvasEdgeID": "edge-route"
            }
          },
          "suppressedAutoMaterializedThreadIDs": [],
          "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
          "updatedAt": "2026-06-03T12:35:00Z"
        }
        """;

        var graph = JsonSerializer.Deserialize<AgentGraph>(json, MapofAgentsJson.Options);

        Assert.IsNotNull(graph);
        var route = graph.MessageRoutes["route-1"];
        Assert.AreEqual("route-1", route.Id);
        Assert.AreEqual("mac-host", route.SourceHostID);
        Assert.AreEqual("source-thread", route.SourceThreadID);
        Assert.AreEqual("turn-1", route.SourceTurnID);
        Assert.AreEqual("item-1", route.SourceItemID);
        Assert.AreEqual("windows-host", route.TargetHostID);
        Assert.AreEqual("target-thread", route.TargetThreadID);
        Assert.AreEqual("target-turn", route.TargetTurnID);
        Assert.AreEqual(DateTimeOffset.Parse("2026-06-03T12:34:56Z"), route.Timestamp);
        Assert.AreEqual("handoff from Mac to Windows", route.Snippet);
        Assert.AreEqual(MessageRouteDeliveryStates.Pending, route.DeliveryState);
        CollectionAssert.AreEqual(new[] { "event-1", "event-2" }, route.EventIDs);
        Assert.AreEqual("edge-route", route.CanvasEdgeID);
    }

    [TestMethod]
    public async Task ControlRoomStoreMigratesLegacyTopLeftNodePositionsToCenters()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"mapofagents-test-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(directory);
            await File.WriteAllTextAsync(
                Path.Combine(directory, "workflows.json"),
                """
                {
                  "activeWorkflowID": "legacy-workflow",
                  "workflows": [
                    {
                      "id": "legacy-workflow",
                      "name": "Legacy",
                      "graph": {
                        "workspaceID": "legacy-workflow",
                        "title": "Legacy",
                        "nodes": {
                          "machine": {
                            "id": "machine",
                            "kind": "machine",
                            "title": "Machine",
                            "subtitle": "",
                            "position": { "x": 96, "y": 96 },
                            "size": { "width": 190, "height": 90 },
                            "metadata": { "platform": "windows" },
                            "zIndex": 0
                          }
                        },
                        "manualEdges": {},
                        "messageRoutes": {},
                        "pendingAttentionRequests": [],
                        "runtimeDiagnostics": [],
                        "suppressedAutoMaterializedThreadIDs": [],
                        "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
                        "updatedAt": "2026-06-04T00:00:00Z"
                      }
                    }
                  ]
                }
                """);

            var store = new ControlRoomStore(directory);
            var graph = await store.LoadOrCreateAsync();

            Assert.AreEqual(CanvasLayoutCoordinateSpaces.Center, graph.LayoutCoordinateSpace);
            Assert.AreEqual(191d, graph.Nodes["machine"].Position.X);
            Assert.AreEqual(141d, graph.Nodes["machine"].Position.Y);

            var persisted = await File.ReadAllTextAsync(Path.Combine(directory, "workflows.json"));
            StringAssert.Contains(persisted, "\"layoutCoordinateSpace\": \"center\"");
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    [TestMethod]
    public async Task ControlRoomStoreMaintainsWorkflowLibrary()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"mapofagents-test-{Guid.NewGuid():N}");
        try
        {
            var store = new ControlRoomStore(directory);
            var first = await store.LoadOrCreateAsync();
            var initialWorkflows = await store.LoadWorkflowsAsync();
            first.Title = "Primary";
            await store.SaveAsync(first);

            var second = await store.CreateWorkflowAsync("Second", "DESKTOP-EXAMPLE");
            var copy = await store.DuplicateActiveWorkflowAsync("Second Copy");
            var selected = await store.SelectWorkflowAsync(first.WorkspaceID);
            var deleted = await store.DeleteWorkflowAsync(second.WorkspaceID);
            var workflows = await store.LoadWorkflowsAsync();

            Assert.IsNotNull(selected);
            Assert.IsNotNull(deleted);
            Assert.AreEqual("Main Workflow", initialWorkflows.Single().Name);
            Assert.AreEqual("Primary", selected.Title);
            Assert.AreEqual(2, workflows.Count);
            Assert.IsTrue(workflows.Any(workflow => workflow.ID == first.WorkspaceID && workflow.IsActive));
            Assert.IsTrue(workflows.Any(workflow => workflow.ID == copy.WorkspaceID));
            Assert.IsFalse(workflows.Any(workflow => workflow.ID == second.WorkspaceID));
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

}
