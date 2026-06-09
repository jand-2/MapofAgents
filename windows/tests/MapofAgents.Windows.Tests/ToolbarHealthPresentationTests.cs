using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarHealthPresentationTests
{
    [TestMethod]
    public void IdleUsesMacHeartTextSquareTreatment()
    {
        var presentation = ToolbarHealthPresentation.Resolve(isRefreshing: false);

        Assert.AreEqual("heart.text.square", presentation.MacSymbolName);
        Assert.IsTrue(presentation.ShowsHeartTextSquareIcon);
        Assert.AreEqual("#D7DCE5", presentation.IconHex);
        Assert.AreEqual(1.0, presentation.Opacity);
        Assert.AreEqual("Refresh machine and runtime health", presentation.ToolTip);
        Assert.AreEqual(16, presentation.IconWidth);
        Assert.AreEqual(14, presentation.IconHeight);
        Assert.AreEqual(1.1, presentation.StrokeThickness);
    }

    [TestMethod]
    public void RefreshingUsesMacCircularArrowsTreatment()
    {
        var presentation = ToolbarHealthPresentation.Resolve(isRefreshing: true);

        Assert.AreEqual("arrow.triangle.2.circlepath", presentation.MacSymbolName);
        Assert.IsFalse(presentation.ShowsHeartTextSquareIcon);
        Assert.AreEqual("#D7DCE5", presentation.IconHex);
        Assert.AreEqual(0.74, presentation.Opacity);
        Assert.AreEqual("Connection refresh is already running.", presentation.ToolTip);
        Assert.AreEqual(16, presentation.IconWidth);
        Assert.AreEqual(14, presentation.IconHeight);
        Assert.AreEqual(1.1, presentation.StrokeThickness);
    }

    [TestMethod]
    public void MenuIconsTrackMacCommandBarSymbols()
    {
        var menu = ToolbarHealthPresentation.ResolveMenu();

        Assert.AreEqual(ToolbarHealthPresentation.RefreshIcon, menu.RefreshIconKind);
        Assert.AreEqual("arrow.clockwise", menu.RefreshMacSymbolName);
        Assert.AreEqual(ToolbarHealthPresentation.DiagnosticsIcon, menu.DiagnosticsIconKind);
        Assert.AreEqual("stethoscope", menu.DiagnosticsMacSymbolName);
        Assert.AreEqual(ToolbarHealthPresentation.RecoveryIcon, menu.RecoveryIconKind);
        Assert.AreEqual("cross.case", menu.RecoveryMacSymbolName);
        Assert.AreEqual(ToolbarHealthPresentation.LogsIcon, menu.LogsIconKind);
        Assert.AreEqual("doc.text.magnifyingglass", menu.LogsMacSymbolName);
        Assert.AreEqual(16, menu.IconSize);
    }
}
