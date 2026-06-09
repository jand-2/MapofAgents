using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineDiscoveryActionPresentationTests
{
    [TestMethod]
    public void ConnectableCodexRemoteActionsUseMacTooltipsAtFullOpacity()
    {
        var diagnose = MachineDiscoveryActionPresentation.DiagnoseCodexRemote(
            isConnectable: true,
            isBusy: false);
        var connect = MachineDiscoveryActionPresentation.ConnectCodexRemote(
            isConnectable: true,
            isBusy: false);

        Assert.IsTrue(diagnose.CanInvoke);
        Assert.AreEqual("Diagnose remote Codex over SSH", diagnose.ToolTip);
        Assert.AreEqual(1.0, diagnose.Opacity, 0.001);
        Assert.IsTrue(connect.CanInvoke);
        Assert.AreEqual("Start remote App Server and connect through SSH", connect.ToolTip);
        Assert.AreEqual(1.0, connect.Opacity, 0.001);
    }

    [TestMethod]
    public void SetupRequiredCodexRemoteActionsStayClickableButDimmedForFeedback()
    {
        var diagnose = MachineDiscoveryActionPresentation.DiagnoseCodexRemote(
            isConnectable: false,
            isBusy: false);
        var connect = MachineDiscoveryActionPresentation.ConnectCodexRemote(
            isConnectable: false,
            isBusy: false);

        Assert.IsFalse(diagnose.CanInvoke);
        Assert.AreEqual("This Codex remote needs SSH setup before it can connect.", diagnose.ToolTip);
        Assert.AreEqual(0.48, diagnose.Opacity, 0.001);
        Assert.IsFalse(connect.CanInvoke);
        Assert.AreEqual("This Codex remote needs SSH setup before it can connect.", connect.ToolTip);
        Assert.AreEqual(0.48, connect.Opacity, 0.001);
    }

    [TestMethod]
    public void BusyCodexRemoteActionsStayClickableButDimmedForFeedback()
    {
        var diagnose = MachineDiscoveryActionPresentation.DiagnoseCodexRemote(
            isConnectable: true,
            isBusy: true);
        var connect = MachineDiscoveryActionPresentation.ConnectCodexRemote(
            isConnectable: true,
            isBusy: true);

        Assert.IsFalse(diagnose.CanInvoke);
        Assert.AreEqual("Remote diagnostics are already running.", diagnose.ToolTip);
        Assert.AreEqual(0.48, diagnose.Opacity, 0.001);
        Assert.IsFalse(connect.CanInvoke);
        Assert.AreEqual("Remote diagnostics are already running.", connect.ToolTip);
        Assert.AreEqual(0.48, connect.Opacity, 0.001);
    }

    [TestMethod]
    public void TailnetFillActionUsesMacFeedbackButtonSemantics()
    {
        var available = MachineDiscoveryActionPresentation.FillEndpoint(hasEndpoint: true);
        var unavailable = MachineDiscoveryActionPresentation.FillEndpoint(hasEndpoint: false);

        Assert.IsTrue(available.CanInvoke);
        Assert.AreEqual("Fill a manual WebSocket endpoint", available.ToolTip);
        Assert.AreEqual(1.0, available.Opacity, 0.001);
        Assert.IsFalse(unavailable.CanInvoke);
        Assert.AreEqual("This tailnet entry does not expose a usable App Server endpoint.", unavailable.ToolTip);
        Assert.AreEqual(0.48, unavailable.Opacity, 0.001);
    }
}
