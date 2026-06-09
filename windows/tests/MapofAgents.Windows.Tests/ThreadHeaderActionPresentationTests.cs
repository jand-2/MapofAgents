using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadHeaderActionPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacPlainHeaderActions()
    {
        var presentation = ThreadHeaderActionPresentation.Resolve();

        Assert.AreEqual("#A7B0BF", presentation.ForegroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.BackgroundHex);
        Assert.AreEqual(24, presentation.HitTargetSize, 0.001);
        Assert.AreEqual(12, presentation.IconFontSize, 0.001);
        Assert.AreEqual(0, presentation.BorderThickness, 0.001);
        Assert.AreEqual("\uE72C", presentation.RefreshWindowsGlyph);
        Assert.AreEqual("\uE711", presentation.CloseWindowsGlyph);
        Assert.AreEqual("Refresh", presentation.RefreshToolTip);
        Assert.AreEqual("Refresh transcript", presentation.RefreshAccessibilityName);
        Assert.AreEqual("Close", presentation.CloseToolTip);
        Assert.AreEqual("Close chat", presentation.CloseAccessibilityName);
    }
}
