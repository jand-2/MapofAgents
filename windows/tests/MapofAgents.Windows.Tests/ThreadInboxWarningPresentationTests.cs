using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxWarningPresentationTests
{
    [TestMethod]
    public void BlankErrorHidesWarning()
    {
        var presentation = ThreadInboxWarningPresentation.Resolve("   ");

        Assert.AreEqual(string.Empty, presentation.Text);
        Assert.IsFalse(presentation.IsVisible);
        Assert.AreEqual("exclamationmark.triangle.fill", presentation.MacSymbolName);
        Assert.AreEqual(ThreadInboxWarningPresentation.Glyph, presentation.Glyph);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual(11, presentation.FontSize);
        Assert.AreEqual(11, presentation.IconFontSize);
        Assert.AreEqual(14, presentation.IconWidth);
        Assert.AreEqual(2, presentation.MaxLines);
    }

    [TestMethod]
    public void ErrorUsesMacStaleHostsCopy()
    {
        var presentation = ThreadInboxWarningPresentation.Resolve("Local search timed out.");

        Assert.AreEqual(
            "Some inbox hosts may be stale: Local search timed out.",
            presentation.Text);
        Assert.IsTrue(presentation.IsVisible);
        Assert.AreEqual("exclamationmark.triangle.fill", presentation.MacSymbolName);
        Assert.AreEqual(ThreadInboxWarningPresentation.Glyph, presentation.Glyph);
        Assert.AreEqual(ThreadInboxPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual(2, presentation.MaxLines);
    }
}
