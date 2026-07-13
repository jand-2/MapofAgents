using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarPairingPresentationTests
{
    [TestMethod]
    public void ResolveDisablesUnavailableWindowsEnrollment()
    {
        var presentation = ToolbarPairingPresentation.Resolve();

        Assert.AreEqual("qrcode", presentation.MacSymbolName);
        Assert.AreEqual("#D7DCE5", presentation.IconHex);
        Assert.AreEqual(WindowsDeviceEnrollmentAvailability.Detail, presentation.ToolTip);
        Assert.AreEqual(WindowsDeviceEnrollmentAvailability.Title, presentation.AccessibilityName);
        Assert.IsFalse(presentation.IsEnabled);
        Assert.IsFalse(WindowsDeviceEnrollmentAvailability.IsAvailable);
        Assert.IsFalse(WindowsDeviceEnrollmentAvailability.CanStartHostListener);
        Assert.IsFalse(WindowsDeviceEnrollmentAvailability.CanGeneratePairingCode);
        Assert.AreEqual(
            "Secure device enrollment is not yet available on Windows.",
            WindowsDeviceEnrollmentAvailability.Detail);
        Assert.AreEqual(15, presentation.IconSize);
        Assert.AreEqual(4.8, presentation.FinderSize);
        Assert.AreEqual(1.8, presentation.InnerFinderSize);
        Assert.AreEqual(1.35, presentation.ModuleSize);
    }
}
