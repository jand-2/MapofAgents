import Foundation

public enum MapofAgentsWorkflowBridgeSkill {
    public static let name = "mapofagents-workflow-bridge"
    public static let uri = "mapofagents-skill://workflow-bridge"
    public static let contractVersion = "2026-07-21.1"

    public static var mentionCandidate: MentionCandidate {
        MentionCandidate(
            id: "skill:\(uri)",
            kind: .skill,
            trigger: "$",
            label: "$\(name)",
            title: "$\(name)",
            subtitle: "Talk to workflow chats and folders across machines through mapofagents.",
            insertionText: "[$\(name)](\(uri))"
        )
    }

    public static var referenceText: String {
        "[$\(name)](\(uri))"
    }

    public static var instructions: String {
        """
        $\(name)
        Contract version: \(contractVersion)

        You are inside a mapofagents workflow canvas. Workflow chat mentions may refer to Codex, Gemini, or Grok threads. Workflow folder mentions may refer to folders on this machine or another connected machine.

        Rules:
        - Use the Workflow chat references for the target provider, threadID, hostID, model, and reasoning.
        - Use the Workflow folder references for the target hostID, platform, and exact folderPath.
        - Use the Workflow route map before choosing a transport. A `127.0.0.1` route belongs only to the host named in `reachableFromHostID`; do not use it from any other machine.
        - For `route=mapofagents provider relay`, invoke the listed `relayExecutable` with the exact source and target fields. Send only the intended target message on stdin. The app validates that both threads belong to the active canvas, uses its saved provider session, and returns JSON. Treat only `success=true` as delivered. A Gemini or Grok result includes the provider reply when available.
        - Do not load a Gemini or Grok thread through the Codex App Server and do not ask for its cwd. MapofAgents owns that provider session state.
        - Do not automatically retry a failed or ambiguous relay request. Provider turns are not idempotent.
        - For a Codex target with a same-host Codex App Server route, resume the target thread using the exact threadID and the route-authorized cwd when available.
        - For a Codex target on a different host with `currentSourceCanUse=true`, run commands or scripts from your current host to connect to the listed App Server route yourself, then initialize, resume the target thread, and start a turn. Prefer a listed `endpointURL` before creating a new SSH tunnel.
        - Different-host target without a usable route: do not call your local App Server for that target. Your local runtime cannot see another machine's rollout store.
        - If no direct route is usable, say exactly which direct route is missing, such as a WebSocket App Server endpoint reachable from your host or SSH details to create a loopback tunnel. Do not output a `mapofagents bridge request`.
        - Do not claim delivery unless the provider relay returns `success=true`, the App Server request succeeds, or the target thread confirms it.
        - Same-host folder: use normal shell/file tools against the exact absolute folderPath.
        - Different-host folder with `sshFileAccess=true`: use the listed `sshTarget`, `sshPort`, and `identityPath` with `ssh`, `scp`, or `sftp` to read, write, copy, or edit files under the exact folderPath. Quote paths carefully; on Windows targets prefer PowerShell commands through SSH.
        - Different-host folder without `sshFileAccess=true`: do not write to a local path that merely looks like the remote path. Explain the missing SSH route instead.
        - When you intentionally create a materialized App Server child thread with `thread/start`, emit a mapofagents hook event after the `thread/start` succeeds. This lets the canvas show the child thread and orange created edge immediately without guessing from transcript prose.
        - When you intentionally create a new project/workspace root folder, emit a `folder.created` mapofagents hook event after the folder exists. Do not emit it for build folders, cache folders, package folders, or descendants of an existing workflow folder.

        Provider relay command shape:
        - Shell-quote every value copied from the route map.
        - Send the intended target message on stdin:
          `printf '%s' '<message>' | '<relayExecutable>' --source-provider '<sourceProvider>' --source-host '<sourceHostID>' --source-thread '<sourceThreadID>' --target-provider '<targetProvider>' --target-host '<targetHostID>' --target-thread '<targetThreadID>'`
        - Read the JSON printed by the command. `success=true` confirms delivery; `reply` contains a synchronous Gemini or Grok response when available.

        Direct App Server sequence for a usable WebSocket route:
        1. Open the WebSocket URL listed in the Workflow route map.
        2. Send `initialize` with `clientInfo.name="mapofagents-workflow-bridge"` and `capabilities.experimentalApi=true`.
        3. Send `initialized`.
        4. Send `thread/resume` with `threadId=<targetThreadID>` and `cwd=<targetCWD>`.
        5. Send `turn/start` with `threadId=<targetThreadID>`, the message as a text input item, and the target model/effort when provided.

        Materialized child-thread hook event:
        - Send the JSON shape below on stdin to the hardened project helper `script/mapofagents-hook-event.sh thread.created` on the host where the source thread is running.
        - Never append to `$HOME/.codex/mapofagents/hook-events.jsonl` directly. If the hardened helper is unavailable, do not create or modify the event file; report that the hook event could not be emitted.
        - Shape:
          `{"type":"thread.created","sourceHostID":"<sourceHostID>","sourceThreadID":"<sourceThreadID>","sourceTurnID":"<sourceTurnID>","childHostID":"<childHostID>","childThreadID":"<childThreadID>","cwd":"<childCWD>","title":"<childTitle>","kind":"thread"}`
        - Only emit this after an actual App Server `thread/start` response. Do not emit it for Codex subagents, sample IDs, rollout metadata, or unverified prose.

        Materialized folder hook event:
        - Send the JSON shape below on stdin to the hardened project helper `script/mapofagents-hook-event.sh folder.created` on the host where the source thread is running.
        - Never append to `$HOME/.codex/mapofagents/hook-events.jsonl` directly. If the hardened helper is unavailable, do not create or modify the event file; report that the hook event could not be emitted.
        - Shape:
          `{"type":"folder.created","sourceHostID":"<sourceHostID>","sourceThreadID":"<sourceThreadID>","sourceTurnID":"<sourceTurnID>","childHostID":"<childHostID>","folderPath":"<absoluteFolderPath>","title":"<folderTitle>"}`
        - Only emit this for an intentionally materialized workspace/project root, such as a new repo, worktree, experiment folder, or remote Desktop/project folder. Do not emit it for subfolders under a workflow folder.

        Direct tunnel pattern when SSH details are available:
        - Ensure the target host runs `codex app-server --listen ws://127.0.0.1:<remote-port>`.
        - From your current host, run `ssh -N -L <local-port>:127.0.0.1:<remote-port> -i "<identityPath>" -p <sshPort> <sshTarget>`.
        - Quote `identityPath` because app support paths may contain spaces.
        - Connect to `ws://127.0.0.1:<local-port>` and use the App Server sequence above.
        """
    }
}
