using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadHeaderIdentityActionPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacPlainIdentityActions()
    {
        var presentation = ThreadHeaderIdentityActionPresentation.Resolve();

        Assert.AreEqual("pencil", presentation.RenameMacSymbolName);
        Assert.AreEqual("checkmark", presentation.SaveMacSymbolName);
        Assert.AreEqual("doc.on.doc", presentation.CopyMacSymbolName);
        Assert.AreEqual("\uE70F", presentation.RenameWindowsGlyph);
        Assert.AreEqual("\uE73E", presentation.SaveWindowsGlyph);
        Assert.AreEqual("\uE8C8", presentation.CopyWindowsGlyph);
        Assert.AreEqual("#A7B0BF", presentation.RenameForegroundHex);
        Assert.AreEqual("#8F9BAA", presentation.CopyForegroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.BackgroundHex);
        Assert.AreEqual(18, presentation.RenameHitTargetSize, 0.001);
        Assert.AreEqual(12, presentation.RenameIconFontSize, 0.001);
        Assert.AreEqual(18, presentation.CopyHitTargetSize, 0.001);
        Assert.AreEqual(10, presentation.CopyIconFontSize, 0.001);
        Assert.AreEqual(0, presentation.BorderThickness, 0.001);
        Assert.AreEqual("Rename", presentation.RenameToolTip);
        Assert.AreEqual("Rename thread", presentation.RenameAccessibilityName);
        Assert.AreEqual("Save thread name", presentation.SaveToolTip);
        Assert.AreEqual("Save thread name", presentation.SaveAccessibilityName);
        Assert.AreEqual("Copy thread id", presentation.CopyToolTip);
        Assert.AreEqual("Copy thread ID", presentation.CopyAccessibilityName);
    }
}
