using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadComposerMetadataPresentationTests
{
    [TestMethod]
    public void ResolveShowsBothMacComposerMetadataChipsWhenPresent()
    {
        var presentation = ThreadComposerMetadataPresentation.Resolve(" gpt-5 ", " high ");

        Assert.AreEqual("cpu", ThreadComposerMetadataPresentation.ModelMacSymbolName);
        Assert.AreEqual("dial.medium", ThreadComposerMetadataPresentation.EffortMacSymbolName);
        Assert.AreEqual("\uE950", ThreadComposerMetadataPresentation.ModelWindowsGlyph);
        Assert.AreEqual("\uE9D9", ThreadComposerMetadataPresentation.EffortWindowsGlyph);
        Assert.AreEqual("cpu", presentation.ModelIconKind);
        Assert.AreEqual("dialMedium", presentation.EffortIconKind);
        Assert.AreEqual("#8F9BAA", presentation.IconForegroundHex);
        Assert.AreEqual(12, presentation.IconWidth);
        Assert.AreEqual(12, presentation.IconHeight);
        Assert.AreEqual(1.15, presentation.IconStrokeThickness);
        Assert.AreEqual("gpt-5", presentation.ModelText);
        Assert.AreEqual("high", presentation.EffortText);
        Assert.IsTrue(presentation.ShowsModel);
        Assert.IsTrue(presentation.ShowsEffort);
        Assert.IsTrue(presentation.ShowsMetadataRow);
    }

    [TestMethod]
    public void ResolveCollapsesMissingMetadataInsteadOfShowingPlaceholders()
    {
        var presentation = ThreadComposerMetadataPresentation.Resolve(null, " ");

        Assert.AreEqual("", presentation.ModelText);
        Assert.AreEqual("", presentation.EffortText);
        Assert.IsFalse(presentation.ShowsModel);
        Assert.IsFalse(presentation.ShowsEffort);
        Assert.IsFalse(presentation.ShowsMetadataRow);
    }

    [TestMethod]
    public void ResolveKeepsSinglePresentChipVisible()
    {
        var modelOnly = ThreadComposerMetadataPresentation.Resolve("gpt-5-codex", null);
        var effortOnly = ThreadComposerMetadataPresentation.Resolve(null, "medium");

        Assert.IsTrue(modelOnly.ShowsMetadataRow);
        Assert.IsTrue(modelOnly.ShowsModel);
        Assert.IsFalse(modelOnly.ShowsEffort);
        Assert.IsTrue(effortOnly.ShowsMetadataRow);
        Assert.IsFalse(effortOnly.ShowsModel);
        Assert.IsTrue(effortOnly.ShowsEffort);
    }
}
