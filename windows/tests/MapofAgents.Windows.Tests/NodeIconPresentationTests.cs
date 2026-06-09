using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NodeIconPresentationTests
{
    [TestMethod]
    public void RegularThreadUsesMacStyleThreadPairIcon()
    {
        var presentation = NodeIconPresentation.Resolve(NodeKinds.CodexThread);

        Assert.IsTrue(presentation.UsesThreadPairIcon);
        Assert.AreEqual(string.Empty, presentation.Glyph);
    }

    [TestMethod]
    public void SubagentUsesPeopleIcon()
    {
        var presentation = NodeIconPresentation.Resolve(NodeKinds.CodexThread, isSubagent: true);

        Assert.IsFalse(presentation.UsesThreadPairIcon);
        Assert.AreEqual(NodeIconPresentation.SubagentGlyph, presentation.Glyph);
    }

    [TestMethod]
    public void MachineAndFolderKeepMacNodeKinds()
    {
        Assert.AreEqual(NodeIconPresentation.MachineGlyph, NodeIconPresentation.Resolve(NodeKinds.Machine).Glyph);
        Assert.AreEqual(NodeIconPresentation.FolderGlyph, NodeIconPresentation.Resolve(NodeKinds.Folder).Glyph);
    }

    [TestMethod]
    public void WebPresentationMapIncludesRendererKeys()
    {
        var map = NodeIconPresentation.WebPresentationMap();

        Assert.IsTrue(map[NodeKinds.CodexThread].UsesThreadPairIcon);
        Assert.AreEqual(NodeIconPresentation.SubagentGlyph, map[ThreadKinds.Subagent].Glyph);
        Assert.AreEqual(NodeIconPresentation.MachineGlyph, map[NodeKinds.Machine].Glyph);
    }
}
