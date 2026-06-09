using System.Text.Json;
using System.Text.Json.Serialization;

namespace MapofAgents.Core;

public sealed class ControlRoomStore
{
    private const string FileName = "control-room.json";
    private const string LibraryFileName = "workflows.json";

    public ControlRoomStore(string? applicationDataDirectory = null)
    {
        ApplicationDataDirectory = string.IsNullOrWhiteSpace(applicationDataDirectory)
            ? Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "MapofAgents")
            : applicationDataDirectory;
    }

    public string ApplicationDataDirectory { get; }

    public string GraphPath => Path.Combine(ApplicationDataDirectory, FileName);

    public string LibraryPath => Path.Combine(ApplicationDataDirectory, LibraryFileName);

    public async Task<AgentGraph> LoadOrCreateAsync(CancellationToken cancellationToken = default)
    {
        var library = await LoadLibraryAsync(cancellationToken).ConfigureAwait(false);
        var layoutWasMigrated = NormalizeLibraryLayouts(library);
        if (library.Workflows.Count == 0)
        {
            var starter = await LoadLegacyGraphOrStarterAsync(cancellationToken).ConfigureAwait(false);
            NormalizeGraphLayout(starter);
            AddWorkflow(library, starter, ToolbarWorkflowPresentation.InitialWorkflowName);
            library.ActiveWorkflowID = starter.WorkspaceID;
            await SaveLibraryAsync(library, starter, cancellationToken).ConfigureAwait(false);
            return starter;
        }

        var activeWorkflow = library.Workflows.FirstOrDefault(workflow => workflow.ID == library.ActiveWorkflowID)
            ?? library.Workflows[0];
        var activeWorkflowChanged = library.ActiveWorkflowID != activeWorkflow.ID;
        library.ActiveWorkflowID = activeWorkflow.ID;
        var graph = CloneGraph(activeWorkflow.Graph);
        if (NormalizeGraphLayout(graph))
        {
            activeWorkflow.Graph = CloneGraph(graph);
            layoutWasMigrated = true;
        }

        if (layoutWasMigrated || activeWorkflowChanged)
        {
            await SaveLibraryAsync(library, graph, cancellationToken).ConfigureAwait(false);
        }
        else
        {
            await SaveLegacyActiveGraphAsync(graph, cancellationToken).ConfigureAwait(false);
        }

        return graph;
    }

    public async Task SaveAsync(AgentGraph graph, CancellationToken cancellationToken = default)
    {
        var library = await LoadLibraryAsync(cancellationToken).ConfigureAwait(false);
        NormalizeGraphLayout(graph);
        graph.UpdatedAt = DateTimeOffset.UtcNow;
        if (string.IsNullOrWhiteSpace(graph.WorkspaceID))
        {
            graph.WorkspaceID = Guid.NewGuid().ToString();
        }

        AddWorkflow(library, graph);
        library.ActiveWorkflowID = graph.WorkspaceID;
        await SaveLibraryAsync(library, graph, cancellationToken).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<WorkflowRecord>> LoadWorkflowsAsync(CancellationToken cancellationToken = default)
    {
        var library = await LoadLibraryAsync(cancellationToken).ConfigureAwait(false);
        return library.Workflows
            .OrderByDescending(workflow => workflow.Graph.UpdatedAt)
            .Select(workflow => new WorkflowRecord(
                workflow.ID,
                workflow.Name,
                workflow.ID == library.ActiveWorkflowID,
                workflow.Graph.Nodes.Count,
                workflow.Graph.ManualEdges.Count,
                workflow.Graph.UpdatedAt))
            .ToList();
    }

    public async Task<AgentGraph?> SelectWorkflowAsync(string id, CancellationToken cancellationToken = default)
    {
        var library = await LoadLibraryAsync(cancellationToken).ConfigureAwait(false);
        var workflow = library.Workflows.FirstOrDefault(item => item.ID == id);
        if (workflow is null)
        {
            return null;
        }

        library.ActiveWorkflowID = workflow.ID;
        var graph = CloneGraph(workflow.Graph);
        if (NormalizeGraphLayout(graph))
        {
            workflow.Graph = CloneGraph(graph);
        }

        await SaveLibraryAsync(library, graph, cancellationToken).ConfigureAwait(false);
        return graph;
    }

    public async Task<AgentGraph> CreateWorkflowAsync(
        string name,
        string machineName,
        CancellationToken cancellationToken = default)
    {
        var library = await LoadLibraryAsync(cancellationToken).ConfigureAwait(false);
        var graph = AgentGraph.CreateStarter(machineName);
        graph.WorkspaceID = Guid.NewGuid().ToString();
        graph.Title = string.IsNullOrWhiteSpace(name) ? NextWorkflowName(library) : name.Trim();
        NormalizeGraphLayout(graph);
        graph.UpdatedAt = DateTimeOffset.UtcNow;
        AddWorkflow(library, graph);
        library.ActiveWorkflowID = graph.WorkspaceID;
        await SaveLibraryAsync(library, graph, cancellationToken).ConfigureAwait(false);
        return CloneGraph(graph);
    }

    public async Task<AgentGraph> DuplicateActiveWorkflowAsync(
        string name,
        CancellationToken cancellationToken = default)
    {
        var library = await LoadLibraryAsync(cancellationToken).ConfigureAwait(false);
        var active = library.Workflows.FirstOrDefault(item => item.ID == library.ActiveWorkflowID)
            ?? library.Workflows.FirstOrDefault();
        var graph = active is null
            ? AgentGraph.CreateStarter(Environment.MachineName)
            : CloneGraph(active.Graph);
        graph.WorkspaceID = Guid.NewGuid().ToString();
        graph.Title = string.IsNullOrWhiteSpace(name)
            ? $"{(active?.Name ?? "Workflow")} Copy"
            : name.Trim();
        NormalizeGraphLayout(graph);
        graph.UpdatedAt = DateTimeOffset.UtcNow;
        AddWorkflow(library, graph);
        library.ActiveWorkflowID = graph.WorkspaceID;
        await SaveLibraryAsync(library, graph, cancellationToken).ConfigureAwait(false);
        return CloneGraph(graph);
    }

    public async Task<AgentGraph?> DeleteWorkflowAsync(string id, CancellationToken cancellationToken = default)
    {
        var library = await LoadLibraryAsync(cancellationToken).ConfigureAwait(false);
        if (library.Workflows.Count <= 1)
        {
            return null;
        }

        var previousActiveID = library.ActiveWorkflowID;
        var removed = library.Workflows.RemoveAll(item => item.ID == id);
        if (removed == 0)
        {
            return null;
        }

        var active = library.Workflows.FirstOrDefault(item => item.ID == previousActiveID)
            ?? library.Workflows
            .OrderByDescending(item => item.Graph.UpdatedAt)
            .First();
        library.ActiveWorkflowID = active.ID;
        var graph = CloneGraph(active.Graph);
        if (NormalizeGraphLayout(graph))
        {
            active.Graph = CloneGraph(graph);
        }

        await SaveLibraryAsync(library, graph, cancellationToken).ConfigureAwait(false);
        return graph;
    }

    private async Task<WorkflowLibraryDocument> LoadLibraryAsync(CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(ApplicationDataDirectory);
        if (!File.Exists(LibraryPath))
        {
            return new WorkflowLibraryDocument();
        }

        await using var stream = File.OpenRead(LibraryPath);
        var library = await JsonSerializer.DeserializeAsync<WorkflowLibraryDocument>(
            stream,
            MapofAgentsJson.Options,
            cancellationToken).ConfigureAwait(false);

        return library ?? new WorkflowLibraryDocument();
    }

    private async Task<AgentGraph> LoadLegacyGraphOrStarterAsync(CancellationToken cancellationToken)
    {
        if (!File.Exists(GraphPath))
        {
            return AgentGraph.CreateStarter(Environment.MachineName);
        }

        await using var stream = File.OpenRead(GraphPath);
        var graph = await JsonSerializer.DeserializeAsync<AgentGraph>(
            stream,
            MapofAgentsJson.Options,
            cancellationToken).ConfigureAwait(false);

        return graph ?? AgentGraph.CreateStarter(Environment.MachineName);
    }

    private static bool NormalizeLibraryLayouts(WorkflowLibraryDocument library)
    {
        var changed = false;
        foreach (var workflow in library.Workflows)
        {
            changed |= NormalizeGraphLayout(workflow.Graph);
        }

        return changed;
    }

    private static bool NormalizeGraphLayout(AgentGraph graph)
    {
        if (string.Equals(
                graph.LayoutCoordinateSpace,
                CanvasLayoutCoordinateSpaces.Center,
                StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        foreach (var node in graph.Nodes.Values)
        {
            node.Position = new CanvasPoint(
                node.Position.X + node.Size.Width / 2,
                node.Position.Y + node.Size.Height / 2);
        }

        graph.LayoutCoordinateSpace = CanvasLayoutCoordinateSpaces.Center;
        return true;
    }

    private async Task SaveLibraryAsync(
        WorkflowLibraryDocument library,
        AgentGraph activeGraph,
        CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(ApplicationDataDirectory);
        var tempPath = $"{LibraryPath}.tmp";
        await using (var stream = File.Create(tempPath))
        {
            await JsonSerializer.SerializeAsync(
                stream,
                library,
                MapofAgentsJson.Options,
                cancellationToken).ConfigureAwait(false);
        }

        if (File.Exists(LibraryPath))
        {
            File.Replace(tempPath, LibraryPath, null);
        }
        else
        {
            File.Move(tempPath, LibraryPath);
        }

        await SaveLegacyActiveGraphAsync(activeGraph, cancellationToken).ConfigureAwait(false);
    }

    private async Task SaveLegacyActiveGraphAsync(AgentGraph graph, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(ApplicationDataDirectory);
        var tempPath = $"{GraphPath}.tmp";
        await using (var stream = File.Create(tempPath))
        {
            await JsonSerializer.SerializeAsync(
                stream,
                graph,
                MapofAgentsJson.Options,
                cancellationToken).ConfigureAwait(false);
        }

        if (File.Exists(GraphPath))
        {
            File.Replace(tempPath, GraphPath, null);
        }
        else
        {
            File.Move(tempPath, GraphPath);
        }
    }

    private static void AddWorkflow(WorkflowLibraryDocument library, AgentGraph graph, string? workflowName = null)
    {
        if (string.IsNullOrWhiteSpace(graph.WorkspaceID))
        {
            graph.WorkspaceID = Guid.NewGuid().ToString();
        }

        if (string.IsNullOrWhiteSpace(graph.Title))
        {
            graph.Title = "mapofagents";
        }

        var resolvedWorkflowName = string.IsNullOrWhiteSpace(workflowName)
            ? graph.Title
            : workflowName.Trim();
        var workflow = library.Workflows.FirstOrDefault(item => item.ID == graph.WorkspaceID);
        if (workflow is null)
        {
            library.Workflows.Add(new WorkflowLibraryItem
            {
                ID = graph.WorkspaceID,
                Name = resolvedWorkflowName,
                Graph = CloneGraph(graph)
            });
            return;
        }

        workflow.Name = resolvedWorkflowName;
        workflow.Graph = CloneGraph(graph);
    }

    private static string NextWorkflowName(WorkflowLibraryDocument library)
    {
        var existingNames = library.Workflows
            .Select(workflow => workflow.Name)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        if (!existingNames.Contains("New Workflow"))
        {
            return "New Workflow";
        }

        var index = 2;
        while (existingNames.Contains($"New Workflow {index}"))
        {
            index++;
        }

        return $"New Workflow {index}";
    }

    private static AgentGraph CloneGraph(AgentGraph graph)
    {
        var json = JsonSerializer.Serialize(graph, MapofAgentsJson.Options);
        return JsonSerializer.Deserialize<AgentGraph>(json, MapofAgentsJson.Options) ?? new AgentGraph();
    }
}

public sealed record WorkflowRecord(
    string ID,
    string Name,
    bool IsActive,
    int NodeCount,
    int LineCount,
    DateTimeOffset UpdatedAt);

internal sealed class WorkflowLibraryDocument
{
    [JsonPropertyName("activeWorkflowID")]
    public string? ActiveWorkflowID { get; set; }

    [JsonPropertyName("workflows")]
    public List<WorkflowLibraryItem> Workflows { get; set; } = [];
}

internal sealed class WorkflowLibraryItem
{
    [JsonPropertyName("id")]
    public string ID { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("graph")]
    public AgentGraph Graph { get; set; } = new();
}
