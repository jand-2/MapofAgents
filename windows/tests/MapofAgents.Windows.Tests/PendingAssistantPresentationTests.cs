using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class PendingAssistantPresentationTests
{
    [TestMethod]
    public void ResolveMatchesMacPendingAssistantRow()
    {
        var presentation = PendingAssistantPresentation.Resolve();

        Assert.AreEqual("ellipsis", presentation.MacSymbolName);
        Assert.AreEqual("\uE712", presentation.WindowsGlyph);
        Assert.AreEqual("Progress", presentation.RoleTitle);
        Assert.AreEqual("Waiting for response", presentation.Text);
    }
}
