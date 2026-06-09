using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxWorkflowMembershipPresentationTests
{
    [TestMethod]
    public void ActiveMembershipUsesMacRectangleGroupIcon()
    {
        var presentation = ThreadInboxWorkflowMembershipPresentation.Resolve(
            hasActiveWorkflowMembership: true,
            workflowMembershipCount: 1);

        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.RectangleGroupIcon,
            presentation.IconKind);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.RectangleGroupMacSymbolName,
            presentation.MacSymbolName);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.RectangleGroupGlyph,
            presentation.Glyph);
        Assert.AreEqual(14, presentation.IconWidth);
        Assert.AreEqual(12, presentation.IconHeight);
        Assert.AreEqual(1.0, presentation.StrokeThickness);
        Assert.AreEqual(0.68, presentation.SecondaryOpacity);
    }

    [TestMethod]
    public void MissingMembershipUsesMacDashedRectangleIcon()
    {
        var presentation = ThreadInboxWorkflowMembershipPresentation.Resolve(
            hasActiveWorkflowMembership: false,
            workflowMembershipCount: 0);

        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.DashedRectangleIcon,
            presentation.IconKind);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.DashedRectangleMacSymbolName,
            presentation.MacSymbolName);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.DashedRectangleGlyph,
            presentation.Glyph);
    }

    [TestMethod]
    public void SingleInactiveMembershipUsesMacRectangleSwapIcon()
    {
        var presentation = ThreadInboxWorkflowMembershipPresentation.Resolve(
            hasActiveWorkflowMembership: false,
            workflowMembershipCount: 1);

        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.RectangleSwapIcon,
            presentation.IconKind);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.RectangleSwapMacSymbolName,
            presentation.MacSymbolName);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.RectangleSwapGlyph,
            presentation.Glyph);
    }

    [TestMethod]
    public void MultipleInactiveMembershipsUseMacSquareStack3dUpIcon()
    {
        var presentation = ThreadInboxWorkflowMembershipPresentation.Resolve(
            hasActiveWorkflowMembership: false,
            workflowMembershipCount: 2);

        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.SquareStack3dUpIcon,
            presentation.IconKind);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.SquareStack3dUpMacSymbolName,
            presentation.MacSymbolName);
        Assert.AreEqual(
            ThreadInboxWorkflowMembershipPresentation.SquareStack3dUpGlyph,
            presentation.Glyph);
    }
}
