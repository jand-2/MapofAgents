using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NewThreadControlChromePresentationTests
{
    [TestMethod]
    public void ResolveUsesMacRoundedControlChromeForNewThreadFields()
    {
        var presentation = NewThreadControlChromePresentation.Resolve();

        Assert.AreEqual(30, presentation.FieldHeight);
        Assert.AreEqual(6, presentation.FieldCornerRadius);
        Assert.AreEqual(1, presentation.FieldBorderThickness);
        Assert.AreEqual(8, presentation.FieldHorizontalPadding);
        Assert.AreEqual(3, presentation.FieldVerticalPadding);
        Assert.AreEqual(13, presentation.FieldFontSize);
        Assert.AreEqual("#142A2C30", presentation.FieldBackgroundHex);
        Assert.AreEqual("#24FFFFFF", presentation.FieldBorderHex);
        Assert.AreEqual("#F2F4F7", presentation.FieldForegroundHex);
        Assert.AreEqual("#8F9BAA", presentation.PlaceholderForegroundHex);
        Assert.AreEqual("#1F2A2C30", presentation.FieldPointerOverBackgroundHex);
        Assert.AreEqual("#292A2C30", presentation.FieldPressedBackgroundHex);
        Assert.AreEqual("#660A84FF", presentation.FieldFocusedBorderHex);
        Assert.AreEqual(9, presentation.PromptHorizontalPadding);
        Assert.AreEqual(6, presentation.PromptVerticalPadding);
    }

    [TestMethod]
    public void ResolveUsesMacPickerGlyphContrast()
    {
        var presentation = NewThreadControlChromePresentation.Resolve();

        Assert.AreEqual("#A7B0BF", presentation.PickerChevronForegroundHex);
    }

    [TestMethod]
    public void ResolveUsesMacProminentCreateActionChrome()
    {
        var presentation = NewThreadControlChromePresentation.Resolve();

        Assert.AreEqual(38, presentation.CreateButtonWidth);
        Assert.AreEqual(34, presentation.CreateButtonHeight);
        Assert.AreEqual(7, presentation.CreateButtonCornerRadius);
        Assert.AreEqual(1, presentation.CreateButtonBorderThickness);
        Assert.AreEqual("#E60A84FF", presentation.CreateButtonBackgroundHex);
        Assert.AreEqual("#FF0A84FF", presentation.CreateButtonBorderHex);
        Assert.AreEqual("#FFFFFFFF", presentation.CreateButtonForegroundHex);
    }
}
