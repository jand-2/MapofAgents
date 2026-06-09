using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TailnetDiscoveryServiceTests
{
    [TestMethod]
    public void ParsesTailscaleStatusPeers()
    {
        var json = """
        {
          "Peer": {
            "nodekey:abc": {
              "ID": "n1",
              "PublicKey": "nodekey:abc",
              "HostName": "desktop",
              "DNSName": "desktop.example.ts.net.",
              "OS": "windows",
              "TailscaleIPs": ["192.0.2.10", "2001:db8::10"],
              "Online": true,
              "LastSeen": "2026-05-21T05:45:12Z"
            },
            "nodekey:def": {
              "ID": "n2",
              "HostName": "Example Mac mini",
              "OS": "macOS",
              "TailscaleIPs": ["192.0.2.11"],
              "Online": false
            }
          }
        }
        """;

        var machines = TailnetDiscoveryService.MachinesFromJson(json);

        Assert.AreEqual(2, machines.Count);
        Assert.AreEqual("desktop", machines[0].Name);
        Assert.AreEqual("desktop.example.ts.net", machines[0].DnsName);
        Assert.AreEqual(HostPlatforms.Windows, machines[0].Platform);
        Assert.IsTrue(machines[0].IsOnline);
        Assert.AreEqual("wss://desktop.example.ts.net:18945", machines[0].SuggestedWebSocketEndpoint());
        Assert.AreEqual("Example Mac mini", machines[1].Name);
        Assert.AreEqual(HostPlatforms.MacOS, machines[1].Platform);
        Assert.IsFalse(machines[1].IsOnline);
    }

    [TestMethod]
    public void WrapsIpv6AddressForSuggestedEndpoint()
    {
        var machine = new TailnetMachine
        {
            Name = "ipv6-host",
            Addresses = ["2001:db8::20"],
            IsOnline = true
        };

        Assert.AreEqual("ws://[2001:db8::20]:18945", machine.SuggestedWebSocketEndpoint());
    }
}
