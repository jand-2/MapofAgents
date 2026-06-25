using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public static class WorkflowEventKinds
{
    public const string TurnStarted = "turnStarted";
    public const string TurnCompleted = "turnCompleted";
    public const string ThreadCreated = "threadCreated";
    public const string FolderCreated = "folderCreated";
    public const string NeedsInput = "needsInput";
    public const string Failed = "failed";
}

public sealed class WorkflowEvent
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("kind")]
    public string Kind { get; set; } = WorkflowEventKinds.TurnCompleted;

    [JsonPropertyName("hostID")]
    public string? HostID { get; set; }

    [JsonPropertyName("threadID")]
    public string? ThreadID { get; set; }

    [JsonPropertyName("turnID")]
    public string? TurnID { get; set; }

    [JsonPropertyName("method")]
    public string Method { get; set; } = "";

    [JsonPropertyName("summary")]
    public string Summary { get; set; } = "";

    [JsonPropertyName("createdAt")]
    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    [JsonPropertyName("childHostID")]
    public string? ChildHostID { get; set; }

    [JsonPropertyName("childThreadID")]
    public string? ChildThreadID { get; set; }

    [JsonPropertyName("childCWD")]
    public string? ChildCWD { get; set; }

    [JsonPropertyName("childFolderPath")]
    public string? ChildFolderPath { get; set; }

    [JsonPropertyName("childTitle")]
    public string? ChildTitle { get; set; }

    [JsonPropertyName("childThreadKind")]
    public string? ChildThreadKind { get; set; }

    [JsonIgnore]
    public string DedupeKey => SemanticDedupeKey() ?? Id;

    public static WorkflowEvent Create(
        string kind,
        string? hostID,
        string? threadID,
        string? turnID,
        string method,
        string summary,
        DateTimeOffset createdAt,
        string? id = null,
        string? childHostID = null,
        string? childThreadID = null,
        string? childCWD = null,
        string? childFolderPath = null,
        string? childTitle = null,
        string? childThreadKind = null)
    {
        var workflowEvent = new WorkflowEvent
        {
            Kind = kind,
            HostID = hostID,
            ThreadID = threadID,
            TurnID = turnID,
            Method = method,
            Summary = summary,
            CreatedAt = createdAt,
            ChildHostID = childHostID,
            ChildThreadID = childThreadID,
            ChildCWD = childCWD,
            ChildFolderPath = childFolderPath,
            ChildTitle = childTitle,
            ChildThreadKind = childThreadKind
        };
        workflowEvent.Id = id ?? workflowEvent.SemanticDedupeKey() ?? StableID(kind, hostID, threadID, turnID, method, summary);
        return workflowEvent;
    }

    public string? SemanticDedupeKey()
    {
        if (Kind == WorkflowEventKinds.ThreadCreated &&
            !string.IsNullOrWhiteSpace(ChildHostID) &&
            !string.IsNullOrWhiteSpace(ChildThreadID))
        {
            return ThreadCreatedID(HostID, ThreadID, ChildHostID, ChildThreadID);
        }

        if (Kind == WorkflowEventKinds.FolderCreated &&
            !string.IsNullOrWhiteSpace(ChildHostID) &&
            !string.IsNullOrWhiteSpace(ChildFolderPath))
        {
            return FolderCreatedID(HostID, ThreadID, ChildHostID, ChildFolderPath);
        }

        var stable = StableID(Kind, HostID, ThreadID, TurnID, Method, Summary);
        if (!string.IsNullOrWhiteSpace(TurnID))
        {
            return stable;
        }

        return string.Equals(Id, stable, StringComparison.Ordinal) ? null : $"workflow-event-explicit-{SafeIDComponent(Id)}";
    }

    public static string StableID(
        string kind,
        string? hostID,
        string? threadID,
        string? turnID,
        string method,
        string summary)
    {
        var turnComponent = !string.IsNullOrWhiteSpace(turnID)
            ? turnID
            : string.IsNullOrWhiteSpace(summary) ? "unknown-turn" : summary;
        return string.Join(
            "-",
            new[]
            {
                "workflow-event",
                kind,
                hostID ?? "unknown-host",
                threadID ?? "unknown-thread",
                turnComponent,
                method
            }.Select(SafeIDComponent));
    }

    public static string ThreadCreatedID(
        string? sourceHostID,
        string? sourceThreadID,
        string childHostID,
        string childThreadID)
    {
        return string.Join(
            "-",
            new[]
            {
                "workflow-event",
                WorkflowEventKinds.ThreadCreated,
                sourceHostID ?? "unknown-source-host",
                sourceThreadID ?? "unknown-source-thread",
                childHostID,
                childThreadID
            }.Select(SafeIDComponent));
    }

    public static string FolderCreatedID(
        string? sourceHostID,
        string? sourceThreadID,
        string childHostID,
        string childFolderPath)
    {
        return string.Join(
            "-",
            new[]
            {
                "workflow-event",
                WorkflowEventKinds.FolderCreated,
                sourceHostID ?? "unknown-source-host",
                sourceThreadID ?? "unknown-source-thread",
                childHostID,
                childFolderPath
            }.Select(SafeIDComponent));
    }

    private static string SafeIDComponent(string value)
    {
        var compact = new string(value
            .ToLowerInvariant()
            .Select(character => char.IsLetterOrDigit(character) ? character : '-')
            .ToArray());
        while (compact.Contains("--", StringComparison.Ordinal))
        {
            compact = compact.Replace("--", "-", StringComparison.Ordinal);
        }

        compact = compact.Trim('-');
        if (string.IsNullOrWhiteSpace(compact))
        {
            return "none";
        }

        return compact.Length <= 96 ? compact : compact[..96];
    }
}

public static class WorkflowEventParser
{
    public static WorkflowEvent? Parse(
        string line,
        string? defaultHostID = null,
        DateTimeOffset? receivedAt = null)
    {
        var trimmed = line.Trim();
        if (string.IsNullOrWhiteSpace(trimmed))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(trimmed);
            return Parse(document.RootElement, defaultHostID, receivedAt);
        }
        catch (JsonException)
        {
            return null;
        }
    }

    public static WorkflowEvent? Parse(
        JsonElement payload,
        string? defaultHostID = null,
        DateTimeOffset? receivedAt = null)
    {
        if (payload.ValueKind != JsonValueKind.Object)
        {
            return null;
        }

        var method = StringIn(payload, "method", "notificationMethod", "notification_method");
        var rawKind = StructuredEventKind(payload) ??
            StringIn(payload, "workflowEventKind", "workflow_event_kind", "kind", "event", "type") ??
            method;
        var kind = WorkflowEventKindFrom(rawKind);
        if (kind is null)
        {
            return null;
        }

        var isCreationEvent = kind is WorkflowEventKinds.ThreadCreated or WorkflowEventKinds.FolderCreated;
        var hostID = StringIn(
                payload,
                isCreationEvent
                    ? ["sourceHostID", "sourceHostId", "source_host_id", "sourceHost", "hostID", "hostId", "host_id", "host"]
                    : ["hostID", "hostId", "host_id", "host"]) ??
            defaultHostID;
        var threadID = StringIn(
                payload,
                isCreationEvent
                    ? ["sourceThreadID", "sourceThreadId", "source_thread_id", "sourceSessionID", "sourceSessionId", "source_session_id", "threadID", "threadId", "thread_id", "sessionID", "sessionId", "session_id"]
                    : ["threadID", "threadId", "thread_id", "sessionID", "sessionId", "session_id"]) ??
            NestedString(payload, "thread", "id");
        var turnID = StringIn(
            payload,
            isCreationEvent
                ? ["sourceTurnID", "sourceTurnId", "source_turn_id", "turnID", "turnId", "turn_id", "rolloutID", "rolloutId", "rollout_id"]
                : ["turnID", "turnId", "turn_id", "rolloutID", "rolloutId", "rollout_id"]) ??
            NestedString(payload, "turn", "id");
        var childHostID = StringIn(payload, "childHostID", "childHostId", "child_host_id", "targetHostID", "targetHostId", "target_host_id") ??
            (isCreationEvent ? hostID : null);
        var childThreadID = StringIn(payload, "childThreadID", "childThreadId", "child_thread_id", "childSessionID", "childSessionId", "child_session_id", "targetThreadID", "targetThreadId", "target_thread_id") ??
            NestedString(payload, "childThread", "id") ??
            NestedString(payload, "child", "threadID", "threadId", "id");
        var childCWD = StringIn(payload, "childCWD", "childCwd", "child_cwd", "childWorkspace", "child_workspace", "cwd") ??
            NestedString(payload, "childThread", "cwd") ??
            NestedString(payload, "child", "cwd");
        var childFolderPath = StringIn(payload, "childFolderPath", "child_folder_path", "folderPath", "folder_path", "path") ??
            NestedString(payload, "childFolder", "path") ??
            NestedString(payload, "folder", "path") ??
            NestedString(payload, "child", "folderPath", "folder_path") ??
            (kind == WorkflowEventKinds.FolderCreated ? childCWD : null);
        var childTitle = StringIn(payload, "childTitle", "child_title", "threadTitle", "thread_title", "name", "title") ??
            NestedString(payload, "childThread", "title", "name") ??
            NestedString(payload, "child", "title", "name");
        var childThreadKind = CodexThreadKindFrom(
            StringIn(payload, "childKind", "child_kind", "childThreadKind", "child_thread_kind", "threadKind", "thread_kind", "kind") ??
            NestedString(payload, "childThread", "kind") ??
            NestedString(payload, "child", "kind"));
        var createdAt = DateIn(payload, receivedAt ?? DateTimeOffset.UtcNow, "createdAt", "created_at", "timestamp", "time");
        var summary = StringIn(payload, "summary", "message") ??
            CreationSummary(kind, childTitle, childThreadID, childFolderPath) ??
            DefaultSummary(kind, method);
        var effectiveMethod = method ?? DefaultMethod(kind);
        var explicitID = ExplicitID(
            payload,
            kind,
            hostID,
            threadID,
            turnID,
            childHostID,
            childThreadID,
            childFolderPath,
            effectiveMethod,
            createdAt);

        return WorkflowEvent.Create(
            kind,
            hostID,
            threadID,
            turnID,
            effectiveMethod,
            summary,
            createdAt,
            id: explicitID,
            childHostID: childHostID,
            childThreadID: childThreadID,
            childCWD: childCWD,
            childFolderPath: childFolderPath,
            childTitle: childTitle,
            childThreadKind: childThreadKind);
    }

    private static string? StructuredEventKind(JsonElement payload)
    {
        foreach (var key in new[] { "type", "event", "method", "notificationMethod", "notification_method" })
        {
            var value = StringIn(payload, key);
            var kind = WorkflowEventKindFrom(value);
            if (kind is WorkflowEventKinds.ThreadCreated or WorkflowEventKinds.FolderCreated)
            {
                return value;
            }
        }

        return null;
    }

    private static string? WorkflowEventKindFrom(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var trimmed = value.Trim();
        if (trimmed is WorkflowEventKinds.TurnStarted or
            WorkflowEventKinds.TurnCompleted or
            WorkflowEventKinds.ThreadCreated or
            WorkflowEventKinds.FolderCreated or
            WorkflowEventKinds.NeedsInput or
            WorkflowEventKinds.Failed)
        {
            return trimmed;
        }

        var normalized = trimmed
            .ToLowerInvariant()
            .Replace("_", "-", StringComparison.Ordinal)
            .Replace(".", "-", StringComparison.Ordinal)
            .Replace("/", "-", StringComparison.Ordinal)
            .Replace(" ", "-", StringComparison.Ordinal);

        if (normalized.Contains("fail", StringComparison.Ordinal) ||
            normalized.Contains("error", StringComparison.Ordinal))
        {
            return WorkflowEventKinds.Failed;
        }

        if (normalized.Contains("approval", StringComparison.Ordinal) ||
            normalized.Contains("needs-input", StringComparison.Ordinal) ||
            normalized.Contains("need-input", StringComparison.Ordinal) ||
            normalized.Contains("request-input", StringComparison.Ordinal) ||
            normalized.Contains("request-user-input", StringComparison.Ordinal) ||
            normalized.Contains("elicitation", StringComparison.Ordinal))
        {
            return WorkflowEventKinds.NeedsInput;
        }

        if (normalized.Contains("complete", StringComparison.Ordinal) ||
            normalized.Contains("completed", StringComparison.Ordinal) ||
            normalized.Contains("ended", StringComparison.Ordinal) ||
            normalized.Contains("turn-ended", StringComparison.Ordinal) ||
            normalized.Contains("turn-end", StringComparison.Ordinal) ||
            normalized.Contains("done", StringComparison.Ordinal) ||
            normalized.Contains("stop", StringComparison.Ordinal))
        {
            return WorkflowEventKinds.TurnCompleted;
        }

        if (normalized.Contains("started", StringComparison.Ordinal) ||
            normalized.Contains("turn-start", StringComparison.Ordinal))
        {
            return WorkflowEventKinds.TurnStarted;
        }

        if (normalized == "thread-created" ||
            normalized == "thread-create" ||
            normalized.Contains("thread-created", StringComparison.Ordinal) ||
            normalized.Contains("thread-create", StringComparison.Ordinal))
        {
            return WorkflowEventKinds.ThreadCreated;
        }

        if (normalized == "folder-created" ||
            normalized == "folder-create" ||
            normalized == "workspace-created" ||
            normalized == "workspace-create" ||
            normalized == "project-created" ||
            normalized == "project-create" ||
            normalized.Contains("folder-created", StringComparison.Ordinal) ||
            normalized.Contains("folder-create", StringComparison.Ordinal) ||
            normalized.Contains("workspace-created", StringComparison.Ordinal) ||
            normalized.Contains("workspace-create", StringComparison.Ordinal) ||
            normalized.Contains("project-created", StringComparison.Ordinal) ||
            normalized.Contains("project-create", StringComparison.Ordinal))
        {
            return WorkflowEventKinds.FolderCreated;
        }

        return null;
    }

    private static string? ExplicitID(
        JsonElement payload,
        string kind,
        string? hostID,
        string? threadID,
        string? turnID,
        string? childHostID,
        string? childThreadID,
        string? childFolderPath,
        string method,
        DateTimeOffset createdAt)
    {
        if (StringIn(payload, "id", "eventID", "eventId", "event_id") is { } id)
        {
            return id.StartsWith("hook-", StringComparison.Ordinal) ? id : $"hook-{id}";
        }

        if (kind == WorkflowEventKinds.ThreadCreated &&
            !string.IsNullOrWhiteSpace(childHostID) &&
            !string.IsNullOrWhiteSpace(childThreadID))
        {
            return $"hook-{WorkflowEvent.ThreadCreatedID(hostID, threadID, childHostID, childThreadID)}";
        }

        if (kind == WorkflowEventKinds.FolderCreated &&
            !string.IsNullOrWhiteSpace(childHostID) &&
            !string.IsNullOrWhiteSpace(childFolderPath))
        {
            return $"hook-{WorkflowEvent.FolderCreatedID(hostID, threadID, childHostID, childFolderPath)}";
        }

        if (!string.IsNullOrWhiteSpace(turnID))
        {
            return null;
        }

        var timestamp = createdAt.ToUnixTimeMilliseconds();
        return $"hook-{kind}-{hostID ?? "unknown-host"}-{threadID ?? "unknown-thread"}-{method}-{timestamp}";
    }

    private static string? StringIn(JsonElement payload, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!payload.TryGetProperty(key, out var value))
            {
                continue;
            }

            var stringValue = StringValue(value);
            if (!string.IsNullOrWhiteSpace(stringValue))
            {
                return stringValue;
            }
        }

        return null;
    }

    private static string? NestedString(JsonElement payload, string objectKey, params string[] keys)
    {
        return payload.TryGetProperty(objectKey, out var value) && value.ValueKind == JsonValueKind.Object
            ? StringIn(value, keys)
            : null;
    }

    private static string? StringValue(JsonElement value)
    {
        return value.ValueKind switch
        {
            JsonValueKind.String => NullIfBlank(value.GetString()),
            JsonValueKind.Number when value.TryGetInt64(out var integer) => integer.ToString(CultureInfo.InvariantCulture),
            JsonValueKind.Number when value.TryGetDouble(out var number) => number.ToString(CultureInfo.InvariantCulture),
            _ => null
        };
    }

    private static string? CodexThreadKindFrom(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value
            .Trim()
            .ToLowerInvariant()
            .Replace("_", "-", StringComparison.Ordinal)
            .Replace(".", "-", StringComparison.Ordinal)
            .Replace("/", "-", StringComparison.Ordinal)
            .Replace(" ", "-", StringComparison.Ordinal);
        if (normalized.Contains("subagent", StringComparison.Ordinal) || normalized == "agent")
        {
            return ThreadKinds.Subagent;
        }

        return normalized.Contains("thread", StringComparison.Ordinal) ? ThreadKinds.Thread : null;
    }

    private static string? CreationSummary(string kind, string? title, string? threadID, string? folderPath)
    {
        return kind switch
        {
            WorkflowEventKinds.ThreadCreated => ThreadCreatedSummary(title, threadID),
            WorkflowEventKinds.FolderCreated => FolderCreatedSummary(title, folderPath),
            _ => null
        };
    }

    private static string ThreadCreatedSummary(string? title, string? threadID)
    {
        if (!string.IsNullOrWhiteSpace(title))
        {
            return $"Created {title.Trim()}";
        }

        return string.IsNullOrWhiteSpace(threadID) ? "Created thread" : $"Created thread {threadID.Trim()}";
    }

    private static string FolderCreatedSummary(string? title, string? folderPath)
    {
        if (!string.IsNullOrWhiteSpace(title))
        {
            return $"Created folder {title.Trim()}";
        }

        return string.IsNullOrWhiteSpace(folderPath)
            ? "Created folder"
            : $"Created folder {FolderName(folderPath)}";
    }

    private static string FolderName(string path)
    {
        var components = path
            .Trim('/', '\\')
            .Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries);
        return components.LastOrDefault() ?? path;
    }

    private static DateTimeOffset DateIn(JsonElement payload, DateTimeOffset fallback, params string[] keys)
    {
        foreach (var key in keys)
        {
            if (!payload.TryGetProperty(key, out var value))
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var seconds))
            {
                return DateTimeOffset.FromUnixTimeMilliseconds((long)(NormalizedEpochSeconds(seconds) * 1_000));
            }

            if (value.ValueKind != JsonValueKind.String ||
                string.IsNullOrWhiteSpace(value.GetString()))
            {
                continue;
            }

            var stringValue = value.GetString()!.Trim();
            if (DateTimeOffset.TryParse(
                    stringValue,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var date))
            {
                return date;
            }

            if (double.TryParse(stringValue, NumberStyles.Float, CultureInfo.InvariantCulture, out seconds))
            {
                return DateTimeOffset.FromUnixTimeMilliseconds((long)(NormalizedEpochSeconds(seconds) * 1_000));
            }
        }

        return fallback;
    }

    private static double NormalizedEpochSeconds(double value)
    {
        return value > 10_000_000_000 ? value / 1_000 : value;
    }

    private static string DefaultMethod(string kind)
    {
        return kind switch
        {
            WorkflowEventKinds.TurnStarted => "turn/started",
            WorkflowEventKinds.TurnCompleted => "turn/completed",
            WorkflowEventKinds.ThreadCreated => "thread/created",
            WorkflowEventKinds.FolderCreated => "folder/created",
            WorkflowEventKinds.NeedsInput => "hook/needsInput",
            WorkflowEventKinds.Failed => "hook/failed",
            _ => "hook/event"
        };
    }

    private static string DefaultSummary(string kind, string? method)
    {
        return kind switch
        {
            WorkflowEventKinds.TurnStarted => "Turn started",
            WorkflowEventKinds.TurnCompleted => "Turn completed",
            WorkflowEventKinds.ThreadCreated => "Created thread",
            WorkflowEventKinds.FolderCreated => "Created folder",
            WorkflowEventKinds.NeedsInput => method ?? "Needs input",
            WorkflowEventKinds.Failed => method ?? "Turn failed",
            _ => method ?? "Workflow event"
        };
    }

    private static string? NullIfBlank(string? value)
    {
        var trimmed = value?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }
}

public sealed record WorkflowEventIngestionResult(
    bool Applied,
    string? NodeID,
    string Message);

public static class WorkflowEventIngestor
{
    public static WorkflowEventIngestionResult Apply(AgentGraph graph, WorkflowEvent workflowEvent)
    {
        if (workflowEvent.Kind != WorkflowEventKinds.FolderCreated)
        {
            return new WorkflowEventIngestionResult(false, null, $"Ignored {workflowEvent.Kind}.");
        }

        if (string.IsNullOrWhiteSpace(workflowEvent.ChildFolderPath))
        {
            return new WorkflowEventIngestionResult(false, null, "Ignored folder.created without folderPath.");
        }

        if (!graph.ContainsWorkflowThread(workflowEvent.HostID, workflowEvent.ThreadID))
        {
            return new WorkflowEventIngestionResult(false, null, "Ignored folder.created from unmapped source thread.");
        }

        var childHostID = string.IsNullOrWhiteSpace(workflowEvent.ChildHostID)
            ? workflowEvent.HostID ?? LocalHostIdentity.CanonicalHostID
            : workflowEvent.ChildHostID;
        var nodeID = graph.MaterializeWorkflowFolderRoot(
            workflowEvent.ChildFolderPath,
            childHostID,
            workflowEvent.ChildTitle);
        return nodeID is null
            ? new WorkflowEventIngestionResult(false, null, "Ignored descendant folder.created event.")
            : new WorkflowEventIngestionResult(true, nodeID, "Materialized folder.created event.");
    }
}
