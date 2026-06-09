namespace MapofAgents.Core;

public readonly record struct TranscriptCategoryPresentationSnapshot(
    string Key,
    string Title,
    string CompactTitle,
    string MacSymbolName,
    string WindowsGlyph,
    string ForegroundHex,
    string BackgroundHex,
    string BadgeBackgroundHex,
    string BorderHex);

public static class TranscriptCategoryPresentation
{
    public const string KeyMessages = "messages";
    public const string KeyProgress = "progress";
    public const string KeyThoughts = "thoughts";
    public const string KeyTools = "tools";
    public const string KeyArtifacts = "artifacts";
    public const string KeyApprovals = "approvals";
    public const string KeySystem = "system";

    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string PurpleHex = "#BF5AF2";
    public const string RedHex = "#FF453A";
    public const string SecondaryHex = "#A7B0BF";
    public const string TealHex = "#40C8E0";
    public const string InactiveForegroundHex = "#8F9BAA";
    public const string InactiveBackgroundHex = "#0F697586";
    public const string InactiveBorderHex = "#18697586";
    public const string ActiveBorderHex = "#00FFFFFF";

    public static TranscriptCategoryPresentationSnapshot Resolve(string? key, bool isActive = true)
    {
        var normalized = NormalizeKey(key);
        var foreground = isActive ? ForegroundHex(normalized) : InactiveForegroundHex;
        return Snapshot(
            normalized,
            foreground,
            isActive ? RowBackgroundHex(normalized, foreground) : InactiveBackgroundHex,
            isActive ? AlphaHex(foreground, 0.11) : InactiveBackgroundHex,
            isActive ? ActiveBorderHex : InactiveBorderHex);
    }

    public static bool TryNormalizeKey(string? key, out string normalized)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            normalized = KeySystem;
            return false;
        }

        normalized = NormalizeKey(key);
        return normalized != KeySystem ||
            key.Trim().Equals(KeySystem, StringComparison.OrdinalIgnoreCase) ||
            key.Trim().Equals("event", StringComparison.OrdinalIgnoreCase) ||
            key.Trim().Equals("events", StringComparison.OrdinalIgnoreCase);
    }

    private static string NormalizeKey(string? key)
    {
        return key?.Trim().ToLowerInvariant() switch
        {
            "message" or KeyMessages => KeyMessages,
            KeyProgress => KeyProgress,
            "thought" or KeyThoughts => KeyThoughts,
            "tool" or KeyTools => KeyTools,
            "artifact" or KeyArtifacts => KeyArtifacts,
            "approval" or KeyApprovals => KeyApprovals,
            "event" or "events" or KeySystem => KeySystem,
            _ => KeySystem
        };
    }

    private static TranscriptCategoryPresentationSnapshot Snapshot(
        string key,
        string foregroundHex,
        string backgroundHex,
        string badgeBackgroundHex,
        string borderHex)
    {
        return new TranscriptCategoryPresentationSnapshot(
            key,
            key switch
            {
                KeyMessages => "Messages",
                KeyProgress => "Progress",
                KeyThoughts => "Thoughts",
                KeyTools => "Tools",
                KeyArtifacts => "Artifacts",
                KeyApprovals => "Approvals",
                _ => "System"
            },
            key switch
            {
                KeyMessages => "Msg",
                KeyProgress => "Progress",
                KeyThoughts => "Thought",
                KeyTools => "Tool",
                KeyArtifacts => "Artifact",
                KeyApprovals => "Approval",
                _ => "Event"
            },
            key switch
            {
                KeyMessages => "bubble.left.and.bubble.right",
                KeyProgress => "arrow.triangle.2.circlepath",
                KeyThoughts => "sparkles",
                KeyTools => "wrench.and.screwdriver",
                KeyArtifacts => "shippingbox",
                KeyApprovals => "hand.raised",
                _ => "info.circle"
            },
            key switch
            {
                KeyMessages => "\uE8F2",
                KeyProgress => "\uE895",
                KeyThoughts => "\uEA80",
                KeyTools => "\uE90F",
                KeyArtifacts => "\uE7C3",
                KeyApprovals => "\uE7BA",
                _ => "\uE946"
            },
            foregroundHex,
            backgroundHex,
            badgeBackgroundHex,
            borderHex);
    }

    private static string ForegroundHex(string key)
    {
        return key switch
        {
            KeyMessages => GreenHex,
            KeyProgress => TealHex,
            KeyThoughts => PurpleHex,
            KeyTools => OrangeHex,
            KeyArtifacts => BlueHex,
            KeyApprovals => RedHex,
            _ => SecondaryHex
        };
    }

    private static string RowBackgroundHex(string key, string foregroundHex)
    {
        var opacity = key is KeyArtifacts or KeyApprovals or KeySystem
            ? 0.08
            : 0.09;
        return AlphaHex(foregroundHex, opacity);
    }

    private static string AlphaHex(string hex, double opacity)
    {
        var clean = hex.TrimStart('#');
        var alpha = Math.Clamp((int)Math.Round(opacity * 255), 0, 255);
        return $"#{alpha:X2}{clean}";
    }
}
