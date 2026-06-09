namespace MapofAgents.Core;

public static class ReaderModeOpeningPolicy
{
    public static string? ThreadToAddWhenOpening(
        bool isOpeningReader,
        int existingReaderThreadCount,
        string? selectedNodeId,
        bool selectedNodeIsThread)
    {
        if (!isOpeningReader || existingReaderThreadCount > 0)
        {
            return null;
        }

        return selectedNodeIsThread && !string.IsNullOrWhiteSpace(selectedNodeId)
            ? selectedNodeId
            : null;
    }
}
