using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TopNotificationCardPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacTopNotificationStackAndDismissAllCapsule()
    {
        var presentation = TopNotificationCardPresentation.Resolve();

        Assert.AreEqual(8, presentation.StackSpacing);
        Assert.AreEqual(10, presentation.DismissAllHorizontalPadding);
        Assert.AreEqual(5, presentation.DismissAllVerticalPadding);
        Assert.AreEqual(14, presentation.DismissAllCornerRadius);
        Assert.AreEqual(12, presentation.DismissAllFontSize);
    }

    [TestMethod]
    public void ResolveMatchesMacTopNotificationCardFrame()
    {
        var presentation = TopNotificationCardPresentation.Resolve();

        Assert.AreEqual(360, presentation.Width);
        Assert.AreEqual(12, presentation.HorizontalPadding);
        Assert.AreEqual(10, presentation.VerticalPadding);
        Assert.AreEqual(8, presentation.CornerRadius);
        Assert.AreEqual(1, presentation.BorderThickness);
        Assert.AreEqual(10, presentation.ColumnSpacing);
        Assert.AreEqual(18, presentation.ShadowTranslationZ);
        Assert.AreEqual(8, presentation.BottomGap);
    }

    [TestMethod]
    public void ResolveMatchesMacTopNotificationContentRhythm()
    {
        var presentation = TopNotificationCardPresentation.Resolve();

        Assert.AreEqual(18, presentation.IconFrameSize);
        Assert.AreEqual(1, presentation.IconTopMargin);
        Assert.AreEqual(14, presentation.FontGlyphSize);
        Assert.AreEqual(17, presentation.FilledIconSize);
        Assert.AreEqual(5, presentation.ContentSpacing);
        Assert.AreEqual(12, presentation.TitleFontSize);
        Assert.AreEqual(12, presentation.MessageFontSize);
        Assert.AreEqual(3, presentation.MessageMaxLines);
        Assert.AreEqual(10, presentation.TimelineFontSize);
        Assert.AreEqual(2, presentation.TimelineMaxLines);
        Assert.AreEqual(18, presentation.DismissButtonSize);
        Assert.AreEqual(11, presentation.DismissIconFontSize);
    }
}
