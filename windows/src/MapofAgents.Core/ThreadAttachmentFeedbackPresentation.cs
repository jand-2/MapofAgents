namespace MapofAgents.Core;

public readonly record struct ThreadAttachmentFeedbackPresentationSnapshot(
    string ClipboardUnavailableReason,
    string ErrorForegroundHex,
    double ErrorFontSize,
    int ErrorLineLimit,
    string CountForegroundHex,
    double CountFontSize);

public static class ThreadAttachmentFeedbackPresentation
{
    public const string ClipboardUnavailableReason = "Clipboard does not contain a file or screenshot.";
    public const string ErrorForegroundHex = "#FF453A";
    public const double ErrorFontSize = 10;
    public const int ErrorLineLimit = 2;
    public const string CountForegroundHex = "#A7B0BF";
    public const double CountFontSize = 10;

    public static string CountText(int pendingAttachmentCount)
    {
        return pendingAttachmentCount <= 0
            ? ""
            : $"{pendingAttachmentCount} attached";
    }

    public static ThreadAttachmentFeedbackPresentationSnapshot Resolve()
    {
        return new ThreadAttachmentFeedbackPresentationSnapshot(
            ClipboardUnavailableReason,
            ErrorForegroundHex,
            ErrorFontSize,
            ErrorLineLimit,
            CountForegroundHex,
            CountFontSize);
    }
}
