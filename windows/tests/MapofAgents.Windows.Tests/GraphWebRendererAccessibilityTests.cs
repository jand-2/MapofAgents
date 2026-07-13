using MapofAgents.Core;
using MapofAgents.WindowsApp;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class GraphWebRendererAccessibilityTests
{
    [TestMethod]
    public void NodesExposeRoleNameSelectionValueAndRovingTabStop()
    {
        var graph = new AgentGraph();
        graph.Nodes["thread-accessible"] = new CanvasNode
        {
            Id = "thread-accessible",
            Kind = NodeKinds.CodexThread,
            Title = "Review queue",
            Subtitle = "Windows host",
            Metadata = new NodeMetadata
            {
                RunStatus = ThreadRunStatuses.Running,
                IsUnread = true,
                Model = "gpt-5"
            }
        };

        var html = GraphWebRenderer.Render(graph);

        StringAssert.Contains(html, "role=\"group\"");
        StringAssert.Contains(html, "class=\"node-primary-action\"");
        StringAssert.Contains(html, "type=\"button\"");
        StringAssert.Contains(html, "tabindex=\"-1\"");
        StringAssert.Contains(html, "aria-label=\"${escapeText(nodeAccessibleName(node))}\"");
        StringAssert.Contains(html, "aria-pressed=\"false\"");
        StringAssert.Contains(html, "aria-haspopup=\"menu\"");
        StringAssert.Contains(html, "aria-keyshortcuts=\"Enter Space Shift+F10\"");
        StringAssert.Contains(html, "return `${String(node.title || node.kind || \"Untitled\")}, ${nodeKindLabel(node)}`;");
        StringAssert.Contains(html, "details.push(`Status ${status}`)");
        StringAssert.Contains(html, "details.push(`Model ${node.metadata.model}`)");
        StringAssert.Contains(html, "\"title\": \"Review queue\"");
    }

    [TestMethod]
    public void KeyboardScriptSupportsRovingActivationAndContextMenuFocus()
    {
        var html = GraphWebRenderer.Render(AgentGraph.CreateStarter("DESKTOP-EXAMPLE"));

        StringAssert.Contains(html, "function syncNodeRovingTabIndex");
        StringAssert.Contains(html, "moveNodeKeyboardFocus(element, event.key)");
        StringAssert.Contains(html, "primaryAction?.addEventListener(\"click\"");
        StringAssert.Contains(html, "event.key === \"ContextMenu\"");
        StringAssert.Contains(html, "event.shiftKey && event.key === \"F10\"");
        StringAssert.Contains(html, "contextMenu.setAttribute(\"role\", \"menu\")");
        StringAssert.Contains(html, "hideNodeContextMenu(true)");

        var graphUpdateStart = html.IndexOf("function applyGraphUpdate", StringComparison.Ordinal);
        var menuFocusCapture = html.IndexOf("const focusedMenuNodeId", graphUpdateStart, StringComparison.Ordinal);
        var menuHide = html.IndexOf("hideNodeContextMenu();", graphUpdateStart, StringComparison.Ordinal);
        Assert.IsTrue(menuFocusCapture > graphUpdateStart);
        Assert.IsTrue(menuHide > menuFocusCapture, "Menu origin must be captured before refresh removes its focused child.");
    }
}
