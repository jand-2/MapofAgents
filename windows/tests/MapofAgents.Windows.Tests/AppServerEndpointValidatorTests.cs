using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AppServerEndpointValidatorTests
{
    [TestMethod]
    public void AllowsLoopbackWebSocketWithoutToken()
    {
        var result = AppServerEndpointValidator.Validate(new Uri("ws://127.0.0.1:18945"), null);

        Assert.IsTrue(result.IsValid);
    }

    [TestMethod]
    public void RejectsRemotePlainWebSocket()
    {
        var result = AppServerEndpointValidator.Validate(new Uri("ws://example-host.local:18945"), null);

        Assert.IsFalse(result.IsValid);
        Assert.IsTrue(result.Message?.Contains("wss://") == true);
    }

    [TestMethod]
    public void AllowsSignedPairingPayloadWebSocketWithNamedHost()
    {
        var result = AppServerEndpointValidator.Validate(
            new Uri("ws://example-host.local:18945"),
            "token-public-example",
            AppServerEndpointTrust.SignedPairingPayload);

        Assert.IsTrue(result.IsValid);
    }

    [TestMethod]
    public void RejectsSignedPairingPayloadWebSocketWithCleartextIp()
    {
        var result = AppServerEndpointValidator.Validate(
            new Uri("ws://192.0.2.10:18945"),
            "token-public-example",
            AppServerEndpointTrust.SignedPairingPayload);

        Assert.IsFalse(result.IsValid);
        Assert.IsTrue(result.Message?.Contains("MagicDNS", StringComparison.OrdinalIgnoreCase) == true);
    }

    [TestMethod]
    public void RequiresBearerTokenForRemoteSecureEndpoint()
    {
        var result = AppServerEndpointValidator.Validate(new Uri("wss://example-host.local:18945"), null);

        Assert.IsFalse(result.IsValid);
        Assert.IsTrue(result.Message?.Contains("bearer token", StringComparison.OrdinalIgnoreCase) == true);
    }

    [TestMethod]
    public void ParsesThreadListCatalogEntries()
    {
        var json = """
        {
          "id": 2,
          "result": {
            "data": [
              {
                "id": "thread-public-1",
                "cwd": "C:\\Users\\example\\workspace",
                "name": "Catalog Thread",
                "preview": "Latest assistant message",
                "status": "running",
                "updatedAt": "2026-06-03T18:45:00Z",
                "model": "gpt-5",
                "reasoningEffort": "high",
                "threadSource": "subagent"
              }
            ]
          }
        }
        """;

        var entries = AppServerClient.ParseThreadCatalogEntries(json, "example-host", "Example Host", searchResult: false);

        Assert.AreEqual(1, entries.Count);
        var entry = entries[0];
        Assert.AreEqual("example-host", entry.ThreadRef.HostID);
        Assert.AreEqual("thread-public-1", entry.ThreadRef.ThreadID);
        Assert.AreEqual("C:\\Users\\example\\workspace", entry.ThreadRef.Cwd);
        Assert.AreEqual("Catalog Thread", entry.Title);
        Assert.AreEqual("Latest assistant message", entry.Preview);
        Assert.AreEqual(ThreadRunStatuses.Running, entry.Status);
        Assert.AreEqual(DateTimeOffset.Parse("2026-06-03T18:45:00Z"), entry.LastActivityAt);
        Assert.AreEqual("gpt-5", entry.Model);
        Assert.AreEqual("high", entry.ReasoningEffort);
        Assert.AreEqual("subagent", entry.ThreadKind);
    }

    [TestMethod]
    public void ParsesThreadSearchCatalogEntries()
    {
        var json = """
        {
          "id": 2,
          "result": {
            "threads": [
              {
                "snippet": "Matched search snippet",
                "thread": {
                  "threadId": "thread-public-search",
                  "working_directory": "C:\\Users\\example\\search",
                  "title": "Search Result Thread",
                  "summary": "Thread summary",
                  "state": "waiting for input",
                  "createdAt": "2026-06-03T19:10:00Z",
                  "effort": "medium"
                }
              }
            ]
          }
        }
        """;

        var entries = AppServerClient.ParseThreadCatalogEntries(json, "example-host", "Example Host", searchResult: true);

        Assert.AreEqual(1, entries.Count);
        var entry = entries[0];
        Assert.AreEqual("thread-public-search", entry.ThreadRef.ThreadID);
        Assert.AreEqual("C:\\Users\\example\\search", entry.ThreadRef.Cwd);
        Assert.AreEqual("Search Result Thread", entry.Title);
        Assert.AreEqual("Matched search snippet", entry.Preview);
        Assert.AreEqual("search", entry.Source);
        Assert.AreEqual(ThreadRunStatuses.NeedsInput, entry.Status);
        Assert.AreEqual(DateTimeOffset.Parse("2026-06-03T19:10:00Z"), entry.LastActivityAt);
        Assert.AreEqual("medium", entry.ReasoningEffort);
        Assert.AreEqual("thread", entry.ThreadKind);
    }

    [TestMethod]
    public void ParsesModelListOptions()
    {
        const string json = """
            {
              "id": 2,
              "result": {
                "data": [
                  {
                    "id": "gpt-remote",
                    "displayName": "GPT Remote",
                    "description": "Remote model",
                    "defaultReasoningEffort": "high",
                    "supportedReasoningEfforts": ["low", {"value": "high"}],
                    "isDefault": true
                  },
                  {
                    "model": "gpt-plain"
                  }
                ]
              }
            }
            """;

        var models = AppServerClient.ParseModelOptions(json);

        Assert.AreEqual(2, models.Count);
        Assert.AreEqual("gpt-remote", models[0].Id);
        Assert.AreEqual("GPT Remote", models[0].DisplayName);
        Assert.AreEqual("high", models[0].DefaultReasoningEffort);
        CollectionAssert.AreEqual(new[] { "low", "high" }, models[0].SupportedReasoningEfforts.ToArray());
        Assert.IsTrue(models[0].IsDefault);
        Assert.AreEqual("gpt-plain", models[1].Id);
        CollectionAssert.AreEqual(
            NewThreadOptionDefaults.SupportedReasoningEfforts.ToArray(),
            models[1].SupportedReasoningEfforts.ToArray());
    }

    [TestMethod]
    public async Task ListThreadCatalogAsyncReadsLoopbackWebSocketCatalog()
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var server = new FakeCatalogAppServer();
        var client = new AppServerClient();

        var entries = await client.ListThreadCatalogAsync(
            new AppServerEndpoint("Fake App Server", server.Url, null),
            "fake-host",
            cancellationToken: cancellation.Token);

        Assert.AreEqual(1, entries.Count);
        var entry = entries[0];
        Assert.AreEqual("fake-host", entry.ThreadRef.HostID);
        Assert.AreEqual("thread-live-catalog-1", entry.ThreadRef.ThreadID);
        Assert.AreEqual("C:\\Users\\example\\workspace", entry.ThreadRef.Cwd);
        Assert.AreEqual("Live Catalog Thread", entry.Title);
        Assert.AreEqual(ThreadRunStatuses.Running, entry.Status);
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "initialize");
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "thread/list");
    }

    [TestMethod]
    public async Task StartThreadAsyncCreatesAndNamesLoopbackAppServerThread()
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var server = new FakeCatalogAppServer();
        var client = new AppServerClient();

        var threadRef = await client.StartThreadAsync(
            new AppServerEndpoint("Fake App Server", server.Url, null),
            "fake-host",
            "C:\\Users\\example\\workspace",
            model: "gpt-live",
            name: "Windows Created Thread",
            approvalPolicy: "never",
            sandboxMode: "read-only",
            cancellationToken: cancellation.Token);

        Assert.AreEqual("fake-host", threadRef.HostID);
        Assert.AreEqual("thread-started-1", threadRef.ThreadID);
        Assert.AreEqual("C:\\Users\\example\\workspace", threadRef.Cwd);
        Assert.AreEqual("Windows Created Thread", threadRef.Name);
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "thread/start");
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "thread/name/set");
    }

    [TestMethod]
    public async Task StartTurnAsyncLaunchesLoopbackAppServerTurn()
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var server = new FakeCatalogAppServer();
        var client = new AppServerClient();

        var turn = await client.StartTurnAsync(
            new AppServerEndpoint("Fake App Server", server.Url, null),
            new ThreadRef
            {
                HostID = "fake-host",
                ThreadID = "thread-started-1",
                Cwd = "C:\\Users\\example\\workspace",
                Name = "Windows Created Thread"
            },
            "ping",
            model: "gpt-live",
            reasoningEffort: "high",
            approvalPolicy: "never",
            sandboxMode: "read-only",
            cancellationToken: cancellation.Token);

        Assert.AreEqual("turn-started-1", turn.TurnId);
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "turn/start");
    }

    [TestMethod]
    public async Task InitializeAsyncAllowsServerToDropSocketAfterInitialized()
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var server = new FakeCatalogAppServer(closeAfterInitializedNotification: true);
        var client = new AppServerClient();

        var result = await client.InitializeAsync(
            new AppServerEndpoint("Fake App Server", server.Url, null),
            cancellation.Token);

        Assert.AreEqual("Fake App Server", result.HostName);
        Assert.AreEqual(HostPlatforms.Windows, result.Platform);
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "initialize");
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "initialized");
    }

    [TestMethod]
    public async Task ListModelsAsyncReadsLoopbackWebSocketModels()
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var server = new FakeCatalogAppServer();
        var client = new AppServerClient();

        var models = await client.ListModelsAsync(
            new AppServerEndpoint("Fake App Server", server.Url, null),
            cancellationToken: cancellation.Token);

        Assert.AreEqual(1, models.Count);
        Assert.AreEqual("gpt-live", models[0].Id);
        Assert.AreEqual("GPT Live", models[0].DisplayName);
        Assert.AreEqual("medium", models[0].DefaultReasoningEffort);
        CollectionAssert.AreEqual(new[] { "medium", "high" }, models[0].SupportedReasoningEfforts.ToArray());
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "initialize");
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "model/list");
    }

    [TestMethod]
    public async Task ListMentionCandidatesAsyncReadsLoopbackWebSocketCatalog()
    {
        using var cancellation = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        using var server = new FakeCatalogAppServer();
        var client = new AppServerClient();

        var candidates = await client.ListMentionCandidatesAsync(
            new AppServerEndpoint("Fake App Server", server.Url, null),
            "C:\\Users\\example\\workspace",
            fileLimit: 2,
            cancellationToken: cancellation.Token);

        Assert.IsTrue(candidates.Any(candidate => candidate.Title == "$mapofagents-workflow-bridge"));
        Assert.IsTrue(candidates.Any(candidate => candidate.Title == "$taildesk-start-app" && candidate.Trigger == '$'));
        Assert.IsTrue(candidates.Any(candidate => candidate.Title == "@browser" && candidate.Trigger == '@'));
        Assert.IsTrue(candidates.Any(candidate => candidate.Title == "@README.md" && candidate.Trigger == '@'));
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "initialize");
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "skills/list");
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "plugin/list");
        CollectionAssert.Contains(server.ReceivedMethods.ToArray(), "fs/readDirectory");
    }

    private sealed class FakeCatalogAppServer : IDisposable
    {
        private readonly TcpListener _listener;
        private readonly Task _serverTask;
        private readonly CancellationTokenSource _cancellation = new();
        private readonly bool _closeAfterInitializedNotification;

        public FakeCatalogAppServer(bool closeAfterInitializedNotification = false)
        {
            _closeAfterInitializedNotification = closeAfterInitializedNotification;
            _listener = new TcpListener(IPAddress.Loopback, 0);
            _listener.Start();
            var port = ((IPEndPoint)_listener.LocalEndpoint).Port;
            Url = new Uri($"ws://127.0.0.1:{port}/");
            _serverTask = Task.Run(() => AcceptClientsAsync(_cancellation.Token));
        }

        public Uri Url { get; }

        public ConcurrentBag<string> ReceivedMethods { get; } = [];

        public void Dispose()
        {
            _cancellation.Cancel();
            _listener.Stop();
            try
            {
                _serverTask.Wait(TimeSpan.FromSeconds(2));
            }
            catch (AggregateException)
            {
            }

            _cancellation.Dispose();
        }

        private async Task AcceptClientsAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                try
                {
                    using var client = await _listener.AcceptTcpClientAsync(cancellationToken);
                    await HandleClientAsync(client, cancellationToken);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (ObjectDisposedException)
                {
                    break;
                }
            }
        }

        private async Task HandleClientAsync(TcpClient client, CancellationToken cancellationToken)
        {
            await using var stream = client.GetStream();

            var request = await ReadHttpRequestAsync(stream, cancellationToken);
            var key = request
                .Split("\r\n", StringSplitOptions.RemoveEmptyEntries)
                .Select(line => line.Split(':', 2))
                .First(parts => parts.Length == 2 && parts[0].Equals("Sec-WebSocket-Key", StringComparison.OrdinalIgnoreCase))[1]
                .Trim();
            var accept = Convert.ToBase64String(SHA1.HashData(Encoding.ASCII.GetBytes($"{key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11")));
            var handshake = Encoding.ASCII.GetBytes(
                "HTTP/1.1 101 Switching Protocols\r\n" +
                "Upgrade: websocket\r\n" +
                "Connection: Upgrade\r\n" +
                $"Sec-WebSocket-Accept: {accept}\r\n\r\n");
            await stream.WriteAsync(handshake, cancellationToken);

            while (!cancellationToken.IsCancellationRequested)
            {
                var frame = await ReadWebSocketFrameAsync(stream, cancellationToken);
                if (frame is null)
                {
                    break;
                }

                if (frame.Value.Opcode == 0x8)
                {
                    await WriteWebSocketCloseFrameAsync(stream, cancellationToken);
                    break;
                }

                var json = Encoding.UTF8.GetString(frame.Value.Payload);
                using var document = JsonDocument.Parse(json);
                var root = document.RootElement;
                var method = root.TryGetProperty("method", out var methodElement)
                    ? methodElement.GetString() ?? ""
                    : "";
                if (!string.IsNullOrWhiteSpace(method))
                {
                    ReceivedMethods.Add(method);
                }

                if (!root.TryGetProperty("id", out var idElement) ||
                    idElement.ValueKind != JsonValueKind.Number)
                {
                    if (_closeAfterInitializedNotification &&
                        string.Equals(method, "initialized", StringComparison.Ordinal))
                    {
                        break;
                    }

                    continue;
                }

                var id = idElement.GetInt32();
                var response = method switch
                {
                    "initialize" => "{\"id\":" + id + ",\"result\":{\"displayName\":\"Fake App Server\",\"platformOs\":\"windows\",\"codexHome\":\"C:\\\\Users\\\\example\\\\.codex\"}}",
                    "thread/list" => "{\"id\":" + id + ",\"result\":{\"data\":[{\"id\":\"thread-live-catalog-1\",\"cwd\":\"C:\\\\Users\\\\example\\\\workspace\",\"name\":\"Live Catalog Thread\",\"preview\":\"Returned by fake app-server thread/list.\",\"status\":\"running\",\"updatedAt\":\"2026-06-03T21:00:00Z\",\"model\":\"gpt-5\",\"reasoningEffort\":\"high\"}]}}",
                    "thread/start" => "{\"id\":" + id + ",\"result\":{\"thread\":{\"id\":\"thread-started-1\",\"cwd\":\"C:\\\\Users\\\\example\\\\workspace\"}}}",
                    "thread/name/set" => "{\"id\":" + id + ",\"result\":{}}",
                    "turn/start" => "{\"id\":" + id + ",\"result\":{\"turn\":{\"id\":\"turn-started-1\"}}}",
                    "model/list" => "{\"id\":" + id + ",\"result\":{\"data\":[{\"id\":\"gpt-live\",\"displayName\":\"GPT Live\",\"defaultReasoningEffort\":\"medium\",\"supportedReasoningEfforts\":[\"medium\",\"high\"],\"isDefault\":true}]}}",
                    "skills/list" => "{\"id\":" + id + ",\"result\":{\"skills\":[{\"name\":\"taildesk-start-app\",\"path\":\"file:///skills/taildesk-start-app/SKILL.md\",\"interface\":{\"displayName\":\"TailDesk\",\"shortDescription\":\"Start the viewer.\"}}]}}",
                    "plugin/list" => "{\"id\":" + id + ",\"result\":{\"marketplaces\":[{\"name\":\"local\",\"plugins\":[{\"id\":\"browser@local\",\"name\":\"browser\",\"installed\":true,\"interface\":{\"displayName\":\"Browser\",\"shortDescription\":\"Control browser.\"}}]}]}}",
                    "fs/readDirectory" => FakeReadDirectoryResponse(id, root),
                    _ => "{\"id\":" + id + ",\"result\":{}}"
                };
                await WriteWebSocketTextFrameAsync(stream, response, cancellationToken);
            }
        }

        private static string FakeReadDirectoryResponse(int id, JsonElement request)
        {
            var path = request.TryGetProperty("params", out var parameters) &&
                parameters.TryGetProperty("path", out var pathElement)
                    ? pathElement.GetString()
                    : "";
            var entries = string.Equals(path, "C:\\Users\\example\\workspace", StringComparison.OrdinalIgnoreCase)
                ? "[{\"fileName\":\"README.md\",\"isFile\":true},{\"fileName\":\"src\",\"isDirectory\":true}]"
                : "[]";
            return "{\"id\":" + id + ",\"result\":{\"entries\":" + entries + "}}";
        }

        private static async Task<string> ReadHttpRequestAsync(NetworkStream stream, CancellationToken cancellationToken)
        {
            using var buffer = new MemoryStream();
            var oneByte = new byte[1];
            while (true)
            {
                var read = await stream.ReadAsync(oneByte, cancellationToken);
                if (read == 0)
                {
                    throw new IOException("Client disconnected before completing the WebSocket handshake.");
                }

                buffer.WriteByte(oneByte[0]);
                var bytes = buffer.ToArray();
                if (bytes.Length >= 4 &&
                    bytes[^4] == '\r' &&
                    bytes[^3] == '\n' &&
                    bytes[^2] == '\r' &&
                    bytes[^1] == '\n')
                {
                    return Encoding.ASCII.GetString(bytes);
                }
            }
        }

        private static async Task<WebSocketFrame?> ReadWebSocketFrameAsync(NetworkStream stream, CancellationToken cancellationToken)
        {
            var header = await ReadExactAsync(stream, 2, cancellationToken);
            if (header.Length == 0)
            {
                return null;
            }

            var opcode = header[0] & 0x0F;
            var isMasked = (header[1] & 0x80) != 0;
            ulong payloadLength = (ulong)(header[1] & 0x7F);
            if (payloadLength == 126)
            {
                payloadLength = BinaryPrimitives.ReadUInt16BigEndian(await ReadExactAsync(stream, 2, cancellationToken));
            }
            else if (payloadLength == 127)
            {
                payloadLength = BinaryPrimitives.ReadUInt64BigEndian(await ReadExactAsync(stream, 8, cancellationToken));
            }

            var mask = isMasked ? await ReadExactAsync(stream, 4, cancellationToken) : [];
            var payload = await ReadExactAsync(stream, checked((int)payloadLength), cancellationToken);
            if (isMasked)
            {
                for (var index = 0; index < payload.Length; index++)
                {
                    payload[index] ^= mask[index % 4];
                }
            }

            return new WebSocketFrame(opcode, payload);
        }

        private static async Task WriteWebSocketTextFrameAsync(NetworkStream stream, string text, CancellationToken cancellationToken)
        {
            var payload = Encoding.UTF8.GetBytes(text);
            using var frame = new MemoryStream();
            frame.WriteByte(0x81);
            if (payload.Length < 126)
            {
                frame.WriteByte((byte)payload.Length);
            }
            else if (payload.Length <= ushort.MaxValue)
            {
                frame.WriteByte(126);
                var length = new byte[2];
                BinaryPrimitives.WriteUInt16BigEndian(length, (ushort)payload.Length);
                frame.Write(length);
            }
            else
            {
                frame.WriteByte(127);
                var length = new byte[8];
                BinaryPrimitives.WriteUInt64BigEndian(length, (ulong)payload.Length);
                frame.Write(length);
            }

            frame.Write(payload);
            await stream.WriteAsync(frame.ToArray(), cancellationToken);
        }

        private static async Task WriteWebSocketCloseFrameAsync(NetworkStream stream, CancellationToken cancellationToken)
        {
            await stream.WriteAsync(new byte[] { 0x88, 0x00 }, cancellationToken);
        }

        private static async Task<byte[]> ReadExactAsync(NetworkStream stream, int count, CancellationToken cancellationToken)
        {
            var buffer = new byte[count];
            var offset = 0;
            while (offset < count)
            {
                var read = await stream.ReadAsync(buffer.AsMemory(offset, count - offset), cancellationToken);
                if (read == 0)
                {
                    return offset == 0 ? [] : throw new IOException("Client disconnected mid-frame.");
                }

                offset += read;
            }

            return buffer;
        }

        private readonly record struct WebSocketFrame(int Opcode, byte[] Payload);
    }
}
