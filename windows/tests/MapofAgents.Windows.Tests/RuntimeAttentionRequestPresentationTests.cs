using System.Text.Json;
using MapofAgents.Core;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace MapofAgents.Windows.Tests;

[TestClass]
public sealed class RuntimeAttentionRequestPresentationTests
{
    [TestMethod]
    public void TypedResponseChoicesUsesRequestUserInputQuestionOptions()
    {
        var request = new RuntimeAttentionRequest
        {
            Method = "requestUserInput",
            RequestParams = Json(
                """
                {
                  "questions": [
                    {
                      "id": "choice",
                      "question": "Pick one",
                      "options": [
                        { "label": "Approve", "value": "approve" },
                        { "label": "Revise", "id": "revise" },
                        "Skip"
                      ]
                    }
                  ]
                }
                """)
        };

        var choices = RuntimeAttentionRequestPresentation.TypedResponseChoices(request);

        Assert.AreEqual(3, choices.Count);
        Assert.AreEqual("Approve", choices[0].Label);
        Assert.AreEqual("approve", choices[0].Value);
        Assert.AreEqual("Revise", choices[1].Label);
        Assert.AreEqual("revise", choices[1].Value);
        Assert.AreEqual("Skip", choices[2].Label);
        Assert.AreEqual("Skip", choices[2].Value);
        Assert.AreEqual("approve", RuntimeAttentionRequestPresentation.InitialTypedResponseValue(request, choices));
    }

    [TestMethod]
    public void InitialTypedResponseValueUsesElicitationEnumDefault()
    {
        var request = new RuntimeAttentionRequest
        {
            Method = "elicitation/request",
            RequestParams = Json(
                """
                {
                  "requestedSchema": {
                    "type": "object",
                    "properties": {
                      "decision": {
                        "type": "string",
                        "default": "Revise",
                        "oneOf": [
                          { "const": "approve", "title": "Approve" },
                          { "const": "revise", "title": "Revise" }
                        ]
                      }
                    }
                  }
                }
                """)
        };

        var choices = RuntimeAttentionRequestPresentation.TypedResponseChoices(request);

        Assert.AreEqual(2, choices.Count);
        Assert.AreEqual("Approve", choices[0].Label);
        Assert.AreEqual("approve", choices[0].Value);
        Assert.AreEqual("Revise", choices[1].Label);
        Assert.AreEqual("revise", choices[1].Value);
        Assert.AreEqual("revise", RuntimeAttentionRequestPresentation.InitialTypedResponseValue(request, choices));
    }

    [TestMethod]
    public void ElicitationChoicesFallBackToFirstWhenDefaultDoesNotMatch()
    {
        var request = new RuntimeAttentionRequest
        {
            Method = "elicitation/request",
            RequestParams = Json(
                """
                {
                  "schema": {
                    "type": "object",
                    "properties": {
                      "decision": {
                        "type": "string",
                        "default": "something else",
                        "enum": [ "allow", "deny" ]
                      }
                    }
                  }
                }
                """)
        };

        var choices = RuntimeAttentionRequestPresentation.TypedResponseChoices(request);

        Assert.AreEqual(2, choices.Count);
        Assert.AreEqual("allow", RuntimeAttentionRequestPresentation.InitialTypedResponseValue(request, choices));
    }

    [TestMethod]
    public void TypedResponseChoicesFallsBackToPersistedResponseChoices()
    {
        var request = new RuntimeAttentionRequest
        {
            Method = "requestUserInput",
            ResponseChoices =
            [
                new RuntimeAttentionResponseChoice { Label = "First", Value = "first" },
                new RuntimeAttentionResponseChoice { Label = "", Value = "second" }
            ]
        };

        var choices = RuntimeAttentionRequestPresentation.TypedResponseChoices(request);

        Assert.AreEqual(2, choices.Count);
        Assert.AreEqual("First", choices[0].Label);
        Assert.AreEqual("first", choices[0].Value);
        Assert.AreEqual("second", choices[1].Label);
        Assert.AreEqual("second", choices[1].Value);
    }

    private static JsonElement Json(string value)
    {
        using var document = JsonDocument.Parse(value);
        return document.RootElement.Clone();
    }
}
