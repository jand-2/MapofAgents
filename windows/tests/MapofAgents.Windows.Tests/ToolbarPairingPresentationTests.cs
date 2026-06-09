using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarPairingPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacQRCodeTreatmentWithWindowsHostCopy()
    {
        var presentation = ToolbarPairingPresentation.Resolve();

        Assert.AreEqual("qrcode", presentation.MacSymbolName);
        Assert.AreEqual("#D7DCE5", presentation.IconHex);
        Assert.AreEqual("Pair an iPhone with this Windows PC", presentation.ToolTip);
        Assert.AreEqual("Pair", presentation.AccessibilityName);
        Assert.AreEqual(15, presentation.IconSize);
        Assert.AreEqual(4.8, presentation.FinderSize);
        Assert.AreEqual(1.8, presentation.InnerFinderSize);
        Assert.AreEqual(1.35, presentation.ModuleSize);
    }
}
