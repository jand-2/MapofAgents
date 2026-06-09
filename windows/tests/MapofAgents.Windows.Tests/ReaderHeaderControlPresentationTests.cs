using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ReaderHeaderControlPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacCompactPickerTreatment()
    {
        var presentation = ReaderHeaderControlPresentation.Resolve();

        Assert.AreEqual(30, presentation.PickerHeight);
        Assert.AreEqual(6, presentation.PickerCornerRadius);
        Assert.AreEqual(1, presentation.PickerBorderThickness);
        Assert.AreEqual(8, presentation.PickerHorizontalPadding);
        Assert.AreEqual(3, presentation.PickerVerticalPadding);
        Assert.AreEqual(13, presentation.PickerFontSize);
        Assert.AreEqual("#142A2C30", presentation.PickerBackgroundHex);
        Assert.AreEqual("#24FFFFFF", presentation.PickerBorderHex);
        Assert.AreEqual("#F2F4F7", presentation.PickerForegroundHex);
        Assert.AreEqual("#660A84FF", presentation.PickerFocusedBorderHex);
    }

    [TestMethod]
    public void ResolveUsesPlainMacHeaderIconButtons()
    {
        var presentation = ReaderHeaderControlPresentation.Resolve();

        Assert.AreEqual(24, presentation.IconButtonSize);
        Assert.AreEqual(12, presentation.IconButtonCornerRadius);
        Assert.AreEqual(0, presentation.IconButtonBorderThickness);
        Assert.AreEqual("#00FFFFFF", presentation.IconButtonBackgroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.IconButtonBorderHex);
        Assert.AreEqual("#A7B0BF", presentation.IconButtonForegroundHex);
        Assert.AreEqual(12, presentation.AddRemoveIconFontSize);
        Assert.AreEqual(12, presentation.CloseIconFontSize);
    }
}
