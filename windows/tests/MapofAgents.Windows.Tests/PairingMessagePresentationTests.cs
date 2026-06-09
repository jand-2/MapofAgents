using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class PairingMessagePresentationTests
{
    [TestMethod]
    public void FailureDetailsUseMacRedErrorTreatment()
    {
        var presentation = PairingMessagePresentation.Resolve(
            PairingMessagePresentation.FailureAccentHex,
            PairingMessagePresentation.FailureBackgroundHex,
            PairingMessagePresentation.FailureBorderHex);

        Assert.AreEqual("#B42318", presentation.AccentHex);
        Assert.AreEqual("#1AB42318", presentation.BackgroundHex);
        Assert.AreEqual("#26B42318", presentation.BorderHex);
        Assert.AreEqual("#FFB4AB", presentation.DetailForegroundHex);
    }

    [TestMethod]
    public void ReadyDetailsStayNeutral()
    {
        var presentation = PairingMessagePresentation.Resolve(
            "#30D158",
            "#1A30D158",
            "#2630D158");

        Assert.AreEqual("#D7DCE5", presentation.DetailForegroundHex);
    }

    [TestMethod]
    public void StartingStateUsesMacBlueProgressTreatment()
    {
        var presentation = PairingMessagePresentation.Resolve(
            PairingMessagePresentation.StartingAccentHex,
            PairingMessagePresentation.StartingBackgroundHex,
            PairingMessagePresentation.StartingBorderHex);

        Assert.AreEqual("Starting pairing host", PairingMessagePresentation.StartingTitle);
        Assert.AreEqual("#0A84FF", presentation.AccentHex);
        Assert.AreEqual("#1A0A84FF", presentation.BackgroundHex);
        Assert.AreEqual("#260A84FF", presentation.BorderHex);
        Assert.AreEqual("#D7DCE5", presentation.DetailForegroundHex);
    }

    [TestMethod]
    public void HeaderSubtitleOnlyAppearsForRealPairingHosts()
    {
        Assert.IsNull(PairingMessagePresentation.HeaderSubtitle(null));
        Assert.IsNull(PairingMessagePresentation.HeaderSubtitle(""));
        Assert.IsNull(PairingMessagePresentation.HeaderSubtitle("   "));
        Assert.AreEqual("Windows PC", PairingMessagePresentation.HeaderSubtitle(" Windows PC "));
    }
}
