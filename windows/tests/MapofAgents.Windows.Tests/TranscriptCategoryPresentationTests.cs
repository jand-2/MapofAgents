using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptCategoryPresentationTests
{
    [TestMethod]
    public void MessagesUseMacLabelsSymbolAndGreenTint()
    {
        var presentation = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyMessages);

        Assert.AreEqual("Messages", presentation.Title);
        Assert.AreEqual("Msg", presentation.CompactTitle);
        Assert.AreEqual("bubble.left.and.bubble.right", presentation.MacSymbolName);
        Assert.AreEqual("\uE8F2", presentation.WindowsGlyph);
        Assert.AreEqual(TranscriptCategoryPresentation.GreenHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void ProgressUsesMacTealCategoryTreatment()
    {
        var presentation = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyProgress);

        Assert.AreEqual("Progress", presentation.Title);
        Assert.AreEqual("arrow.triangle.2.circlepath", presentation.MacSymbolName);
        Assert.AreEqual("\uE895", presentation.WindowsGlyph);
        Assert.AreEqual(TranscriptCategoryPresentation.TealHex, presentation.ForegroundHex);
        Assert.AreEqual("#1740C8E0", presentation.BackgroundHex);
        Assert.AreEqual("#1C40C8E0", presentation.BadgeBackgroundHex);
        Assert.AreEqual(TranscriptCategoryPresentation.ActiveBorderHex, presentation.BorderHex);
    }

    [TestMethod]
    public void ToolArtifactAndApprovalUseMacOrangeBlueAndRed()
    {
        var tool = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyTools);
        var artifact = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyArtifacts);
        var approval = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyApprovals);

        Assert.AreEqual(TranscriptCategoryPresentation.OrangeHex, tool.ForegroundHex);
        Assert.AreEqual("wrench.and.screwdriver", tool.MacSymbolName);
        Assert.AreEqual(TranscriptCategoryPresentation.BlueHex, artifact.ForegroundHex);
        Assert.AreEqual("shippingbox", artifact.MacSymbolName);
        Assert.AreEqual(TranscriptCategoryPresentation.RedHex, approval.ForegroundHex);
        Assert.AreEqual("hand.raised", approval.MacSymbolName);
    }

    [TestMethod]
    public void ActiveCategoriesSplitMacRowAndPillOpacity()
    {
        var tool = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyTools);
        var artifact = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyArtifacts);
        var approval = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyApprovals);
        var system = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeySystem);

        Assert.AreEqual("#17FF9F0A", tool.BackgroundHex);
        Assert.AreEqual("#1CFF9F0A", tool.BadgeBackgroundHex);
        Assert.AreEqual("#140A84FF", artifact.BackgroundHex);
        Assert.AreEqual("#1C0A84FF", artifact.BadgeBackgroundHex);
        Assert.AreEqual("#14FF453A", approval.BackgroundHex);
        Assert.AreEqual("#1CFF453A", approval.BadgeBackgroundHex);
        Assert.AreEqual("#14A7B0BF", system.BackgroundHex);
        Assert.AreEqual("#1CA7B0BF", system.BadgeBackgroundHex);
        Assert.AreEqual(TranscriptCategoryPresentation.ActiveBorderHex, approval.BorderHex);
    }

    [TestMethod]
    public void AllFilterMenuCategoriesExposeMacSymbolsAndWindowsGlyphs()
    {
        var expected = new[]
        {
            (TranscriptCategoryPresentation.KeyMessages, "bubble.left.and.bubble.right", "\uE8F2"),
            (TranscriptCategoryPresentation.KeyProgress, "arrow.triangle.2.circlepath", "\uE895"),
            (TranscriptCategoryPresentation.KeyThoughts, "sparkles", "\uEA80"),
            (TranscriptCategoryPresentation.KeyTools, "wrench.and.screwdriver", "\uE90F"),
            (TranscriptCategoryPresentation.KeyArtifacts, "shippingbox", "\uE7C3"),
            (TranscriptCategoryPresentation.KeyApprovals, "hand.raised", "\uE7BA"),
            (TranscriptCategoryPresentation.KeySystem, "info.circle", "\uE946")
        };

        foreach (var (key, macSymbol, windowsGlyph) in expected)
        {
            var presentation = TranscriptCategoryPresentation.Resolve(key);

            Assert.AreEqual(macSymbol, presentation.MacSymbolName);
            Assert.AreEqual(windowsGlyph, presentation.WindowsGlyph);
        }
    }

    [TestMethod]
    public void SystemAcceptsLegacyEventKeysButPresentsAsMacSystemCategory()
    {
        Assert.IsTrue(TranscriptCategoryPresentation.TryNormalizeKey("events", out var normalized));

        var presentation = TranscriptCategoryPresentation.Resolve(normalized);

        Assert.AreEqual(TranscriptCategoryPresentation.KeySystem, normalized);
        Assert.AreEqual("System", presentation.Title);
        Assert.AreEqual("Event", presentation.CompactTitle);
        Assert.AreEqual("info.circle", presentation.MacSymbolName);
        Assert.AreEqual(TranscriptCategoryPresentation.SecondaryHex, presentation.ForegroundHex);
    }

    [TestMethod]
    public void InactiveCategoryUsesSharedMutedChrome()
    {
        var presentation = TranscriptCategoryPresentation.Resolve(
            TranscriptCategoryPresentation.KeyThoughts,
            isActive: false);

        Assert.AreEqual(TranscriptCategoryPresentation.InactiveForegroundHex, presentation.ForegroundHex);
        Assert.AreEqual(TranscriptCategoryPresentation.InactiveBackgroundHex, presentation.BackgroundHex);
        Assert.AreEqual(TranscriptCategoryPresentation.InactiveBackgroundHex, presentation.BadgeBackgroundHex);
        Assert.AreEqual(TranscriptCategoryPresentation.InactiveBorderHex, presentation.BorderHex);
    }
}
