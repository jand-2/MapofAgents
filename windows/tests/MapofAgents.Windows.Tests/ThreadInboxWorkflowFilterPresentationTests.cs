using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class ThreadInboxWorkflowFilterPresentationTests
{
    [TestMethod]
    public void UsesMacBaseFilterIcons()
    {
        Assert.AreEqual(
            ThreadInboxWorkflowFilterPresentation.TrayFullIcon,
            ThreadInboxWorkflowFilterPresentation.Resolve(ThreadInboxWorkflowFilterPresentation.All).IconKind);
        Assert.AreEqual(
            ThreadInboxWorkflowFilterPresentation.RectangleGroupIcon,
            ThreadInboxWorkflowFilterPresentation.Resolve(ThreadInboxWorkflowFilterPresentation.OnWorkflows).IconKind);
        Assert.AreEqual(
            ThreadInboxWorkflowFilterPresentation.DashedRectangleIcon,
            ThreadInboxWorkflowFilterPresentation.Resolve(ThreadInboxWorkflowFilterPresentation.NotOnWorkflows).IconKind);
    }

    [TestMethod]
    public void UsesMacWorkflowStackIcons()
    {
        Assert.AreEqual(
            ThreadInboxWorkflowFilterPresentation.RectangleStackIcon,
            ThreadInboxWorkflowFilterPresentation.Resolve(ThreadInboxWorkflowFilterPresentation.Workflow).IconKind);
        Assert.AreEqual(
            ThreadInboxWorkflowFilterPresentation.CheckmarkRectangleStackIcon,
            ThreadInboxWorkflowFilterPresentation.Resolve(
                ThreadInboxWorkflowFilterPresentation.Workflow,
                isActiveWorkflow: true).IconKind);
    }

    [TestMethod]
    public void WorkflowTitlesUseMacNameAndCountWithoutCurrentPrefix()
    {
        var inactive = ThreadInboxWorkflowFilterPresentation.Resolve(
            ThreadInboxWorkflowFilterPresentation.Workflow,
            workflowName: "Release Prep",
            workflowCount: 3);
        var active = ThreadInboxWorkflowFilterPresentation.Resolve(
            ThreadInboxWorkflowFilterPresentation.Workflow,
            isActiveWorkflow: true,
            workflowName: "Current Workflow",
            workflowCount: 1);

        Assert.AreEqual("Release Prep (3)", inactive.Title);
        Assert.AreEqual("Current Workflow (1)", active.Title);
        Assert.IsFalse(active.Title.StartsWith("Current:", StringComparison.OrdinalIgnoreCase));
    }

    [TestMethod]
    public void WorkflowTitlesFallBackToGenericWorkflowName()
    {
        var presentation = ThreadInboxWorkflowFilterPresentation.Resolve(
            ThreadInboxWorkflowFilterPresentation.Workflow,
            workflowName: "   ",
            workflowCount: 2);

        Assert.AreEqual("Workflow (2)", presentation.Title);
    }
}
