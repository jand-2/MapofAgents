using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadPopoverShellPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacRoundedOutlinedShadowedShell()
    {
        var presentation = ThreadPopoverShellPresentation.Resolve();

        Assert.AreEqual("#24FFFFFF", presentation.BorderHex);
        Assert.AreEqual(1, presentation.BorderThickness, 0.001);
        Assert.AreEqual(8, presentation.CornerRadius, 0.001);
        Assert.AreEqual(18, presentation.ShadowTranslationZ, 0.001);
        Assert.AreEqual(10, presentation.HeaderColumnSpacing, 0.001);
        Assert.AreEqual(10, presentation.HeaderActionSpacing, 0.001);
        Assert.AreEqual(2, presentation.HeaderControlsLeftInset, 0.001);
        Assert.AreEqual(12, presentation.HeaderColumnSpacing + presentation.HeaderControlsLeftInset, 0.001);
    }

    [TestMethod]
    public void ReaderTilesUseSameMacPopoverShell()
    {
        var popover = ThreadPopoverShellPresentation.Resolve();
        var readerTile = ThreadPopoverShellPresentation.ResolveReaderTile();

        Assert.AreEqual(popover.BorderHex, readerTile.BorderHex);
        Assert.AreEqual(popover.BorderThickness, readerTile.BorderThickness, 0.001);
        Assert.AreEqual(popover.CornerRadius, readerTile.CornerRadius, 0.001);
        Assert.AreEqual(popover.ShadowTranslationZ, readerTile.ShadowTranslationZ, 0.001);
        Assert.AreEqual(popover.HeaderColumnSpacing, readerTile.HeaderColumnSpacing, 0.001);
        Assert.AreEqual(popover.HeaderActionSpacing, readerTile.HeaderActionSpacing, 0.001);
        Assert.AreEqual(popover.HeaderControlsLeftInset, readerTile.HeaderControlsLeftInset, 0.001);
    }
}
