namespace MapofAgents.Core;

public readonly record struct AttentionRequestCardSnapshot(
    string MethodText,
    string PromptText,
    bool ShowTargetLabel,
    string BackgroundHex,
    string BorderHex,
    double BorderThickness,
    double HorizontalPadding,
    double VerticalPadding,
    double CornerRadius,
    double StackSpacing,
    double BottomMargin,
    string FocusIconKind,
    double FocusIconWidth,
    double FocusIconHeight,
    double FocusIconStrokeThickness,
    double ActionButtonSpacing,
    double ActionButtonHorizontalPadding,
    double ActionButtonVerticalPadding);

public static class AttentionRequestCardPresentation
{
    public const string MacBackgroundHex = "#18D97706";
    public const string MacBorderHex = "#00FFFFFF";
    public const double MacBorderThickness = 0;
    public const double MacHorizontalPadding = 8;
    public const double MacVerticalPadding = 6;
    public const double MacCornerRadius = 8;
    public const double MacStackSpacing = 8;
    public const double MacBottomMargin = 8;
    public const string FocusExpandIcon = "arrowUpLeftAndArrowDownRight";
    public const double FocusIconWidth = 18;
    public const double FocusIconHeight = 18;
    public const double FocusIconStrokeThickness = 1.15;
    public const double ActionButtonSpacing = 8;
    public const double ActionButtonHorizontalPadding = 7;
    public const double ActionButtonVerticalPadding = 4;

    public static AttentionRequestCardSnapshot Resolve(string? method, string? promptText)
    {
        return new AttentionRequestCardSnapshot(
            string.IsNullOrWhiteSpace(method) ? "Attention request" : method.Trim(),
            string.IsNullOrWhiteSpace(promptText) ? "This thread needs a response." : promptText.Trim(),
            ShowTargetLabel: false,
            MacBackgroundHex,
            MacBorderHex,
            MacBorderThickness,
            MacHorizontalPadding,
            MacVerticalPadding,
            MacCornerRadius,
            MacStackSpacing,
            MacBottomMargin,
            FocusExpandIcon,
            FocusIconWidth,
            FocusIconHeight,
            FocusIconStrokeThickness,
            ActionButtonSpacing,
            ActionButtonHorizontalPadding,
            ActionButtonVerticalPadding);
    }
}
