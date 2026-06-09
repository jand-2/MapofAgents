namespace MapofAgents.Core;

public sealed record CodexModelOption(
    string Id,
    string DisplayName,
    string Description,
    string DefaultReasoningEffort,
    IReadOnlyList<string> SupportedReasoningEfforts,
    bool IsDefault)
{
    public string PickerTitle => string.IsNullOrWhiteSpace(DisplayName) ? Id : DisplayName;
}
