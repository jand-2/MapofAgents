using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class NewThreadOptionDefaultsTests
{
    [TestMethod]
    public void DefaultsMatchMacNewThreadFallbacks()
    {
        Assert.AreEqual("gpt-5.5", NewThreadOptionDefaults.DefaultModel);
        Assert.AreEqual("high", NewThreadOptionDefaults.DefaultReasoningEffort);
        CollectionAssert.AreEqual(
            new[] { "low", "medium", "high", "xhigh" },
            NewThreadOptionDefaults.SupportedReasoningEfforts.ToArray());
        Assert.AreEqual("gpt-5.5", NewThreadOptionDefaults.DefaultModelOption.Id);
        Assert.IsTrue(NewThreadOptionDefaults.DefaultModelOption.IsDefault);
    }

    [TestMethod]
    public void PermissionsMatchMacThreadPermissionDefaults()
    {
        Assert.AreEqual("on-request", NewThreadOptionDefaults.DefaultApprovalPolicy);
        Assert.AreEqual("workspace-write", NewThreadOptionDefaults.DefaultSandboxMode);
        CollectionAssert.AreEqual(
            new[] { "on-request", "on-failure", "untrusted", "never" },
            NewThreadOptionDefaults.ApprovalPolicies.Select(policy => policy.Value).ToArray());
        CollectionAssert.AreEqual(
            new[] { "danger-full-access", "workspace-write", "read-only" },
            NewThreadOptionDefaults.SandboxModes.Select(mode => mode.Value).ToArray());
        Assert.IsTrue(NewThreadOptionDefaults.RequiresFullAccessConfirmation("danger-full-access"));
        Assert.IsFalse(NewThreadOptionDefaults.RequiresFullAccessConfirmation("workspace-write"));
        Assert.IsFalse(NewThreadOptionDefaults.RequiresFullAccessConfirmation("read-only"));
    }

    [TestMethod]
    public void ModelCatalogPrefersSelectedModelWhenStillAvailable()
    {
        var options = new[]
        {
            new CodexModelOption("gpt-fast", "GPT Fast", "", "low", new[] { "low", "medium" }, false),
            new CodexModelOption("gpt-deep", "GPT Deep", "", "high", new[] { "medium", "high" }, true)
        };

        var selected = NewThreadModelCatalog.CurrentModel(options, "gpt-fast");
        var effort = NewThreadModelCatalog.CurrentReasoningEffort(selected, "medium");

        Assert.AreEqual("gpt-fast", selected.Id);
        Assert.AreEqual("medium", effort);
    }

    [TestMethod]
    public void ModelCatalogFallsBackToDefaultAndSupportedEffort()
    {
        var options = new[]
        {
            new CodexModelOption("gpt-small", "GPT Small", "", "low", new[] { "low" }, false),
            new CodexModelOption("gpt-deep", "GPT Deep", "", "high", new[] { "medium", "high" }, true)
        };

        var selected = NewThreadModelCatalog.CurrentModel(options, "missing-model");
        var effort = NewThreadModelCatalog.CurrentReasoningEffort(selected, "xhigh");

        Assert.AreEqual("gpt-deep", selected.Id);
        Assert.AreEqual("high", effort);
    }
}
