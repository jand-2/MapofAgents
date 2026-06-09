using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxModePickerPresentationTests
{
    [TestMethod]
    public void UsesMacPrimaryModesWithoutVisibleSecondaryOverflow()
    {
        var presentation = ThreadInboxModePickerPresentation.Resolve(isSecondaryModeSelected: false);

        CollectionAssert.AreEqual(
            new[] { "active", "finished" },
            presentation.PrimaryModeKeys);
        CollectionAssert.AreEqual(
            new[] { "needsYou", "unread", "recent", "archived" },
            presentation.SecondaryModeKeys);
        Assert.IsFalse(presentation.ShowsSecondaryOverflow);
        Assert.AreEqual("ellipsis", presentation.OverflowMacSymbolName);
        Assert.AreEqual("More inbox views", presentation.OverflowToolTip);
        Assert.AreEqual(4, presentation.PrimaryButtonSpacing);
        Assert.AreEqual(24, presentation.PrimaryButtonHeight);
        Assert.AreEqual(6, presentation.PrimaryButtonCornerRadius);
        Assert.AreEqual(1, presentation.PrimaryButtonBorderThickness);
        Assert.AreEqual(0, presentation.PrimaryButtonHorizontalPadding);
        Assert.AreEqual(2, presentation.PrimaryButtonVerticalPadding);
        Assert.AreEqual(11, presentation.PrimaryButtonFontSize);
        Assert.AreEqual("#A7B0BF", presentation.OverflowFillHex);
        Assert.AreEqual(15, presentation.OverflowIconWidth);
        Assert.AreEqual(15, presentation.OverflowIconHeight);
        Assert.AreEqual(2.2, presentation.OverflowDotSize);
        Assert.AreEqual(2.2, presentation.OverflowDotSpacing);
    }

    [TestMethod]
    public void SecondaryOverflowUsesSelectedTintWhenActive()
    {
        var presentation = ThreadInboxModePickerPresentation.Resolve(isSecondaryModeSelected: true);

        Assert.AreEqual("#6AB7FF", presentation.OverflowFillHex);
    }

    [TestMethod]
    public void UsesMacMiniBorderedButtonTintTokens()
    {
        Assert.AreEqual("#180A84FF", ThreadInboxModePickerPresentation.SelectedBackgroundHex);
        Assert.AreEqual("#00FFFFFF", ThreadInboxModePickerPresentation.InactiveBackgroundHex);
        Assert.AreEqual("#440A84FF", ThreadInboxModePickerPresentation.SelectedBorderHex);
        Assert.AreEqual("#24FFFFFF", ThreadInboxModePickerPresentation.InactiveBorderHex);
    }
}
