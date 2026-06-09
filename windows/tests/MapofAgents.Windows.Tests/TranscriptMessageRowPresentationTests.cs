using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class TranscriptMessageRowPresentationTests
{
    [TestMethod]
    public void UserMessagesUseMacBlueMessageSurface()
    {
        var presentation = TranscriptMessageRowPresentation.Resolve("user");

        Assert.AreEqual(TranscriptMessageRowPresentation.UserRole, presentation.SourceRole);
        Assert.AreEqual("You", presentation.RoleTitle);
        Assert.AreEqual("\uE13D", presentation.WindowsGlyph);
        Assert.AreEqual("#1A0A84FF", presentation.RowBackgroundHex);
        Assert.AreEqual(TranscriptCategoryPresentation.BlueHex, presentation.RoleForegroundHex);
        Assert.AreEqual(TranscriptMessageRowPresentation.RowBorderHex, presentation.RowBorderHex);
        Assert.AreEqual(TranscriptMessageRowPresentation.HiddenBadgeBackgroundHex, presentation.BadgeBackgroundHex);
    }

    [TestMethod]
    public void AssistantMessagesUseMacGreenCodexSurface()
    {
        var presentation = TranscriptMessageRowPresentation.Resolve("assistant");

        Assert.AreEqual(TranscriptMessageRowPresentation.AssistantRole, presentation.SourceRole);
        Assert.AreEqual("Codex", presentation.RoleTitle);
        Assert.AreEqual("\uE8F2", presentation.WindowsGlyph);
        Assert.AreEqual("#1A30D158", presentation.RowBackgroundHex);
        Assert.AreEqual(TranscriptCategoryPresentation.GreenHex, presentation.RoleForegroundHex);
    }

    [TestMethod]
    public void UnknownMessagesFallBackToUserTreatment()
    {
        var presentation = TranscriptMessageRowPresentation.Resolve("speaker");

        Assert.AreEqual(TranscriptMessageRowPresentation.UserRole, presentation.SourceRole);
        Assert.AreEqual("You", presentation.RoleTitle);
        Assert.AreEqual(TranscriptMessageRowPresentation.UserRowBackgroundHex, presentation.RowBackgroundHex);
    }
}
