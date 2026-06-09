using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarButtonChromePresentationTests
{
    [TestMethod]
    public void PlainButtonsMatchMacPlainCommandChrome()
    {
        var presentation = ToolbarButtonChromePresentation.Resolve();

        Assert.AreEqual("ToolbarPlainButtonStyle", presentation.Plain.StyleKey);
        Assert.AreEqual(28, presentation.Plain.MinHeight);
        Assert.AreEqual(7, presentation.Plain.HorizontalPadding);
        Assert.AreEqual(3, presentation.Plain.VerticalPadding);
        Assert.AreEqual("#00FFFFFF", presentation.Plain.BackgroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.Plain.BorderHex);
        Assert.AreEqual(0, presentation.Plain.BorderThickness);
        Assert.AreEqual(6, presentation.Plain.CornerRadius);
        Assert.AreEqual("#D7DCE5", presentation.Plain.ForegroundHex);
        Assert.AreEqual(13, presentation.Plain.FontSize);
    }

    [TestMethod]
    public void BorderedButtonsMatchMacBorderedCommandChrome()
    {
        var presentation = ToolbarButtonChromePresentation.Resolve();

        Assert.AreEqual("ToolbarButtonStyle", presentation.Bordered.StyleKey);
        Assert.AreEqual(28, presentation.Bordered.MinHeight);
        Assert.AreEqual(9, presentation.Bordered.HorizontalPadding);
        Assert.AreEqual(3, presentation.Bordered.VerticalPadding);
        Assert.AreEqual("#10FFFFFF", presentation.Bordered.BackgroundHex);
        Assert.AreEqual("#24FFFFFF", presentation.Bordered.BorderHex);
        Assert.AreEqual(1, presentation.Bordered.BorderThickness);
        Assert.AreEqual(6, presentation.Bordered.CornerRadius);
        Assert.AreEqual("#F2F4F7", presentation.Bordered.ForegroundHex);
        Assert.AreEqual(13, presentation.Bordered.FontSize);
    }

    [TestMethod]
    public void ProminentCommandRolesKeepMacAccentTreatments()
    {
        var presentation = ToolbarButtonChromePresentation.Resolve();

        Assert.AreEqual("ToolbarPrimaryButtonStyle", presentation.Primary.StyleKey);
        Assert.AreEqual("#E60A84FF", presentation.Primary.BackgroundHex);
        Assert.AreEqual("#FF0A84FF", presentation.Primary.BorderHex);
        Assert.AreEqual("#FFFFFFFF", presentation.Primary.ForegroundHex);
        Assert.AreEqual("ToolbarPurpleButtonStyle", presentation.Purple.StyleKey);
        Assert.AreEqual("#24BF5AF2", presentation.Purple.BackgroundHex);
        Assert.AreEqual("#70BF5AF2", presentation.Purple.BorderHex);
        Assert.AreEqual("#FFDDB8FF", presentation.Purple.ForegroundHex);
    }

    [TestMethod]
    public void SplitButtonStyleKeysShareTheSameChromeRoles()
    {
        var plainSplit = ToolbarButtonChromePresentation.Plain(ToolbarButtonChromePresentation.PlainSplitStyleKey);
        var borderedSplit = ToolbarButtonChromePresentation.Bordered(ToolbarButtonChromePresentation.BorderedSplitStyleKey);

        Assert.AreEqual("ToolbarPlainSplitButtonStyle", plainSplit.StyleKey);
        Assert.AreEqual(ToolbarButtonChromePresentation.PlainHorizontalPadding, plainSplit.HorizontalPadding);
        Assert.AreEqual(ToolbarButtonChromePresentation.PlainBorderThickness, plainSplit.BorderThickness);
        Assert.AreEqual("ToolbarSplitButtonStyle", borderedSplit.StyleKey);
        Assert.AreEqual(ToolbarButtonChromePresentation.BorderedHorizontalPadding, borderedSplit.HorizontalPadding);
        Assert.AreEqual(ToolbarButtonChromePresentation.BorderedBorderThickness, borderedSplit.BorderThickness);
    }
}
