namespace MapofAgents.Core;

public readonly record struct ThreadInboxEmptyStatePresentationSnapshot(
    string Message);

public static class ThreadInboxEmptyStatePresentation
{
    public const string ActiveMode = "active";
    public const string FinishedMode = "finished";
    public const string NeedsYouMode = "needsYou";
    public const string UnreadMode = "unread";
    public const string RecentMode = "recent";
    public const string SearchMode = "search";
    public const string ArchivedMode = "archived";
    public const string ActiveEmptyMessage = "No active threads found.";
    public const string FinishedEmptyMessage = "No finished threads found.";
    public const string NeedsYouEmptyMessage = "Nothing needs you right now.";
    public const string UnreadEmptyMessage = "No unread thread changes.";
    public const string RecentEmptyMessage = "No known threads yet.";
    public const string SearchPromptMessage = "Type to search known threads.";
    public const string SearchNoMatchMessage = "No matching threads.";
    public const string ArchivedEmptyMessage = "No archived threads loaded.";

    public static ThreadInboxEmptyStatePresentationSnapshot Resolve(
        string? mode,
        string? searchText,
        string? workflowFilter = null)
    {
        // Mac derives this copy from the selected inbox mode and search text only.
        _ = workflowFilter;

        var query = searchText?.Trim() ?? string.Empty;
        if (!string.IsNullOrWhiteSpace(query))
        {
            return new ThreadInboxEmptyStatePresentationSnapshot(SearchNoMatchMessage);
        }

        return new ThreadInboxEmptyStatePresentationSnapshot(mode switch
        {
            FinishedMode => FinishedEmptyMessage,
            NeedsYouMode => NeedsYouEmptyMessage,
            UnreadMode => UnreadEmptyMessage,
            RecentMode => RecentEmptyMessage,
            SearchMode => SearchPromptMessage,
            ArchivedMode => ArchivedEmptyMessage,
            _ => ActiveEmptyMessage
        });
    }
}
