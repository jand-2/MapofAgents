using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NewThreadNamingPresentationTests
{
    [TestMethod]
    public void FolderTargetUsesMacAgentSuffix()
    {
        var name = NewThreadNamingPresentation.ResolveForTarget("MapofAgents", NodeKinds.Folder);

        Assert.AreEqual("MapofAgents agent", name);
    }

    [TestMethod]
    public void MachineTargetUsesMacChatSuffix()
    {
        var name = NewThreadNamingPresentation.ResolveForTarget("Windows Desktop", NodeKinds.Machine);

        Assert.AreEqual("Windows Desktop chat", name);
    }

    [TestMethod]
    public void MissingTargetFallsBackToMacCodexThreadName()
    {
        var name = NewThreadNamingPresentation.ResolveForTarget(null, NodeKinds.Folder);

        Assert.AreEqual("Codex thread", name);
    }
}
