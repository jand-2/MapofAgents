using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class SelectionInspectorChromePresentationTests
{
    [TestMethod]
    public void ResolveUsesMacRoundedBorderTextFieldChrome()
    {
        var presentation = SelectionInspectorChromePresentation.Resolve();

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
        Assert.AreEqual("#660A84FF", presentation.FieldFocusedBorderHex);
    }

    [TestMethod]
    public void ResolveKeepsMacCompactInspectorActionRow()
    {
        var presentation = SelectionInspectorChromePresentation.Resolve();

        Assert.AreEqual(8, presentation.ActionRowSpacing);
        Assert.AreEqual(28, presentation.ActionButtonMinHeight);
        Assert.AreEqual(6, presentation.ActionButtonCornerRadius);
        Assert.AreEqual(9, presentation.ActionButtonHorizontalPadding);
        Assert.AreEqual(4, presentation.ActionButtonVerticalPadding);
        Assert.AreEqual(7, presentation.ActionContentSpacing);
        Assert.AreEqual(14, presentation.ActionIconFontSize);
        Assert.AreEqual(13, presentation.ActionFontSize);
    }

    [TestMethod]
    public void ResolveUsesProminentSaveAndDestructiveDeleteColors()
    {
        var presentation = SelectionInspectorChromePresentation.Resolve();

        Assert.AreEqual("#E60A84FF", presentation.SaveBackgroundHex);
        Assert.AreEqual("#FF0A84FF", presentation.SaveBorderHex);
        Assert.AreEqual("#FFFFFFFF", presentation.SaveForegroundHex);
        Assert.AreEqual("#18B42318", presentation.DeleteBackgroundHex);
        Assert.AreEqual("#40B42318", presentation.DeleteBorderHex);
        Assert.AreEqual("#FCA5A5", presentation.DeleteForegroundHex);
    }
}
