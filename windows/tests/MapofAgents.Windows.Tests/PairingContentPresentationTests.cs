using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class PairingContentPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacPairingPopoverRhythm()
    {
        var presentation = PairingContentPresentation.Resolve();

        Assert.AreEqual(14, presentation.SurfacePadding);
        Assert.AreEqual(14, presentation.SurfaceSpacing);
        Assert.AreEqual(10, presentation.HeaderSpacing);
        Assert.AreEqual(26, presentation.HeaderIconTileSize);
        Assert.AreEqual(6, presentation.HeaderIconCornerRadius);
        Assert.AreEqual(1, presentation.HeaderTextSpacing);
        Assert.AreEqual(24, presentation.HeaderActionButtonSize);
        Assert.AreEqual(10, presentation.BodySpacing);
    }

    [TestMethod]
    public void ResolveMatchesMacPairingStatusAndLoadingMetrics()
    {
        var presentation = PairingContentPresentation.Resolve();

        Assert.AreEqual(7, presentation.StatusSpacing);
        Assert.AreEqual(13, presentation.StatusIconFontSize);
        Assert.AreEqual(12, presentation.StatusTextFontSize);
        Assert.AreEqual(10, presentation.DetailPadding);
        Assert.AreEqual(8, presentation.DetailCornerRadius);
        Assert.AreEqual(11, presentation.NetworkAccessFontSize);
        Assert.AreEqual(430, presentation.LoadingWidth);
        Assert.AreEqual(188, presentation.LoadingHeight);
    }

    [TestMethod]
    public void ResolveMatchesMacPairingQrAndImportMetrics()
    {
        var presentation = PairingContentPresentation.Resolve();

        Assert.AreEqual(188, presentation.QrSize);
        Assert.AreEqual(8, presentation.QrCornerRadius);
        Assert.AreEqual(10, presentation.QrImagePadding);
        Assert.AreEqual(14, presentation.QrDetailSpacing);
        Assert.AreEqual(230, presentation.GeneratedDetailsWidth);
        Assert.AreEqual(7, presentation.ActionButtonContentSpacing);
        Assert.AreEqual(76, presentation.ImportTextBoxMinHeight);
        Assert.AreEqual(10, presentation.PreviewPanelPadding);
        Assert.AreEqual(8, presentation.PreviewPanelCornerRadius);
    }
}
