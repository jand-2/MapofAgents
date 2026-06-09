using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxEmptyStateLayoutTests
{
    [TestMethod]
    public void MeasureUsesMacEmptyStateCaptionSpacing()
    {
        var layout = ThreadInboxEmptyStateLayout.Measure();

        Assert.AreEqual(12, layout.FontSize);
        Assert.AreEqual(8, layout.VerticalPadding);
    }
}
