using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class CodexRemoteDiagnosticsSummaryPresentationTests
{
    [TestMethod]
    public void ResolveShowsBlueRunningSummaryWithoutDetailsButton()
    {
        var presentation = CodexRemoteDiagnosticsSummaryPresentation.Resolve(
            [
                new RuntimeDiagnosticStep
                {
                    Id = "ssh",
                    Title = "SSH tunnel opened",
                    Status = RuntimeDiagnosticStatuses.Running
                }
            ],
            isBusy: false);

        Assert.IsTrue(presentation.ShowsSummary);
        Assert.IsFalse(presentation.ShowsDiagnosticsButton);
        Assert.AreEqual("Remote diagnostics running", presentation.Text);
        Assert.AreEqual(ThreadInboxPresentation.BlueHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void ResolveShowsOrangeAttentionSummaryWithDetailsButton()
    {
        var presentation = CodexRemoteDiagnosticsSummaryPresentation.Resolve(
            [
                new RuntimeDiagnosticStep
                {
                    Id = "codex",
                    Title = "Codex CLI found",
                    Status = RuntimeDiagnosticStatuses.Warning
                }
            ],
            isBusy: false);

        Assert.IsTrue(presentation.ShowsSummary);
        Assert.IsTrue(presentation.ShowsDiagnosticsButton);
        Assert.AreEqual("Codex CLI found", presentation.Text);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual("Open remote diagnostics", presentation.ToolTip);
    }

    [TestMethod]
    public void ResolveKeepsPassedOrEmptyDiagnosticsQuiet()
    {
        var passed = CodexRemoteDiagnosticsSummaryPresentation.Resolve(
            [
                new RuntimeDiagnosticStep
                {
                    Id = "readyz",
                    Title = "Local tunnel /readyz passed",
                    Status = RuntimeDiagnosticStatuses.Passed
                }
            ],
            isBusy: false);
        var empty = CodexRemoteDiagnosticsSummaryPresentation.Resolve([], isBusy: false);

        Assert.IsFalse(passed.ShowsSummary);
        Assert.IsFalse(passed.ShowsDiagnosticsButton);
        Assert.IsFalse(empty.ShowsSummary);
        Assert.IsFalse(empty.ShowsDiagnosticsButton);
    }
}
