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

public static class AgentProviders
{
    public const string Codex = "codex";
    public const string Gemini = "gemini";
    public const string Grok = "grok";
}

public static class AgentApprovalPolicies
{
    public const string OnRequest = "on-request";
    public const string OnFailure = "on-failure";
    public const string Untrusted = "untrusted";
    public const string Never = "never";
}

public static class AgentSandboxModes
{
    public const string DangerFullAccess = "danger-full-access";
    public const string WorkspaceWrite = "workspace-write";
    public const string ReadOnly = "read-only";
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
    [JsonPropertyName("provider")]
    public string Provider { get; set; } = AgentProviders.Codex;

    [JsonPropertyName("hostID")]
    public string HostID { get; set; } = "";

    [JsonPropertyName("threadID")]
    public string ThreadID { get; set; } = "";

    [JsonPropertyName("cwd")]
    public string Cwd { get; set; } = "";

    [JsonPropertyName("name")]
    public string? Name { get; set; }

    [JsonIgnore]
    public string QualifiedID => Provider == AgentProviders.Codex
        ? $"{HostID}::{ThreadID}"
        : $"{Provider}::{HostID}::{ThreadID}";

    public bool Matches(ThreadRef other)
    {
        return string.Equals(Provider, other.Provider, StringComparison.Ordinal) &&
            string.Equals(HostID, other.HostID, StringComparison.Ordinal) &&
            string.Equals(ThreadID, other.ThreadID, StringComparison.Ordinal);
    }
}

public sealed class AgentThreadPermissions
{
    [JsonPropertyName("approvalPolicy")]
    public string ApprovalPolicy { get; set; } = AgentApprovalPolicies.OnRequest;

    [JsonPropertyName("sandboxMode")]
    public string SandboxMode { get; set; } = AgentSandboxModes.WorkspaceWrite;
}

public sealed class NodeMetadata : IJsonOnDeserialized
{
    private AgentThreadPermissions? _threadPermissions;
    private string? _legacyApprovalPolicy;
    private string? _legacySandboxMode;
    private bool _hasCanonicalThreadPermissions;

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

    [JsonPropertyName("threadPermissions")]
    public AgentThreadPermissions? ThreadPermissions
    {
        get => _threadPermissions;
        set
        {
            _threadPermissions = value;
            _hasCanonicalThreadPermissions = value is not null;
        }
    }

    [JsonIgnore]
    public string? ApprovalPolicy
    {
        get => ThreadPermissions?.ApprovalPolicy;
        set
        {
            if (value is null)
            {
                return;
            }

            ThreadPermissions ??= new AgentThreadPermissions();
            ThreadPermissions.ApprovalPolicy = value;
        }
    }

    [JsonIgnore]
    public string? SandboxMode
    {
        get => ThreadPermissions?.SandboxMode;
        set
        {
            if (value is null)
            {
                return;
            }

            ThreadPermissions ??= new AgentThreadPermissions();
            ThreadPermissions.SandboxMode = value;
        }
    }

    // Decode the pre-contract flattened fields, but never write them back.
    [JsonPropertyName("approvalPolicy")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? LegacyApprovalPolicy
    {
        get => null;
        set => _legacyApprovalPolicy = value;
    }

    [JsonPropertyName("sandboxMode")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public string? LegacySandboxMode
    {
        get => null;
        set => _legacySandboxMode = value;
    }

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

    void IJsonOnDeserialized.OnDeserialized()
    {
        if (_hasCanonicalThreadPermissions ||
            (_legacyApprovalPolicy is null && _legacySandboxMode is null))
        {
            return;
        }

        _threadPermissions = new AgentThreadPermissions
        {
            ApprovalPolicy = _legacyApprovalPolicy ?? AgentApprovalPolicies.OnRequest,
            // Preserve the historical fallback for partially flattened documents.
            SandboxMode = _legacySandboxMode ?? AgentSandboxModes.DangerFullAccess
        };
    }
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
    public JsonRpcRequestId? RequestID { get; set; }

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

    [JsonIgnore]
    public JsonElement? RequestParams { get; set; }

    // Older graphs may contain the full app-server payload. Decode it for
    // compatibility and live presentation, but never write it back to disk.
    [JsonPropertyName("requestParams")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public JsonElement? LegacyRequestParams
    {
        get => null;
        set => RequestParams = value;
    }

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
    [JsonConverter(typeof(ObjectOrAlternatingArrayDictionaryConverter<CanvasNode>))]
    public Dictionary<string, CanvasNode> Nodes { get; set; } = [];

    [JsonPropertyName("manualEdges")]
    [JsonConverter(typeof(ObjectOrAlternatingArrayDictionaryConverter<CanvasEdge>))]
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

    public bool ContainsWorkflowThread(string? hostID, string? threadID)
    {
        if (string.IsNullOrWhiteSpace(threadID))
        {
            return false;
        }

        var trimmedThreadID = threadID.Trim();
        var trimmedHostID = hostID?.Trim();
        return Nodes.Values.Any(node =>
            node.Kind == NodeKinds.CodexThread &&
            node.Metadata.ThreadRef is { } threadRef &&
            string.Equals(threadRef.ThreadID, trimmedThreadID, StringComparison.OrdinalIgnoreCase) &&
            (string.IsNullOrWhiteSpace(trimmedHostID) ||
                string.Equals(threadRef.HostID, trimmedHostID, StringComparison.OrdinalIgnoreCase)));
    }

    public string? MaterializeWorkflowFolderRoot(
        string path,
        string hostID,
        string? title = null)
    {
        var folderPath = path.Trim();
        if (string.IsNullOrWhiteSpace(folderPath))
        {
            return null;
        }

        var resolvedHostID = string.IsNullOrWhiteSpace(hostID)
            ? LocalHostIdentity.CanonicalHostID
            : hostID.Trim();
        if (MatchingFolderNodeID(resolvedHostID, folderPath) is { } existingID)
        {
            UpdateExistingWorkflowFolder(existingID, folderPath, title);
            return existingID;
        }

        if (IsDescendantOfExistingFolderRoot(folderPath, resolvedHostID))
        {
            return null;
        }

        var platform =
            Nodes.Values.FirstOrDefault(node =>
                node.Kind == NodeKinds.Machine &&
                string.Equals(node.Metadata.HostID, resolvedHostID, StringComparison.Ordinal))?.Metadata.Platform ??
            Nodes.Values.FirstOrDefault(node =>
                string.Equals(node.Metadata.HostID, resolvedHostID, StringComparison.Ordinal) &&
                !string.IsNullOrWhiteSpace(node.Metadata.Platform))?.Metadata.Platform ??
            HostPlatforms.MacOS;
        var displayTitle = PreferredDisplayName(title, FolderTitleForPath(folderPath)) ??
            FolderTitleForPath(folderPath);
        var node = new CanvasNode
        {
            Kind = NodeKinds.Folder,
            Title = displayTitle,
            Subtitle = folderPath,
            Position = NextFolderPosition(resolvedHostID),
            Size = CanvasSize.Folder,
            Metadata = new NodeMetadata
            {
                HostID = resolvedHostID,
                Platform = platform,
                FolderPath = folderPath,
                HasManualPosition = false
            },
            ZIndex = NextZIndex()
        };

        Nodes[node.Id] = node;
        UpdatedAt = DateTimeOffset.UtcNow;
        return node.Id;
    }

    private string? MatchingFolderNodeID(string hostID, string path)
    {
        var normalizedPath = StandardizePath(path);
        return Nodes.Values.FirstOrDefault(node =>
            node.Kind == NodeKinds.Folder &&
            string.Equals(node.Metadata.HostID, hostID, StringComparison.Ordinal) &&
            !string.IsNullOrWhiteSpace(node.Metadata.FolderPath) &&
            string.Equals(StandardizePath(node.Metadata.FolderPath), normalizedPath, StringComparison.Ordinal))?.Id;
    }

    private void UpdateExistingWorkflowFolder(string id, string path, string? title)
    {
        if (!Nodes.TryGetValue(id, out var node))
        {
            return;
        }

        var changed = false;
        var preferredTitle = PreferredDisplayName(node.Title, title);
        if (preferredTitle is not null &&
            !string.Equals(preferredTitle, node.Title, StringComparison.Ordinal))
        {
            node.Title = preferredTitle;
            changed = true;
        }

        if (!string.Equals(node.Metadata.FolderPath, path, StringComparison.Ordinal))
        {
            node.Metadata.FolderPath = path;
            node.Subtitle = path;
            changed = true;
        }

        if (changed)
        {
            UpdatedAt = DateTimeOffset.UtcNow;
        }
    }

    private bool IsDescendantOfExistingFolderRoot(string path, string hostID)
    {
        var normalizedPath = StandardizePath(path);
        return Nodes.Values.Any(node =>
            node.Kind == NodeKinds.Folder &&
            string.Equals(node.Metadata.HostID, hostID, StringComparison.Ordinal) &&
            !string.IsNullOrWhiteSpace(node.Metadata.FolderPath) &&
            !string.Equals(StandardizePath(node.Metadata.FolderPath), normalizedPath, StringComparison.Ordinal) &&
            PathIsInsideOrEqualTo(path, node.Metadata.FolderPath));
    }

    private CanvasPoint NextFolderPosition(string hostID)
    {
        var machine = Nodes.Values.FirstOrDefault(node =>
            node.Kind == NodeKinds.Machine &&
            string.Equals(node.Metadata.HostID, hostID, StringComparison.Ordinal));
        var existingFolderCount = Nodes.Values.Count(node =>
            node.Kind == NodeKinds.Folder &&
            string.Equals(node.Metadata.HostID, hostID, StringComparison.Ordinal));
        var origin = new CanvasPoint(
            (machine?.Position.X ?? 180) + 220 + existingFolderCount * 300,
            Math.Max(330, (machine?.Position.Y ?? 130) + 200));
        return AvoidCollisions(origin);
    }

    private CanvasPoint AvoidCollisions(CanvasPoint point)
    {
        var candidate = point;
        var attempts = 0;
        while (attempts < 80 && Nodes.Values.Any(node => Overlaps(candidate, node)))
        {
            attempts += 1;
            var column = attempts % 5;
            var row = attempts / 5;
            candidate = new CanvasPoint(
                point.X + column * 240 + (row % 2) * 72,
                point.Y + row * 150);
        }

        return candidate;
    }

    private static bool Overlaps(CanvasPoint point, CanvasNode node)
    {
        var horizontalDistance = Math.Abs(point.X - node.Position.X);
        var verticalDistance = Math.Abs(point.Y - node.Position.Y);
        return horizontalDistance < node.Size.Width / 2 + CanvasSize.Thread.Width / 2 + 24 &&
            verticalDistance < node.Size.Height / 2 + CanvasSize.Thread.Height / 2 + 24;
    }

    private int NextZIndex()
    {
        return (Nodes.Values.Select(node => node.ZIndex).DefaultIfEmpty(0).Max()) + 1;
    }

    private static bool PathIsInsideOrEqualTo(string path, string root)
    {
        var normalizedRoot = StandardizePath(root);
        var normalizedPath = StandardizePath(path);

        if (string.Equals(normalizedPath, normalizedRoot, StringComparison.Ordinal))
        {
            return true;
        }

        var rootWithSlash = normalizedRoot.EndsWith("/", StringComparison.Ordinal)
            ? normalizedRoot
            : $"{normalizedRoot}/";
        return normalizedPath.StartsWith(rootWithSlash, StringComparison.Ordinal);
    }

    private static string FolderTitleForPath(string path)
    {
        var trimmed = path.Trim();
        var components = trimmed
            .Trim('/', '\\')
            .Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
        return components.LastOrDefault() ?? trimmed;
    }

    private static string StandardizePath(string path)
    {
        var slashNormalized = path.Replace('\\', '/');
        if (IsWindowsStylePath(slashNormalized))
        {
            return slashNormalized.ToLowerInvariant().Trim('/');
        }

        return NormalizePosixPath(slashNormalized);
    }

    private static string NormalizePosixPath(string path)
    {
        var collapsed = CollapseSlashes(path);
        var hasRoot = collapsed.StartsWith("/", StringComparison.Ordinal);
        var segments = new List<string>();
        foreach (var segment in collapsed.Split('/', StringSplitOptions.RemoveEmptyEntries))
        {
            if (segment == ".")
            {
                continue;
            }

            if (segment == ".." && segments.Count > 0 && segments[^1] != "..")
            {
                segments.RemoveAt(segments.Count - 1);
                continue;
            }

            if (segment != ".." || !hasRoot)
            {
                segments.Add(segment);
            }
        }

        var normalized = string.Join("/", segments);
        if (!hasRoot)
        {
            return normalized;
        }

        return string.IsNullOrEmpty(normalized) ? "/" : $"/{normalized}";
    }

    private static bool IsWindowsStylePath(string path)
    {
        return (path.Length >= 2 && char.IsAsciiLetter(path[0]) && path[1] == ':') ||
            path.StartsWith("//", StringComparison.Ordinal);
    }

    private static string CollapseSlashes(string path)
    {
        while (path.Contains("//", StringComparison.Ordinal))
        {
            path = path.Replace("//", "/", StringComparison.Ordinal);
        }

        return path;
    }

    private static string? PreferredDisplayName(string? current, string? incoming)
    {
        var normalizedCurrent = NormalizedDisplayName(current);
        var normalizedIncoming = NormalizedDisplayName(incoming);
        if (normalizedCurrent is null)
        {
            return normalizedIncoming;
        }

        if (normalizedIncoming is null)
        {
            return normalizedCurrent;
        }

        return DisplayNameScore(normalizedIncoming) > DisplayNameScore(normalizedCurrent)
            ? normalizedIncoming
            : normalizedCurrent;
    }

    private static string? NormalizedDisplayName(string? value)
    {
        var trimmed = value?.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return null;
        }

        var firstLine = trimmed
            .Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries)
            .FirstOrDefault()?
            .Trim();
        if (string.IsNullOrEmpty(firstLine))
        {
            return trimmed;
        }

        if (firstLine.Contains("thread name:", StringComparison.OrdinalIgnoreCase))
        {
            var pieces = firstLine.Split(':', 2, StringSplitOptions.None);
            if (pieces.Length == 2)
            {
                var named = pieces[1].Trim();
                if (!string.IsNullOrEmpty(named))
                {
                    return named;
                }
            }
        }

        return trimmed;
    }

    private static int DisplayNameScore(string value)
    {
        var trimmed = value.Trim();
        if (string.IsNullOrEmpty(trimmed))
        {
            return 0;
        }

        if (trimmed is "Created thread" or "Codex thread")
        {
            return 1;
        }

        if (trimmed.Contains("thread name:", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains('\n') ||
            trimmed.Length > 80)
        {
            return 2;
        }

        if (trimmed.StartsWith("worker ", StringComparison.OrdinalIgnoreCase))
        {
            return 3;
        }

        return 4;
    }
}
