using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public static class NodeKinds
{
    public const string Machine = "machine";
    public const string Folder = "folder";
    public const string CodexThread = "codexThread";
}

public static class HostPlatforms
{
    public const string MacOS = "macOS";
    public const string IOS = "iOS";
    public const string IPadOS = "iPadOS";
    public const string Windows = "windows";
    public const string Linux = "linux";
    public const string Unknown = "unknown";
}

public static class LocalHostIdentity
{
    public const string CanonicalHostID = "local";
    public const string WindowsLegacyHostID = "local-windows";
    public const string LocalMachineNodeID = "local-machine";

    public static bool IsLocalHostID(string? hostID, string? machineName = null)
    {
        if (string.IsNullOrWhiteSpace(hostID))
        {
            return true;
        }

        return string.Equals(hostID, CanonicalHostID, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(hostID, WindowsLegacyHostID, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(hostID, "localhost", StringComparison.OrdinalIgnoreCase) ||
            string.Equals(hostID, "127.0.0.1", StringComparison.OrdinalIgnoreCase) ||
            (!string.IsNullOrWhiteSpace(machineName) &&
                string.Equals(hostID, machineName, StringComparison.OrdinalIgnoreCase));
    }
}

public static class HostStatuses
{
    public const string Connected = "connected";
    public const string Connecting = "connecting";
    public const string Disconnected = "disconnected";
    public const string Unavailable = "unavailable";
}

public static class ThreadRunStatuses
{
    public const string Idle = "idle";
    public const string Running = "running";
    public const string NeedsInput = "needsInput";
    public const string Failed = "failed";
    public const string Complete = "complete";
    public const string Unknown = "unknown";
}

public static class ThreadKinds
{
    public const string Thread = "thread";
    public const string Subagent = "subagent";
}

public static class EdgeKinds
{
    public const string MachineFolder = "machineFolder";
    public const string FolderThread = "folderThread";
    public const string MachineThread = "machineThread";
    public const string ManualNote = "manualNote";
    public const string ThreadMessage = "threadMessage";
    public const string CreatedBy = "createdBy";
}

public sealed class CanvasPoint
{
    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }

    public CanvasPoint()
    {
    }

    public CanvasPoint(double x, double y)
    {
        X = x;
        Y = y;
    }
}

public sealed class CanvasSize
{
    [JsonPropertyName("width")]
    public double Width { get; set; }

    [JsonPropertyName("height")]
    public double Height { get; set; }

    public CanvasSize()
    {
    }

    public CanvasSize(double width, double height)
    {
        Width = width;
        Height = height;
    }

    public static CanvasSize Machine => new(190, 90);
    public static CanvasSize Folder => new(210, 96);
    public static CanvasSize Thread => new(200, 132);
}

public sealed class CanvasViewport
{
    [JsonPropertyName("scale")]
    public double Scale { get; set; } = 1;

    [JsonPropertyName("offset")]
    public CanvasPoint Offset { get; set; } = new();
}

public static class CanvasLayoutCoordinateSpaces
{
    public const string Center = "center";
}

public sealed class ThreadRef
{
    [JsonPropertyName("hostID")]
    public string HostID { get; set; } = "";

    [JsonPropertyName("threadID")]
    public string ThreadID { get; set; } = "";

    [JsonPropertyName("cwd")]
    public string Cwd { get; set; } = "";

    [JsonPropertyName("name")]
    public string? Name { get; set; }
}

public sealed class NodeMetadata
{
    [JsonPropertyName("hostID")]
    public string? HostID { get; set; }

    [JsonPropertyName("platform")]
    public string? Platform { get; set; }

    [JsonPropertyName("hostStatus")]
    public string? HostStatus { get; set; }

    [JsonPropertyName("hostLastError")]
    public string? HostLastError { get; set; }

    [JsonPropertyName("codexHome")]
    public string? CodexHome { get; set; }

    [JsonPropertyName("appServerEndpointUrl")]
    public string? AppServerEndpointUrl { get; set; }

    [JsonPropertyName("folderPath")]
    public string? FolderPath { get; set; }

    [JsonPropertyName("threadRef")]
    public ThreadRef? ThreadRef { get; set; }

    [JsonPropertyName("model")]
    public string? Model { get; set; }

    [JsonPropertyName("reasoningEffort")]
    public string? ReasoningEffort { get; set; }

    [JsonPropertyName("threadKind")]
    public string? ThreadKind { get; set; }

    [JsonPropertyName("approvalPolicy")]
    public string? ApprovalPolicy { get; set; }

    [JsonPropertyName("sandboxMode")]
    public string? SandboxMode { get; set; }

    [JsonPropertyName("initialPrompt")]
    public string? InitialPrompt { get; set; }

    [JsonPropertyName("localTranscript")]
    public List<LocalThreadMessage> LocalTranscript { get; set; } = [];

    [JsonPropertyName("localTranscriptTurns")]
    public List<LocalThreadTurn> LocalTranscriptTurns { get; set; } = [];

    [JsonPropertyName("runStatus")]
    public string? RunStatus { get; set; }

    [JsonPropertyName("isUnread")]
    public bool? IsUnread { get; set; }

    [JsonPropertyName("isArchived")]
    public bool? IsArchived { get; set; }

    [JsonPropertyName("popoverOffset")]
    public CanvasPoint? PopoverOffset { get; set; }

    [JsonPropertyName("hasManualPosition")]
    public bool? HasManualPosition { get; set; }
}

public sealed class LocalThreadMessage
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("role")]
    public string Role { get; set; } = "user";

    [JsonPropertyName("text")]
    public string Text { get; set; } = "";

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public static class ThreadTurnItemsViews
{
    public const string NotLoaded = "notLoaded";
    public const string Summary = "summary";
    public const string Full = "full";
}

public sealed class LocalThreadTurn
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("status")]
    public string Status { get; set; } = ThreadRunStatuses.Unknown;

    [JsonPropertyName("startedAt")]
    public DateTimeOffset StartedAt { get; set; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("completedAt")]
    public DateTimeOffset? CompletedAt { get; set; }

    [JsonPropertyName("error")]
    public string? Error { get; set; }

    [JsonPropertyName("itemsView")]
    public string ItemsView { get; set; } = ThreadTurnItemsViews.Full;

    [JsonPropertyName("durationMilliseconds")]
    public int? DurationMilliseconds { get; set; }

    [JsonPropertyName("itemMessageIds")]
    public List<string> ItemMessageIds { get; set; } = [];
}

public sealed class CanvasNode
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = NodeKinds.Machine;

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("subtitle")]
    public string Subtitle { get; set; } = "";

    [JsonPropertyName("position")]
    public CanvasPoint Position { get; set; } = new();

    [JsonPropertyName("size")]
    public CanvasSize Size { get; set; } = CanvasSize.Machine;

    [JsonPropertyName("metadata")]
    public NodeMetadata Metadata { get; set; } = new();

    [JsonPropertyName("zIndex")]
    public int ZIndex { get; set; }
}

public sealed class CanvasEdge
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("source")]
    public string Source { get; set; } = "";

    [JsonPropertyName("target")]
    public string Target { get; set; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = EdgeKinds.MachineFolder;

    [JsonPropertyName("isManual")]
    public bool IsManual { get; set; }

    [JsonPropertyName("label")]
    public string? Label { get; set; }
}

public sealed class MessageRoute
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("sourceHostID")]
    public string SourceHostID { get; set; } = "";

    [JsonPropertyName("sourceThreadID")]
    public string SourceThreadID { get; set; } = "";

    [JsonPropertyName("sourceTurnID")]
    public string? SourceTurnID { get; set; }

    [JsonPropertyName("sourceItemID")]
    public string? SourceItemID { get; set; }

    [JsonPropertyName("targetHostID")]
    public string TargetHostID { get; set; } = "";

    [JsonPropertyName("targetThreadID")]
    public string TargetThreadID { get; set; } = "";

    [JsonPropertyName("targetTurnID")]
    public string? TargetTurnID { get; set; }

    [JsonPropertyName("timestamp")]
    public DateTimeOffset Timestamp { get; set; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("snippet")]
    public string Snippet { get; set; } = "";

    [JsonPropertyName("deliveryState")]
    public string DeliveryState { get; set; } = MessageRouteDeliveryStates.Unknown;

    [JsonPropertyName("eventIDs")]
    public List<string> EventIDs { get; set; } = [];

    [JsonPropertyName("canvasEdgeID")]
    public string? CanvasEdgeID { get; set; }
}

public sealed class RuntimeAttentionResponseChoice
{
    [JsonPropertyName("label")]
    public string Label { get; set; } = "";

    [JsonPropertyName("value")]
    public string Value { get; set; } = "";
}

public sealed class RuntimeAttentionRequest
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("hostID")]
    public string? HostID { get; set; }

    [JsonPropertyName("requestID")]
    public string? RequestID { get; set; }

    [JsonPropertyName("method")]
    public string Method { get; set; } = "";

    [JsonPropertyName("threadID")]
    public string? ThreadID { get; set; }

    [JsonPropertyName("turnID")]
    public string? TurnID { get; set; }

    [JsonPropertyName("summary")]
    public string Summary { get; set; } = "";

    [JsonPropertyName("prompt")]
    public string? Prompt { get; set; }

    [JsonPropertyName("requestParams")]
    public JsonElement? RequestParams { get; set; }

    [JsonPropertyName("responseChoices")]
    public List<RuntimeAttentionResponseChoice> ResponseChoices { get; set; } = [];

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public static class MessageRouteDeliveryStates
{
    public const string Pending = "pending";
    public const string Delivered = "delivered";
    public const string Failed = "failed";
    public const string Unknown = "unknown";
}

public static class RuntimeDiagnosticStatuses
{
    public const string Pending = "pending";
    public const string Running = "running";
    public const string Passed = "passed";
    public const string Warning = "warning";
    public const string Failed = "failed";
}

public sealed class RuntimeDiagnosticStep
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("title")]
    public string Title { get; set; } = "";

    [JsonPropertyName("status")]
    public string Status { get; set; } = RuntimeDiagnosticStatuses.Pending;

    [JsonPropertyName("detail")]
    public string Detail { get; set; } = "";

    [JsonPropertyName("evidence")]
    public string Evidence { get; set; } = "";

    [JsonPropertyName("action")]
    public string? Action { get; set; }
}

public sealed class AgentGraph
{
    [JsonPropertyName("workspaceID")]
    public string WorkspaceID { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("title")]
    public string Title { get; set; } = "mapofagents";

    [JsonPropertyName("layoutCoordinateSpace")]
    public string? LayoutCoordinateSpace { get; set; }

    [JsonPropertyName("nodes")]
    public Dictionary<string, CanvasNode> Nodes { get; set; } = [];

    [JsonPropertyName("manualEdges")]
    public Dictionary<string, CanvasEdge> ManualEdges { get; set; } = [];

    [JsonPropertyName("messageRoutes")]
    public Dictionary<string, MessageRoute> MessageRoutes { get; set; } = [];

    [JsonPropertyName("pendingAttentionRequests")]
    public List<RuntimeAttentionRequest> PendingAttentionRequests { get; set; } = [];

    [JsonPropertyName("runtimeDiagnostics")]
    public List<RuntimeDiagnosticStep> RuntimeDiagnostics { get; set; } = [];

    [JsonPropertyName("suppressedAutoMaterializedThreadIDs")]
    public List<string> SuppressedAutoMaterializedThreadIDs { get; set; } = [];

    [JsonPropertyName("viewport")]
    public CanvasViewport Viewport { get; set; } = new();

    [JsonPropertyName("updatedAt")]
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public static AgentGraph CreateStarter(string machineName)
    {
        var hostID = LocalHostIdentity.CanonicalHostID;
        var machine = new CanvasNode
        {
            Id = LocalHostIdentity.LocalMachineNodeID,
            Kind = NodeKinds.Machine,
            Title = string.IsNullOrWhiteSpace(machineName) ? "Windows PC" : machineName,
            Subtitle = $"{HostPlatforms.Windows} - local",
            Position = new CanvasPoint(120, 100),
            Size = CanvasSize.Machine,
            Metadata = new NodeMetadata
            {
                HostID = hostID,
                Platform = HostPlatforms.Windows,
                HostStatus = HostStatuses.Disconnected
            }
        };

        return new AgentGraph
        {
            LayoutCoordinateSpace = CanvasLayoutCoordinateSpaces.Center,
            Nodes = new Dictionary<string, CanvasNode>
            {
                [machine.Id] = machine
            }
        };
    }
}
