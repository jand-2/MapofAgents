using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadComposerAttachmentToolbarPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacPlainAttachmentToolbar()
    {
        var presentation = ThreadComposerAttachmentToolbarPresentation.Resolve();

        Assert.AreEqual("paperclip", presentation.AttachMacSymbolName);
        Assert.AreEqual("doc.on.clipboard", presentation.PasteMacSymbolName);
        Assert.AreEqual("\uE723", presentation.AttachWindowsGlyph);
        Assert.AreEqual("\uE77F", presentation.PasteWindowsGlyph);
        Assert.AreEqual("#A7B0BF", presentation.ForegroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.BackgroundHex);
        Assert.AreEqual(8, presentation.ToolbarSpacing, 0.001);
        Assert.AreEqual(18, presentation.ButtonSize, 0.001);
        Assert.AreEqual(12, presentation.IconFontSize, 0.001);
        Assert.AreEqual(0, presentation.BorderThickness, 0.001);
        Assert.AreEqual(ThreadAttachmentFeedbackPresentation.CountFontSize, presentation.CountFontSize, 0.001);
        Assert.AreEqual(ThreadAttachmentFeedbackPresentation.CountForegroundHex, presentation.CountForegroundHex);
        Assert.AreEqual("Attach files", presentation.AttachToolTip);
        Assert.AreEqual("Attach files", presentation.AttachAccessibilityName);
        Assert.AreEqual("Paste screenshot or files", presentation.PasteToolTip);
        Assert.AreEqual("Paste screenshot or files", presentation.PasteAccessibilityName);
    }
}
