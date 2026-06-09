using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadAttachmentChipPresentationTests
{
    [TestMethod]
    public void ImageAttachmentChipMatchesMacNeutralPillWithBlueIcon()
    {
        var presentation = ThreadAttachmentChipPresentation.Resolve("image");

        Assert.AreEqual("\uEB9F", presentation.KindGlyph);
        Assert.AreEqual("#0A84FF", presentation.KindForegroundHex);
        Assert.AreEqual("#1AFFFFFF", presentation.ChipBackgroundHex);
        Assert.AreEqual("#24FFFFFF", presentation.ChipBorderHex);
        Assert.AreEqual(9, presentation.HorizontalPadding, 0.001);
        Assert.AreEqual(7, presentation.VerticalPadding, 0.001);
        Assert.AreEqual(12, presentation.NameFontSize, 0.001);
        Assert.AreEqual(10, presentation.DetailFontSize, 0.001);
    }

    [TestMethod]
    public void FileAndDiffAttachmentChipsUseSecondaryIconColor()
    {
        var file = ThreadAttachmentChipPresentation.Resolve("file");
        var diff = ThreadAttachmentChipPresentation.Resolve("diff");

        Assert.AreEqual("\uE7C3", file.KindGlyph);
        Assert.AreEqual("\uE8AB", diff.KindGlyph);
        Assert.AreEqual("#A7B0BF", file.KindForegroundHex);
        Assert.AreEqual("#A7B0BF", diff.KindForegroundHex);
        Assert.AreEqual("#8F9BAA", file.RemoveForegroundHex);
    }

    [TestMethod]
    public void UnknownAttachmentKindFallsBackToFileTreatment()
    {
        var presentation = ThreadAttachmentChipPresentation.Resolve(" other ");

        Assert.AreEqual("\uE7C3", presentation.KindGlyph);
        Assert.AreEqual("#A7B0BF", presentation.KindForegroundHex);
    }
}
