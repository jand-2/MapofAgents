namespace MapofAgents.Core;

public readonly record struct TranscriptTransientRowCounts(
    int ProgressCount,
    int SystemCount)
{
    public int TotalCount => ProgressCount + SystemCount;
}

public static class TranscriptTransientRows
{
    public static TranscriptTransientRowCounts Count(
        bool isLoadingTranscript,
        bool hasTranscriptError)
    {
        return new TranscriptTransientRowCounts(
            isLoadingTranscript ? 1 : 0,
            hasTranscriptError ? 1 : 0);
    }
}
