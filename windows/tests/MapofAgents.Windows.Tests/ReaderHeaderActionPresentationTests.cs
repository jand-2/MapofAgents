using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ReaderHeaderActionPresentationTests
{
    [TestMethod]
    public void ResolveClearUsesMacXmarkCircleTreatment()
    {
        var presentation = ReaderHeaderActionPresentation.ResolveClear();

        Assert.AreEqual("xmark.circle", presentation.ClearMacSymbolName);
        Assert.AreEqual("\uE711", presentation.ClearGlyph);
        Assert.AreEqual("Clear", presentation.ClearLabel);
        Assert.AreEqual("#A7B0BF", presentation.ClearForegroundHex);
        Assert.AreEqual("#A7B0BF", presentation.ClearCircleStrokeHex);
        Assert.AreEqual(13, presentation.ClearIconDiameter);
        Assert.AreEqual(7, presentation.ClearGlyphFontSize);
    }
}
