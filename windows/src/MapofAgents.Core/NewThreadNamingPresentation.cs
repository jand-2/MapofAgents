namespace MapofAgents.Core;

public static class NewThreadNamingPresentation
{
    public const string DefaultThreadName = "Codex thread";
    public const string FolderThreadSuffix = "agent";
    public const string MachineThreadSuffix = "chat";

    public static string ResolveForTarget(string? targetTitle, string targetKind)
    {
        if (string.IsNullOrWhiteSpace(targetTitle))
        {
            return DefaultThreadName;
        }

        var suffix = string.Equals(targetKind, NodeKinds.Machine, StringComparison.Ordinal)
            ? MachineThreadSuffix
            : FolderThreadSuffix;
        return $"{targetTitle} {suffix}";
    }
}
