using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class CodexRemoteTunnelServiceTests
{
    [TestMethod]
    public void UsesWindowsPortPreferenceForWindowsRemotes()
    {
        var windowsRemote = new CodexDesktopRemote { DisplayName = "Windows DESKTOP-EXAMPLE" };
        var linuxRemote = new CodexDesktopRemote { DisplayName = "linux-builder" };

        CollectionAssert.AreEqual(
            new[] { 14_500, 18_945 },
            CodexRemoteTunnelService.RemoteAppServerPortCandidates(windowsRemote).ToArray());
        CollectionAssert.AreEqual(
            new[] { 18_945, 14_500 },
            CodexRemoteTunnelService.RemoteAppServerPortCandidates(linuxRemote).ToArray());
    }

    [TestMethod]
    public void PendingConnectionStepsMirrorMacDiagnosticFlow()
    {
        var remote = new CodexDesktopRemote
        {
            DisplayName = "Windows DESKTOP-EXAMPLE",
            HostID = "remote-ssh-codex-managed:Windows%20DESKTOP-EXAMPLE",
            Hostname = "User@windows.example.ts.net"
        };

        var steps = CodexRemoteTunnelService.PendingConnectionDiagnosticSteps(remote);

        Assert.AreEqual(10, steps.Count);
        Assert.AreEqual("ssh-reachable", steps[0].Id);
        Assert.AreEqual(RuntimeDiagnosticStatuses.Running, steps[0].Status);
        Assert.AreEqual("relay-handshake", steps[^1].Id);
    }

    [TestMethod]
    public void DebugReportMatchesMacRemoteDiagnosticsFields()
    {
        var remote = new CodexDesktopRemote
        {
            Id = "desktop-1",
            DisplayName = "Windows Desktop",
            HostID = "desktop-1",
            Hostname = "example-host.local",
            IdentityPath = "configured",
            SshPort = 2222
        };
        var generatedAt = new DateTimeOffset(2026, 6, 8, 12, 30, 0, TimeSpan.Zero);

        var report = CodexRemoteTunnelService.DebugReport(
            remote,
            [
                new RuntimeDiagnosticStep
                {
                    Id = "codex",
                    Title = "Codex CLI found",
                    Status = RuntimeDiagnosticStatuses.Passed,
                    Detail = "codex ok",
                    Evidence = "remote ports checked"
                }
            ],
            generatedAt);

        StringAssert.Contains(report, "MapofAgents Remote Diagnostics");
        StringAssert.Contains(report, "generatedAt: 2026-06-08T12:30:00.0000000+00:00");
        StringAssert.Contains(report, "remoteName: Windows Desktop");
        StringAssert.Contains(report, "remoteID: desktop-1");
        StringAssert.Contains(report, "platform: windows");
        StringAssert.Contains(report, "sshTarget: example-host.local");
        StringAssert.Contains(report, "sshPort: 2222");
        StringAssert.Contains(report, "identity: configured");
        StringAssert.Contains(report, "appServerPortCandidates: 14500, 18945");
        StringAssert.Contains(report, "- [passed] Codex CLI found");
        StringAssert.Contains(report, "detail: codex ok");
        StringAssert.Contains(report, "evidence: remote ports checked");
    }

    [TestMethod]
    public void DebugReportRedactsSensitiveDiagnosticText()
    {
        var remote = new CodexDesktopRemote
        {
            Id = "desktop-1",
            DisplayName = "Mac Desktop",
            HostID = "desktop-1",
            Hostname = "example-host.local"
        };

        var report = CodexRemoteTunnelService.DebugReport(
            remote,
            [
                new RuntimeDiagnosticStep
                {
                    Id = "token",
                    Title = "Token file found",
                    Status = RuntimeDiagnosticStatuses.Failed,
                    Detail = "Bearer abcdefghijklmnopqrstuvwxyz",
                    Evidence = "token file mapofagents-codex-app-server-18945.token --ws-token-file /tmp/remote-token"
                }
            ],
            new DateTimeOffset(2026, 6, 8, 12, 30, 0, TimeSpan.Zero));

        StringAssert.Contains(report, "Bearer <redacted>");
        StringAssert.Contains(report, "--ws-token-file <token-file>");
        StringAssert.Contains(report, "mapofagents-codex-app-server-<port>.token");
        Assert.IsFalse(report.Contains("abcdefghijklmnopqrstuvwxyz", StringComparison.Ordinal));
        Assert.IsFalse(report.Contains("18945.token", StringComparison.Ordinal));
    }

    [TestMethod]
    public void RedactsTokensFromDiagnostics()
    {
        var redacted = CodexRemoteTunnelService.RedactSensitiveDiagnosticText(
            "token:abcdef1234567890 --ws-token-file C:\\Users\\example\\mapofagents-codex-app-server-14500.token Bearer abcdef1234567890 Warning: Identity file C:\\Users\\example\\.ssh\\codex_example not accessible.");

        Assert.IsFalse(redacted.Contains("abcdef1234567890"));
        Assert.IsFalse(redacted.Contains("14500.token"));
        Assert.IsFalse(redacted.Contains("codex_example"));
        Assert.IsTrue(redacted.Contains("token:<redacted>"));
        Assert.IsTrue(redacted.Contains("--ws-token-file <token-file>"));
        Assert.IsTrue(redacted.Contains("Bearer <redacted>"));
        Assert.IsTrue(redacted.Contains("Identity file <identity-file> not accessible"));
    }

    [TestMethod]
    public void CleansPowerShellClixmlFromSshOutput()
    {
        var progressOnly = """
            #< CLIXML
            ready
            <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><Obj S="progress" RefId="0"><MS><PR N="Record"><AV>Preparing modules for first use.</AV></PR></MS></Obj></Objs>
            """;

        Assert.AreEqual("ready", CodexRemoteTunnelService.CleanedSshOutputForDisplay(progressOnly));

        var error = """
            #< CLIXML
            <Objs Version="1.1.0.1" xmlns="http://schemas.microsoft.com/powershell/2004/04"><S S="Error">Port 14500 is already in use_x000D__x000A_Restart MapofAgents on Windows</S></Objs>
            """;

        Assert.AreEqual(
            "Port 14500 is already in use\nRestart MapofAgents on Windows",
            CodexRemoteTunnelService.CleanedSshOutputForDisplay(error));
    }

    [TestMethod]
    public void BrowseRemoteFoldersRequiresConnectableDesktopPlatform()
    {
        Assert.IsTrue(CodexRemoteTunnelService.CanBrowseRemoteFolders(new CodexDesktopRemote
        {
            DisplayName = "Windows DESKTOP-EXAMPLE",
            Hostname = "User@windows.example.ts.net"
        }));
        Assert.IsTrue(CodexRemoteTunnelService.CanBrowseRemoteFolders(new CodexDesktopRemote
        {
            DisplayName = "macbook-pro",
            Hostname = "user@example-mac.local"
        }));
        Assert.IsFalse(CodexRemoteTunnelService.CanBrowseRemoteFolders(new CodexDesktopRemote
        {
            DisplayName = "iPad",
            Hostname = "user@example-ipad.local"
        }));
        Assert.IsFalse(CodexRemoteTunnelService.CanBrowseRemoteFolders(new CodexDesktopRemote
        {
            DisplayName = "Windows DESKTOP-EXAMPLE"
        }));
    }

    [TestMethod]
    public void ParsesRemoteFolderListingFromNoisyOutput()
    {
        var listing = CodexRemoteTunnelService.RemoteFolderListingFromOutput(
            """
            Warning: remote banner
            {"path":"C:\\Users\\User","parent":"C:\\Users","entries":[{"name":"Desktop","path":"C:\\Users\\User\\Desktop"},{"name":"source","path":"C:\\Users\\User\\source"}]}
            """);

        Assert.AreEqual("C:\\Users\\User", listing.Path);
        Assert.AreEqual("C:\\Users", listing.ParentPath);
        Assert.AreEqual(2, listing.Entries.Count);
        Assert.AreEqual("Desktop", listing.Entries[0].Name);
        Assert.AreEqual("C:\\Users\\User\\Desktop", listing.Entries[0].Path);
    }

    [TestMethod]
    public void RejectsEmptyRemoteFolderListingOutput()
    {
        Assert.ThrowsException<CodexRemoteTunnelException>(() =>
            CodexRemoteTunnelService.RemoteFolderListingFromOutput("remote command printed no json"));
    }
}
