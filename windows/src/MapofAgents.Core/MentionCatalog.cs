using System.Text.Json;

namespace MapofAgents.Core;

public sealed record MentionCatalogCandidate(
    string Id,
    string Kind,
    char Trigger,
    string Label,
    string Title,
    string Subtitle,
    string InsertionText);

public static class MentionCatalog
{
    public const string KindPlugin = "plugin";
    public const string KindThread = "thread";
    public const string KindFolder = "folder";
    public const string KindFile = "file";
    public const string KindSkill = "skill";

    private static readonly HashSet<string> IgnoredDirectoryNames = new(StringComparer.OrdinalIgnoreCase)
    {
        ".build",
        ".git",
        ".swiftpm",
        "DerivedData",
        "dist",
        "node_modules"
    };

    public static MentionCatalogCandidate WorkflowBridgeCandidate { get; } = new(
        "skill:mapofagents-skill://workflow-bridge",
        KindSkill,
        '$',
        "$mapofagents-workflow-bridge",
        "$mapofagents-workflow-bridge",
        "Talk to workflow chats and folders across machines through mapofagents.",
        "[$mapofagents-workflow-bridge](mapofagents-skill://workflow-bridge)");

    public static IReadOnlyList<MentionCatalogCandidate> CatalogMentionCandidates(
        string? skillsJson,
        string? pluginsJson,
        IEnumerable<MentionCatalogCandidate> fileCandidates)
    {
        return UniqueCandidates(
                new[] { WorkflowBridgeCandidate }
                    .Concat(skillsJson is null
                        ? Enumerable.Empty<MentionCatalogCandidate>()
                        : ParseSkillMentionCandidates(skillsJson))
                    .Concat(pluginsJson is null
                        ? Enumerable.Empty<MentionCatalogCandidate>()
                        : ParsePluginMentionCandidates(pluginsJson))
                    .Concat(fileCandidates))
            .OrderBy(candidate => SortPriority(candidate.Kind))
            .ThenBy(candidate => candidate.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    public static IReadOnlyList<MentionCatalogCandidate> UniqueCandidates(
        IEnumerable<MentionCatalogCandidate> candidates)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var unique = new List<MentionCatalogCandidate>();
        foreach (var candidate in candidates)
        {
            var key = string.IsNullOrWhiteSpace(candidate.Id)
                ? $"{candidate.Trigger}:{candidate.InsertionText}"
                : candidate.Id;
            if (seen.Add(key))
            {
                unique.Add(candidate);
            }
        }

        return unique;
    }

    public static IReadOnlyList<MentionCatalogCandidate> ParseSkillMentionCandidates(string json)
    {
        using var document = JsonDocument.Parse(json);
        var payload = Payload(document.RootElement);
        var groupedSkills = CatalogArray(payload)
            .SelectMany(group => ArrayProperty(group, "skills"));
        var directSkills = ArrayProperty(payload, "skills");

        return groupedSkills
            .Concat(directSkills)
            .Select(SkillMentionCandidateFrom)
            .Where(candidate => candidate is not null)
            .Select(candidate => candidate!)
            .ToList();
    }

    public static IReadOnlyList<MentionCatalogCandidate> ParsePluginMentionCandidates(string json)
    {
        using var document = JsonDocument.Parse(json);
        var payload = Payload(document.RootElement);
        return ArrayProperty(payload, "marketplaces")
            .SelectMany(marketplace =>
            {
                var marketplaceName = TryReadString(marketplace, "name") ?? "local";
                return ArrayProperty(marketplace, "plugins")
                    .Select(plugin => PluginMentionCandidateFrom(plugin, marketplaceName));
            })
            .Where(candidate => candidate is not null)
            .Select(candidate => candidate!)
            .ToList();
    }

    public static IReadOnlyList<MentionCatalogCandidate> LocalFileMentionCandidates(
        string? rootPath,
        int limit = 120)
    {
        if (string.IsNullOrWhiteSpace(rootPath) || limit <= 0 || !Directory.Exists(rootPath))
        {
            return [];
        }

        var root = Path.GetFullPath(rootPath);
        var queue = new Queue<string>();
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var candidates = new List<MentionCatalogCandidate>();
        queue.Enqueue(root);

        while (queue.Count > 0 && candidates.Count < limit)
        {
            var current = queue.Dequeue();
            if (!visited.Add(current))
            {
                continue;
            }

            IEnumerable<string> entries;
            try
            {
                entries = Directory.EnumerateFileSystemEntries(current)
                    .OrderBy(path => Path.GetFileName(path), StringComparer.OrdinalIgnoreCase)
                    .ToList();
            }
            catch
            {
                continue;
            }

            foreach (var entry in entries)
            {
                if (candidates.Count >= limit)
                {
                    break;
                }

                var name = Path.GetFileName(entry);
                if (string.IsNullOrWhiteSpace(name) || name.StartsWith('.'))
                {
                    continue;
                }

                FileAttributes attributes;
                try
                {
                    attributes = File.GetAttributes(entry);
                }
                catch
                {
                    continue;
                }

                if ((attributes & FileAttributes.Hidden) != 0 ||
                    (attributes & FileAttributes.ReparsePoint) != 0)
                {
                    continue;
                }

                var isDirectory = (attributes & FileAttributes.Directory) != 0;
                if (isDirectory && IgnoredDirectoryNames.Contains(name))
                {
                    continue;
                }

                var isFile = !isDirectory;
                if (!isDirectory && !isFile)
                {
                    continue;
                }

                var relativePath = Path.GetRelativePath(root, entry)
                    .Replace(Path.DirectorySeparatorChar, '/')
                    .Replace(Path.AltDirectorySeparatorChar, '/');
                var displayName = isDirectory ? $"{name}/" : name;
                candidates.Add(FileMentionCandidate(entry, displayName, relativePath));

                if (isDirectory)
                {
                    queue.Enqueue(entry);
                }
            }
        }

        return candidates;
    }

    public static MentionCatalogCandidate FileMentionCandidate(
        string path,
        string displayName,
        string relativePath)
    {
        return new MentionCatalogCandidate(
            $"file:{path}",
            KindFile,
            '@',
            $"@{relativePath}",
            $"@{displayName}",
            relativePath,
            $"[@{displayName}]({MarkdownTarget(path)})");
    }

    public static int SortPriority(string kind)
    {
        return kind switch
        {
            KindPlugin => 0,
            KindThread => 1,
            KindFolder => 2,
            KindFile => 3,
            KindSkill => 4,
            _ => 9
        };
    }

    private static MentionCatalogCandidate? SkillMentionCandidateFrom(JsonElement skill)
    {
        if (TryReadBool(skill, "enabled") == false)
        {
            return null;
        }

        var name = TryReadString(skill, "name");
        var path = TryReadString(skill, "path");
        if (string.IsNullOrWhiteSpace(name) || string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        var interfaceValue = skill.TryGetProperty("interface", out var interfaceElement)
            ? interfaceElement
            : default;
        var displayName = TryReadString(interfaceValue, "displayName") ?? name;
        var description =
            TryReadString(interfaceValue, "shortDescription") ??
            TryReadString(skill, "description") ??
            path;
        var title = $"${name}";

        return new MentionCatalogCandidate(
            $"skill:{path}",
            KindSkill,
            '$',
            title,
            title,
            string.Equals(displayName, name, StringComparison.Ordinal)
                ? description
                : $"{displayName} - {description}",
            $"[${name}]({path})");
    }

    private static MentionCatalogCandidate? PluginMentionCandidateFrom(JsonElement plugin, string marketplaceName)
    {
        if (TryReadBool(plugin, "enabled") == false ||
            TryReadBool(plugin, "installed") == false)
        {
            return null;
        }

        var rawId = TryReadString(plugin, "id");
        var name = TryReadString(plugin, "name") ?? PluginNameFrom(rawId);
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        var id = rawId ?? $"{name}@{marketplaceName}";
        var interfaceValue = plugin.TryGetProperty("interface", out var interfaceElement)
            ? interfaceElement
            : default;
        var displayName = TryReadString(interfaceValue, "displayName") ?? name;
        var description = TryReadString(interfaceValue, "shortDescription") ?? marketplaceName;
        var title = $"@{name}";

        return new MentionCatalogCandidate(
            $"plugin:{id}",
            KindPlugin,
            '@',
            title,
            title,
            string.Equals(displayName, name, StringComparison.Ordinal)
                ? description
                : $"{displayName} - {description}",
            $"[@{name}](plugin://{id})");
    }

    private static JsonElement Payload(JsonElement root)
    {
        return root.TryGetProperty("result", out var result) ? result : root;
    }

    private static IReadOnlyList<JsonElement> CatalogArray(JsonElement result)
    {
        if (result.ValueKind == JsonValueKind.Array)
        {
            return result.EnumerateArray().ToList();
        }

        foreach (var propertyName in new[] { "data", "items", "results" })
        {
            if (result.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.Array)
            {
                return value.EnumerateArray().ToList();
            }
        }

        return [];
    }

    private static IReadOnlyList<JsonElement> ArrayProperty(JsonElement element, string propertyName)
    {
        return element.ValueKind == JsonValueKind.Object &&
            element.TryGetProperty(propertyName, out var value) &&
            value.ValueKind == JsonValueKind.Array
                ? value.EnumerateArray().ToList()
                : [];
    }

    private static string? TryReadString(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
    }

    private static bool? TryReadBool(JsonElement element, string propertyName)
    {
        if (element.ValueKind != JsonValueKind.Object ||
            !element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String when bool.TryParse(value.GetString(), out var parsed) => parsed,
            _ => null
        };
    }

    private static string? PluginNameFrom(string? id)
    {
        return string.IsNullOrWhiteSpace(id)
            ? null
            : id.Split('@', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
    }

    private static string MarkdownTarget(string path)
    {
        var needsAngleBrackets = path.Any(character =>
            char.IsWhiteSpace(character) ||
            character is '(' or ')');
        return needsAngleBrackets
            ? $"<{path.Replace(">", "%3E", StringComparison.Ordinal)}>"
            : path;
    }
}
