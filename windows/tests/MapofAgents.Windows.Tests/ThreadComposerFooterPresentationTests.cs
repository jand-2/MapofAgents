using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadComposerFooterPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacComposerStackGeometry()
    {
        var presentation = ThreadComposerFooterPresentation.Resolve();

        Assert.AreEqual(14, presentation.OuterPadding);
        Assert.AreEqual(10, presentation.SectionSpacing);
        Assert.AreEqual(8, presentation.MetadataItemSpacing);
        Assert.AreEqual(10, presentation.InputActionSpacing);
        Assert.AreEqual(6, presentation.MentionComposerSpacing);
        Assert.AreEqual(8, presentation.ReplyInputStackSpacing);
        Assert.AreEqual(8, presentation.ReplyActionStackSpacing);
    }

    [TestMethod]
    public void ResolveKeepsMacSecondaryMetadataTreatment()
    {
        var presentation = ThreadComposerFooterPresentation.Resolve();

        Assert.AreEqual(5, presentation.MetadataChipSpacing);
        Assert.AreEqual(12, presentation.MetadataFontSize);
        Assert.AreEqual("#A7B0BF", presentation.MetadataForegroundHex);
    }
}
