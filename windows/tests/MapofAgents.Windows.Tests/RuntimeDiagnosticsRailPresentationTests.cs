using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class RuntimeDiagnosticsRailPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacRuntimeDiagnosticsRowMetrics()
    {
        var presentation = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Pending);

        Assert.AreEqual(10, presentation.ContentSpacing);
        Assert.AreEqual(8, presentation.RowColumnSpacing);
        Assert.AreEqual(0, presentation.RowVerticalPadding);
        Assert.AreEqual(16, presentation.IconColumnWidth);
        Assert.AreEqual(13, presentation.IconFontSize);
        Assert.AreEqual(13, presentation.FilledStatusIconSize);
        Assert.AreEqual(1.45, presentation.FilledStatusIconStrokeThickness);
        Assert.AreEqual(1, presentation.DetailStackSpacing);
        Assert.AreEqual(12, presentation.TitleFontSize);
        Assert.AreEqual(11, presentation.DetailFontSize);
        Assert.AreEqual(ThreadInboxPresentation.SecondaryHex, presentation.DetailForegroundHex);
    }

    [TestMethod]
    public void ResolveKeepsMacDetailLineLimitAndEllipsis()
    {
        var presentation = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Warning);

        Assert.AreEqual(1, presentation.DetailLineLimit);
        Assert.IsFalse(presentation.DetailAllowsWrapping);
        Assert.AreEqual("CharacterEllipsis", presentation.DetailTrimmingMode);
    }

    [TestMethod]
    public void ResolveUsesMacStatusColors()
    {
        Assert.AreEqual(ThreadInboxPresentation.SecondaryHex, RuntimeDiagnosticsRailPresentation.Resolve("pending").ForegroundHex);
        Assert.AreEqual(ThreadInboxPresentation.BlueHex, RuntimeDiagnosticsRailPresentation.Resolve("running").ForegroundHex);
        Assert.AreEqual(ThreadInboxPresentation.GreenHex, RuntimeDiagnosticsRailPresentation.Resolve("passed").ForegroundHex);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, RuntimeDiagnosticsRailPresentation.Resolve("warning").ForegroundHex);
        Assert.AreEqual(ThreadInboxPresentation.RedHex, RuntimeDiagnosticsRailPresentation.Resolve("failed").ForegroundHex);
    }

    [TestMethod]
    public void ResolveUsesMacStatusSymbolsForEveryStatus()
    {
        var pending = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Pending);
        var running = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Running);
        var passed = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Passed);
        var warning = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Warning);
        var failed = RuntimeDiagnosticsRailPresentation.Resolve(RuntimeDiagnosticStatuses.Failed);

        Assert.AreEqual("circle", pending.MacSymbolName);
        Assert.IsTrue(pending.UsesPendingCircleIcon);
        Assert.IsFalse(pending.UsesRunningArrowsIcon);
        Assert.IsFalse(pending.UsesFilledCheckIcon);
        Assert.IsFalse(pending.UsesFilledXIcon);
        Assert.IsFalse(pending.UsesFilledWarningIcon);
        Assert.AreEqual("arrow.triangle.2.circlepath", running.MacSymbolName);
        Assert.IsTrue(running.UsesRunningArrowsIcon);
        Assert.IsFalse(running.UsesPendingCircleIcon);
        Assert.IsFalse(running.UsesFilledCheckIcon);
        Assert.IsFalse(running.UsesFilledXIcon);
        Assert.IsFalse(running.UsesFilledWarningIcon);
        Assert.AreEqual("checkmark.circle.fill", passed.MacSymbolName);
        Assert.IsFalse(passed.UsesPendingCircleIcon);
        Assert.IsFalse(passed.UsesRunningArrowsIcon);
        Assert.IsTrue(passed.UsesFilledCheckIcon);
        Assert.IsFalse(passed.UsesFilledXIcon);
        Assert.IsFalse(passed.UsesFilledWarningIcon);
        Assert.AreEqual("exclamationmark.triangle.fill", warning.MacSymbolName);
        Assert.IsFalse(warning.UsesPendingCircleIcon);
        Assert.IsFalse(warning.UsesRunningArrowsIcon);
        Assert.IsFalse(warning.UsesFilledCheckIcon);
        Assert.IsFalse(warning.UsesFilledXIcon);
        Assert.IsTrue(warning.UsesFilledWarningIcon);
        Assert.AreEqual("xmark.circle.fill", failed.MacSymbolName);
        Assert.IsFalse(failed.UsesPendingCircleIcon);
        Assert.IsFalse(failed.UsesRunningArrowsIcon);
        Assert.IsTrue(failed.UsesFilledXIcon);
        Assert.IsFalse(failed.UsesFilledCheckIcon);
        Assert.IsFalse(failed.UsesFilledWarningIcon);
    }

    [TestMethod]
    public void ResolveFallsBackToPendingForUnknownStatus()
    {
        var presentation = RuntimeDiagnosticsRailPresentation.Resolve("mystery");

        Assert.AreEqual("Pending", presentation.StatusLabel);
        Assert.AreEqual("\uEA3A", presentation.Glyph);
        Assert.AreEqual(ThreadInboxPresentation.SecondaryHex, presentation.ForegroundHex);
    }
}
