namespace MapofAgents.Core;

public readonly record struct PendingAssistantPresentationSnapshot(
    string MacSymbolName,
    string WindowsGlyph,
    string RoleTitle,
    string Text);

public static class PendingAssistantPresentation
{
    public const string MacSymbolName = "ellipsis";
    public const string WindowsGlyph = "\uE712";
    public const string RoleTitle = "Progress";
    public const string Text = "Waiting for response";

    public static PendingAssistantPresentationSnapshot Resolve()
    {
        return new PendingAssistantPresentationSnapshot(
            MacSymbolName,
            WindowsGlyph,
            RoleTitle,
            Text);
    }
}
