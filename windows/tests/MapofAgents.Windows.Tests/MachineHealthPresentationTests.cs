using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineHealthPresentationTests
{
    [TestMethod]
    public void FailedMachineUsesMacOrangeWarningTreatment()
    {
        var presentation = MachineHealthPresentation.Resolve(HostStatuses.Unavailable);

        Assert.AreEqual("failed", presentation.Text);
        Assert.AreEqual(MachineHealthPresentation.FailedGlyph, presentation.Glyph);
        Assert.AreEqual("exclamationmark.triangle.fill", presentation.MacSymbolName);
        Assert.AreEqual(MachineHealthPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual(MachineHealthPresentation.OrangeBackgroundHex, presentation.BackgroundHex);
        Assert.AreEqual(MachineHealthPresentation.OrangeBorderHex, presentation.BorderHex);
    }

    [TestMethod]
    public void ConnectedAndConnectingUseMacMachineRowColors()
    {
        var connected = MachineHealthPresentation.Resolve(HostStatuses.Connected);
        var connecting = MachineHealthPresentation.Resolve(HostStatuses.Connecting);

        Assert.AreEqual("connected", connected.Text);
        Assert.AreEqual("checkmark.circle.fill", connected.MacSymbolName);
        Assert.IsTrue(connected.UsesFilledCheckIcon);
        Assert.AreEqual(MachineHealthPresentation.GreenHex, connected.ForegroundHex);
        Assert.AreEqual("connecting", connecting.Text);
        Assert.AreEqual("arrow.triangle.2.circlepath", connecting.MacSymbolName);
        Assert.IsFalse(connecting.UsesFilledCheckIcon);
        Assert.AreEqual(MachineHealthPresentation.BlueHex, connecting.ForegroundHex);
    }

    [TestMethod]
    public void ConnectedMachineRowsUseMacFilledCheckMetrics()
    {
        var connected = MachineHealthPresentation.Resolve(HostStatuses.Connected);

        Assert.AreEqual(18, connected.IconColumnWidth);
        Assert.AreEqual(13, connected.FilledCheckIconSize);
        Assert.AreEqual(1.45, connected.FilledCheckStrokeThickness);
    }

    [TestMethod]
    public void UnknownMachineStatusFallsBackToMacOfflineCircle()
    {
        var presentation = MachineHealthPresentation.Resolve(null);

        Assert.AreEqual("offline", presentation.Text);
        Assert.AreEqual(MachineHealthPresentation.DisconnectedGlyph, presentation.Glyph);
        Assert.AreEqual("circle", presentation.MacSymbolName);
        Assert.AreEqual(MachineHealthPresentation.SecondaryHex, presentation.ForegroundHex);
    }
}
