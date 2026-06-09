using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class OperationalRailHeaderTypographyTests
{
    [TestMethod]
    public void UsesMacHeadlineScaleForRailTitles()
    {
        var typography = OperationalRailHeaderTypography.Resolve();

        Assert.AreEqual("headline", typography.MacFontStyleName);
        Assert.AreEqual(13, typography.TitleFontSize);
        Assert.AreEqual("SemiBold", typography.TitleFontWeightName);
        Assert.AreEqual(8, typography.IconTitleSpacing);
    }
}
