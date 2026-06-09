using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptLoadPhasePresentationTests
{
    [DataTestMethod]
    [DataRow(TranscriptLoadPhase.Idle, "Ready", "", "checkmark.circle")]
    [DataRow(
        TranscriptLoadPhase.ConnectingHost,
        "Checking host connection",
        "Waiting on the owning machine or App Server route.",
        "antenna.radiowaves.left.and.right")]
    [DataRow(
        TranscriptLoadPhase.LoadingHistory,
        "Loading message history",
        "Waiting on thread history from Codex App Server.",
        "text.bubble")]
    [DataRow(
        TranscriptLoadPhase.HydratingArtifacts,
        "Hydrating artifacts",
        "Reading generated files, diffs, or images.",
        "shippingbox")]
    [DataRow(
        TranscriptLoadPhase.Refreshing,
        "Refreshing transcript",
        "Keeping the last loaded messages visible.",
        "arrow.clockwise")]
    [DataRow(
        TranscriptLoadPhase.LoadingOlder,
        "Loading older messages",
        "Prepending an older transcript page.",
        "clock.arrow.circlepath")]
    public void ResolveMatchesMacTranscriptLoadPhaseCopyAndSymbols(
        TranscriptLoadPhase phase,
        string expectedTitle,
        string expectedDetail,
        string expectedMacSymbol)
    {
        var presentation = TranscriptLoadPhasePresentation.Resolve(phase);

        Assert.AreEqual(phase, presentation.Phase);
        Assert.AreEqual(expectedTitle, presentation.Title);
        Assert.AreEqual(expectedDetail, presentation.Detail);
        Assert.AreEqual(expectedMacSymbol, presentation.MacSymbolName);
        Assert.IsFalse(string.IsNullOrWhiteSpace(presentation.WindowsGlyph));
    }

    [TestMethod]
    public void InitialPhaseMatchesMacFirstLoadRefreshAndOlderBehavior()
    {
        Assert.AreEqual(
            TranscriptLoadPhase.ConnectingHost,
            TranscriptLoadPhasePresentation.InitialPhase(isLoadingOlder: false, hasLoadedTranscript: false));
        Assert.AreEqual(
            TranscriptLoadPhase.Refreshing,
            TranscriptLoadPhasePresentation.InitialPhase(isLoadingOlder: false, hasLoadedTranscript: true));
        Assert.AreEqual(
            TranscriptLoadPhase.LoadingOlder,
            TranscriptLoadPhasePresentation.InitialPhase(isLoadingOlder: true, hasLoadedTranscript: true));
    }
}
