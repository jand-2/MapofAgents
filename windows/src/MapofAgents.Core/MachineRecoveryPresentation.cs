namespace MapofAgents.Core;

public readonly record struct MachineRecoveryHeaderPresentationSnapshot(
    string MacSymbolName,
    string IconKind,
    string ForegroundHex,
    double IconSize,
    string AccessibilityName);

public readonly record struct MachineRecoveryStatusPresentationSnapshot(
    string Text,
    string Glyph,
    string ForegroundHex,
    string BackgroundHex,
    string BorderHex);

public readonly record struct MachineRecoveryRailPresentationSnapshot(
    bool ShowsFooterActions,
    bool RequiresRecoveryTargets,
    bool ShowsEmptyState,
    string StepActionControlKind,
    string RecommendedStepActionStyle,
    string StandardStepActionStyle);

public readonly record struct MachineRecoveryActionPresentationSnapshot(
    string StepId,
    string MacSymbolName,
    string Glyph);

public static class MachineRecoveryPresentation
{
    public const string HeaderMacSymbolName = "cross.case";
    public const string HeaderIconKind = "crossCase";
    public const string HeaderForegroundHex = "#D7DCE5";
    public const double HeaderIconSize = 16;
    public const string HeaderAccessibilityName = "Machine Recovery";
    public const string SecondaryHex = "#A7B0BF";
    public const string BlueHex = "#0A84FF";
    public const string GreenHex = "#30D158";
    public const string OrangeHex = "#FF9F0A";
    public const string RedHex = "#FF453A";
    public const string SecondaryBackgroundHex = "#1FA7B0BF";
    public const string BlueBackgroundHex = "#1F0A84FF";
    public const string GreenBackgroundHex = "#1F30D158";
    public const string OrangeBackgroundHex = "#1FFF9F0A";
    public const string RedBackgroundHex = "#1FFF453A";
    public const string SecondaryBorderHex = "#2EA7B0BF";
    public const string BlueBorderHex = "#2E0A84FF";
    public const string GreenBorderHex = "#2E30D158";
    public const string OrangeBorderHex = "#2EFF9F0A";
    public const string RedBorderHex = "#2EFF453A";
    public const string MachineGlyph = "\uE950";
    public const string RunningGlyph = "\uE895";
    public const string PassedGlyph = "\uE73E";
    public const string WarningGlyph = "\uE7BA";
    public const string FailedGlyph = "\uE711";
    public const string PendingGlyph = "\uEA3A";
    public const bool ShowsFooterActions = false;
    public const bool RequiresRecoveryTargets = true;
    public const bool ShowsEmptyState = false;
    public const string StepActionControlKind = "button";
    public const string RecommendedStepActionStyle = "borderedProminent";
    public const string StandardStepActionStyle = "bordered";
    public const string VerifyEndpointStepId = "verify-endpoint";
    public const string AppServerStepId = "app-server";
    public const string ReconnectStepId = "reconnect";
    public const string RemoveRouteStepId = "remove-route";
    public const string VerifyEndpointActionMacSymbolName = "network";
    public const string AppServerActionMacSymbolName = "arrow.clockwise";
    public const string ReconnectActionMacSymbolName = "antenna.radiowaves.left.and.right";
    public const string RemoveRouteActionMacSymbolName = "trash";
    public const string DefaultActionMacSymbolName = "circle";
    public const string VerifyEndpointActionGlyph = "\uE8CE";
    public const string AppServerActionGlyph = "\uE72C";
    public const string ReconnectActionGlyph = "\uE8CE";
    public const string RemoveRouteActionGlyph = "\uE74D";
    public const string DefaultActionGlyph = "\uEA3A";

    public static MachineRecoveryHeaderPresentationSnapshot Header()
    {
        return new MachineRecoveryHeaderPresentationSnapshot(
            HeaderMacSymbolName,
            HeaderIconKind,
            HeaderForegroundHex,
            HeaderIconSize,
            HeaderAccessibilityName);
    }

    public static MachineRecoveryRailPresentationSnapshot Rail()
    {
        return new MachineRecoveryRailPresentationSnapshot(
            ShowsFooterActions,
            RequiresRecoveryTargets,
            ShowsEmptyState,
            StepActionControlKind,
            RecommendedStepActionStyle,
            StandardStepActionStyle);
    }

    public static bool ShouldShowRail(bool isPresented, int recoveryTargetCount)
    {
        var rail = Rail();
        return isPresented &&
            (!rail.RequiresRecoveryTargets || Math.Max(0, recoveryTargetCount) > 0);
    }

    public static MachineRecoveryActionPresentationSnapshot StepAction(string? stepId)
    {
        return stepId switch
        {
            VerifyEndpointStepId => Action(VerifyEndpointStepId, VerifyEndpointActionMacSymbolName, VerifyEndpointActionGlyph),
            AppServerStepId => Action(AppServerStepId, AppServerActionMacSymbolName, AppServerActionGlyph),
            ReconnectStepId => Action(ReconnectStepId, ReconnectActionMacSymbolName, ReconnectActionGlyph),
            RemoveRouteStepId => Action(RemoveRouteStepId, RemoveRouteActionMacSymbolName, RemoveRouteActionGlyph),
            _ => Action(stepId ?? "", DefaultActionMacSymbolName, DefaultActionGlyph)
        };
    }

    public static MachineRecoveryStatusPresentationSnapshot TargetStatus(string? hostStatus)
    {
        return hostStatus switch
        {
            HostStatuses.Connected => Snapshot(
                "connected",
                PassedGlyph,
                GreenHex,
                GreenBackgroundHex,
                GreenBorderHex),
            HostStatuses.Connecting => Snapshot(
                "running",
                RunningGlyph,
                BlueHex,
                BlueBackgroundHex,
                BlueBorderHex),
            HostStatuses.Unavailable => Snapshot(
                "failed",
                WarningGlyph,
                OrangeHex,
                OrangeBackgroundHex,
                OrangeBorderHex),
            _ => Snapshot(
                "offline",
                MachineGlyph,
                SecondaryHex,
                SecondaryBackgroundHex,
                SecondaryBorderHex)
        };
    }

    public static MachineRecoveryStatusPresentationSnapshot StepStatus(string? status)
    {
        return status switch
        {
            RecoveryStepStatuses.Running => Snapshot(
                RecoveryStepStatuses.Running,
                RunningGlyph,
                BlueHex,
                BlueBackgroundHex,
                BlueBorderHex),
            RecoveryStepStatuses.Passed => Snapshot(
                RecoveryStepStatuses.Passed,
                PassedGlyph,
                GreenHex,
                GreenBackgroundHex,
                GreenBorderHex),
            RecoveryStepStatuses.Warning => Snapshot(
                RecoveryStepStatuses.Warning,
                WarningGlyph,
                OrangeHex,
                OrangeBackgroundHex,
                OrangeBorderHex),
            RecoveryStepStatuses.Failed => Snapshot(
                RecoveryStepStatuses.Failed,
                FailedGlyph,
                RedHex,
                RedBackgroundHex,
                RedBorderHex),
            _ => Snapshot(
                RecoveryStepStatuses.Pending,
                PendingGlyph,
                SecondaryHex,
                SecondaryBackgroundHex,
                SecondaryBorderHex)
        };
    }

    private static MachineRecoveryStatusPresentationSnapshot Snapshot(
        string text,
        string glyph,
        string foregroundHex,
        string backgroundHex,
        string borderHex)
    {
        return new MachineRecoveryStatusPresentationSnapshot(
            text,
            glyph,
            foregroundHex,
            backgroundHex,
            borderHex);
    }

    private static MachineRecoveryActionPresentationSnapshot Action(
        string stepId,
        string macSymbolName,
        string glyph)
    {
        return new MachineRecoveryActionPresentationSnapshot(stepId, macSymbolName, glyph);
    }
}

public static class RecoveryStepStatuses
{
    public const string Pending = "pending";
    public const string Running = "running";
    public const string Passed = "passed";
    public const string Warning = "warning";
    public const string Failed = "failed";
}
