using System.Text;
using System.Text.Json;
using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MapofAgentsPairingTests
{
    [TestMethod]
    public void DecodesPairingUrlAndPrefersTailnetEndpoint()
    {
        var url = PairingUrl(new
        {
            version = 1,
            hostID = "host-public-example",
            name = "Example Mac",
            bearerToken = "token-public-example",
            createdAt = "2026-06-05T09:00:00Z",
            expiresAt = DateTimeOffset.UtcNow.AddMinutes(30),
            endpoints = new[]
            {
                new { id = "local", kind = "local", url = "ws://127.0.0.1:18945", label = "Local" },
                new { id = "tailnet", kind = "tailnet", url = "ws://example-host.tail.example.ts.net:18945", label = "Tailnet" }
            }
        });

        var payload = MapofAgentsPairingPayload.Decode(url);
        payload.ValidateForImport();
        var endpoint = payload.PreferredEndpoint();

        Assert.AreEqual("Example Mac", payload.Name);
        Assert.AreEqual("token-public-example", payload.BearerToken);
        Assert.IsNotNull(endpoint);
        Assert.AreEqual("tailnet", endpoint!.Kind);
        Assert.AreEqual("ws://example-host.tail.example.ts.net:18945", endpoint.Url);
    }

    [TestMethod]
    public void ImportPreviewListsPreferredEndpointFirst()
    {
        var payload = MapofAgentsPairingPayload.Decode(PairingUrl(new
        {
            version = 1,
            hostID = "host-public-example",
            name = "Example Mac",
            bearerToken = "token-public-example",
            createdAt = "2026-06-05T09:00:00Z",
            expiresAt = DateTimeOffset.UtcNow.AddMinutes(30),
            endpoints = new[]
            {
                new { id = "local", kind = "local", url = "ws://127.0.0.1:18945", label = "Local" },
                new { id = "tailnet-b", kind = "tailnet", url = "ws://z.example.ts.net:18945", label = "Zed" },
                new { id = "tailnet-a", kind = "tailnet", url = "ws://a.example.ts.net:18945", label = "Alpha" }
            }
        }));

        var preview = MapofAgentsPairingImportPreview.FromPayload(payload);

        Assert.AreEqual("Example Mac", preview.HostName);
        Assert.AreEqual(3, preview.Endpoints.Count);
        Assert.AreEqual("tailnet-b", preview.Endpoints[0].Id);
        Assert.IsTrue(preview.Endpoints[0].IsPreferred);
        Assert.IsFalse(preview.Endpoints[1].IsPreferred);
        Assert.AreEqual("local", preview.Endpoints[2].Id);
        Assert.AreEqual("Zed", preview.PreferredEndpoint?.Label);
    }

    [TestMethod]
    public void RejectsExpiredPairingPayload()
    {
        var rawPayload = EncodedPayload(new
        {
            version = 1,
            hostID = "host-public-example",
            name = "Example Mac",
            bearerToken = "token-public-example",
            createdAt = "2026-06-05T09:00:00Z",
            expiresAt = DateTimeOffset.UtcNow.AddMinutes(-1),
            endpoints = new[]
            {
                new { id = "tailnet", kind = "tailnet", url = "wss://example-host.tail.example.ts.net:18945", label = "Tailnet" }
            }
        });

        var payload = MapofAgentsPairingPayload.Decode(rawPayload);

        Assert.ThrowsException<MapofAgentsPairingException>(payload.ValidateForImport);
    }

    [TestMethod]
    public void IgnoresRemoteCleartextEndpointForImport()
    {
        var payload = MapofAgentsPairingPayload.Decode(PairingUrl(new
        {
            version = 1,
            hostID = "host-public-example",
            name = "Example Mac",
            bearerToken = "token-public-example",
            createdAt = "2026-06-05T09:00:00Z",
            expiresAt = DateTimeOffset.UtcNow.AddMinutes(30),
            endpoints = new[]
            {
                new { id = "remote-ip", kind = "tailnet", url = "ws://192.0.2.10:18945", label = "Remote IP" },
                new { id = "loopback", kind = "local", url = "ws://127.0.0.1:18945", label = "Loopback" }
            }
        }));

        var endpoint = payload.PreferredEndpoint();

        Assert.IsNotNull(endpoint);
        Assert.AreEqual("loopback", endpoint!.Id);
    }

    [TestMethod]
    public void PairingPayloadEncodesPairingUrl()
    {
        var payload = new MapofAgentsPairingPayload
        {
            Version = 1,
            HostID = "host-public-example",
            Name = "Example Windows",
            BearerToken = "token-public-example",
            CreatedAt = DateTimeOffset.Parse("2026-06-05T09:00:00Z"),
            ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(30),
            MapofAgentsSupportDirectory = @"C:\Users\example\AppData\Roaming\MapofAgents",
            Endpoints =
            [
                new MapofAgentsPairingEndpoint
                {
                    Id = "tailnet",
                    Kind = "tailnet",
                    Url = "ws://example-host.local:18945",
                    Label = "example-host.local"
                }
            ]
        };

        var decoded = MapofAgentsPairingPayload.Decode(payload.PairingUrl());

        Assert.AreEqual(payload.HostID, decoded.HostID);
        Assert.AreEqual(payload.Name, decoded.Name);
        Assert.AreEqual(payload.BearerToken, decoded.BearerToken);
        Assert.AreEqual(payload.MapofAgentsSupportDirectory, decoded.MapofAgentsSupportDirectory);
        Assert.AreEqual(payload.Endpoints[0].Url, decoded.Endpoints[0].Url);
    }

    [TestMethod]
    public void SignedBearerTokenCarriesPairingClaims()
    {
        var issuedAt = DateTimeOffset.FromUnixTimeSeconds(1_000);
        var expiresAt = DateTimeOffset.FromUnixTimeSeconds(1_600);
        var token = MapofAgentsPairingHostService.SignedBearerToken(
            new string('a', 32),
            expiresAt,
            issuedAt);
        var parts = token.Split('.');
        var payloadData = Base64UrlDecodedData(parts[1]);
        var payload = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(payloadData);

        Assert.AreEqual(3, parts.Length);
        Assert.IsNotNull(payload);
        Assert.AreEqual("mapofagents", payload!["iss"].GetString());
        Assert.AreEqual("codex-app-server", payload["aud"].GetString());
        Assert.AreEqual("mapofagents-pairing", payload["sub"].GetString());
        Assert.AreEqual(1_000, payload["iat"].GetInt64());
        Assert.AreEqual(995, payload["nbf"].GetInt64());
        Assert.AreEqual(1_600, payload["exp"].GetInt64());
        Assert.AreEqual(expiresAt, MapofAgentsPairingHostService.SignedBearerExpiration(token));
    }

    [TestMethod]
    public void TailscaleSelfStatusProducesPairingEndpoints()
    {
        var json = """
        {
          "Self": {
            "DNSName": "desktop.example.ts.net.",
            "TailscaleIPs": ["192.0.2.10", "2001:db8::10"]
          }
        }
        """;

        var endpoints = MapofAgentsPairingHostService.EndpointCandidatesFromTailscaleStatusJson(json);

        Assert.AreEqual(3, endpoints.Count);
        Assert.AreEqual("tailnet", endpoints[0].Kind);
        Assert.AreEqual("desktop.example.ts.net", endpoints[0].Label);
        Assert.AreEqual("ws://desktop.example.ts.net:18945", endpoints[0].Url);
        Assert.AreEqual("ws://192.0.2.10:18945", endpoints[1].Url);
        Assert.AreEqual("ws://[2001:db8::10]:18945", endpoints[2].Url);
    }

    [TestMethod]
    public void PairingHostReadinessUsesLoopbackReadyEndpoint()
    {
        var url = MapofAgentsPairingHostService.ReadyzUrl(18_999);

        Assert.AreEqual("http://127.0.0.1:18999/readyz", url.AbsoluteUri);
    }

    [TestMethod]
    public void PairingHostListenerTracksWindowsNetworkApprovalNeed()
    {
        var listenerUrl = MapofAgentsPairingHostService.ListenerUrl(18_999);

        Assert.AreEqual("ws://0.0.0.0:18999", MapofAgentsPairingHostService.ListenerUrlString(18_999));
        Assert.IsTrue(MapofAgentsPairingHostService.MayRequireNetworkAccessApproval(listenerUrl, isWindows: true));
        Assert.IsFalse(MapofAgentsPairingHostService.MayRequireNetworkAccessApproval(listenerUrl, isWindows: false));
        Assert.IsFalse(MapofAgentsPairingHostService.MayRequireNetworkAccessApproval(new Uri("ws://127.0.0.1:18999"), isWindows: true));
        Assert.IsFalse(MapofAgentsPairingHostService.MayRequireNetworkAccessApproval(new Uri("wss://example-host.local:18999"), isWindows: true));
    }

    private static string PairingUrl(object payload)
    {
        return $"mapofagents://pair?payload={EncodedPayload(payload)}";
    }

    private static string EncodedPayload(object payload)
    {
        var json = JsonSerializer.Serialize(payload, MapofAgentsJson.Options);
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(json))
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static byte[] Base64UrlDecodedData(string value)
    {
        var base64 = value
            .Replace('-', '+')
            .Replace('_', '/');
        var padding = base64.Length % 4;
        if (padding > 0)
        {
            base64 = base64.PadRight(base64.Length + (4 - padding), '=');
        }

        return Convert.FromBase64String(base64);
    }
}
