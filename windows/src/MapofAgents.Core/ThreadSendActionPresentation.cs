namespace MapofAgents.Core;

public readonly record struct ThreadSendActionPresentationSnapshot(
    string MacSymbolName,
    string WindowsGlyph,
    string PaperPlanePathData,
    string IconFillHex,
    double IconWidth,
    double IconHeight,
    double UnavailableOpacity,
    string MissingContentReason,
    string AwaitingResponseReason,
    string SubmittingReason,
    string ToolTip,
    string AccessibilityName);

public static class ThreadSendActionPresentation
{
    public const string MacSymbolName = "paperplane.fill";
    public const string WindowsGlyph = "\uE724";
    public const string PaperPlanePathData =
        "M 1.2 8.2 L 16.1 1.3 C 16.8 1 17.4 1.7 17 2.4 L 10.4 15 C 10 15.8 8.9 15.6 8.7 14.7 L 7.5 10.4 L 4 12.6 C 3.4 13 2.7 12.4 3 11.7 L 4.3 8.9 L 1.4 8.5 C 0.7 8.4 0.6 8.5 1.2 8.2 Z M 5.2 8.4 L 8.2 9.4 L 13 3.8 Z";
    public const string IconFillHex = "#FFFFFFFF";
    public const double IconWidth = 18;
    public const double IconHeight = 16;
    public const double UnavailableOpacity = 0.48;
    public const string MissingContentReason = "Type a message or attach a file before sending.";
    public const string AwaitingResponseReason = "This thread is still running. Wait for the current turn to finish.";
    public const string SubmittingReason = "This message is still being sent.";
    public const string ToolTip = "Send";
    public const string AccessibilityName = "Send message";

    public static ThreadSendActionAvailability Availability(
        bool isAwaitingResponse,
        bool isSubmitting,
        string draft,
        int pendingAttachmentCount)
    {
        if (isAwaitingResponse)
        {
            return new ThreadSendActionAvailability(AwaitingResponseReason, UnavailableOpacity);
        }

        if (isSubmitting)
        {
            return new ThreadSendActionAvailability(SubmittingReason, UnavailableOpacity);
        }

        if (string.IsNullOrWhiteSpace(draft) && pendingAttachmentCount == 0)
        {
            return new ThreadSendActionAvailability(MissingContentReason, UnavailableOpacity);
        }

        return new ThreadSendActionAvailability(null, 1.0);
    }

    public static ThreadSendActionPresentationSnapshot Resolve()
    {
        return new ThreadSendActionPresentationSnapshot(
            MacSymbolName,
            WindowsGlyph,
            PaperPlanePathData,
            IconFillHex,
            IconWidth,
            IconHeight,
            UnavailableOpacity,
            MissingContentReason,
            AwaitingResponseReason,
            SubmittingReason,
            ToolTip,
            AccessibilityName);
    }
}

public readonly record struct ThreadSendActionAvailability(
    string? UnavailableReason,
    double Opacity);
