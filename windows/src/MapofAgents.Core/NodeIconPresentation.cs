namespace MapofAgents.Core;

public readonly record struct NodeIconPresentationSnapshot(
    string Glyph,
    bool UsesThreadPairIcon);

public static class NodeIconPresentation
{
    public const string MachineGlyph = "\uE950";
    public const string FolderGlyph = "\uE8B7";
    public const string SubagentGlyph = "\uE716";

    public static NodeIconPresentationSnapshot Resolve(string? kind, bool isSubagent = false)
    {
        if (isSubagent)
        {
            return new NodeIconPresentationSnapshot(SubagentGlyph, UsesThreadPairIcon: false);
        }

        return kind switch
        {
            NodeKinds.Machine => new NodeIconPresentationSnapshot(MachineGlyph, UsesThreadPairIcon: false),
            NodeKinds.Folder => new NodeIconPresentationSnapshot(FolderGlyph, UsesThreadPairIcon: false),
            NodeKinds.CodexThread => new NodeIconPresentationSnapshot(string.Empty, UsesThreadPairIcon: true),
            _ => new NodeIconPresentationSnapshot("\uE8A5", UsesThreadPairIcon: false)
        };
    }

    public static IReadOnlyDictionary<string, NodeIconPresentationSnapshot> WebPresentationMap()
    {
        return new Dictionary<string, NodeIconPresentationSnapshot>(StringComparer.Ordinal)
        {
            [NodeKinds.Machine] = Resolve(NodeKinds.Machine),
            [NodeKinds.Folder] = Resolve(NodeKinds.Folder),
            [NodeKinds.CodexThread] = Resolve(NodeKinds.CodexThread),
            [ThreadKinds.Subagent] = Resolve(NodeKinds.CodexThread, isSubagent: true),
            ["unknown"] = Resolve(null)
        };
    }
}
