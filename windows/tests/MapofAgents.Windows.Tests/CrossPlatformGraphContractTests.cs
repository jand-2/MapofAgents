using System.Text.Json;
using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class CrossPlatformGraphContractTests
{
    [DataTestMethod]
    [DataRow("sample-cross-platform-graph.json")]
    [DataRow("sample-cross-platform-graph.apple-golden.json")]
    public void SharedGraphFixturesRoundTripCanonicalContract(string fixtureName)
    {
        var fixturePath = RepositoryFile(
            "shared",
            "protocol",
            "fixtures",
            fixtureName);
        var graph = JsonSerializer.Deserialize<AgentGraph>(
            File.ReadAllText(fixturePath),
            MapofAgentsJson.Options);

        Assert.IsNotNull(graph);
        if (fixtureName == "sample-cross-platform-graph.json")
        {
            Assert.AreEqual(
                "18212dbe409170c6",
                CanonicalJsonSemanticFingerprint(fixturePath));
        }
        var thread = graph.Nodes["thread-example"];
        var machine = graph.Nodes["machine-example"];
        var codexThread = graph.Nodes["thread-codex-example"];
        var edge = graph.ManualEdges["edge-example"];
        var stringRequest = graph.PendingAttentionRequests.Single(request => request.Id == "attention-1");
        var numericRequest = graph.PendingAttentionRequests.Single(request => request.Id == "attention-2");
        Assert.IsNotNull(thread.Metadata.ThreadRef);
        Assert.IsNotNull(thread.Metadata.ThreadPermissions);
        Assert.AreEqual("workflow-example", graph.WorkspaceID);
        Assert.AreEqual("Cross-platform example", graph.Title);
        Assert.AreEqual(CanvasLayoutCoordinateSpaces.Center, graph.LayoutCoordinateSpace);
        CollectionAssert.AreEquivalent(
            new[] { "machine-example", "thread-example", "thread-codex-example" },
            graph.Nodes.Keys.ToArray());
        Assert.AreEqual("machine-example", machine.Id);
        Assert.AreEqual(NodeKinds.Machine, machine.Kind);
        Assert.AreEqual("Example host", machine.Title);
        Assert.AreEqual("Unavailable", machine.Subtitle);
        Assert.AreEqual(80.25, machine.Position.X);
        Assert.AreEqual(64.5, machine.Position.Y);
        Assert.AreEqual(190, machine.Size.Width);
        Assert.AreEqual(90, machine.Size.Height);
        Assert.AreEqual(0, machine.ZIndex);
        Assert.AreEqual("example-host", machine.Metadata.HostID);
        Assert.AreEqual(HostPlatforms.Windows, machine.Metadata.Platform);
        Assert.AreEqual(HostStatuses.Unavailable, machine.Metadata.HostStatus);
        Assert.AreEqual("Example transient connection error", machine.Metadata.HostLastError);
        Assert.AreEqual(@"C:\Users\example\.codex", machine.Metadata.CodexHome);
        Assert.AreEqual("wss://example-host.local/app-server", machine.Metadata.AppServerEndpointUrl);
        Assert.IsNull(machine.Metadata.FolderPath);
        Assert.IsNull(machine.Metadata.ThreadRef);
        Assert.AreEqual(0, machine.Metadata.LocalTranscript.Count);
        Assert.AreEqual(0, machine.Metadata.LocalTranscriptTurns.Count);

        Assert.AreEqual("thread-example", thread.Id);
        Assert.AreEqual(NodeKinds.CodexThread, thread.Kind);
        Assert.AreEqual("Example thread", thread.Title);
        Assert.AreEqual("Ready", thread.Subtitle);
        Assert.AreEqual(240.5, thread.Position.X);
        Assert.AreEqual(180, thread.Position.Y);
        Assert.AreEqual(200, thread.Size.Width);
        Assert.AreEqual(132, thread.Size.Height);
        Assert.AreEqual(1, thread.ZIndex);
        Assert.AreEqual("example-host", thread.Metadata.HostID);
        Assert.AreEqual(HostPlatforms.Windows, thread.Metadata.Platform);
        Assert.AreEqual(HostStatuses.Connected, thread.Metadata.HostStatus);
        Assert.AreEqual(AgentProviders.Gemini, thread.Metadata.ThreadRef.Provider);
        Assert.AreEqual("example-host", thread.Metadata.ThreadRef.HostID);
        Assert.AreEqual("thread-17", thread.Metadata.ThreadRef.ThreadID);
        Assert.AreEqual(@"C:\Users\example\project", thread.Metadata.ThreadRef.Cwd);
        Assert.AreEqual("Example thread", thread.Metadata.ThreadRef.Name);
        Assert.AreEqual(AgentProviders.Codex, codexThread.Metadata.ThreadRef?.Provider);
        Assert.AreEqual(
            thread.Metadata.ThreadRef.HostID,
            codexThread.Metadata.ThreadRef?.HostID);
        Assert.AreEqual(
            thread.Metadata.ThreadRef.ThreadID,
            codexThread.Metadata.ThreadRef?.ThreadID);
        Assert.AreNotEqual(
            thread.Metadata.ThreadRef.QualifiedID,
            codexThread.Metadata.ThreadRef?.QualifiedID);
        Assert.IsFalse(thread.Metadata.ThreadRef.Matches(codexThread.Metadata.ThreadRef!));
        Assert.AreEqual("example-model", thread.Metadata.Model);
        Assert.AreEqual("medium", thread.Metadata.ReasoningEffort);
        Assert.AreEqual(
            AgentApprovalPolicies.OnRequest,
            thread.Metadata.ThreadPermissions.ApprovalPolicy);
        Assert.AreEqual(
            AgentSandboxModes.WorkspaceWrite,
            thread.Metadata.ThreadPermissions.SandboxMode);
        Assert.AreEqual("Hello", thread.Metadata.InitialPrompt);
        Assert.AreEqual(ThreadKinds.Thread, thread.Metadata.ThreadKind);
        Assert.AreEqual(ThreadRunStatuses.Idle, thread.Metadata.RunStatus);
        Assert.AreEqual(false, thread.Metadata.IsUnread);
        Assert.AreEqual(false, thread.Metadata.IsArchived);
        Assert.AreEqual(true, thread.Metadata.HasManualPosition);
        CollectionAssert.AreEqual(
            new[] { "user", "file" },
            thread.Metadata.LocalTranscript.Select(message => message.Role).ToArray());
        CollectionAssert.AreEqual(
            new[] { "turn-1" },
            thread.Metadata.LocalTranscriptTurns.Select(turn => turn.Id).ToArray());
        var firstMessage = thread.Metadata.LocalTranscript[0];
        var attachmentMessage = thread.Metadata.LocalTranscript[1];
        Assert.AreEqual("message-1", firstMessage.Id);
        Assert.AreEqual("Hello", firstMessage.Text);
        Assert.AreEqual(1_780_358_400_125, firstMessage.CreatedAt.ToUnixTimeMilliseconds());
        Assert.AreEqual("attachment-1", attachmentMessage.Id);
        Assert.AreEqual("file", attachmentMessage.Role);
        Assert.AreEqual("File artifact: example.txt", attachmentMessage.Text);
        Assert.AreEqual(1_780_358_430_000, attachmentMessage.CreatedAt.ToUnixTimeMilliseconds());
        var turn = thread.Metadata.LocalTranscriptTurns[0];
        Assert.AreEqual(ThreadRunStatuses.Complete, turn.Status);
        Assert.AreEqual(1_780_358_400_000, turn.StartedAt.ToUnixTimeMilliseconds());
        Assert.AreEqual(
            1_780_358_430_000,
            turn.CompletedAt?.ToUnixTimeMilliseconds());
        Assert.IsNull(turn.Error);
        Assert.AreEqual(ThreadTurnItemsViews.Full, turn.ItemsView);
        Assert.AreEqual(30_000, turn.DurationMilliseconds);
        CollectionAssert.AreEqual(
            new[] { "message-1", "attachment-1" },
            turn.ItemMessageIds.ToArray());
        CollectionAssert.AreEqual(
            new[] { "attention-1", "attention-2" },
            graph.PendingAttentionRequests.Select(request => request.Id).ToArray());
        Assert.AreEqual("thread-example", edge.Source);
        Assert.AreEqual("thread-codex-example", edge.Target);
        Assert.AreEqual(EdgeKinds.ManualNote, edge.Kind);
        Assert.IsTrue(edge.IsManual);
        Assert.AreEqual("Compare providers", edge.Label);
        var route = graph.MessageRoutes["route-1"];
        Assert.AreEqual("route-1", route.Id);
        Assert.AreEqual("example-host", route.SourceHostID);
        Assert.AreEqual("thread-17", route.SourceThreadID);
        Assert.IsNull(route.SourceTurnID);
        Assert.IsNull(route.SourceItemID);
        Assert.AreEqual("example-host", route.TargetHostID);
        Assert.AreEqual("thread-18", route.TargetThreadID);
        Assert.IsNull(route.TargetTurnID);
        Assert.AreEqual(1_780_358_460_000, route.Timestamp.ToUnixTimeMilliseconds());
        Assert.AreEqual("Example handoff", route.Snippet);
        Assert.AreEqual(MessageRouteDeliveryStates.Delivered, route.DeliveryState);
        CollectionAssert.AreEqual(new[] { "event-1" }, route.EventIDs.ToArray());
        Assert.IsNull(route.CanvasEdgeID);

        Assert.AreEqual("example-host", stringRequest.HostID);
        Assert.AreEqual("approval-1", stringRequest.RequestID?.StringValue);
        Assert.AreEqual(
            "item/commandExecution/requestApproval",
            stringRequest.Method);
        Assert.AreEqual("thread-17", stringRequest.ThreadID);
        Assert.AreEqual("turn-1", stringRequest.TurnID);
        Assert.AreEqual("Approve example command", stringRequest.Summary);
        Assert.AreEqual("Approve example command", stringRequest.Prompt);
        CollectionAssert.AreEqual(
            new[] { "accept", "decline" },
            stringRequest.ResponseChoices.Select(choice => choice.Value).ToArray());
        Assert.AreEqual(
            1_780_358_415_000,
            stringRequest.CreatedAt.ToUnixTimeMilliseconds());
        Assert.AreEqual("example-host", numericRequest.HostID);
        Assert.AreEqual(17L, numericRequest.RequestID?.IntegerValue);
        Assert.AreEqual("item/tool/requestUserInput", numericRequest.Method);
        Assert.AreEqual("thread-17", numericRequest.ThreadID);
        Assert.AreEqual("turn-1", numericRequest.TurnID);
        Assert.AreEqual("Choose a safe mode", numericRequest.Summary);
        Assert.AreEqual("Choose a safe mode", numericRequest.Prompt);
        CollectionAssert.AreEqual(
            new[] { "workspace-write", "read-only" },
            numericRequest.ResponseChoices.Select(choice => choice.Value).ToArray());
        Assert.AreEqual(
            1_780_358_416_500,
            numericRequest.CreatedAt.ToUnixTimeMilliseconds());
        Assert.IsNull(numericRequest.RequestParams);
        CollectionAssert.AreEqual(
            new[] { "runtime" },
            graph.RuntimeDiagnostics.Select(step => step.Id).ToArray());
        var diagnostic = graph.RuntimeDiagnostics[0];
        Assert.AreEqual("Runtime", diagnostic.Title);
        Assert.AreEqual(RuntimeDiagnosticStatuses.Passed, diagnostic.Status);
        Assert.AreEqual("Ready", diagnostic.Detail);
        Assert.AreEqual("Fixture", diagnostic.Evidence);
        Assert.IsNull(diagnostic.Action);
        Assert.AreEqual(0, graph.SuppressedAutoMaterializedThreadIDs.Count);
        Assert.AreEqual(1, graph.Viewport.Scale);
        Assert.AreEqual(0, graph.Viewport.Offset.X);
        Assert.AreEqual(0, graph.Viewport.Offset.Y);
        Assert.AreEqual(
            DateTimeOffset.Parse("2026-06-02T00:02:00.125Z"),
            graph.UpdatedAt.ToUniversalTime());

        var encoded = JsonSerializer.Serialize(graph, MapofAgentsJson.Options);
        using var encodedDocument = JsonDocument.Parse(encoded);
        var metadata = encodedDocument.RootElement
            .GetProperty("nodes")
            .GetProperty("thread-example")
            .GetProperty("metadata");
        var encodedPermissions = metadata.GetProperty("threadPermissions");
        var encodedThreadRef = metadata.GetProperty("threadRef");

        Assert.AreEqual(
            AgentApprovalPolicies.OnRequest,
            encodedPermissions.GetProperty("approvalPolicy").GetString());
        Assert.AreEqual(
            AgentSandboxModes.WorkspaceWrite,
            encodedPermissions.GetProperty("sandboxMode").GetString());
        Assert.IsFalse(metadata.TryGetProperty("approvalPolicy", out _));
        Assert.IsFalse(metadata.TryGetProperty("sandboxMode", out _));
        Assert.AreEqual(
            AgentProviders.Gemini,
            encodedThreadRef.GetProperty("provider").GetString());
        foreach (var attention in encodedDocument.RootElement
                     .GetProperty("pendingAttentionRequests")
                     .EnumerateArray())
        {
            Assert.IsFalse(attention.TryGetProperty("requestParams", out _));
            Assert.IsFalse(attention.TryGetProperty("connectionID", out _));
        }

        var roundTripped = JsonSerializer.Deserialize<AgentGraph>(
            encoded,
            MapofAgentsJson.Options);
        Assert.IsNotNull(roundTripped);
        var roundTrippedMetadata = roundTripped.Nodes["thread-example"].Metadata;
        Assert.AreEqual(
            AgentProviders.Gemini,
            roundTrippedMetadata.ThreadRef?.Provider);
        Assert.AreEqual(
            AgentSandboxModes.WorkspaceWrite,
            roundTrippedMetadata.ThreadPermissions?.SandboxMode);
        Assert.AreEqual(
            thread.Metadata.InitialPrompt,
            roundTrippedMetadata.InitialPrompt);
        Assert.AreEqual(
            thread.Metadata.LocalTranscript.Count,
            roundTrippedMetadata.LocalTranscript.Count);
        Assert.AreEqual(
            thread.Metadata.LocalTranscriptTurns.Count,
            roundTrippedMetadata.LocalTranscriptTurns.Count);
        Assert.AreEqual(
            graph.PendingAttentionRequests.Count,
            roundTripped.PendingAttentionRequests.Count);
        Assert.AreEqual(
            "approval-1",
            roundTripped.PendingAttentionRequests[0].RequestID?.StringValue);
        Assert.AreEqual(
            17L,
            roundTripped.PendingAttentionRequests[1].RequestID?.IntegerValue);
        Assert.AreEqual(
            graph.RuntimeDiagnostics.Count,
            roundTripped.RuntimeDiagnostics.Count);
    }

    [TestMethod]
    public void SharedGraphSchemaDeclaresCanonicalProviderAndPermissionsShape()
    {
        using var schema = JsonDocument.Parse(
            File.ReadAllText(RepositoryFile("shared", "protocol", "graph.schema.json")));
        var definitions = schema.RootElement.GetProperty("$defs");
        var provider = definitions
            .GetProperty("threadRef")
            .GetProperty("properties")
            .GetProperty("provider");
        var providerValues = provider
            .GetProperty("enum")
            .EnumerateArray()
            .Select(value => value.GetString())
            .ToArray();
        var permissions = definitions
            .GetProperty("nodeMetadata")
            .GetProperty("properties")
            .GetProperty("threadPermissions");
        var attentionProperties = definitions
            .GetProperty("runtimeAttentionRequest")
            .GetProperty("properties");

        Assert.AreEqual(
            "https://mapofagents.dev/schema/graph.schema.json",
            schema.RootElement.GetProperty("$id").GetString());
        CollectionAssert.AreEquivalent(
            new[] { AgentProviders.Codex, AgentProviders.Gemini, AgentProviders.Grok },
            providerValues);
        Assert.AreEqual(
            "#/$defs/threadPermissions",
            permissions.GetProperty("$ref").GetString());
        Assert.IsTrue(attentionProperties.TryGetProperty("prompt", out _));
        Assert.IsTrue(attentionProperties.TryGetProperty("responseChoices", out _));
        Assert.IsFalse(attentionProperties.TryGetProperty("connectionID", out _));
        Assert.IsFalse(attentionProperties.TryGetProperty("requestParams", out _));
    }

    [DataTestMethod]
    [DataRow(false)]
    [DataRow(true)]
    public void CanonicalThreadPermissionsWinRegardlessOfJsonPropertyOrder(
        bool canonicalFirst)
    {
        var canonical =
            "\"threadPermissions\":{\"approvalPolicy\":\"never\",\"sandboxMode\":\"read-only\"}";
        var legacy =
            "\"approvalPolicy\":\"on-failure\",\"sandboxMode\":\"danger-full-access\"";
        var properties = canonicalFirst
            ? $"{canonical},{legacy}"
            : $"{legacy},{canonical}";
        var metadata = JsonSerializer.Deserialize<NodeMetadata>(
            $"{{{properties}}}",
            MapofAgentsJson.Options);

        Assert.IsNotNull(metadata?.ThreadPermissions);
        Assert.AreEqual(
            AgentApprovalPolicies.Never,
            metadata.ThreadPermissions.ApprovalPolicy);
        Assert.AreEqual(
            AgentSandboxModes.ReadOnly,
            metadata.ThreadPermissions.SandboxMode);
    }

    [TestMethod]
    public void LegacyFlattenedThreadPermissionsDecodeAndRewriteCanonically()
    {
        var legacyJson = """
            {
              "workspaceID": "legacy-permissions",
              "title": "Legacy permissions",
              "nodes": {
                "thread": {
                  "id": "thread",
                  "kind": "codexThread",
                  "title": "Thread",
                  "subtitle": "",
                  "position": { "x": 0, "y": 0 },
                  "size": { "width": 200, "height": 132 },
                  "metadata": {
                    "threadRef": {
                      "hostID": "example-host",
                      "threadID": "legacy-thread",
                      "cwd": "C:\\Users\\example\\project"
                    },
                    "approvalPolicy": "on-failure",
                    "sandboxMode": "read-only"
                  },
                  "zIndex": 0
                }
              },
              "manualEdges": {},
              "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
              "updatedAt": "2026-06-02T00:00:00Z"
            }
            """;

        var graph = JsonSerializer.Deserialize<AgentGraph>(
            legacyJson,
            MapofAgentsJson.Options);
        Assert.IsNotNull(graph);
        var metadata = graph.Nodes["thread"].Metadata;
        Assert.AreEqual(AgentProviders.Codex, metadata.ThreadRef?.Provider);
        Assert.AreEqual(AgentApprovalPolicies.OnFailure, metadata.ApprovalPolicy);
        Assert.AreEqual(AgentSandboxModes.ReadOnly, metadata.SandboxMode);

        var encoded = JsonSerializer.Serialize(graph, MapofAgentsJson.Options);
        using var document = JsonDocument.Parse(encoded);
        var rewrittenMetadata = document.RootElement
            .GetProperty("nodes")
            .GetProperty("thread")
            .GetProperty("metadata");
        Assert.IsTrue(rewrittenMetadata.TryGetProperty("threadPermissions", out _));
        Assert.IsFalse(rewrittenMetadata.TryGetProperty("approvalPolicy", out _));
        Assert.IsFalse(rewrittenMetadata.TryGetProperty("sandboxMode", out _));
    }

    [DataTestMethod]
    [DataRow(
        "\"approvalPolicy\": \"on-failure\"",
        AgentApprovalPolicies.OnFailure,
        AgentSandboxModes.DangerFullAccess)]
    [DataRow(
        "\"sandboxMode\": \"read-only\"",
        AgentApprovalPolicies.OnRequest,
        AgentSandboxModes.ReadOnly)]
    public void PartialLegacyThreadPermissionsUseHistoricalFallbacks(
        string legacyField,
        string expectedApprovalPolicy,
        string expectedSandboxMode)
    {
        var legacyJson = $$"""
            {
              "workspaceID": "partial-legacy-permissions",
              "title": "Partial legacy permissions",
              "nodes": {
                "thread": {
                  "id": "thread",
                  "kind": "codexThread",
                  "title": "Thread",
                  "subtitle": "",
                  "position": { "x": 0, "y": 0 },
                  "size": { "width": 200, "height": 132 },
                  "metadata": { {{legacyField}} },
                  "zIndex": 0
                }
              },
              "manualEdges": {},
              "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
              "updatedAt": "2026-06-02T00:00:00Z"
            }
            """;

        var graph = JsonSerializer.Deserialize<AgentGraph>(
            legacyJson,
            MapofAgentsJson.Options);
        Assert.IsNotNull(graph);
        var permissions = graph.Nodes["thread"].Metadata.ThreadPermissions;
        Assert.IsNotNull(permissions);
        Assert.AreEqual(expectedApprovalPolicy, permissions.ApprovalPolicy);
        Assert.AreEqual(expectedSandboxMode, permissions.SandboxMode);
    }

    [TestMethod]
    public void LegacySwiftTypedKeyDictionariesDecodeAndRewriteAsContractObjects()
    {
        var legacyJson = """
            {
              "workspaceID": "legacy-swift-dictionaries",
              "title": "Legacy Swift dictionaries",
              "nodes": [
                "thread",
                {
                  "id": "thread",
                  "kind": "codexThread",
                  "title": "Thread",
                  "subtitle": "",
                  "position": { "x": 0, "y": 0 },
                  "size": { "width": 200, "height": 132 },
                  "metadata": {},
                  "zIndex": 0
                }
              ],
              "manualEdges": [
                "edge",
                {
                  "id": "edge",
                  "source": "thread",
                  "target": "thread",
                  "kind": "manualNote",
                  "isManual": true,
                  "label": "Legacy"
                }
              ],
              "viewport": { "scale": 1, "offset": { "x": 0, "y": 0 } },
              "updatedAt": "2026-06-02T00:00:00Z"
            }
            """;

        var graph = JsonSerializer.Deserialize<AgentGraph>(
            legacyJson,
            MapofAgentsJson.Options);
        Assert.IsNotNull(graph);
        Assert.AreEqual("Thread", graph.Nodes["thread"].Title);
        Assert.AreEqual("Legacy", graph.ManualEdges["edge"].Label);

        var encoded = JsonSerializer.Serialize(graph, MapofAgentsJson.Options);
        using var document = JsonDocument.Parse(encoded);
        Assert.AreEqual(
            JsonValueKind.Object,
            document.RootElement.GetProperty("nodes").ValueKind);
        Assert.AreEqual(
            JsonValueKind.Object,
            document.RootElement.GetProperty("manualEdges").ValueKind);
    }

    [TestMethod]
    public void LegacyAttentionPayloadDecodesButIsNotReencoded()
    {
        var legacyJson = """
            {
              "id": "attention",
              "hostID": "example-host",
              "requestID": 42,
              "method": "item/tool/requestUserInput",
              "threadID": "thread",
              "summary": "Choose",
              "prompt": "Choose a mode",
              "requestParams": {
                "command": "do-not-persist-command-payload"
              },
              "responseChoices": [
                { "label": "Safe", "value": "safe" }
              ],
              "createdAt": "2026-06-02T00:00:00Z"
            }
            """;
        var request = JsonSerializer.Deserialize<RuntimeAttentionRequest>(
            legacyJson,
            MapofAgentsJson.Options);

        Assert.IsNotNull(request);
        Assert.AreEqual(42L, request.RequestID?.IntegerValue);
        Assert.AreEqual(
            "do-not-persist-command-payload",
            request.RequestParams?.GetProperty("command").GetString());

        var encoded = JsonSerializer.Serialize(request, MapofAgentsJson.Options);
        using var document = JsonDocument.Parse(encoded);
        Assert.IsFalse(document.RootElement.TryGetProperty("requestParams", out _));
        Assert.IsFalse(document.RootElement.TryGetProperty("connectionID", out _));
        Assert.AreEqual(
            JsonValueKind.Number,
            document.RootElement.GetProperty("requestID").ValueKind);
    }

    private static string RepositoryFile(params string[] components)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
             directory is not null;
             directory = directory.Parent)
        {
            var schemaPath = Path.Combine(
                directory.FullName,
                "shared",
                "protocol",
                "graph.schema.json");
            if (File.Exists(schemaPath))
            {
                var pathComponents = new string[components.Length + 1];
                pathComponents[0] = directory.FullName;
                Array.Copy(components, 0, pathComponents, 1, components.Length);
                return Path.Combine(pathComponents);
            }
        }

        throw new DirectoryNotFoundException(
            "Could not locate the repository shared protocol directory.");
    }

    private static string CanonicalJsonSemanticFingerprint(string path)
    {
        using var document = JsonDocument.Parse(File.ReadAllText(path));
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(
                   stream,
                   new JsonWriterOptions
                   {
                       Encoder = System.Text.Encodings.Web.JavaScriptEncoder
                           .UnsafeRelaxedJsonEscaping
                   }))
        {
            WriteCanonicalJson(writer, document.RootElement);
        }

        ulong hash = 14_695_981_039_346_656_037;
        foreach (var value in stream.ToArray())
        {
            hash ^= value;
            hash = unchecked(hash * 1_099_511_628_211);
        }
        return hash.ToString("x16");
    }

    private static void WriteCanonicalJson(Utf8JsonWriter writer, JsonElement value)
    {
        switch (value.ValueKind)
        {
            case JsonValueKind.Object:
                writer.WriteStartObject();
                foreach (var property in value.EnumerateObject()
                             .OrderBy(property => property.Name, StringComparer.Ordinal))
                {
                    writer.WritePropertyName(property.Name);
                    WriteCanonicalJson(writer, property.Value);
                }
                writer.WriteEndObject();
                break;
            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (var item in value.EnumerateArray())
                {
                    WriteCanonicalJson(writer, item);
                }
                writer.WriteEndArray();
                break;
            default:
                value.WriteTo(writer);
                break;
        }
    }
}
