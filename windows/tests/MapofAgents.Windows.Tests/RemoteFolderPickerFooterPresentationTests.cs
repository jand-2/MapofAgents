using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class RemoteFolderPickerFooterPresentationTests
{
    [TestMethod]
    public void ResolveUsesLoadedListingPathForCurrentSelection()
    {
        var presentation = RemoteFolderPickerFooterPresentation.Resolve(
            "  ~/project  ",
            "~/draft");

        Assert.AreEqual("~/project", presentation.SelectedCurrentPath);
        Assert.AreEqual(RemoteFolderPickerFooterPresentation.AddLabel, presentation.AddLabel);
        Assert.AreEqual(RemoteFolderPickerFooterPresentation.AddGlyph, presentation.AddGlyph);
        Assert.AreEqual(RemoteFolderPickerFooterPresentation.AddAutomationName, presentation.AutomationName);
        Assert.IsNull(presentation.UnavailableReason);
        Assert.IsTrue(presentation.CanAddCurrentFolder);
    }

    [TestMethod]
    public void ResolveFallsBackToDraftPathBeforeListingLoads()
    {
        var presentation = RemoteFolderPickerFooterPresentation.Resolve(null, " ~/code ");

        Assert.AreEqual("~/code", presentation.SelectedCurrentPath);
        Assert.IsTrue(presentation.CanAddCurrentFolder);
    }

    [TestMethod]
    public void ResolveExplainsEmptySelection()
    {
        var presentation = RemoteFolderPickerFooterPresentation.Resolve(null, "   ");

        Assert.AreEqual(string.Empty, presentation.SelectedCurrentPath);
        Assert.AreEqual(
            RemoteFolderPickerFooterPresentation.EmptySelectionReason,
            presentation.UnavailableReason);
        Assert.IsFalse(presentation.CanAddCurrentFolder);
    }
}
