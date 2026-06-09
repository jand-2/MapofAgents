using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AttentionRequestCardPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacStyleMethodAndPromptContent()
    {
        var presentation = AttentionRequestCardPresentation.Resolve(
            " item/commandExecution/requestApproval ",
            " Allow this command? ");

        Assert.AreEqual("item/commandExecution/requestApproval", presentation.MethodText);
        Assert.AreEqual("Allow this command?", presentation.PromptText);
    }

    [TestMethod]
    public void ResolveUsesMacCardChrome()
    {
        var presentation = AttentionRequestCardPresentation.Resolve("exec_command", "Continue?");

        Assert.IsFalse(presentation.ShowTargetLabel);
        Assert.AreEqual("#18D97706", presentation.BackgroundHex);
        Assert.AreEqual("#00FFFFFF", presentation.BorderHex);
        Assert.AreEqual(0, presentation.BorderThickness);
        Assert.AreEqual(8, presentation.HorizontalPadding);
        Assert.AreEqual(6, presentation.VerticalPadding);
        Assert.AreEqual(8, presentation.CornerRadius);
        Assert.AreEqual(8, presentation.StackSpacing);
        Assert.AreEqual(8, presentation.BottomMargin);
    }

    [TestMethod]
    public void ResolveUsesMacFocusExpandIcon()
    {
        var presentation = AttentionRequestCardPresentation.Resolve("exec_command", "Continue?");

        Assert.AreEqual(AttentionRequestCardPresentation.FocusExpandIcon, presentation.FocusIconKind);
        Assert.AreEqual(18, presentation.FocusIconWidth);
        Assert.AreEqual(18, presentation.FocusIconHeight);
        Assert.AreEqual(1.15, presentation.FocusIconStrokeThickness);
    }

    [TestMethod]
    public void ResolveUsesMacCompactActionRowMetrics()
    {
        var presentation = AttentionRequestCardPresentation.Resolve("exec_command", "Continue?");

        Assert.AreEqual(8, presentation.ActionButtonSpacing);
        Assert.AreEqual(7, presentation.ActionButtonHorizontalPadding);
        Assert.AreEqual(4, presentation.ActionButtonVerticalPadding);
    }

    [TestMethod]
    public void ResolveFallsBackForBlankContent()
    {
        var presentation = AttentionRequestCardPresentation.Resolve("", "");

        Assert.AreEqual("Attention request", presentation.MethodText);
        Assert.AreEqual("This thread needs a response.", presentation.PromptText);
    }
}
