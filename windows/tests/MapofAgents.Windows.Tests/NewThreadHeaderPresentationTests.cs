using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NewThreadHeaderPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacPlusBubbleTreatment()
    {
        var presentation = NewThreadHeaderPresentation.Resolve();

        Assert.AreEqual("plus.bubble", presentation.MacSymbolName);
        Assert.AreEqual("\uE8F2", presentation.ThreadGlyph);
        Assert.AreEqual("+", presentation.BadgeText);
        Assert.AreEqual("#1A0A84FF", presentation.BackgroundHex);
        Assert.AreEqual("#0A84FF", presentation.ForegroundHex);
        Assert.AreEqual("#FFFFFFFF", presentation.BadgeBackgroundHex);
        Assert.AreEqual("#0A84FF", presentation.BadgeForegroundHex);
    }
}
