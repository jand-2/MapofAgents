namespace MapofAgents.Core;

public enum MentionSelectionKey
{
    ArrowUp,
    ArrowDown,
    Enter,
    Escape
}

public readonly record struct MentionSelectionResult(
    bool Handled,
    int SelectedIndex,
    bool ShouldAccept,
    bool ShouldDismiss);

/// <summary>
/// Owns keyboard selection for a mention suggestion list without taking focus
/// away from its composer. The UI remains responsible for applying the
/// selected suggestion and reflecting <see cref="SelectedIndex"/> visually.
/// </summary>
public sealed class MentionSelectionController
{
    public int SelectedIndex { get; private set; } = -1;

    public string? QueryIdentity { get; private set; }

    public bool IsDismissed { get; private set; }

    public bool ActivateQuery(string queryIdentity)
    {
        ArgumentNullException.ThrowIfNull(queryIdentity);
        if (!string.Equals(QueryIdentity, queryIdentity, StringComparison.Ordinal))
        {
            QueryIdentity = queryIdentity;
            IsDismissed = false;
            SelectedIndex = -1;
        }

        return !IsDismissed;
    }

    public void UpdateSuggestionCount(int suggestionCount)
    {
        ValidateSuggestionCount(suggestionCount);
        if (suggestionCount == 0)
        {
            SelectedIndex = -1;
            return;
        }

        if (SelectedIndex < 0 || SelectedIndex >= suggestionCount)
        {
            SelectedIndex = 0;
        }
    }

    public MentionSelectionResult Handle(MentionSelectionKey key, int suggestionCount)
    {
        ValidateSuggestionCount(suggestionCount);
        if (suggestionCount == 0)
        {
            SelectedIndex = -1;
            return default;
        }

        UpdateSuggestionCount(suggestionCount);
        switch (key)
        {
            case MentionSelectionKey.ArrowUp:
                SelectedIndex = SelectedIndex <= 0
                    ? suggestionCount - 1
                    : SelectedIndex - 1;
                return new MentionSelectionResult(true, SelectedIndex, false, false);
            case MentionSelectionKey.ArrowDown:
                SelectedIndex = SelectedIndex >= suggestionCount - 1
                    ? 0
                    : SelectedIndex + 1;
                return new MentionSelectionResult(true, SelectedIndex, false, false);
            case MentionSelectionKey.Enter:
                return new MentionSelectionResult(true, SelectedIndex, true, false);
            case MentionSelectionKey.Escape:
                IsDismissed = true;
                SelectedIndex = -1;
                return new MentionSelectionResult(true, -1, false, true);
            default:
                return default;
        }
    }

    public void Reset()
    {
        SelectedIndex = -1;
        QueryIdentity = null;
        IsDismissed = false;
    }

    private static void ValidateSuggestionCount(int suggestionCount)
    {
        if (suggestionCount < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(suggestionCount));
        }
    }
}
