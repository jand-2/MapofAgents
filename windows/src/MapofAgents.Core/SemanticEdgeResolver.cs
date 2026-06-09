namespace MapofAgents.Core;

public static class SemanticEdgeResolver
{
    public static IReadOnlyList<CanvasEdge> ResolveEdges(AgentGraph graph)
    {
        var machines = graph.Nodes.Values.Where(node => node.Kind == NodeKinds.Machine).ToList();
        var folders = graph.Nodes.Values.Where(node => node.Kind == NodeKinds.Folder).ToList();
        var threads = graph.Nodes.Values
            .Where(node => node.Kind == NodeKinds.CodexThread)
            .Where(node => !string.Equals(node.Metadata.ThreadKind, ThreadKinds.Subagent, StringComparison.Ordinal))
            .ToList();

        var existingEdgeKeys = graph.ManualEdges.Values
            .Select(EdgeKey)
            .ToHashSet(StringComparer.Ordinal);
        var edges = new List<CanvasEdge>();
        var projectThreadIds = new HashSet<string>(StringComparer.Ordinal);

        foreach (var machine in machines)
        {
            foreach (var folder in folders.Where(folder => SameHost(folder.Metadata.HostID, machine.Metadata.HostID)))
            {
                AddSemanticEdge(
                    edges,
                    existingEdgeKeys,
                    machine.Id,
                    folder.Id,
                    EdgeKinds.MachineFolder);
            }
        }

        foreach (var thread in threads)
        {
            var threadRef = thread.Metadata.ThreadRef;
            if (threadRef is null)
            {
                continue;
            }

            var matchingFolder = folders
                .Select(folder => FolderMatch(folder, thread, threadRef))
                .Where(match => match is not null)
                .Select(match => match!.Value)
                .OrderByDescending(match => match.Specificity)
                .ThenBy(match => match.Folder.Id, StringComparer.Ordinal)
                .FirstOrDefault();

            if (matchingFolder.Folder is null)
            {
                continue;
            }

            projectThreadIds.Add(thread.Id);
            AddSemanticEdge(
                edges,
                existingEdgeKeys,
                matchingFolder.Folder.Id,
                thread.Id,
                EdgeKinds.FolderThread);
        }

        foreach (var machine in machines)
        {
            foreach (var thread in threads.Where(thread =>
                         SameHost(thread.Metadata.ThreadRef?.HostID, machine.Metadata.HostID) &&
                         !projectThreadIds.Contains(thread.Id)))
            {
                AddSemanticEdge(
                    edges,
                    existingEdgeKeys,
                    machine.Id,
                    thread.Id,
                    EdgeKinds.MachineThread);
            }
        }

        return edges;
    }

    public static IReadOnlyList<CanvasEdge> AllEdges(AgentGraph graph)
    {
        return ResolveEdges(graph)
            .Concat(graph.ManualEdges.Values.OrderBy(edge => edge.Id, StringComparer.Ordinal))
            .ToList();
    }

    private static void AddSemanticEdge(
        List<CanvasEdge> edges,
        HashSet<string> existingEdgeKeys,
        string source,
        string target,
        string kind)
    {
        var key = EdgeKey(source, target, kind);
        if (existingEdgeKeys.Contains(key))
        {
            return;
        }

        edges.Add(new CanvasEdge
        {
            Id = $"semantic-{kind}-{source}-{target}",
            Source = source,
            Target = target,
            Kind = kind,
            IsManual = false
        });
    }

    private static (CanvasNode Folder, int Specificity)? FolderMatch(
        CanvasNode folder,
        CanvasNode thread,
        ThreadRef threadRef)
    {
        if (string.IsNullOrWhiteSpace(folder.Metadata.FolderPath) ||
            string.IsNullOrWhiteSpace(folder.Metadata.HostID) ||
            !SameHost(threadRef.HostID, folder.Metadata.HostID))
        {
            return null;
        }

        var caseInsensitive = UsesCaseInsensitivePaths(folder, thread);
        var normalizedFolder = Standardize(folder.Metadata.FolderPath, caseInsensitive);
        var normalizedThread = Standardize(threadRef.Cwd, caseInsensitive);
        if (!MatchesInsideOrEqualTo(normalizedThread.Value, normalizedFolder.Value))
        {
            return null;
        }

        return (folder, normalizedFolder.Specificity);
    }

    private static bool MatchesInsideOrEqualTo(string path, string root)
    {
        if (string.Equals(path, root, StringComparison.Ordinal))
        {
            return true;
        }

        var rootWithSlash = root.EndsWith("/", StringComparison.Ordinal)
            ? root
            : $"{root}/";
        return path.StartsWith(rootWithSlash, StringComparison.Ordinal);
    }

    private static NormalizedPath Standardize(string? rawPath, bool caseInsensitive)
    {
        var slashNormalized = (rawPath ?? "").Replace('\\', '/');
        var windowsStyle = IsWindowsStylePath(slashNormalized);
        var standardized = windowsStyle
            ? TrimTrailingSlashes(CollapseSlashes(slashNormalized))
            : TrimTrailingSlashes(NormalizePosixPath(slashNormalized));
        var value = caseInsensitive || windowsStyle
            ? standardized.ToLowerInvariant()
            : standardized;
        var segments = value
            .Split('/', StringSplitOptions.RemoveEmptyEntries)
            .ToList();
        return new NormalizedPath(value, segments.Sum(segment => segment.Length) + segments.Count);
    }

    private static string NormalizePosixPath(string path)
    {
        var hasRoot = path.StartsWith("/", StringComparison.Ordinal);
        var segments = new List<string>();
        foreach (var segment in CollapseSlashes(path).Split('/', StringSplitOptions.RemoveEmptyEntries))
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
        return hasRoot ? $"/{normalized}" : normalized;
    }

    private static bool UsesCaseInsensitivePaths(CanvasNode folder, CanvasNode thread)
    {
        return string.Equals(folder.Metadata.Platform, HostPlatforms.Windows, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(thread.Metadata.Platform, HostPlatforms.Windows, StringComparison.OrdinalIgnoreCase) ||
            IsWindowsStylePath(folder.Metadata.FolderPath) ||
            IsWindowsStylePath(thread.Metadata.ThreadRef?.Cwd);
    }

    private static bool IsWindowsStylePath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return false;
        }

        var slashNormalized = path.Replace('\\', '/');
        return (slashNormalized.Length >= 2 && char.IsAsciiLetter(slashNormalized[0]) && slashNormalized[1] == ':') ||
            slashNormalized.StartsWith("//", StringComparison.Ordinal);
    }

    private static string CollapseSlashes(string path)
    {
        var hasUncPrefix = path.StartsWith("//", StringComparison.Ordinal);
        while (path.Contains("//", StringComparison.Ordinal))
        {
            path = path.Replace("//", "/", StringComparison.Ordinal);
        }

        return hasUncPrefix && !path.StartsWith("//", StringComparison.Ordinal)
            ? $"/{path}"
            : path;
    }

    private static string TrimTrailingSlashes(string path)
    {
        while (path.Length > 1 && path.EndsWith("/", StringComparison.Ordinal))
        {
            path = path[..^1];
        }

        return path;
    }

    private static bool SameHost(string? lhs, string? rhs)
    {
        return string.Equals(lhs, rhs, StringComparison.Ordinal);
    }

    private static string EdgeKey(CanvasEdge edge)
    {
        return EdgeKey(edge.Source, edge.Target, edge.Kind);
    }

    private static string EdgeKey(string source, string target, string kind)
    {
        return $"{kind}\u001F{source}\u001F{target}";
    }

    private readonly record struct NormalizedPath(string Value, int Specificity);
}
