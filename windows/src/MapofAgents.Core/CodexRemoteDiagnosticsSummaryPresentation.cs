namespace MapofAgents.Core;

public readonly record struct CodexRemoteDiagnosticsSummaryPresentationSnapshot(
    bool ShowsSummary,
    bool ShowsDiagnosticsButton,
    string Glyph,
    string Text,
    string ForegroundHex,
    string ToolTip,
    string AutomationName);

public static class CodexRemoteDiagnosticsSummaryPresentation
{
    public const string RunningText = "Remote diagnostics running";
    public const string DiagnosticsButtonToolTip = "Open remote diagnostics";
    public const string DiagnosticsButtonAutomationName = "Remote Diagnostics";

    public static CodexRemoteDiagnosticsSummaryPresentationSnapshot Resolve(
        IEnumerable<RuntimeDiagnosticStep> steps,
        bool isBusy)
    {
        var stepList = steps.ToList();
        if (isBusy || stepList.Any(IsRunning))
        {
            var running = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Running);
            return new CodexRemoteDiagnosticsSummaryPresentationSnapshot(
                ShowsSummary: true,
                ShowsDiagnosticsButton: false,
                running.Glyph,
                RunningText,
                ThreadInboxPresentation.BlueHex,
                RunningText,
                DiagnosticsButtonAutomationName);
        }

        var attentionStep = stepList.FirstOrDefault(IsAttention);
        if (attentionStep is null)
        {
            return new CodexRemoteDiagnosticsSummaryPresentationSnapshot(
                ShowsSummary: false,
                ShowsDiagnosticsButton: false,
                string.Empty,
                string.Empty,
                ThreadInboxPresentation.SecondaryHex,
                DiagnosticsButtonToolTip,
                DiagnosticsButtonAutomationName);
        }

        var presentation = RuntimeDiagnosticsRailPresentation.Resolve(attentionStep.Status);
        var text = string.IsNullOrWhiteSpace(attentionStep.Title)
            ? "Remote diagnostics need attention"
            : attentionStep.Title.Trim();
        return new CodexRemoteDiagnosticsSummaryPresentationSnapshot(
            ShowsSummary: true,
            ShowsDiagnosticsButton: true,
            presentation.Glyph,
            text,
            ThreadInboxPresentation.OrangeHex,
            DiagnosticsButtonToolTip,
            DiagnosticsButtonAutomationName);
    }

    private static bool IsRunning(RuntimeDiagnosticStep step)
    {
        return string.Equals(step.Status, RuntimeDiagnosticStatuses.Running, StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsAttention(RuntimeDiagnosticStep step)
    {
        return string.Equals(step.Status, RuntimeDiagnosticStatuses.Failed, StringComparison.OrdinalIgnoreCase) ||
            string.Equals(step.Status, RuntimeDiagnosticStatuses.Warning, StringComparison.OrdinalIgnoreCase);
    }
}
