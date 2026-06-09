using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class StatusStripPresentationTests
{
    [TestMethod]
    public void LocalDisconnectedUsesMacRuntimeMessage()
    {
        var presentation = StatusStripPresentation.Local(
            HostStatuses.Disconnected,
            "Not connected");

        Assert.AreEqual("Local: Not connected", presentation.Text);
        Assert.AreEqual("\uEA3A", presentation.Glyph);
        Assert.AreEqual(StatusStripPresentation.LocalDisconnectedIcon, presentation.IconKind);
        Assert.AreEqual(StatusStripPresentation.SecondaryHex, presentation.ForegroundHex);
        Assert.AreEqual("Not connected", presentation.HelpText);
    }

    [TestMethod]
    public void LocalConnectedUsesMacFilledCheckSymbol()
    {
        var presentation = StatusStripPresentation.Local(
            HostStatuses.Connected,
            "Connected");

        Assert.AreEqual("Local: Connected", presentation.Text);
        Assert.AreEqual("\uE73E", presentation.Glyph);
        Assert.AreEqual("checkmark.circle.fill", presentation.IconKind);
        Assert.AreEqual(StatusStripPresentation.ConnectedHex, presentation.ForegroundHex);
        Assert.AreEqual("Connected", presentation.HelpText);
    }

    [TestMethod]
    public void LocalUnavailableUsesMacOrangeRuntimeTreatment()
    {
        var presentation = StatusStripPresentation.Local(
            HostStatuses.Unavailable,
            "Startup failed",
            "codex app-server was not available");

        Assert.AreEqual("Local: Startup failed", presentation.Text);
        Assert.AreEqual("\uE7BA", presentation.Glyph);
        Assert.AreEqual(StatusStripPresentation.WarningIcon, presentation.IconKind);
        Assert.AreEqual(StatusStripPresentation.UnavailableHex, presentation.ForegroundHex);
        Assert.AreEqual("codex app-server was not available", presentation.HelpText);
    }

    [TestMethod]
    public void RemoteStableMatchesMacSummary()
    {
        var presentation = StatusStripPresentation.Remote(
        [
            Machine("remote-a", "Remote A", HostStatuses.Connected),
            Machine("remote-b", "Remote B", HostStatuses.Disconnected)
        ]);

        Assert.AreEqual("1 remote connected", presentation.Text);
        Assert.AreEqual("\uE8CE", presentation.Glyph);
        Assert.AreEqual(StatusStripPresentation.RemoteAntennaIcon, presentation.IconKind);
        Assert.AreEqual(StatusStripPresentation.SecondaryHex, presentation.ForegroundHex);
        Assert.AreEqual("Remote App Server and tunnel status looks stable.", presentation.HelpText);
    }

    [TestMethod]
    public void RemoteHostIssuesUseMacOrangeIssueSummary()
    {
        var presentation = StatusStripPresentation.Remote(
        [
            Machine("remote-c", "Zulu", HostStatuses.Unavailable, "SSH tunnel closed"),
            Machine("remote-a", "Alpha", HostStatuses.Unavailable, " App Server refused initialize "),
            Machine("remote-b", "Bravo", HostStatuses.Connected)
        ]);

        Assert.AreEqual("1 connected, 2 host issues", presentation.Text);
        Assert.AreEqual("\uE7BA", presentation.Glyph);
        Assert.AreEqual(StatusStripPresentation.WarningIcon, presentation.IconKind);
        Assert.AreEqual(StatusStripPresentation.UnavailableHex, presentation.ForegroundHex);
        Assert.AreEqual(
            string.Join(Environment.NewLine, "Alpha: App Server refused initialize", "Zulu: SSH tunnel closed"),
            presentation.HelpText);
    }

    [TestMethod]
    public void RemoteHostIssuesFallBackToFailedWhenNoLastErrorIsKnown()
    {
        var presentation = StatusStripPresentation.Remote(
        [
            Machine("remote-a", "Alpha", HostStatuses.Unavailable)
        ]);

        Assert.AreEqual("0 connected, 1 host issue", presentation.Text);
        Assert.AreEqual("Alpha: failed", presentation.HelpText);
    }

    [TestMethod]
    public void CanvasErrorsUseMacRedTreatment()
    {
        Assert.AreEqual("#FF453A", StatusStripPresentation.ErrorHex);
    }

    private static CanvasNode Machine(string id, string title, string status, string? hostLastError = null)
    {
        return new CanvasNode
        {
            Id = id,
            Kind = NodeKinds.Machine,
            Title = title,
            Metadata = new NodeMetadata
            {
                HostStatus = status,
                HostLastError = hostLastError
            }
        };
    }
}
