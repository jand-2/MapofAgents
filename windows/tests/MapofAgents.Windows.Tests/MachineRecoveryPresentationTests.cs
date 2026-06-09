using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MachineRecoveryPresentationTests
{
    [TestMethod]
    public void HeaderUsesMacCrossCaseTreatment()
    {
        var presentation = MachineRecoveryPresentation.Header();

        Assert.AreEqual("cross.case", presentation.MacSymbolName);
        Assert.AreEqual("crossCase", presentation.IconKind);
        Assert.AreEqual("#D7DCE5", presentation.ForegroundHex);
        Assert.AreEqual(16, presentation.IconSize);
        Assert.AreEqual("Machine Recovery", presentation.AccessibilityName);
    }

    [TestMethod]
    public void RailUsesMacStepActionButtonsWithoutExtraFooterActions()
    {
        var presentation = MachineRecoveryPresentation.Rail();

        Assert.IsFalse(presentation.ShowsFooterActions);
        Assert.IsTrue(presentation.RequiresRecoveryTargets);
        Assert.IsFalse(presentation.ShowsEmptyState);
        Assert.AreEqual("button", presentation.StepActionControlKind);
        Assert.AreEqual("borderedProminent", presentation.RecommendedStepActionStyle);
        Assert.AreEqual("bordered", presentation.StandardStepActionStyle);
    }

    [TestMethod]
    public void RailVisibilityRequiresActualRecoveryTargets()
    {
        Assert.IsFalse(MachineRecoveryPresentation.ShouldShowRail(isPresented: false, recoveryTargetCount: 1));
        Assert.IsFalse(MachineRecoveryPresentation.ShouldShowRail(isPresented: true, recoveryTargetCount: 0));
        Assert.IsFalse(MachineRecoveryPresentation.ShouldShowRail(isPresented: true, recoveryTargetCount: -1));
        Assert.IsTrue(MachineRecoveryPresentation.ShouldShowRail(isPresented: true, recoveryTargetCount: 1));
    }

    [TestMethod]
    public void StepActionsUseMacIconVocabulary()
    {
        var verify = MachineRecoveryPresentation.StepAction(MachineRecoveryPresentation.VerifyEndpointStepId);
        var restart = MachineRecoveryPresentation.StepAction(MachineRecoveryPresentation.AppServerStepId);
        var reconnect = MachineRecoveryPresentation.StepAction(MachineRecoveryPresentation.ReconnectStepId);
        var remove = MachineRecoveryPresentation.StepAction(MachineRecoveryPresentation.RemoveRouteStepId);

        Assert.AreEqual("network", verify.MacSymbolName);
        Assert.AreEqual(MachineRecoveryPresentation.VerifyEndpointActionGlyph, verify.Glyph);
        Assert.AreEqual("arrow.clockwise", restart.MacSymbolName);
        Assert.AreEqual(MachineRecoveryPresentation.AppServerActionGlyph, restart.Glyph);
        Assert.AreEqual("antenna.radiowaves.left.and.right", reconnect.MacSymbolName);
        Assert.AreEqual(MachineRecoveryPresentation.ReconnectActionGlyph, reconnect.Glyph);
        Assert.AreEqual("trash", remove.MacSymbolName);
        Assert.AreEqual(MachineRecoveryPresentation.RemoveRouteActionGlyph, remove.Glyph);
    }

    [TestMethod]
    public void FailedMachineTargetUsesMacOrangeRecoveryPill()
    {
        var presentation = MachineRecoveryPresentation.TargetStatus(HostStatuses.Unavailable);

        Assert.AreEqual("failed", presentation.Text);
        Assert.AreEqual(MachineRecoveryPresentation.WarningGlyph, presentation.Glyph);
        Assert.AreEqual(MachineRecoveryPresentation.OrangeHex, presentation.ForegroundHex);
        Assert.AreEqual(MachineRecoveryPresentation.OrangeBackgroundHex, presentation.BackgroundHex);
        Assert.AreEqual(MachineRecoveryPresentation.OrangeBorderHex, presentation.BorderHex);
    }

    [TestMethod]
    public void RecoveryStepFailedKeepsMacRedDiagnosticTreatment()
    {
        var failed = MachineRecoveryPresentation.StepStatus(RecoveryStepStatuses.Failed);
        var warning = MachineRecoveryPresentation.StepStatus(RecoveryStepStatuses.Warning);

        Assert.AreEqual("failed", failed.Text);
        Assert.AreEqual(MachineRecoveryPresentation.FailedGlyph, failed.Glyph);
        Assert.AreEqual(MachineRecoveryPresentation.RedHex, failed.ForegroundHex);
        Assert.AreEqual(MachineRecoveryPresentation.RedBackgroundHex, failed.BackgroundHex);
        Assert.AreEqual("warning", warning.Text);
        Assert.AreEqual(MachineRecoveryPresentation.OrangeHex, warning.ForegroundHex);
    }

    [TestMethod]
    public void RunningAndPendingMatchMacRecoveryPalette()
    {
        var running = MachineRecoveryPresentation.TargetStatus(HostStatuses.Connecting);
        var pending = MachineRecoveryPresentation.StepStatus(RecoveryStepStatuses.Pending);

        Assert.AreEqual("running", running.Text);
        Assert.AreEqual(MachineRecoveryPresentation.BlueHex, running.ForegroundHex);
        Assert.AreEqual("pending", pending.Text);
        Assert.AreEqual(MachineRecoveryPresentation.SecondaryHex, pending.ForegroundHex);
    }
}
