namespace MapofAgents.Core;

public static class NewThreadOptionDefaults
{
    public const string DefaultModel = "gpt-5.5";
    public const string DefaultReasoningEffort = "high";
    public const string DefaultApprovalPolicy = "on-request";
    public const string DefaultSandboxMode = "danger-full-access";

    public static IReadOnlyList<string> SupportedReasoningEfforts =>
    [
        "low",
        "medium",
        "high",
        "xhigh"
    ];

    public static IReadOnlyList<CodexModelOption> ModelOptions =>
    [
        DefaultModelOption,
        new CodexModelOption("gpt-5", "gpt-5", "", DefaultReasoningEffort, SupportedReasoningEfforts, false),
        new CodexModelOption("gpt-5-codex", "gpt-5-codex", "", DefaultReasoningEffort, SupportedReasoningEfforts, false),
        new CodexModelOption("gpt-4.1", "gpt-4.1", "", DefaultReasoningEffort, SupportedReasoningEfforts, false)
    ];

    public static CodexModelOption DefaultModelOption =>
        new(DefaultModel, DefaultModel, "", DefaultReasoningEffort, SupportedReasoningEfforts, true);

    public static IReadOnlyList<(string DisplayName, string Value)> ApprovalPolicies =>
    [
        ("On Request", "on-request"),
        ("On Failure", "on-failure"),
        ("Untrusted", "untrusted"),
        ("Never", "never")
    ];

    public static IReadOnlyList<(string DisplayName, string Value)> SandboxModes =>
    [
        ("Full Access", "danger-full-access"),
        ("Workspace Write", "workspace-write"),
        ("Read Only", "read-only")
    ];
}
