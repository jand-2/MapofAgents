namespace MapofAgents.Core;

public static class NewThreadModelCatalog
{
    public static IReadOnlyList<CodexModelOption> OptionsOrFallback(IEnumerable<CodexModelOption>? modelOptions)
    {
        var options = modelOptions?
            .Where(option => !string.IsNullOrWhiteSpace(option.Id))
            .ToList();

        return options is { Count: > 0 }
            ? options
            : NewThreadOptionDefaults.ModelOptions;
    }

    public static CodexModelOption CurrentModel(
        IEnumerable<CodexModelOption>? modelOptions,
        string? selectedModelId)
    {
        var options = OptionsOrFallback(modelOptions);
        if (!string.IsNullOrWhiteSpace(selectedModelId))
        {
            var selected = options.FirstOrDefault(option =>
                string.Equals(option.Id, selectedModelId.Trim(), StringComparison.OrdinalIgnoreCase));
            if (selected is not null)
            {
                return selected;
            }
        }

        return options.FirstOrDefault(option => option.IsDefault)
            ?? options.FirstOrDefault()
            ?? NewThreadOptionDefaults.DefaultModelOption;
    }

    public static string CurrentReasoningEffort(
        CodexModelOption model,
        string? selectedReasoningEffort)
    {
        var efforts = SupportedReasoningEfforts(model);
        if (!string.IsNullOrWhiteSpace(selectedReasoningEffort))
        {
            var selected = selectedReasoningEffort.Trim();
            if (efforts.Contains(selected, StringComparer.OrdinalIgnoreCase))
            {
                return efforts.First(effort => string.Equals(effort, selected, StringComparison.OrdinalIgnoreCase));
            }
        }

        if (!string.IsNullOrWhiteSpace(model.DefaultReasoningEffort) &&
            efforts.Contains(model.DefaultReasoningEffort, StringComparer.OrdinalIgnoreCase))
        {
            return efforts.First(effort =>
                string.Equals(effort, model.DefaultReasoningEffort, StringComparison.OrdinalIgnoreCase));
        }

        return efforts.FirstOrDefault()
            ?? NewThreadOptionDefaults.DefaultReasoningEffort;
    }

    public static IReadOnlyList<string> SupportedReasoningEfforts(CodexModelOption model)
    {
        var efforts = model.SupportedReasoningEfforts
            .Where(effort => !string.IsNullOrWhiteSpace(effort))
            .Select(effort => effort.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();

        return efforts.Count > 0
            ? efforts
            : NewThreadOptionDefaults.SupportedReasoningEfforts;
    }
}
