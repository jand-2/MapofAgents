using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadNodeUpdatedPresentationTests
{
    [TestMethod]
    public void RecentActivityUsesMacNowCutoff()
    {
        var now = new DateTimeOffset(2026, 6, 6, 12, 0, 0, TimeSpan.Zero);
        var presentation = ThreadNodeUpdatedPresentation.Resolve(now.AddSeconds(-4), now);

        Assert.AreEqual("updated now", presentation.Text);
    }

    [TestMethod]
    public void PastActivityUsesAbbreviatedPlatformWords()
    {
        var now = new DateTimeOffset(2026, 6, 6, 12, 0, 0, TimeSpan.Zero);
        var presentation = ThreadNodeUpdatedPresentation.Resolve(now.AddMinutes(-3), now);

        Assert.AreEqual("updated 3 min. ago", presentation.Text);
    }

    [TestMethod]
    public void FutureActivityKeepsRelativeDirection()
    {
        var now = new DateTimeOffset(2026, 6, 6, 12, 0, 0, TimeSpan.Zero);
        var presentation = ThreadNodeUpdatedPresentation.Resolve(now.AddHours(2), now);

        Assert.AreEqual("updated in 2 hr.", presentation.Text);
    }

    [TestMethod]
    public void WebFormatterConfigMatchesMacRelativeStyle()
    {
        var config = ThreadNodeUpdatedPresentation.WebFormatterConfig();
        var minute = config.Units.First(unit => unit.Unit == "minute");

        Assert.AreEqual(5, config.NowThresholdSeconds);
        Assert.AreEqual("short", config.IntlStyle);
        Assert.AreEqual(60, minute.Seconds);
        Assert.AreEqual(3_600, minute.CeilingSeconds);
        Assert.AreEqual("min.", minute.SingularLabel);
    }

    [TestMethod]
    public void WebFormatterConfigMatchesMacNodeUpdatedCaptionTreatment()
    {
        var config = ThreadNodeUpdatedPresentation.WebFormatterConfig();

        Assert.AreEqual(11, config.TextFontSize);
        Assert.AreEqual(13, config.TextLineHeight);
        Assert.AreEqual(GraphNodeCardPresentation.TertiaryTextHex, config.TextForegroundHex);
        Assert.AreEqual(1, config.TextMaxLines);
    }
}
