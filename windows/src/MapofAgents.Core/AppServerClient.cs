using System.Net;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace MapofAgents.Core;

public enum AppServerEndpointTrust
{
    Standard,
    SignedPairingPayload
}

public sealed record AppServerEndpoint(
    string Name,
    Uri Url,
    string? BearerToken,
    AppServerEndpointTrust Trust = AppServerEndpointTrust.Standard);

public sealed record EndpointValidationResult(bool IsValid, string? Message)
{
    public static EndpointValidationResult Valid { get; } = new(true, null);
}

public sealed record AppServerInitializeResult(string HostName, string Platform, string? CodexHome, string RawJson);

public sealed record AppServerThreadCatalogEntry(
    ThreadRef ThreadRef,
    string HostName,
    string Title,
    string Preview,
    string? Source,
    bool Archived,
    string Status,
    DateTimeOffset LastActivityAt,
    string? Model,
    string? ReasoningEffort,
    string ThreadKind);

public sealed record AppServerThreadTranscript(
    IReadOnlyList<LocalThreadMessage> Messages,
    IReadOnlyList<LocalThreadTurn> Turns,
    string? NextCursor,
    string RawJson);

public sealed record AppServerTurnStartResult(string? TurnId, string RawJson);

public static class AppServerEndpointValidator
{
    public static EndpointValidationResult Validate(
        Uri? url,
        string? bearerToken,
        AppServerEndpointTrust trust = AppServerEndpointTrust.Standard)
    {
        if (url is null)
        {
            return new EndpointValidationResult(false, "Enter a WebSocket endpoint.");
        }

        var scheme = url.Scheme.ToLowerInvariant();
        if (scheme is not ("ws" or "wss"))
        {
            return new EndpointValidationResult(false, "Codex App Server endpoints must use ws:// or wss://.");
        }

        var token = string.IsNullOrWhiteSpace(bearerToken) ? null : bearerToken.Trim();
        var isLoopback = IsLoopback(url);

        if (trust == AppServerEndpointTrust.SignedPairingPayload)
        {
            return ValidateSignedPairingEndpoint(url, token, isLoopback);
        }

        if (scheme == "ws" && !isLoopback)
        {
            return token is null
                ? new EndpointValidationResult(false, "Remote App Server endpoints must use wss:// with a bearer token, or loopback ws://.")
                : new EndpointValidationResult(false, "Bearer-token App Server endpoints must use wss:// unless they are loopback.");
        }

        if (!isLoopback && token is null)
        {
            return new EndpointValidationResult(false, "Remote App Server endpoints require a bearer token.");
        }

        return EndpointValidationResult.Valid;
    }

    public static bool IsLoopback(Uri url)
    {
        var host = url.Host.Trim('[', ']').ToLowerInvariant();
        return host is "localhost" or "127.0.0.1" or "::1";
    }

    private static EndpointValidationResult ValidateSignedPairingEndpoint(Uri url, string? token, bool isLoopback)
    {
        if (token is null)
        {
            return new EndpointValidationResult(false, "Pairing endpoints require a bearer token.");
        }

        if (url.Scheme.Equals("wss", StringComparison.OrdinalIgnoreCase) ||
            isLoopback ||
            !IsIPAddress(url))
        {
            return EndpointValidationResult.Valid;
        }

        return new EndpointValidationResult(
            false,
            "Pairing endpoints that use cleartext IP addresses need a Tailscale MagicDNS or .local host name.");
    }

    private static bool IsIPAddress(Uri url)
    {
        var host = url.Host.Trim('[', ']');
        return IPAddress.TryParse(host, out _);
    }
}

public sealed class AppServerClient
{
    public async Task<AppServerInitializeResult> InitializeAsync(
        AppServerEndpoint endpoint,
        CancellationToken cancellationToken = default)
    {
        var validation = AppServerEndpointValidator.Validate(endpoint.Url, endpoint.BearerToken, endpoint.Trust);
        if (!validation.IsValid)
        {
            throw new InvalidOperationException(validation.Message);
        }

        using var webSocket = new ClientWebSocket();
        if (!string.IsNullOrWhiteSpace(endpoint.BearerToken))
        {
            webSocket.Options.SetRequestHeader("Authorization", $"Bearer {endpoint.BearerToken.Trim()}");
        }

        await webSocket.ConnectAsync(endpoint.Url, cancellationToken).ConfigureAwait(false);
        var initializeJson = await InitializeWebSocketAsync(webSocket, cancellationToken).ConfigureAwait(false);
        await SendJsonAsync(webSocket, new
        {
            method = "initialized",
            @params = new { }
        }, cancellationToken).ConfigureAwait(false);

        await CloseBestEffortAsync(webSocket, "initialized").ConfigureAwait(false);
        return ParseInitializeResult(endpoint.Name, initializeJson);
    }

    public async Task<IReadOnlyList<AppServerThreadCatalogEntry>> ListThreadCatalogAsync(
        AppServerEndpoint endpoint,
        string hostId,
        int limit = 100,
        bool archived = false,
        CancellationToken cancellationToken = default)
    {
        var result = await RequestAsync(
            endpoint,
            "thread/list",
            new
            {
                limit,
                archived
            },
            cancellationToken).ConfigureAwait(false);

        return ParseThreadCatalogEntries(result, hostId, endpoint.Name, searchResult: false);
    }

    public async Task<IReadOnlyList<AppServerThreadCatalogEntry>> SearchThreadCatalogAsync(
        AppServerEndpoint endpoint,
        string hostId,
        string query,
        int limit = 50,
        CancellationToken cancellationToken = default)
    {
        var trimmed = query.Trim();
        if (trimmed.Length == 0)
        {
            return [];
        }

        var result = await RequestAsync(
            endpoint,
            "thread/search",
            new
            {
                searchTerm = trimmed,
                limit
            },
            cancellationToken).ConfigureAwait(false);

        return ParseThreadCatalogEntries(result, hostId, endpoint.Name, searchResult: true);
    }

    public async Task<IReadOnlyList<CodexModelOption>> ListModelsAsync(
        AppServerEndpoint endpoint,
        int limit = 100,
        bool includeHidden = false,
        CancellationToken cancellationToken = default)
    {
        var result = await RequestAsync(
            endpoint,
            "model/list",
            new
            {
                limit,
                includeHidden
            },
            cancellationToken).ConfigureAwait(false);

        return ParseModelOptions(result);
    }

    public async Task<IReadOnlyList<MentionCatalogCandidate>> ListMentionCandidatesAsync(
        AppServerEndpoint endpoint,
        string? cwd,
        int fileLimit = 120,
        CancellationToken cancellationToken = default)
    {
        var parameters = CatalogRequestParams(cwd);
        var retryWithoutParams = parameters.Count > 0;
        var skillsJson = await OptionalRequestAsync(
            endpoint,
            "skills/list",
            parameters,
            retryWithoutParams,
            cancellationToken).ConfigureAwait(false);
        var pluginsJson = await OptionalRequestAsync(
            endpoint,
            "plugin/list",
            parameters,
            retryWithoutParams,
            cancellationToken).ConfigureAwait(false);
        var fileCandidates = await RemoteFileMentionCandidatesAsync(
            endpoint,
            cwd,
            fileLimit,
            cancellationToken).ConfigureAwait(false);

        return MentionCatalog.CatalogMentionCandidates(skillsJson, pluginsJson, fileCandidates);
    }

    public async Task<ThreadRef> StartThreadAsync(
        AppServerEndpoint endpoint,
        string hostId,
        string cwd,
        string? model = null,
        string? name = null,
        string? approvalPolicy = null,
        string? sandboxMode = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(cwd))
        {
            throw new InvalidOperationException("A working directory is required to create a Codex thread.");
        }

        var parameters = new Dictionary<string, object?>
        {
            ["cwd"] = cwd.Trim(),
            ["experimentalRawEvents"] = false
        };
        if (!string.IsNullOrWhiteSpace(model))
        {
            parameters["model"] = model.Trim();
        }

        if (!string.IsNullOrWhiteSpace(approvalPolicy))
        {
            parameters["approvalPolicy"] = approvalPolicy.Trim();
        }

        if (!string.IsNullOrWhiteSpace(sandboxMode))
        {
            parameters["sandbox"] = sandboxMode.Trim();
        }

        var result = await RequestAsync(
            endpoint,
            "thread/start",
            parameters,
            cancellationToken).ConfigureAwait(false);

        var threadRef = ParseThreadRef(
            result,
            new ThreadRef
            {
                HostID = hostId,
                Cwd = cwd.Trim(),
                Name = string.IsNullOrWhiteSpace(name) ? null : name.Trim()
            },
            "started");
        if (!string.IsNullOrWhiteSpace(name))
        {
            await RequestAsync(
                endpoint,
                "thread/name/set",
                new Dictionary<string, object?>
                {
                    ["threadId"] = threadRef.ThreadID,
                    ["name"] = name.Trim()
                },
                cancellationToken).ConfigureAwait(false);
            threadRef.Name = name.Trim();
        }

        return threadRef;
    }

    public async Task<AppServerTurnStartResult> StartTurnAsync(
        AppServerEndpoint endpoint,
        ThreadRef threadRef,
        string message,
        string? model = null,
        string? reasoningEffort = null,
        string? approvalPolicy = null,
        string? sandboxMode = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(threadRef.ThreadID))
        {
            throw new InvalidOperationException("Thread ID is required to start a turn.");
        }

        if (string.IsNullOrWhiteSpace(message))
        {
            throw new InvalidOperationException("A message is required to start a turn.");
        }

        var parameters = new Dictionary<string, object?>
        {
            ["threadId"] = threadRef.ThreadID.Trim(),
            ["cwd"] = threadRef.Cwd,
            ["input"] = new object[]
            {
                new
                {
                    type = "text",
                    text = message.Trim(),
                    text_elements = Array.Empty<object>()
                }
            }
        };
        if (!string.IsNullOrWhiteSpace(model))
        {
            parameters["model"] = model.Trim();
        }

        if (!string.IsNullOrWhiteSpace(reasoningEffort))
        {
            parameters["effort"] = reasoningEffort.Trim();
        }

        if (!string.IsNullOrWhiteSpace(approvalPolicy))
        {
            parameters["approvalPolicy"] = approvalPolicy.Trim();
        }

        var sandboxPolicy = SandboxPolicy(sandboxMode, threadRef.Cwd);
        if (sandboxPolicy is not null)
        {
            parameters["sandboxPolicy"] = sandboxPolicy;
        }

        var result = await RequestAsync(
            endpoint,
            "turn/start",
            parameters,
            cancellationToken).ConfigureAwait(false);

        return new AppServerTurnStartResult(ParseTurnId(result), result);
    }

    public async Task<AppServerThreadTranscript> LoadThreadTranscriptAsync(
        AppServerEndpoint endpoint,
        ThreadRef threadRef,
        string? cursor = null,
        int limit = 40,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(threadRef.ThreadID))
        {
            throw new InvalidOperationException("Thread ID is required to load a transcript.");
        }

        var parameters = new Dictionary<string, object?>
        {
            ["threadId"] = threadRef.ThreadID,
            ["limit"] = limit,
            ["sortDirection"] = "desc",
            ["itemsView"] = "full"
        };
        if (!string.IsNullOrWhiteSpace(cursor))
        {
            parameters["cursor"] = cursor.Trim();
        }

        var result = await RequestAsync(
            endpoint,
            "thread/turns/list",
            parameters,
            cancellationToken).ConfigureAwait(false);

        return ParseThreadTranscript(result, threadRef);
    }

    public async Task<ThreadRef> ForkThreadAsync(
        AppServerEndpoint endpoint,
        ThreadRef threadRef,
        string? model = null,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(threadRef.ThreadID))
        {
            throw new InvalidOperationException("Thread ID is required to fork a thread.");
        }

        var parameters = new Dictionary<string, object?>
        {
            ["threadId"] = threadRef.ThreadID,
            ["cwd"] = threadRef.Cwd
        };
        if (!string.IsNullOrWhiteSpace(model))
        {
            parameters["model"] = model.Trim();
        }

        var result = await RequestAsync(
            endpoint,
            "thread/fork",
            parameters,
            cancellationToken).ConfigureAwait(false);

        return ParseForkedThread(result, threadRef);
    }

    public static IReadOnlyList<AppServerThreadCatalogEntry> ParseThreadCatalogEntries(
        string json,
        string hostId,
        string hostName,
        bool searchResult)
    {
        using var document = JsonDocument.Parse(json);
        return ParseThreadCatalogEntries(document.RootElement, hostId, hostName, searchResult);
    }

    public static IReadOnlyList<CodexModelOption> ParseModelOptions(string json)
    {
        using var document = JsonDocument.Parse(json);
        var payload = document.RootElement.TryGetProperty("result", out var resultElement)
            ? resultElement
            : document.RootElement;
        return CatalogArray(payload)
            .Select(ModelOptionFrom)
            .Where(option => option is not null)
            .Select(option => option!)
            .ToList();
    }

    private static IReadOnlyList<AppServerThreadCatalogEntry> ParseThreadCatalogEntries(
        JsonElement result,
        string hostId,
        string hostName,
        bool searchResult)
    {
        var payload = result.TryGetProperty("result", out var resultElement)
            ? resultElement
            : result;
        var values = CatalogArray(payload);
        var entries = new List<AppServerThreadCatalogEntry>();
        foreach (var value in values)
        {
            if (TryParseThreadCatalogEntry(value, hostId, hostName, searchResult, out var entry))
            {
                entries.Add(entry);
            }
        }

        return entries;
    }

    public static AppServerThreadTranscript ParseThreadTranscript(string json, ThreadRef threadRef)
    {
        using var document = JsonDocument.Parse(json);
        var payload = document.RootElement.TryGetProperty("result", out var resultElement)
            ? resultElement
            : document.RootElement;
        var messages = new List<LocalThreadMessage>();
        var turnGroups = new List<(LocalThreadTurn Turn, List<LocalThreadMessage> Messages)>();

        foreach (var (turn, turnIndex) in TranscriptTurns(payload).Select((value, index) => (value, index)))
        {
            var turnMessages = new List<LocalThreadMessage>();
            foreach (var item in TranscriptItems(turn))
            {
                var type = TryReadString(item, "type") ?? "";
                var createdAt = MessageDateFrom(item, turn);
                LocalThreadMessage? message = type switch
                {
                    "userMessage" => UserMessageFrom(item, createdAt, messages.Count),
                    "agentMessage" => AgentMessageFrom(item, createdAt, messages.Count),
                    "reasoning" => ReasoningMessageFrom(item, createdAt, messages.Count),
                    "commandExecution" => CommandMessageFrom(item, createdAt, messages.Count),
                    "fileChange" or "file_change" => FileChangeMessageFrom(item, createdAt, messages.Count),
                    "mcpToolCall" => ToolMessageFrom(item, "MCP tool", createdAt, messages.Count),
                    "imageGeneration" => ToolMessageFrom(item, "Image generation", createdAt, messages.Count),
                    "imageView" => ToolMessageFrom(item, "Image", createdAt, messages.Count),
                    _ when IsGenericToolItem(type) => ToolMessageFrom(item, DisplayNameForToolType(type), createdAt, messages.Count),
                    _ => null
                };

                if (message is not null && !string.IsNullOrWhiteSpace(message.Text))
                {
                    messages.Add(message);
                    turnMessages.Add(message);
                }
            }

            turnGroups.Add((TurnFrom(turn, threadRef, turnIndex, turnMessages), turnMessages));
        }

        var uniqueMessages = MessagesWithUniqueIds(messages)
            .OrderBy(message => message.CreatedAt)
            .ToList();
        foreach (var group in turnGroups)
        {
            group.Turn.ItemMessageIds = group.Messages
                .Select(message => message.Id)
                .Where(id => !string.IsNullOrWhiteSpace(id))
                .Distinct(StringComparer.Ordinal)
                .ToList();
        }

        return new AppServerThreadTranscript(
            uniqueMessages,
            turnGroups
                .Select(group => group.Turn)
                .OrderBy(turn => turn.StartedAt)
                .ToList(),
            TryReadString(payload, "nextCursor"),
            json);
    }

    public static ThreadRef ParseForkedThread(string json, ThreadRef sourceThreadRef)
    {
        return ParseThreadRef(json, sourceThreadRef, "forked");
    }

    private static ThreadRef ParseThreadRef(string json, ThreadRef sourceThreadRef, string operation)
    {
        using var document = JsonDocument.Parse(json);
        var payload = document.RootElement.TryGetProperty("result", out var resultElement)
            ? resultElement
            : document.RootElement;
        var thread = payload.TryGetProperty("thread", out var threadElement) && threadElement.ValueKind == JsonValueKind.Object
            ? threadElement
            : payload;
        var threadID =
            TryReadString(thread, "id") ??
            TryReadString(thread, "threadId") ??
            TryReadString(thread, "threadID");
        if (string.IsNullOrWhiteSpace(threadID))
        {
            throw new InvalidOperationException($"Codex App Server did not return a {operation} thread ID.");
        }

        return new ThreadRef
        {
            HostID = sourceThreadRef.HostID,
            ThreadID = threadID,
            Cwd = TryReadString(thread, "cwd") ?? TryReadString(payload, "cwd") ?? sourceThreadRef.Cwd,
            Name = TryReadString(thread, "name") ?? TryReadString(thread, "title") ?? sourceThreadRef.Name
        };
    }

    private static string? ParseTurnId(string json)
    {
        using var document = JsonDocument.Parse(json);
        var payload = document.RootElement.TryGetProperty("result", out var resultElement)
            ? resultElement
            : document.RootElement;
        var turn = payload.TryGetProperty("turn", out var turnElement) && turnElement.ValueKind == JsonValueKind.Object
            ? turnElement
            : payload;
        return TryReadString(turn, "id") ??
            TryReadString(turn, "turnId") ??
            TryReadString(turn, "turnID");
    }

    private static object? SandboxPolicy(string? sandboxMode, string cwd)
    {
        return sandboxMode?.Trim() switch
        {
            "danger-full-access" => new Dictionary<string, object?>
            {
                ["type"] = "dangerFullAccess"
            },
            "read-only" => new Dictionary<string, object?>
            {
                ["type"] = "readOnly",
                ["networkAccess"] = true
            },
            "workspace-write" => new Dictionary<string, object?>
            {
                ["type"] = "workspaceWrite",
                ["writableRoots"] = new[] { cwd },
                ["networkAccess"] = true,
                ["excludeTmpdirEnvVar"] = false,
                ["excludeSlashTmp"] = false
            },
            _ => null
        };
    }

    private async Task<string?> OptionalRequestAsync(
        AppServerEndpoint endpoint,
        string method,
        object parameters,
        bool retryWithoutParams,
        CancellationToken cancellationToken)
    {
        try
        {
            return await RequestAsync(endpoint, method, parameters, cancellationToken).ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch when (retryWithoutParams)
        {
            try
            {
                return await RequestAsync(endpoint, method, new Dictionary<string, object?>(), cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                return null;
            }
        }
        catch
        {
            return null;
        }
    }

    private async Task<IReadOnlyList<MentionCatalogCandidate>> RemoteFileMentionCandidatesAsync(
        AppServerEndpoint endpoint,
        string? rootPath,
        int limit,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(rootPath) || limit <= 0)
        {
            return [];
        }

        var root = rootPath.Trim();
        var candidates = new List<MentionCatalogCandidate>();
        var queue = new Queue<(string Path, string RelativePath)>();
        var visited = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        queue.Enqueue((root, ""));

        while (queue.Count > 0 && candidates.Count < limit)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var current = queue.Dequeue();
            if (!visited.Add(current.Path))
            {
                continue;
            }

            var json = await OptionalRequestAsync(
                endpoint,
                "fs/readDirectory",
                new Dictionary<string, object?> { ["path"] = current.Path },
                retryWithoutParams: false,
                cancellationToken).ConfigureAwait(false);
            if (string.IsNullOrWhiteSpace(json))
            {
                continue;
            }

            foreach (var entry in RemoteDirectoryEntriesFrom(json).OrderBy(entry => entry.FileName, StringComparer.OrdinalIgnoreCase))
            {
                if (candidates.Count >= limit)
                {
                    break;
                }

                if (string.IsNullOrWhiteSpace(entry.FileName) ||
                    entry.FileName.StartsWith('.') ||
                    (entry.IsDirectory && IsIgnoredMentionDirectory(entry.FileName)) ||
                    (!entry.IsDirectory && !entry.IsFile))
                {
                    continue;
                }

                var path = JoinRemotePath(current.Path, entry.FileName);
                var relativePath = string.IsNullOrWhiteSpace(current.RelativePath)
                    ? entry.FileName
                    : $"{current.RelativePath}/{entry.FileName}";
                var displayName = entry.IsDirectory ? $"{entry.FileName}/" : entry.FileName;
                candidates.Add(MentionCatalog.FileMentionCandidate(path, displayName, relativePath));

                if (entry.IsDirectory)
                {
                    queue.Enqueue((path, relativePath));
                }
            }
        }

        return candidates;
    }

    private static Dictionary<string, object?> CatalogRequestParams(string? cwd)
    {
        return string.IsNullOrWhiteSpace(cwd)
            ? []
            : new Dictionary<string, object?> { ["cwds"] = new[] { cwd.Trim() } };
    }

    private static IReadOnlyList<RemoteDirectoryEntry> RemoteDirectoryEntriesFrom(string json)
    {
        using var document = JsonDocument.Parse(json);
        var payload = document.RootElement.TryGetProperty("result", out var resultElement)
            ? resultElement
            : document.RootElement;
        var entries = DirectoryEntriesArray(payload);
        return entries
            .Select(RemoteDirectoryEntryFrom)
            .Where(entry => entry is not null)
            .Select(entry => entry!)
            .ToList();
    }

    private static RemoteDirectoryEntry? RemoteDirectoryEntryFrom(JsonElement value)
    {
        var fileName =
            TryReadString(value, "fileName") ??
            TryReadString(value, "name") ??
            LastPathComponent(TryReadString(value, "path"));
        if (string.IsNullOrWhiteSpace(fileName))
        {
            return null;
        }

        var type =
            TryReadString(value, "type") ??
            TryReadString(value, "kind") ??
            "";
        var isDirectory =
            TryReadBool(value, "isDirectory") ??
            TryReadBool(value, "directory") ??
            type.Contains("dir", StringComparison.OrdinalIgnoreCase);
        var isFile =
            TryReadBool(value, "isFile") ??
            TryReadBool(value, "file") ??
            type.Contains("file", StringComparison.OrdinalIgnoreCase);

        return new RemoteDirectoryEntry(fileName, isDirectory, isFile);
    }

    private static IReadOnlyList<JsonElement> DirectoryEntriesArray(JsonElement payload)
    {
        foreach (var propertyName in new[] { "entries", "data", "items", "results" })
        {
            if (payload.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.Array)
            {
                return value.EnumerateArray().ToList();
            }
        }

        return payload.ValueKind == JsonValueKind.Array
            ? payload.EnumerateArray().ToList()
            : [];
    }

    private static bool IsIgnoredMentionDirectory(string name)
    {
        return name is ".build" or ".git" or ".swiftpm" or "DerivedData" or "dist" or "node_modules";
    }

    private static string? LastPathComponent(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        return path.Split(['/', '\\'], StringSplitOptions.RemoveEmptyEntries).LastOrDefault();
    }

    private static string JoinRemotePath(string rootPath, string fileName)
    {
        var trimmed = rootPath.TrimEnd('/', '\\');
        var separator = rootPath.Contains('\\') ? "\\" : "/";
        return $"{trimmed}{separator}{fileName}";
    }

    private async Task<string> RequestAsync(
        AppServerEndpoint endpoint,
        string method,
        object parameters,
        CancellationToken cancellationToken)
    {
        var validation = AppServerEndpointValidator.Validate(endpoint.Url, endpoint.BearerToken, endpoint.Trust);
        if (!validation.IsValid)
        {
            throw new InvalidOperationException(validation.Message);
        }

        using var webSocket = new ClientWebSocket();
        if (!string.IsNullOrWhiteSpace(endpoint.BearerToken))
        {
            webSocket.Options.SetRequestHeader("Authorization", $"Bearer {endpoint.BearerToken.Trim()}");
        }

        await webSocket.ConnectAsync(endpoint.Url, cancellationToken).ConfigureAwait(false);
        await InitializeWebSocketAsync(webSocket, cancellationToken).ConfigureAwait(false);
        await SendJsonAsync(webSocket, new
        {
            method = "initialized",
            @params = new { }
        }, cancellationToken).ConfigureAwait(false);

        await SendJsonAsync(webSocket, new
        {
            id = 2,
            method,
            @params = parameters
        }, cancellationToken).ConfigureAwait(false);

        var response = await ReceiveResponseTextAsync(webSocket, expectedId: 2, cancellationToken).ConfigureAwait(false);
        await CloseBestEffortAsync(webSocket, method).ConfigureAwait(false);
        return response;
    }

    private static async Task CloseBestEffortAsync(
        ClientWebSocket webSocket,
        string statusDescription)
    {
        if (webSocket.State is not (WebSocketState.Open or WebSocketState.CloseReceived))
        {
            return;
        }

        try
        {
            using var closeCancellation = new CancellationTokenSource(TimeSpan.FromSeconds(1));
            await webSocket.CloseAsync(
                WebSocketCloseStatus.NormalClosure,
                statusDescription,
                closeCancellation.Token).ConfigureAwait(false);
        }
        catch
        {
        }
    }

    private static async Task<string> InitializeWebSocketAsync(
        ClientWebSocket webSocket,
        CancellationToken cancellationToken)
    {
        await SendJsonAsync(webSocket, new
        {
            id = 1,
            method = "initialize",
            @params = new
            {
                clientInfo = new
                {
                    name = "mapofagents-windows",
                    title = "MapofAgents Windows",
                    version = "0.1.0"
                },
                capabilities = new
                {
                    experimentalApi = true
                }
            }
        }, cancellationToken).ConfigureAwait(false);

        return await ReceiveResponseTextAsync(webSocket, expectedId: 1, cancellationToken).ConfigureAwait(false);
    }

    private static AppServerInitializeResult ParseInitializeResult(string fallbackName, string json)
    {
        using var document = JsonDocument.Parse(json);
        var result = document.RootElement.TryGetProperty("result", out var resultElement)
            ? resultElement
            : document.RootElement;

        var platform =
            TryReadString(result, "platformFamily")
            ?? TryReadString(result, "platformOs")
            ?? TryReadString(result, "os")
            ?? HostPlatforms.Unknown;
        var hostName =
            TryReadString(result, "displayName")
            ?? TryReadString(result, "hostname")
            ?? TryReadString(result, "hostName")
            ?? fallbackName;
        var codexHome = TryReadString(result, "codexHome");

        return new AppServerInitializeResult(
            hostName,
            HostPlatformResolver.Resolve(platform),
            codexHome,
            json);
    }

    private static string? TryReadString(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
    }

    private static CodexModelOption? ModelOptionFrom(JsonElement value)
    {
        var id = TryReadString(value, "id") ?? TryReadString(value, "model");
        if (string.IsNullOrWhiteSpace(id))
        {
            return null;
        }

        var supportedEfforts = SupportedReasoningEffortsFrom(value);
        return new CodexModelOption(
            id.Trim(),
            TryReadString(value, "displayName") ?? id.Trim(),
            TryReadString(value, "description") ?? "",
            TryReadString(value, "defaultReasoningEffort") ?? "medium",
            supportedEfforts.Count > 0 ? supportedEfforts : NewThreadOptionDefaults.SupportedReasoningEfforts,
            TryReadBool(value, "isDefault") ?? false);
    }

    private static IReadOnlyList<string> SupportedReasoningEffortsFrom(JsonElement value)
    {
        if (!value.TryGetProperty("supportedReasoningEfforts", out var efforts) ||
            efforts.ValueKind != JsonValueKind.Array)
        {
            return [];
        }

        return efforts
            .EnumerateArray()
            .Select(effort => effort.ValueKind == JsonValueKind.Object
                ? TryReadString(effort, "reasoningEffort") ??
                    TryReadString(effort, "effort") ??
                    TryReadString(effort, "value")
                : effort.ValueKind == JsonValueKind.String
                    ? effort.GetString()
                    : effort.ToString())
            .Where(effort => !string.IsNullOrWhiteSpace(effort))
            .Select(effort => effort!.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private static IReadOnlyList<JsonElement> TranscriptTurns(JsonElement result)
    {
        if (result.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array)
        {
            return data.EnumerateArray().ToList();
        }

        return result.ValueKind == JsonValueKind.Array ? result.EnumerateArray().ToList() : [];
    }

    private static IReadOnlyList<JsonElement> TranscriptItems(JsonElement turn)
    {
        if (turn.TryGetProperty("items", out var items) && items.ValueKind == JsonValueKind.Array)
        {
            return items.EnumerateArray().ToList();
        }

        return turn.ValueKind == JsonValueKind.Array ? turn.EnumerateArray().ToList() : [];
    }

    private static LocalThreadTurn TurnFrom(
        JsonElement turn,
        ThreadRef threadRef,
        int fallbackIndex,
        IReadOnlyList<LocalThreadMessage> messages)
    {
        var startedAt =
            DateFrom(turn, "startedAt", "started_at", "createdAt", "created_at", "timestamp") ??
            messages.FirstOrDefault()?.CreatedAt ??
            DateTimeOffset.UtcNow;

        return new LocalThreadTurn
        {
            Id = TurnIdFrom(turn, threadRef, fallbackIndex),
            Status = TurnStatusFrom(turn),
            StartedAt = startedAt,
            CompletedAt = DateFrom(turn, "completedAt", "completed_at"),
            Error = ErrorMessageFrom(turn),
            ItemsView = ItemsViewFrom(turn),
            DurationMilliseconds = IntFrom(turn, "durationMs") ?? IntFrom(turn, "duration_ms"),
            ItemMessageIds = messages.Select(message => message.Id).ToList()
        };
    }

    private static string TurnIdFrom(JsonElement turn, ThreadRef threadRef, int fallbackIndex)
    {
        var id =
            TryReadString(turn, "id") ??
            TryReadString(turn, "turnId") ??
            TryReadString(turn, "turnID");
        if (!string.IsNullOrWhiteSpace(id))
        {
            return id;
        }

        var threadID = string.IsNullOrWhiteSpace(threadRef.ThreadID) ? "thread" : threadRef.ThreadID;
        return $"{threadID}-turn-{fallbackIndex + 1}";
    }

    private static string TurnStatusFrom(JsonElement turn)
    {
        return TryReadString(turn, "status")?.Trim().ToLowerInvariant() switch
        {
            "inprogress" or "in_progress" or "running" or "active" => ThreadRunStatuses.Running,
            "failed" or "error" => ThreadRunStatuses.Failed,
            "interrupted" or "needsinput" or "needs_input" => ThreadRunStatuses.NeedsInput,
            "completed" or "complete" or "done" => ThreadRunStatuses.Complete,
            _ => ThreadRunStatuses.Unknown
        };
    }

    private static string ItemsViewFrom(JsonElement turn)
    {
        return (TryReadString(turn, "itemsView") ?? TryReadString(turn, "items_view"))?.Trim().ToLowerInvariant() switch
        {
            "notloaded" or "not_loaded" => ThreadTurnItemsViews.NotLoaded,
            "summary" => ThreadTurnItemsViews.Summary,
            "full" => ThreadTurnItemsViews.Full,
            _ => ThreadTurnItemsViews.Full
        };
    }

    private static string? ErrorMessageFrom(JsonElement turn)
    {
        if (!turn.TryGetProperty("error", out var error) ||
            error.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
        {
            return null;
        }

        if (error.ValueKind == JsonValueKind.Object)
        {
            return TryReadString(error, "message") ?? TryReadString(error, "detail") ?? PrettyJson(error);
        }

        return error.ValueKind == JsonValueKind.String ? error.GetString() : error.ToString();
    }

    private static LocalThreadMessage? UserMessageFrom(JsonElement item, DateTimeOffset createdAt, int fallbackIndex)
    {
        var text = ContentText(item, "content");
        return string.IsNullOrWhiteSpace(text)
            ? null
            : TranscriptMessage("user", text, createdAt, MessageIdFrom(item, "user-message", fallbackIndex));
    }

    private static LocalThreadMessage? AgentMessageFrom(JsonElement item, DateTimeOffset createdAt, int fallbackIndex)
    {
        var text = TryReadString(item, "text") ?? ContentText(item, "content");
        return string.IsNullOrWhiteSpace(text)
            ? null
            : TranscriptMessage("assistant", text, createdAt, MessageIdFrom(item, "agent-message", fallbackIndex));
    }

    private static LocalThreadMessage? ReasoningMessageFrom(JsonElement item, DateTimeOffset createdAt, int fallbackIndex)
    {
        var text = ContentText(item, "summary");
        return string.IsNullOrWhiteSpace(text)
            ? null
            : TranscriptMessage("reasoning", text, createdAt, MessageIdFrom(item, "reasoning", fallbackIndex));
    }

    private static LocalThreadMessage CommandMessageFrom(JsonElement item, DateTimeOffset createdAt, int fallbackIndex)
    {
        var command = TryReadString(item, "command") ?? "Command";
        var output = FormattedOutput(item);
        return TranscriptMessage(
            "tool",
            ToolMessageText(command, null, output),
            createdAt,
            MessageIdFrom(item, "command", fallbackIndex));
    }

    private static LocalThreadMessage FileChangeMessageFrom(JsonElement item, DateTimeOffset createdAt, int fallbackIndex)
    {
        return TranscriptMessage(
            "tool",
            ToolMessageText("file_change", null, FormattedOutput(item) ?? FormattedArguments(item) ?? PrettyJson(item)),
            createdAt,
            MessageIdFrom(item, "file-change", fallbackIndex));
    }

    private static LocalThreadMessage ToolMessageFrom(
        JsonElement item,
        string fallbackName,
        DateTimeOffset createdAt,
        int fallbackIndex)
    {
        var name =
            TryReadString(item, "name") ??
            TryReadString(item, "toolName") ??
            TryReadString(item, "tool_name") ??
            TryReadString(item, "command") ??
            fallbackName;
        return TranscriptMessage(
            "tool",
            ToolMessageText(name, FormattedArguments(item), FormattedOutput(item)),
            createdAt,
            MessageIdFrom(item, "tool", fallbackIndex));
    }

    private static LocalThreadMessage TranscriptMessage(string role, string text, DateTimeOffset createdAt, string id)
    {
        return new LocalThreadMessage
        {
            Id = id,
            Role = role,
            Text = text,
            CreatedAt = createdAt
        };
    }

    private static string MessageIdFrom(JsonElement item, string fallbackPrefix, int fallbackIndex)
    {
        foreach (var propertyName in new[] { "id", "itemId", "itemID", "messageId", "messageID", "call_id", "callId" })
        {
            var value = TryReadString(item, propertyName);
            if (!string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }

        return $"{fallbackPrefix}-{fallbackIndex}";
    }

    private static DateTimeOffset MessageDateFrom(JsonElement item, JsonElement fallback)
    {
        return DateFrom(item) ?? DateFrom(fallback) ?? DateTimeOffset.UtcNow;
    }

    private static string ContentText(JsonElement element, string propertyName)
    {
        return element.TryGetProperty(propertyName, out var value) ? ContentText(value) : "";
    }

    private static string ContentText(JsonElement value)
    {
        return value.ValueKind switch
        {
            JsonValueKind.String => value.GetString() ?? "",
            JsonValueKind.Array => string.Join(
                "\n",
                value.EnumerateArray()
                    .Select(ContentText)
                    .Where(text => !string.IsNullOrWhiteSpace(text))),
            JsonValueKind.Object => ContentObjectText(value),
            _ => ""
        };
    }

    private static string ContentObjectText(JsonElement value)
    {
        var direct =
            TryReadString(value, "text") ??
            TryReadString(value, "input_text") ??
            TryReadString(value, "output_text");
        if (!string.IsNullOrWhiteSpace(direct))
        {
            return direct;
        }

        if (value.TryGetProperty("content", out var content))
        {
            return ContentText(content);
        }

        return "";
    }

    private static string? FormattedArguments(JsonElement item)
    {
        foreach (var propertyName in new[] { "arguments", "input", "parameters", "params" })
        {
            if (!item.TryGetProperty(propertyName, out var value) ||
                value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                continue;
            }

            var text = value.ValueKind == JsonValueKind.String ? value.GetString() : PrettyJson(value);
            if (!string.IsNullOrWhiteSpace(text))
            {
                return text;
            }
        }

        return null;
    }

    private static string? FormattedOutput(JsonElement item)
    {
        foreach (var propertyName in new[] { "aggregatedOutput", "output", "result", "content" })
        {
            if (!item.TryGetProperty(propertyName, out var value) ||
                value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                continue;
            }

            var text = value.ValueKind == JsonValueKind.Array || value.ValueKind == JsonValueKind.Object
                ? ContentText(value)
                : value.ValueKind == JsonValueKind.String
                    ? value.GetString()
                    : value.ToString();
            if (!string.IsNullOrWhiteSpace(text))
            {
                return text;
            }
        }

        return null;
    }

    private static string ToolMessageText(string name, string? arguments, string? output)
    {
        var lines = new List<string> { $"Tool: {name}" };
        if (!string.IsNullOrWhiteSpace(arguments))
        {
            lines.Add($"Arguments:\n{arguments}");
        }

        if (!string.IsNullOrWhiteSpace(output))
        {
            lines.Add($"Output:\n{output}");
        }

        return string.Join("\n\n", lines);
    }

    private static string PrettyJson(JsonElement element)
    {
        return JsonSerializer.Serialize(element, new JsonSerializerOptions { WriteIndented = true });
    }

    private static bool IsGenericToolItem(string type)
    {
        var lower = type.ToLowerInvariant();
        return lower.Contains("tool") ||
            lower.Contains("command") ||
            lower.Contains("function") ||
            lower.Contains("exec") ||
            lower.Contains("patch");
    }

    private static string DisplayNameForToolType(string type)
    {
        return string.IsNullOrWhiteSpace(type) ? "Tool" : type;
    }

    private static IReadOnlyList<LocalThreadMessage> MessagesWithUniqueIds(IReadOnlyList<LocalThreadMessage> messages)
    {
        var used = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var message in messages)
        {
            if (!used.TryGetValue(message.Id, out var count))
            {
                used[message.Id] = 1;
                continue;
            }

            used[message.Id] = count + 1;
            message.Id = $"{message.Id}-{count + 1}";
        }

        return messages;
    }

    private static IReadOnlyList<JsonElement> CatalogArray(JsonElement result)
    {
        if (result.ValueKind == JsonValueKind.Array)
        {
            return result.EnumerateArray().ToList();
        }

        foreach (var propertyName in new[] { "data", "threads", "items", "results" })
        {
            if (result.TryGetProperty(propertyName, out var value) && value.ValueKind == JsonValueKind.Array)
            {
                return value.EnumerateArray().ToList();
            }
        }

        return [];
    }

    private static bool TryParseThreadCatalogEntry(
        JsonElement value,
        string hostId,
        string hostName,
        bool searchResult,
        out AppServerThreadCatalogEntry entry)
    {
        var threadValue = searchResult ? NestedThreadValue(value) : value;
        var threadId =
            TryReadString(threadValue, "id") ??
            TryReadString(threadValue, "threadId") ??
            TryReadString(threadValue, "threadID");
        if (string.IsNullOrWhiteSpace(threadId))
        {
            entry = EmptyThreadCatalogEntry();
            return false;
        }

        var title =
            TryReadString(threadValue, "name") ??
            TryReadString(threadValue, "title") ??
            TryReadString(threadValue, "preview");
        var preview =
            searchResult
                ? TryReadString(value, "snippet") ?? TryReadString(value, "preview") ?? TryReadString(value, "summary")
                : null;
        preview ??=
            TryReadString(threadValue, "preview") ??
            TryReadString(threadValue, "summary") ??
            TryReadString(threadValue, "lastMessage") ??
            "";
        var cwd =
            TryReadString(threadValue, "cwd") ??
            TryReadString(threadValue, "workingDirectory") ??
            TryReadString(threadValue, "working_directory") ??
            "";
        var source =
            TryReadString(value, "source") ??
            TryReadString(threadValue, "source") ??
            TryReadString(threadValue, "thread_source") ??
            (searchResult ? "search" : null);

        entry = new AppServerThreadCatalogEntry(
            new ThreadRef
            {
                HostID = hostId,
                ThreadID = threadId,
                Cwd = cwd,
                Name = title
            },
            hostName,
            string.IsNullOrWhiteSpace(title) ? "Codex thread" : title,
            preview,
            source,
            TryReadBool(threadValue, "archived") ?? false,
            StatusFrom(threadValue),
            DateFrom(threadValue) ?? DateTimeOffset.UtcNow,
            TryReadString(threadValue, "model"),
            TryReadString(threadValue, "reasoningEffort") ?? TryReadString(threadValue, "effort"),
            ThreadKindFrom(threadValue));
        return true;
    }

    private static JsonElement NestedThreadValue(JsonElement value)
    {
        foreach (var propertyName in new[] { "thread", "item" })
        {
            if (value.TryGetProperty(propertyName, out var nested) && nested.ValueKind == JsonValueKind.Object)
            {
                return nested;
            }
        }

        return value;
    }

    private static bool? TryReadBool(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            JsonValueKind.String when bool.TryParse(value.GetString(), out var parsed) => parsed,
            _ => null
        };
    }

    private static int? IntFrom(JsonElement element, string propertyName)
    {
        if (!element.TryGetProperty(propertyName, out var value))
        {
            return null;
        }

        return value.ValueKind switch
        {
            JsonValueKind.Number when value.TryGetInt32(out var parsed) => parsed,
            JsonValueKind.String when int.TryParse(value.GetString(), out var parsed) => parsed,
            _ => null
        };
    }

    private static DateTimeOffset? DateFrom(JsonElement element)
    {
        return DateFrom(
            element,
            "lastActivityAt",
            "updatedAt",
            "updated_at",
            "modifiedAt",
            "createdAt",
            "created_at",
            "timestamp",
            "time",
            "completedAt",
            "completed_at",
            "startedAt",
            "started_at");
    }

    private static DateTimeOffset? DateFrom(JsonElement element, params string[] propertyNames)
    {
        foreach (var propertyName in propertyNames)
        {
            if (!element.TryGetProperty(propertyName, out var value) ||
                value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined)
            {
                continue;
            }

            if (value.ValueKind == JsonValueKind.Number &&
                value.TryGetDouble(out var seconds))
            {
                return DateTimeOffset.FromUnixTimeMilliseconds(seconds > 10_000_000_000
                    ? (long)seconds
                    : (long)(seconds * 1000));
            }

            var raw = value.ValueKind == JsonValueKind.String ? value.GetString() : value.ToString();
            if (string.IsNullOrWhiteSpace(raw))
            {
                continue;
            }

            if (long.TryParse(raw, out var numeric))
            {
                return DateTimeOffset.FromUnixTimeMilliseconds(numeric > 10_000_000_000
                    ? numeric
                    : numeric * 1000);
            }

            if (DateTimeOffset.TryParse(raw, out var parsed))
            {
                return parsed;
            }
        }

        return null;
    }

    private static string StatusFrom(JsonElement element)
    {
        var raw =
            TryReadString(element, "status") ??
            TryReadString(element, "loadedStatus") ??
            TryReadString(element, "loaded_status") ??
            TryReadString(element, "state") ??
            "";
        var lower = raw.ToLowerInvariant();
        if (lower.Contains("approval") || lower.Contains("input") || lower.Contains("waiting"))
        {
            return ThreadRunStatuses.NeedsInput;
        }

        if (lower.Contains("running") || lower.Contains("active"))
        {
            return ThreadRunStatuses.Running;
        }

        if (lower.Contains("fail") || lower.Contains("error"))
        {
            return ThreadRunStatuses.Failed;
        }

        if (lower.Contains("complete") || lower.Contains("done"))
        {
            return ThreadRunStatuses.Complete;
        }

        return ThreadRunStatuses.Idle;
    }

    private static string ThreadKindFrom(JsonElement element)
    {
        var raw =
            TryReadString(element, "threadKind") ??
            TryReadString(element, "thread_kind") ??
            TryReadString(element, "threadSource") ??
            TryReadString(element, "thread_source") ??
            TryReadString(element, "source") ??
            "";
        return raw.Contains("subagent", StringComparison.OrdinalIgnoreCase) ? ThreadKinds.Subagent : ThreadKinds.Thread;
    }

    private static AppServerThreadCatalogEntry EmptyThreadCatalogEntry()
    {
        return new AppServerThreadCatalogEntry(
            new ThreadRef(),
            "",
            "",
            "",
            null,
            false,
            ThreadRunStatuses.Idle,
            DateTimeOffset.UnixEpoch,
            null,
            null,
            ThreadKinds.Thread);
    }

    private sealed record RemoteDirectoryEntry(string FileName, bool IsDirectory, bool IsFile);

    private static async Task SendJsonAsync(ClientWebSocket webSocket, object payload, CancellationToken cancellationToken)
    {
        var data = JsonSerializer.SerializeToUtf8Bytes(payload, MapofAgentsJson.Options);
        await webSocket.SendAsync(data, WebSocketMessageType.Text, true, cancellationToken).ConfigureAwait(false);
    }

    private static async Task<string> ReceiveResponseTextAsync(
        ClientWebSocket webSocket,
        int expectedId,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < 24; attempt++)
        {
            var json = await ReceiveTextAsync(webSocket, cancellationToken).ConfigureAwait(false);
            using var document = JsonDocument.Parse(json);
            if (!document.RootElement.TryGetProperty("id", out var idElement) ||
                idElement.ValueKind != JsonValueKind.Number ||
                idElement.GetInt32() != expectedId)
            {
                continue;
            }

            if (document.RootElement.TryGetProperty("error", out var error) &&
                error.ValueKind != JsonValueKind.Null &&
                error.ValueKind != JsonValueKind.Undefined)
            {
                throw new InvalidOperationException($"Codex App Server returned an error: {error}");
            }

            return json;
        }

        throw new InvalidOperationException("Codex App Server did not return the expected response.");
    }

    private static async Task<string> ReceiveTextAsync(ClientWebSocket webSocket, CancellationToken cancellationToken)
    {
        var buffer = new byte[16 * 1024];
        using var stream = new MemoryStream();

        while (true)
        {
            var result = await webSocket.ReceiveAsync(buffer, cancellationToken).ConfigureAwait(false);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                throw new InvalidOperationException("Codex App Server closed the connection before initialize completed.");
            }

            stream.Write(buffer, 0, result.Count);
            if (result.EndOfMessage)
            {
                break;
            }
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }
}
