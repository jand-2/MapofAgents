using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class MentionCatalogTests
{
    [TestMethod]
    public void ParsesSkillPluginAndFileMentionCandidates()
    {
        const string skillsJson = """
            {
              "id": 2,
              "result": {
                "data": [
                  {
                    "skills": [
                      {
                        "name": "taildesk-start-app",
                        "path": "file:///skills/taildesk-start-app/SKILL.md",
                        "interface": {
                          "displayName": "TailDesk",
                          "shortDescription": "Start the viewer."
                        }
                      },
                      {
                        "name": "disabled-skill",
                        "path": "file:///skills/disabled/SKILL.md",
                        "enabled": false
                      }
                    ]
                  }
                ]
              }
            }
            """;
        const string pluginsJson = """
            {
              "id": 2,
              "result": {
                "marketplaces": [
                  {
                    "name": "local",
                    "plugins": [
                      {
                        "id": "browser@local",
                        "name": "browser",
                        "installed": true,
                        "interface": {
                          "displayName": "Browser",
                          "shortDescription": "Control the in-app browser."
                        }
                      },
                      {
                        "id": "disabled@local",
                        "installed": false
                      }
                    ]
                  }
                ]
              }
            }
            """;
        var file = MentionCatalog.FileMentionCandidate(
            "C:\\Users\\example\\workspace\\README.md",
            "README.md",
            "README.md");

        var candidates = MentionCatalog.CatalogMentionCandidates(skillsJson, pluginsJson, new[] { file });

        var bridge = candidates.Single(candidate => candidate.Title == "$mapofagents-workflow-bridge");
        Assert.AreEqual('$', bridge.Trigger);
        var skill = candidates.Single(candidate => candidate.Title == "$taildesk-start-app");
        Assert.AreEqual(MentionCatalog.KindSkill, skill.Kind);
        Assert.AreEqual('$', skill.Trigger);
        Assert.IsTrue(skill.Subtitle.Contains("TailDesk", StringComparison.Ordinal));
        var plugin = candidates.Single(candidate => candidate.Title == "@browser");
        Assert.AreEqual(MentionCatalog.KindPlugin, plugin.Kind);
        Assert.AreEqual('@', plugin.Trigger);
        var fileCandidate = candidates.Single(candidate => candidate.Title == "@README.md");
        Assert.AreEqual(MentionCatalog.KindFile, fileCandidate.Kind);
        Assert.AreEqual('@', fileCandidate.Trigger);
        Assert.IsFalse(candidates.Any(candidate => candidate.Title.Contains("disabled", StringComparison.OrdinalIgnoreCase)));
    }

    [TestMethod]
    public void LocalFileMentionCandidatesSkipHiddenAndIgnoredDirectories()
    {
        var root = Path.Combine(Path.GetTempPath(), $"mapofagents-mentions-{Guid.NewGuid():N}");
        try
        {
            Directory.CreateDirectory(root);
            File.WriteAllText(Path.Combine(root, "README.md"), "public fixture");
            File.WriteAllText(Path.Combine(root, ".env"), "ignored fixture");
            var source = Path.Combine(root, "src");
            Directory.CreateDirectory(source);
            File.WriteAllText(Path.Combine(source, "Program.cs"), "public fixture");
            var ignored = Path.Combine(root, "node_modules");
            Directory.CreateDirectory(ignored);
            File.WriteAllText(Path.Combine(ignored, "package.json"), "ignored fixture");

            var candidates = MentionCatalog.LocalFileMentionCandidates(root, limit: 10);

            Assert.IsTrue(candidates.Any(candidate => candidate.Subtitle == "README.md"));
            Assert.IsTrue(candidates.Any(candidate => candidate.Subtitle == "src"));
            Assert.IsTrue(candidates.Any(candidate => candidate.Subtitle == "src/Program.cs"));
            Assert.IsFalse(candidates.Any(candidate => candidate.Subtitle.Contains("node_modules", StringComparison.OrdinalIgnoreCase)));
            Assert.IsFalse(candidates.Any(candidate => candidate.Subtitle.Contains(".env", StringComparison.OrdinalIgnoreCase)));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }
}
