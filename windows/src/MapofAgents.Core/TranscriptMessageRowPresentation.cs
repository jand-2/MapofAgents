namespace MapofAgents.Core;

public readonly record struct TranscriptMessageRowPresentationSnapshot(
    string SourceRole,
    string RoleTitle,
    string WindowsGlyph,
    string RowBackgroundHex,
    string RowBorderHex,
    string BadgeBackgroundHex,
    string RoleForegroundHex);

public static class TranscriptMessageRowPresentation
{
    public const string UserRole = "user";
    public const string AssistantRole = "assistant";
    public const string UserRoleTitle = "You";
    public const string AssistantRoleTitle = "Codex";
    public const string UserWindowsGlyph = "\uE13D";
    public const string AssistantWindowsGlyph = "\uE8F2";
    public const string UserRowBackgroundHex = "#1A0A84FF";
    public const string AssistantRowBackgroundHex = "#1A30D158";
    public const string RowBorderHex = "#00FFFFFF";
    public const string HiddenBadgeBackgroundHex = "#00FFFFFF";

    public static TranscriptMessageRowPresentationSnapshot Resolve(string? role)
    {
        var isAssistant = string.Equals(
            role?.Trim(),
            AssistantRole,
            StringComparison.OrdinalIgnoreCase);

        return new TranscriptMessageRowPresentationSnapshot(
            isAssistant ? AssistantRole : UserRole,
            isAssistant ? AssistantRoleTitle : UserRoleTitle,
            isAssistant ? AssistantWindowsGlyph : UserWindowsGlyph,
            isAssistant ? AssistantRowBackgroundHex : UserRowBackgroundHex,
            RowBorderHex,
            HiddenBadgeBackgroundHex,
            isAssistant ? TranscriptCategoryPresentation.GreenHex : TranscriptCategoryPresentation.BlueHex);
    }
}
