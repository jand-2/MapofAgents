using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class CodexDesktopRemoteServiceTests
{
    [TestMethod]
    public void ParsesManagedRemoteConnections()
    {
        var json = """
        {
          "version": 1,
          "codex-managed-remote-connections": [
            {
              "alias": null,
              "displayName": "Windows DESKTOP-EXAMPLE",
              "hostId": "remote-ssh-codex-managed:Windows%20DESKTOP-EXAMPLE",
              "hostname": "User@windows.example.ts.net",
              "identity": "C:\\Users\\example\\.ssh\\codex_example",
              "source": "codex-managed",
              "sshPort": 22
            },
            {
              "alias": "windows-erp",
              "displayName": "windows-erp",
              "hostId": "remote-ssh-discovered:windows-erp",
              "hostname": null,
              "identity": null,
              "source": "discovered",
              "sshPort": null
            }
          ]
        }
        """;

        var remotes = CodexDesktopRemoteService.RemotesFromJson(json);
        var managedRemote = remotes[0];

        Assert.AreEqual(2, remotes.Count);
        Assert.AreEqual("Windows DESKTOP-EXAMPLE", managedRemote.DisplayName);
        Assert.AreEqual("User@windows.example.ts.net", managedRemote.Hostname);
        Assert.AreEqual("C:\\Users\\example\\.ssh\\codex_example", managedRemote.IdentityPath);
        Assert.AreEqual(22, managedRemote.SshPort);
        Assert.AreEqual("codex-managed", managedRemote.Source);
        Assert.AreEqual(HostPlatforms.Windows, managedRemote.Platform);
        Assert.IsTrue(managedRemote.IsConnectable);
        Assert.IsFalse(remotes[1].IsConnectable);
    }

    [TestMethod]
    public void RejectsUnsafeSshTargets()
    {
        var json = """
        {
          "codex-managed-remote-connections": [
            {
              "displayName": "Unsafe",
              "hostId": "remote-ssh-codex-managed:Unsafe",
              "hostname": "-oProxyCommand=touch example",
              "identity": null,
              "source": "codex-managed",
              "sshPort": 22
            }
          ]
        }
        """;

        var remotes = CodexDesktopRemoteService.RemotesFromJson(json);

        Assert.IsNull(remotes[0].Hostname);
        Assert.IsFalse(remotes[0].IsConnectable);
        Assert.IsTrue(CodexDesktopRemoteService.IsValidSSHTarget("User@windows.example.ts.net"));
        Assert.IsFalse(CodexDesktopRemoteService.IsValidSSHTarget("User@windows.example.ts.net -oProxyCommand=nope"));
    }
}
