using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineDiscoverySectionPresentationTests
{
    [TestMethod]
    public void ResolveUsesMacNestedSectionMetrics()
    {
        var presentation = MachineDiscoverySectionPresentation.Resolve(
            itemCount: 2,
            isDiscovering: false,
            singularNoun: "remote",
            pluralNoun: "remotes",
            message: null);

        Assert.AreEqual(7, presentation.SectionSpacing);
        Assert.AreEqual(6, presentation.HeaderColumnSpacing);
        Assert.AreEqual(16, presentation.HeaderIconWidth);
        Assert.AreEqual(18, presentation.CollapseButtonSize);
        Assert.AreEqual(7, presentation.ContentSpacing);
        Assert.AreEqual(260, presentation.ListMaxHeight);
        Assert.AreEqual(8, presentation.RowColumnSpacing);
        Assert.AreEqual(8, presentation.RowHorizontalPadding);
        Assert.AreEqual(6, presentation.RowVerticalPadding);
        Assert.AreEqual(16, presentation.RowIconWidth);
        Assert.AreEqual(12, presentation.RowTitleFontSize);
        Assert.AreEqual(11, presentation.RowDetailFontSize);
        Assert.AreEqual(11, presentation.BadgeFontSize);
    }

    [TestMethod]
    public void ResolvePlacesCountsInExpandedContentOnlyWhenRowsExist()
    {
        var populated = MachineDiscoverySectionPresentation.Resolve(
            itemCount: 1,
            isDiscovering: false,
            singularNoun: "machine",
            pluralNoun: "machines",
            message: "No machines found.");
        var empty = MachineDiscoverySectionPresentation.Resolve(
            itemCount: 0,
            isDiscovering: false,
            singularNoun: "machine",
            pluralNoun: "machines",
            message: "No machines found.");

        Assert.AreEqual("1 machine", populated.CountText);
        Assert.IsTrue(populated.ShowsCount);
        Assert.IsFalse(populated.ShowsMessage);
        Assert.AreEqual("0 machines", empty.CountText);
        Assert.IsFalse(empty.ShowsCount);
        Assert.IsTrue(empty.ShowsMessage);
    }

    [TestMethod]
    public void ResolveSuppressesEmptyMessageWhileDiscoveryRuns()
    {
        var presentation = MachineDiscoverySectionPresentation.Resolve(
            itemCount: 0,
            isDiscovering: true,
            singularNoun: "remote",
            pluralNoun: "remotes",
            message: "Discovering Codex remotes...");

        Assert.IsFalse(presentation.ShowsCount);
        Assert.IsFalse(presentation.ShowsMessage);
    }
}
