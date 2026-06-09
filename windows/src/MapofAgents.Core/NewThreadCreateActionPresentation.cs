namespace MapofAgents.Core;

public readonly record struct NewThreadCreateActionPresentationSnapshot(
    string StatusText,
    bool IsButtonEnabled,
    double ButtonOpacity,
    string ToolTip);

public static class NewThreadCreateActionPresentation
{
    public const string ReadyText = "Ready for a new thread.";
    public const string CreatingText = "Creating the new thread...";
    public const string CreateToolTip = "Create thread";
    public const string CreatingUnavailableReason = "Creating this thread now.";
    public const string MissingTargetReason = "Select a machine or folder before creating a thread.";
    public const double AvailableOpacity = 1.0;
    public const double UnavailableOpacity = 0.48;

    public static NewThreadCreateActionPresentationSnapshot Resolve(
        bool isCreating,
        string? unavailableReason)
    {
        if (isCreating)
        {
            return new NewThreadCreateActionPresentationSnapshot(
                CreatingText,
                true,
                UnavailableOpacity,
                CreatingUnavailableReason);
        }

        if (!string.IsNullOrWhiteSpace(unavailableReason))
        {
            return new NewThreadCreateActionPresentationSnapshot(
                ReadyText,
                true,
                UnavailableOpacity,
                unavailableReason);
        }

        return new NewThreadCreateActionPresentationSnapshot(
            ReadyText,
            true,
            AvailableOpacity,
            CreateToolTip);
    }
}
