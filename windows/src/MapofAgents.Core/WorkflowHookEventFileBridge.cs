using System.Text;

namespace MapofAgents.Core;

public sealed class WorkflowHookEventFileBridge
{
    public WorkflowHookEventFileBridge(
        string? eventFilePath = null,
        TimeSpan? pollInterval = null,
        string? defaultHostID = null)
    {
        EventFilePath = string.IsNullOrWhiteSpace(eventFilePath)
            ? DefaultEventFilePath()
            : eventFilePath.Trim();
        PollInterval = pollInterval ?? TimeSpan.FromMilliseconds(500);
        DefaultHostID = defaultHostID;
    }

    public string EventFilePath { get; }

    public TimeSpan PollInterval { get; }

    public string? DefaultHostID { get; }

    public static string DefaultEventFilePath(string? homeDirectory = null)
    {
        var home = string.IsNullOrWhiteSpace(homeDirectory)
            ? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
            : homeDirectory.Trim();
        if (string.IsNullOrWhiteSpace(home))
        {
            home = Environment.GetEnvironmentVariable("USERPROFILE") ?? Environment.CurrentDirectory;
        }

        return Path.Combine(home, ".codex", "mapofagents", "hook-events.jsonl");
    }

    public async Task RunAsync(
        Func<IReadOnlyList<WorkflowEvent>, CancellationToken, Task> onEvents,
        bool replayExistingEvents = false,
        CancellationToken cancellationToken = default)
    {
        PrepareEventFile();
        var offset = replayExistingEvents ? 0L : FileSize();
        var pendingLine = "";

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var currentSize = FileSize();
                if (currentSize < offset)
                {
                    offset = replayExistingEvents ? 0L : currentSize;
                    pendingLine = "";
                }

                var text = await ReadAppendedTextAsync(offset, cancellationToken).ConfigureAwait(false);
                if (!string.IsNullOrEmpty(text.Content))
                {
                    offset = text.NextOffset;
                    var lines = CompleteLines(text.Content, ref pendingLine);
                    var events = lines
                        .Select(line => WorkflowEventParser.Parse(line, DefaultHostID))
                        .Where(workflowEvent => workflowEvent is not null)
                        .Select(workflowEvent => workflowEvent!)
                        .ToList();
                    if (events.Count > 0)
                    {
                        await onEvents(events, cancellationToken).ConfigureAwait(false);
                    }
                }
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }

            try
            {
                await Task.Delay(PollInterval, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
        }
    }

    private void PrepareEventFile()
    {
        var directory = Path.GetDirectoryName(EventFilePath);
        if (!string.IsNullOrWhiteSpace(directory))
        {
            Directory.CreateDirectory(directory);
        }

        if (!File.Exists(EventFilePath))
        {
            using var _ = File.Create(EventFilePath);
        }
    }

    private long FileSize()
    {
        return File.Exists(EventFilePath) ? new FileInfo(EventFilePath).Length : 0L;
    }

    private async Task<AppendedText> ReadAppendedTextAsync(long offset, CancellationToken cancellationToken)
    {
        if (!File.Exists(EventFilePath))
        {
            return new AppendedText("", 0L);
        }

        await using var stream = new FileStream(
            EventFilePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        if (offset >= stream.Length)
        {
            return new AppendedText("", offset);
        }

        stream.Seek(offset, SeekOrigin.Begin);
        using var reader = new StreamReader(
            stream,
            Encoding.UTF8,
            detectEncodingFromByteOrderMarks: true,
            leaveOpen: true);
        var content = await reader.ReadToEndAsync(cancellationToken).ConfigureAwait(false);
        return new AppendedText(content, stream.Position);
    }

    private static IReadOnlyList<string> CompleteLines(string text, ref string pendingLine)
    {
        var combined = pendingLine + text;
        if (string.IsNullOrEmpty(combined))
        {
            return [];
        }

        var parts = combined
            .Split('\n', StringSplitOptions.None)
            .ToList();
        if (combined.EndsWith('\n'))
        {
            pendingLine = "";
            if (parts.Count > 0 && parts[^1] == "")
            {
                parts.RemoveAt(parts.Count - 1);
            }
        }
        else
        {
            pendingLine = parts.Count == 0 ? "" : parts[^1];
            if (parts.Count > 0)
            {
                parts.RemoveAt(parts.Count - 1);
            }
        }

        return parts
            .Select(line => line.Trim())
            .Where(line => line.Length > 0)
            .ToList();
    }

    private readonly record struct AppendedText(string Content, long NextOffset);
}
