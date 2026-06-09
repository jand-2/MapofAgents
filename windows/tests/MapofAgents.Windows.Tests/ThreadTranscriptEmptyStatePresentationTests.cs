using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadTranscriptEmptyStatePresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacNoLoadedTurnsEmptyState()
    {
        var presentation = ThreadTranscriptEmptyStatePresentation.Resolve();

        Assert.AreEqual("No loaded turns", presentation.Title);
        Assert.AreEqual(
            "Send the first message or refresh after the thread starts responding.",
            presentation.Detail);
        Assert.AreEqual("text.bubble", presentation.MacSymbolName);
        Assert.AreEqual("\uE8F2", presentation.WindowsGlyph);
        Assert.AreEqual("#12697586", presentation.BackgroundHex);
        Assert.AreEqual("#24697586", presentation.BorderHex);
        Assert.AreEqual("#D7DCE5", presentation.TitleForegroundHex);
        Assert.AreEqual("#A7B0BF", presentation.DetailForegroundHex);
        Assert.AreEqual(310, presentation.Width, 0.001);
        Assert.AreEqual(220, presentation.MinHeight, 0.001);
        Assert.AreEqual(24, presentation.IconFontSize, 0.001);
        Assert.AreEqual(13, presentation.TitleFontSize, 0.001);
        Assert.AreEqual(13, presentation.DetailFontSize, 0.001);
    }
}
