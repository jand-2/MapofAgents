using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MentionSelectionControllerTests
{
    [TestMethod]
    public void SuggestionsSelectFirstItemWithoutMovingComposerFocus()
    {
        var controller = new MentionSelectionController();

        controller.UpdateSuggestionCount(3);

        Assert.AreEqual(0, controller.SelectedIndex);
    }

    [TestMethod]
    public void ArrowKeysWrapThroughSuggestions()
    {
        var controller = new MentionSelectionController();

        var up = controller.Handle(MentionSelectionKey.ArrowUp, 3);
        var down = controller.Handle(MentionSelectionKey.ArrowDown, 3);

        Assert.IsTrue(up.Handled);
        Assert.AreEqual(2, up.SelectedIndex);
        Assert.IsTrue(down.Handled);
        Assert.AreEqual(0, down.SelectedIndex);
    }

    [TestMethod]
    public void EnterAcceptsCurrentSelectionBeforeComposerSubmission()
    {
        var controller = new MentionSelectionController();
        controller.Handle(MentionSelectionKey.ArrowDown, 3);

        var result = controller.Handle(MentionSelectionKey.Enter, 3);

        Assert.IsTrue(result.Handled);
        Assert.IsTrue(result.ShouldAccept);
        Assert.IsFalse(result.ShouldDismiss);
        Assert.AreEqual(1, result.SelectedIndex);
    }

    [TestMethod]
    public void EscapeDismissesSuggestionsAndClearsSelection()
    {
        var controller = new MentionSelectionController();
        controller.ActivateQuery("@rev");
        controller.UpdateSuggestionCount(2);

        var result = controller.Handle(MentionSelectionKey.Escape, 2);

        Assert.IsTrue(result.Handled);
        Assert.IsTrue(result.ShouldDismiss);
        Assert.AreEqual(-1, result.SelectedIndex);
        Assert.AreEqual(-1, controller.SelectedIndex);
        Assert.IsTrue(controller.IsDismissed);
        Assert.IsFalse(controller.ActivateQuery("@rev"));
        Assert.IsTrue(controller.ActivateQuery("@review"));
        Assert.IsFalse(controller.IsDismissed);
    }

    [TestMethod]
    public void EmptySuggestionListDoesNotConsumeComposerKeys()
    {
        var controller = new MentionSelectionController();

        var result = controller.Handle(MentionSelectionKey.Enter, 0);

        Assert.IsFalse(result.Handled);
        Assert.IsFalse(result.ShouldAccept);
    }
}
