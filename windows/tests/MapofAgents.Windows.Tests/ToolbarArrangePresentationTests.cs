using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ToolbarArrangePresentationTests
{
    [TestMethod]
    public void UsesMacRectangleGroupTreatment()
    {
        var presentation = ToolbarArrangePresentation.Resolve();

        Assert.IsTrue(presentation.UsesRectangleGroupIcon);
        Assert.AreEqual("#D7DCE5", presentation.StrokeHex);
        Assert.AreEqual("Arrange machines, folders, and threads into default zones", presentation.ToolTip);
        Assert.AreEqual("Arrange", presentation.AccessibilityName);
    }
}
