namespace MapofAgents.Core;

public readonly record struct ThreadInboxRowActionPresentationSnapshot(
    string AddToCanvasToolTip,
    string AddToCanvasAccessibilityLabel,
    string MarkReadIconKind,
    string MarkReadLabel,
    string MarkReadAccessibilityLabel,
    string ArchiveIconKind,
    string ArchiveLabel,
    string ArchiveAccessibilityLabel,
    bool ShowsArchiveAction,
    double ActionButtonSize,
    string ActionIconHex,
    double AddToCanvasStrokeThickness,
    double AddToCanvasBackLayerOpacity,
    double MarkReadStrokeThickness,
    double MarkReadBadgeSize,
    double ArchiveStrokeThickness);

public static class ThreadInboxRowActionPresentation
{
    public const string PlusSquareOnSquareIcon = "plusSquareOnSquare";
    public const string EnvelopeOpenIcon = "envelopeOpen";
    public const string EnvelopeBadgeIcon = "envelopeBadge";
    public const string ArchiveBoxIcon = "archiveBox";
    public const string AddToCanvasToolTip = "Add to canvas";
    public const double ActionButtonSize = 18;
    public const string ActionIconHex = ThreadInboxPresentation.SecondaryHex;
    public const double AddToCanvasStrokeThickness = 1.1;
    public const double AddToCanvasBackLayerOpacity = 0.72;
    public const double MarkReadStrokeThickness = 1.15;
    public const double MarkReadBadgeSize = 4;
    public const double ArchiveStrokeThickness = 1.15;

    public static ThreadInboxRowActionPresentationSnapshot Resolve(bool unread, bool archived, string title)
    {
        var actionTarget = string.IsNullOrWhiteSpace(title) ? "thread" : title.Trim();
        var markReadLabel = unread ? "Mark read" : "Mark unread";

        return new ThreadInboxRowActionPresentationSnapshot(
            AddToCanvasToolTip,
            $"Add {actionTarget} to canvas",
            unread ? EnvelopeOpenIcon : EnvelopeBadgeIcon,
            markReadLabel,
            unread ? $"Mark {actionTarget} read" : $"Mark {actionTarget} unread",
            ArchiveBoxIcon,
            "Archive",
            $"Archive {actionTarget}",
            !archived,
            ActionButtonSize,
            ActionIconHex,
            AddToCanvasStrokeThickness,
            AddToCanvasBackLayerOpacity,
            MarkReadStrokeThickness,
            MarkReadBadgeSize,
            ArchiveStrokeThickness);
    }
}
