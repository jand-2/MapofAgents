import Testing
@testable import MapofAgentsCore

@Test
func threadPermissionsEncodeLaunchParams() {
    let permissions = CodexThreadPermissions(
        approvalPolicy: .onRequest,
        sandboxMode: .dangerFullAccess
    )

    let params = permissions.threadParams()
    #expect(params["approvalPolicy"] == .string("on-request"))
    #expect(params["sandbox"] == .string("danger-full-access"))
}

@Test
func threadStartParamsExcludeDeprecatedExtendedHistoryFlag() {
    let params = CodexRuntimeStore.threadStartParams(
        cwd: "/tmp/project",
        model: "gpt-5.5",
        permissions: CodexThreadPermissions(
            approvalPolicy: .onFailure,
            sandboxMode: .workspaceWrite
        )
    )

    #expect(params["cwd"] == .string("/tmp/project"))
    #expect(params["model"] == .string("gpt-5.5"))
    #expect(params["experimentalRawEvents"] == .bool(false))
    #expect(params["approvalPolicy"] == .string("on-failure"))
    #expect(params["sandbox"] == .string("workspace-write"))
    #expect(params["persistExtendedHistory"] == nil)
}

@Test
func threadPermissionsEncodeSandboxPolicies() {
    let fullAccess = CodexSandboxMode.dangerFullAccess.sandboxPolicy(cwd: "/tmp/project")
    #expect(fullAccess == .object(["type": .string("dangerFullAccess")]))

    let readOnly = CodexSandboxMode.readOnly.sandboxPolicy(cwd: "/tmp/project")
    #expect(readOnly == .object([
        "type": .string("readOnly"),
        "networkAccess": .bool(true),
    ]))

    let workspaceWrite = CodexSandboxMode.workspaceWrite.sandboxPolicy(cwd: "/tmp/project")
    #expect(workspaceWrite["type"] == .string("workspaceWrite"))
    #expect(workspaceWrite["writableRoots"] == .array([.string("/tmp/project")]))
    #expect(workspaceWrite["networkAccess"] == .bool(true))
    #expect(workspaceWrite["excludeTmpdirEnvVar"] == .bool(false))
    #expect(workspaceWrite["excludeSlashTmp"] == .bool(false))
}

@Test
func attentionApprovalResponsesPreserveRequestedPermissions() {
    let request = RuntimeAttentionRequest(
        id: "local::7",
        hostID: HostID(rawValue: "local"),
        requestID: .int(7),
        method: "item/permissions/requestApproval",
        threadID: "thread",
        summary: "permissions",
        requestParams: .object([
            "permissions": .object([
                "network": .bool(true),
            ]),
        ])
    )

    #expect(request.appServerApprovalResult(allow: true) == .object([
        "permissions": .object(["network": .bool(true)]),
        "scope": .string("session"),
    ]))
    #expect(request.appServerApprovalResult(allow: false) == .object([
        "permissions": .object([:]),
        "scope": .string("turn"),
    ]))
}

@Test
func attentionRequestsPreserveStringRequestIDs() {
    let notification = CodexServerNotification(
        method: "item/commandExecution/requestApproval",
        params: .object([
            "threadId": .string("thread"),
            "command": .string("date"),
        ]),
        requestID: .string("approval-1")
    )

    let request = RuntimeAttentionRequest.appServerRequest(
        from: notification,
        hostID: HostID(rawValue: "remote")
    )

    #expect(request?.id == "remote::approval-1")
    #expect(request?.requestID == .string("approval-1"))
    #expect(request?.appServerApprovalResult(allow: true) == .object([
        "decision": .string("accept"),
    ]))
}

@Test
func typedAttentionResponseEncodesRequestUserInputAnswers() {
    let request = RuntimeAttentionRequest(
        id: "local::input",
        hostID: HostID(rawValue: "local"),
        requestID: .string("input"),
        method: "item/tool/requestUserInput",
        threadID: "thread",
        summary: "Pick a mode",
        requestParams: .object([
            "questions": .array([
                .object([
                    "id": .string("mode"),
                    "question": .string("Pick a mode"),
                ]),
            ]),
        ])
    )

    #expect(request.supportsTypedResponse)
    #expect(request.promptText == "Pick a mode")
    #expect(request.appServerTextResponseResult("safe") == .object([
        "answers": .object([
            "mode": .object([
                "answers": .array([.string("safe")]),
            ]),
        ]),
    ]))
}

@Test
func attentionRequestTargetThreadRefUsesDefaultAndRemoteHosts() {
    let local = RuntimeAttentionRequest(
        id: "local::input",
        hostID: nil,
        requestID: .string("input"),
        method: "item/tool/requestUserInput",
        threadID: "thread-local",
        summary: "Input",
        requestParams: .object([
            "cwd": .string("/tmp/local"),
        ])
    )
    let remote = RuntimeAttentionRequest(
        id: "remote::input",
        hostID: HostID(rawValue: "remote"),
        requestID: .string("input"),
        method: "item/tool/requestUserInput",
        threadID: "thread-remote",
        summary: "Input",
        requestParams: .object([
            "workingDirectory": .string("C:\\\\Users\\\\User\\\\Project"),
        ])
    )

    #expect(local.targetThreadRef(defaultHostID: HostID(rawValue: "local")) == ThreadRef(
        hostID: HostID(rawValue: "local"),
        threadID: "thread-local",
        cwd: "/tmp/local",
        name: nil
    ))
    #expect(remote.targetThreadRef(defaultHostID: HostID(rawValue: "local")) == ThreadRef(
        hostID: HostID(rawValue: "remote"),
        threadID: "thread-remote",
        cwd: "C:\\\\Users\\\\User\\\\Project",
        name: nil
    ))
}

@Test
func typedAttentionResponseEncodesElicitationAcceptAndDecline() {
    let request = RuntimeAttentionRequest(
        id: "remote::elicit",
        hostID: HostID(rawValue: "remote"),
        requestID: .string("elicit"),
        method: "mcpServer/elicitation/request",
        threadID: "thread",
        summary: "Need form input"
    )

    #expect(request.appServerTextResponseResult("approved") == .object([
        "action": .string("accept"),
        "content": .object(["response": .string("approved")]),
    ]))
    #expect(request.appServerTextDeclineResult() == .object([
        "action": .string("decline"),
        "content": .null,
    ]))
}

@Test
func typedAttentionResponseUsesMcpElicitationSchemaFields() {
    let request = RuntimeAttentionRequest(
        id: "remote::elicit",
        hostID: HostID(rawValue: "remote"),
        requestID: .string("elicit"),
        method: "mcpServer/elicitation/request",
        threadID: "thread",
        summary: "Need form input",
        requestParams: .object([
            "message": .string("Enter approval details"),
            "requestedSchema": .object([
                "type": .string("object"),
                "properties": .object([
                    "email": .object([
                        "type": .string("string"),
                    ]),
                    "confirmed": .object([
                        "type": .string("boolean"),
                    ]),
                ]),
                "required": .array([.string("email"), .string("confirmed")]),
            ]),
        ])
    )

    #expect(request.promptText == "Enter approval details")
    #expect(request.appServerTextResponseResult(#"{"email":"dev@example.com","confirmed":true}"#) == .object([
        "action": .string("accept"),
        "content": .object([
            "confirmed": .bool(true),
            "email": .string("dev@example.com"),
        ]),
    ]))
}

@Test
func typedAttentionResponseUsesSingleEnumOption() {
    let request = RuntimeAttentionRequest(
        id: "remote::elicit",
        hostID: HostID(rawValue: "remote"),
        requestID: .string("elicit"),
        method: "mcpServer/elicitation/request",
        threadID: "thread",
        summary: "Pick action",
        requestParams: .object([
            "requestedSchema": .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "enum": .array([.string("allow"), .string("deny")]),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
        ])
    )

    #expect(request.typedResponseOptions == ["allow", "deny"])
    #expect(request.typedResponseChoices.map(\.label) == ["allow", "deny"])
    #expect(request.initialTypedResponseValue == "allow")
    #expect(request.appServerTextResponseResult("deny") == .object([
        "action": .string("accept"),
        "content": .object([
            "action": .string("deny"),
        ]),
    ]))
}

@Test
func typedAttentionResponseUsesTitledOneOfConstValues() {
    let request = RuntimeAttentionRequest(
        id: "remote::elicit",
        hostID: HostID(rawValue: "remote"),
        requestID: .string("elicit"),
        method: "mcpServer/elicitation/request",
        threadID: "thread",
        summary: "Pick action",
        requestParams: .object([
            "requestedSchema": .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "oneOf": .array([
                            .object([
                                "const": .string("allow"),
                                "title": .string("Allow this command"),
                            ]),
                            .object([
                                "const": .string("deny"),
                                "title": .string("Deny this command"),
                            ]),
                        ]),
                        "default": .string("deny"),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
        ])
    )

    #expect(request.typedResponseOptions == ["allow", "deny"])
    #expect(request.typedResponseChoices.map(\.label) == ["Allow this command", "Deny this command"])
    #expect(request.initialTypedResponseValue == "deny")
    #expect(request.appServerTextResponseResult(request.initialTypedResponseValue) == .object([
        "action": .string("accept"),
        "content": .object([
            "action": .string("deny"),
        ]),
    ]))
    #expect(request.appServerTextResponseResult("Allow this command") == .object([
        "action": .string("accept"),
        "content": .object([
            "action": .string("allow"),
        ]),
    ]))
    #expect(request.appServerTextResponseResult("") == .object([
        "action": .string("accept"),
        "content": .object([
            "action": .string("deny"),
        ]),
    ]))
}

@Test
func typedAttentionResponseUsesFirstTitledOneOfOptionWhenDefaultIsMissing() {
    let request = RuntimeAttentionRequest(
        id: "remote::elicit",
        hostID: HostID(rawValue: "remote"),
        requestID: .string("elicit"),
        method: "mcpServer/elicitation/request",
        threadID: "thread",
        summary: "Pick action",
        requestParams: .object([
            "requestedSchema": .object([
                "type": .string("object"),
                "properties": .object([
                    "action": .object([
                        "type": .string("string"),
                        "oneOf": .array([
                            .object(["const": .string("allow"), "title": .string("Allow this command")]),
                            .object(["const": .string("deny"), "title": .string("Deny this command")]),
                        ]),
                    ]),
                ]),
                "required": .array([.string("action")]),
            ]),
        ])
    )

    #expect(request.typedResponseChoices.map(\.label) == ["Allow this command", "Deny this command"])
    #expect(request.initialTypedResponseValue == "allow")
    #expect(request.appServerTextResponseResult(request.initialTypedResponseValue) == .object([
        "action": .string("accept"),
        "content": .object([
            "action": .string("allow"),
        ]),
    ]))
}

@Test
func typedAttentionResponseLeavesArrayEnumsAsJsonTextInput() {
    let request = RuntimeAttentionRequest(
        id: "remote::elicit",
        hostID: HostID(rawValue: "remote"),
        requestID: .string("elicit"),
        method: "mcpServer/elicitation/request",
        threadID: "thread",
        summary: "Pick actions",
        requestParams: .object([
            "requestedSchema": .object([
                "type": .string("object"),
                "properties": .object([
                    "actions": .object([
                        "type": .string("array"),
                        "items": .object([
                            "oneOf": .array([
                                .object(["const": .string("allow"), "title": .string("Allow")]),
                                .object(["const": .string("deny"), "title": .string("Deny")]),
                            ]),
                        ]),
                    ]),
                ]),
            ]),
        ])
    )

    #expect(request.typedResponseChoices.isEmpty)
    #expect(request.appServerTextResponseResult(#"{"actions":["allow","deny"]}"#) == .object([
        "action": .string("accept"),
        "content": .object([
            "actions": .array([.string("allow"), .string("deny")]),
        ]),
    ]))
}
