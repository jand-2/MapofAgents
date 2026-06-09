using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class AppServerClientTranscriptTests
{
    [TestMethod]
    public void ParseThreadTranscriptReadsRowsAndCursor()
    {
        var json = """
        {
          "id": 2,
          "result": {
            "nextCursor": "older-page",
            "data": [
              {
                "id": "turn-2",
                "createdAt": "2026-06-04T12:02:00Z",
                "items": [
                  {
                    "id": "assistant-1",
                    "type": "agentMessage",
                    "text": "Done."
                  },
                  {
                    "id": "cmd-1",
                    "type": "commandExecution",
                    "command": "swift test",
                    "aggregatedOutput": "Build succeeded"
                  }
                ]
              },
              {
                "id": "turn-1",
                "createdAt": "2026-06-04T12:00:00Z",
                "items": [
                  {
                    "id": "user-1",
                    "type": "userMessage",
                    "content": [
                      { "type": "input_text", "text": "Please run tests." }
                    ]
                  },
                  {
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "summary": [
                      { "type": "output_text", "text": "Checking the build first." }
                    ]
                  }
                ]
              }
            ]
          }
        }
        """;

        var transcript = AppServerClient.ParseThreadTranscript(
            json,
            new ThreadRef { HostID = "host", ThreadID = "thread" });

        Assert.AreEqual("older-page", transcript.NextCursor);
        Assert.AreEqual(4, transcript.Messages.Count);
        Assert.AreEqual("user", transcript.Messages[0].Role);
        Assert.AreEqual("Please run tests.", transcript.Messages[0].Text);
        Assert.AreEqual("reasoning", transcript.Messages[1].Role);
        Assert.AreEqual("Checking the build first.", transcript.Messages[1].Text);
        Assert.AreEqual("assistant", transcript.Messages[2].Role);
        Assert.AreEqual("Done.", transcript.Messages[2].Text);
        Assert.AreEqual("tool", transcript.Messages[3].Role);
        StringAssert.Contains(transcript.Messages[3].Text, "swift test");
        StringAssert.Contains(transcript.Messages[3].Text, "Build succeeded");
        Assert.AreEqual(2, transcript.Turns.Count);
        Assert.AreEqual("turn-1", transcript.Turns[0].Id);
        Assert.AreEqual(ThreadRunStatuses.Unknown, transcript.Turns[0].Status);
        CollectionAssert.AreEqual(new[] { "user-1", "reasoning-1" }, transcript.Turns[0].ItemMessageIds);
        Assert.AreEqual("turn-2", transcript.Turns[1].Id);
        CollectionAssert.AreEqual(new[] { "assistant-1", "cmd-1" }, transcript.Turns[1].ItemMessageIds);
    }

    [TestMethod]
    public void ParseThreadTranscriptPreservesTurnEnvelope()
    {
        var json = """
        {
          "id": 2,
          "result": {
            "data": [
              {
                "id": "turn-running",
                "status": "in_progress",
                "startedAt": "2026-06-04T12:02:00Z",
                "completedAt": "2026-06-04T12:02:02Z",
                "itemsView": "summary",
                "durationMs": 2500,
                "error": { "message": "Tool output truncated." },
                "items": [
                  {
                    "id": "assistant-1",
                    "type": "agentMessage",
                    "text": "Still working."
                  }
                ]
              }
            ]
          }
        }
        """;

        var transcript = AppServerClient.ParseThreadTranscript(
            json,
            new ThreadRef { HostID = "host", ThreadID = "thread" });

        Assert.AreEqual(1, transcript.Turns.Count);
        var turn = transcript.Turns[0];
        Assert.AreEqual("turn-running", turn.Id);
        Assert.AreEqual(ThreadRunStatuses.Running, turn.Status);
        Assert.AreEqual(ThreadTurnItemsViews.Summary, turn.ItemsView);
        Assert.AreEqual(2500, turn.DurationMilliseconds);
        Assert.AreEqual("Tool output truncated.", turn.Error);
        CollectionAssert.AreEqual(new[] { "assistant-1" }, turn.ItemMessageIds);
    }

    [TestMethod]
    public void ParseForkedThreadReadsThreadReference()
    {
        var json = """
        {
          "id": 2,
          "result": {
            "thread": {
              "id": "forked-thread",
              "cwd": "C:\\Users\\example\\project",
              "name": "Layout fork"
            }
          }
        }
        """;

        var threadRef = AppServerClient.ParseForkedThread(
            json,
            new ThreadRef
            {
                HostID = "windows-host",
                ThreadID = "source-thread",
                Cwd = "C:\\Users\\example\\source",
                Name = "Layout"
            });

        Assert.AreEqual("windows-host", threadRef.HostID);
        Assert.AreEqual("forked-thread", threadRef.ThreadID);
        Assert.AreEqual("C:\\Users\\example\\project", threadRef.Cwd);
        Assert.AreEqual("Layout fork", threadRef.Name);
    }
}
