using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Text.Json;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class WorkflowEventTests
{
    [TestMethod]
    public void WorkflowEventParserMapsSharedFolderCreatedFixture()
    {
        var line = File.ReadAllText(SharedWorkflowEventFixturePath("folder-created.json"));

        var workflowEvent = WorkflowEventParser.Parse(
            line,
            defaultHostID: "fallback",
            receivedAt: DateTimeOffset.Parse("2026-05-28T10:18:30Z"));

        Assert.IsNotNull(workflowEvent);
        Assert.AreEqual(WorkflowEventKinds.FolderCreated, workflowEvent.Kind);
        Assert.AreEqual("local", workflowEvent.HostID);
        Assert.AreEqual("source-thread", workflowEvent.ThreadID);
        Assert.AreEqual("turn-1", workflowEvent.TurnID);
        Assert.AreEqual("remote-windows", workflowEvent.ChildHostID);
        Assert.AreEqual(@"C:\Users\Example\Desktop", workflowEvent.ChildFolderPath);
        Assert.AreEqual("Desktop", workflowEvent.ChildTitle);
        Assert.AreEqual("folder/created", workflowEvent.Method);
        Assert.AreEqual("Created folder Desktop", workflowEvent.Summary);
        Assert.AreEqual(DateTimeOffset.Parse("2026-05-28T10:17:30Z"), workflowEvent.CreatedAt);
        Assert.AreEqual(
            WorkflowEvent.FolderCreatedID(
                "local",
                "source-thread",
                "remote-windows",
                @"C:\Users\Example\Desktop"),
            workflowEvent.DedupeKey);
    }

    [TestMethod]
    public void WorkflowEventIngestorMaterializesSharedFolderCreatedFixture()
    {
        var line = File.ReadAllText(SharedWorkflowEventFixturePath("folder-created.json"));
        var workflowEvent = WorkflowEventParser.Parse(line);
        Assert.IsNotNull(workflowEvent);
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
            }
        };
        graph.Nodes["source-thread-node"] = new CanvasNode
        {
            Id = "source-thread-node",
            Kind = NodeKinds.CodexThread,
            Title = "Source thread",
            Subtitle = "/Users/example/project",
            Position = new CanvasPoint(120, 330),
            Size = CanvasSize.Thread,
            Metadata = new NodeMetadata
            {
                HostID = "local",
                Platform = HostPlatforms.MacOS,
                ThreadRef = new ThreadRef
                {
                    HostID = "local",
                    ThreadID = "source-thread",
                    Cwd = "/Users/example/project",
                    Name = "Source thread"
                }
            }
        };

        var result = WorkflowEventIngestor.Apply(graph, workflowEvent!);

        Assert.IsTrue(result.Applied);
        Assert.IsFalse(string.IsNullOrWhiteSpace(result.NodeID));
        var folder = graph.Nodes[result.NodeID!];
        Assert.AreEqual(NodeKinds.Folder, folder.Kind);
        Assert.AreEqual("Desktop", folder.Title);
        Assert.AreEqual(@"C:\Users\Example\Desktop", folder.Metadata.FolderPath);
        Assert.AreEqual("remote-windows", folder.Metadata.HostID);
        Assert.AreEqual(HostPlatforms.Windows, folder.Metadata.Platform);
    }

    [TestMethod]
    public void WorkflowEventIngestorIgnoresFolderCreatedFromUnmappedThread()
    {
        var line = File.ReadAllText(SharedWorkflowEventFixturePath("folder-created.json"));
        var workflowEvent = WorkflowEventParser.Parse(line);
        Assert.IsNotNull(workflowEvent);
        var graph = AgentGraph.CreateStarter("DESKTOP-EXAMPLE");

        var result = WorkflowEventIngestor.Apply(graph, workflowEvent!);

        Assert.IsFalse(result.Applied);
        Assert.IsNull(result.NodeID);
        Assert.AreEqual("Ignored folder.created from unmapped source thread.", result.Message);
        Assert.IsFalse(graph.Nodes.Values.Any(node => node.Kind == NodeKinds.Folder));
    }

    [TestMethod]
    public void WorkflowEventParserIgnoresUnknownLines()
    {
        Assert.IsNull(WorkflowEventParser.Parse("not json", defaultHostID: "local"));
        Assert.IsNull(WorkflowEventParser.Parse("""{"event":"noise"}""", defaultHostID: "local"));
    }

    [TestMethod]
    public async Task WorkflowHookEventFileBridgeReplaysExistingEventsWhenRequested()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"mapofagents-hook-event-bridge-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(directory);
            var eventFilePath = Path.Combine(directory, "hook-events.jsonl");
            await File.WriteAllTextAsync(
                eventFilePath,
                SharedWorkflowEventFixtureLine("folder-created.json") + Environment.NewLine);
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            var completion = new TaskCompletionSource<IReadOnlyList<WorkflowEvent>>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var bridge = new WorkflowHookEventFileBridge(
                eventFilePath,
                pollInterval: TimeSpan.FromMilliseconds(25),
                defaultHostID: "fallback");

            var bridgeTask = bridge.RunAsync(
                (events, _) =>
                {
                    completion.TrySetResult(events);
                    return Task.CompletedTask;
                },
                replayExistingEvents: true,
                cancellation.Token);
            var completed = await Task.WhenAny(completion.Task, Task.Delay(TimeSpan.FromSeconds(4)));
            await cancellation.CancelAsync();
            await bridgeTask;

            Assert.AreEqual(completion.Task, completed);
            Assert.AreEqual(1, completion.Task.Result.Count);
            Assert.AreEqual(WorkflowEventKinds.FolderCreated, completion.Task.Result[0].Kind);
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
    public async Task WorkflowHookEventFileBridgeWaitsForCompleteAppendedLines()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"mapofagents-hook-event-bridge-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(directory);
            var eventFilePath = Path.Combine(directory, "hook-events.jsonl");
            await File.WriteAllTextAsync(eventFilePath, "");
            using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            var completion = new TaskCompletionSource<IReadOnlyList<WorkflowEvent>>(
                TaskCreationOptions.RunContinuationsAsynchronously);
            var bridge = new WorkflowHookEventFileBridge(
                eventFilePath,
                pollInterval: TimeSpan.FromMilliseconds(25),
                defaultHostID: "fallback");
            var line = SharedWorkflowEventFixtureLine("folder-created.json");
            var midpoint = line.Length / 2;

            var bridgeTask = bridge.RunAsync(
                (events, _) =>
                {
                    completion.TrySetResult(events);
                    return Task.CompletedTask;
                },
                replayExistingEvents: false,
                cancellation.Token);
            await Task.Delay(100, cancellation.Token);
            await File.AppendAllTextAsync(eventFilePath, line[..midpoint], cancellation.Token);
            await Task.Delay(100, cancellation.Token);
            Assert.IsFalse(completion.Task.IsCompleted);

            await File.AppendAllTextAsync(eventFilePath, line[midpoint..] + Environment.NewLine, cancellation.Token);
            var completed = await Task.WhenAny(completion.Task, Task.Delay(TimeSpan.FromSeconds(4)));
            await cancellation.CancelAsync();
            await bridgeTask;

            Assert.AreEqual(completion.Task, completed);
            Assert.AreEqual(1, completion.Task.Result.Count);
            Assert.AreEqual(@"C:\Users\Example\Desktop", completion.Task.Result[0].ChildFolderPath);
        }
        finally
        {
            if (Directory.Exists(directory))
            {
                Directory.Delete(directory, recursive: true);
            }
        }
    }

    private static string SharedWorkflowEventFixturePath(string fileName)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(
                directory.FullName,
                "shared",
                "workflow-events",
                "fixtures",
                fileName);
            if (File.Exists(candidate))
            {
                return candidate;
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Could not locate shared workflow event fixture {fileName}.");
    }

    private static string SharedWorkflowEventFixtureLine(string fileName)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(SharedWorkflowEventFixturePath(fileName)));
        return JsonSerializer.Serialize(document.RootElement);
    }
}
