namespace MapofAgents.Core;

public enum TranscriptLoadPhase
{
    Idle,
    ConnectingHost,
    LoadingHistory,
    HydratingArtifacts,
    Refreshing,
    LoadingOlder
}

public readonly record struct TranscriptLoadPhasePresentationSnapshot(
    TranscriptLoadPhase Phase,
    string Title,
    string Detail,
    string MacSymbolName,
    string WindowsGlyph);

public static class TranscriptLoadPhasePresentation
{
    public const string CheckmarkCircleMacSymbolName = "checkmark.circle";
    public const string ConnectingHostMacSymbolName = "antenna.radiowaves.left.and.right";
    public const string LoadingHistoryMacSymbolName = "text.bubble";
    public const string HydratingArtifactsMacSymbolName = "shippingbox";
    public const string RefreshingMacSymbolName = "arrow.clockwise";
    public const string LoadingOlderMacSymbolName = "clock.arrow.circlepath";

    public const string CheckmarkCircleGlyph = "\uE73E";
    public const string ConnectingHostGlyph = "\uE968";
    public const string LoadingHistoryGlyph = "\uE8F2";
    public const string HydratingArtifactsGlyph = "\uE7C3";
    public const string RefreshingGlyph = "\uE72C";
    public const string LoadingOlderGlyph = "\uE823";

    public static TranscriptLoadPhase InitialPhase(bool isLoadingOlder, bool hasLoadedTranscript)
    {
        if (isLoadingOlder)
        {
            return TranscriptLoadPhase.LoadingOlder;
        }

        return hasLoadedTranscript
            ? TranscriptLoadPhase.Refreshing
            : TranscriptLoadPhase.ConnectingHost;
    }

    public static TranscriptLoadPhasePresentationSnapshot Resolve(TranscriptLoadPhase phase)
    {
        return phase switch
        {
            TranscriptLoadPhase.ConnectingHost => new TranscriptLoadPhasePresentationSnapshot(
                phase,
                "Checking host connection",
                "Waiting on the owning machine or App Server route.",
                ConnectingHostMacSymbolName,
                ConnectingHostGlyph),
            TranscriptLoadPhase.LoadingHistory => new TranscriptLoadPhasePresentationSnapshot(
                phase,
                "Loading message history",
                "Waiting on thread history from Codex App Server.",
                LoadingHistoryMacSymbolName,
                LoadingHistoryGlyph),
            TranscriptLoadPhase.HydratingArtifacts => new TranscriptLoadPhasePresentationSnapshot(
                phase,
                "Hydrating artifacts",
                "Reading generated files, diffs, or images.",
                HydratingArtifactsMacSymbolName,
                HydratingArtifactsGlyph),
            TranscriptLoadPhase.Refreshing => new TranscriptLoadPhasePresentationSnapshot(
                phase,
                "Refreshing transcript",
                "Keeping the last loaded messages visible.",
                RefreshingMacSymbolName,
                RefreshingGlyph),
            TranscriptLoadPhase.LoadingOlder => new TranscriptLoadPhasePresentationSnapshot(
                phase,
                "Loading older messages",
                "Prepending an older transcript page.",
                LoadingOlderMacSymbolName,
                LoadingOlderGlyph),
            _ => new TranscriptLoadPhasePresentationSnapshot(
                TranscriptLoadPhase.Idle,
                "Ready",
                "",
                CheckmarkCircleMacSymbolName,
                CheckmarkCircleGlyph)
        };
    }
}
