namespace MapofAgents.Core;

public readonly record struct ThreadInboxWorkflowFilterPresentationSnapshot(
    string IconKind,
    string Title);

public static class ThreadInboxWorkflowFilterPresentation
{
    public const string All = "all";
    public const string OnWorkflows = "onWorkflows";
    public const string NotOnWorkflows = "notOnWorkflows";
    public const string Workflow = "workflow";

    public const string TrayFullIcon = "trayFull";
    public const string RectangleGroupIcon = "rectangleGroup";
    public const string DashedRectangleIcon = "dashedRectangle";
    public const string RectangleStackIcon = "rectangleStack";
    public const string CheckmarkRectangleStackIcon = "checkmarkRectangleStack";

    public static ThreadInboxWorkflowFilterPresentationSnapshot Resolve(
        string kind,
        bool isActiveWorkflow = false,
        string? workflowName = null,
        int? workflowCount = null)
    {
        if (kind == Workflow)
        {
            return new ThreadInboxWorkflowFilterPresentationSnapshot(
                isActiveWorkflow ? CheckmarkRectangleStackIcon : RectangleStackIcon,
                WorkflowTitle(workflowName, workflowCount));
        }

        return new ThreadInboxWorkflowFilterPresentationSnapshot(kind switch
        {
            All => TrayFullIcon,
            OnWorkflows => RectangleGroupIcon,
            NotOnWorkflows => DashedRectangleIcon,
            _ => TrayFullIcon
        }, "");
    }

    public static string WorkflowTitle(string? workflowName, int? count)
    {
        var name = string.IsNullOrWhiteSpace(workflowName) ? "Workflow" : workflowName.Trim();
        return count is null ? name : $"{name} ({count.Value})";
    }
}
