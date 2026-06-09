import Foundation

public enum MapofAgentsWorkflowBridgeSkill {
    public static let name = "mapofagents-workflow-bridge"
    public static let uri = "mapofagents-skill://workflow-bridge"
    public static let contractVersion = "2026-05-28.1"

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

        You are inside a mapofagents workflow canvas. Workflow chat mentions may refer to Codex threads on this machine or on another connected machine. Workflow folder mentions may refer to folders on this machine or another connected machine.

        Rules:
        - Use the Workflow chat references for the target threadID, hostID, cwd, model, and reasoning.
        - Use the Workflow folder references for the target hostID, platform, and exact folderPath.
        - Use the Workflow route map before choosing a transport. A `127.0.0.1` route belongs only to the host named in `reachableFromHostID`; do not use it from any other machine.
        - You are responsible for chat delivery and folder/file work. mapofagents will not forward a bridge request or perform remote file writes for you.
        - Same-host target: resume the target thread through the Codex App Server for this host, using the exact threadID and cwd from mapofagents.
        - Different-host target with `currentSourceCanUse=true`: run commands or scripts from your current host to connect to the listed App Server route yourself, then initialize, resume the target thread, and start a turn. Prefer a listed `endpointURL` before creating a new SSH tunnel.
        - Different-host target without a usable route: do not call your local App Server for that target. Your local runtime cannot see another machine's rollout store.
        - If no direct route is usable, say exactly which direct route is missing, such as a WebSocket App Server endpoint reachable from your host or SSH details to create a loopback tunnel. Do not output a `mapofagents bridge request`.
        - Do not claim delivery unless the App Server request succeeds or the target thread confirms it.
        - Same-host folder: use normal shell/file tools against the exact absolute folderPath.
        - Different-host folder with `sshFileAccess=true`: use the listed `sshTarget`, `sshPort`, and `identityPath` with `ssh`, `scp`, or `sftp` to read, write, copy, or edit files under the exact folderPath. Quote paths carefully; on Windows targets prefer PowerShell commands through SSH.
        - Different-host folder without `sshFileAccess=true`: do not write to a local path that merely looks like the remote path. Explain the missing SSH route instead.
        - When you intentionally create a materialized App Server child thread with `thread/start`, emit a mapofagents hook event after the `thread/start` succeeds. This lets the canvas show the child thread and orange created edge immediately without guessing from transcript prose.
        - When you intentionally create a new project/workspace root folder, emit a `folder.created` mapofagents hook event after the folder exists. Do not emit it for build folders, cache folders, package folders, or descendants of an existing workflow folder.

        Direct App Server sequence for a usable WebSocket route:
        1. Open the WebSocket URL listed in the Workflow route map.
        2. Send `initialize` with `clientInfo.name="mapofagents-workflow-bridge"` and `capabilities.experimentalApi=true`.
        3. Send `initialized`.
        4. Send `thread/resume` with `threadId=<targetThreadID>` and `cwd=<targetCWD>`.
        5. Send `turn/start` with `threadId=<targetThreadID>`, the message as a text input item, and the target model/effort when provided.

        Materialized child-thread hook event:
        - Append one JSON line to `$HOME/.codex/mapofagents/hook-events.jsonl` on the host where the source thread is running, or call the project helper `script/mapofagents-hook-event.sh thread.created` when available.
        - Shape:
          `{"type":"thread.created","sourceHostID":"<sourceHostID>","sourceThreadID":"<sourceThreadID>","sourceTurnID":"<sourceTurnID>","childHostID":"<childHostID>","childThreadID":"<childThreadID>","cwd":"<childCWD>","title":"<childTitle>","kind":"thread"}`
        - Only emit this after an actual App Server `thread/start` response. Do not emit it for Codex subagents, sample IDs, rollout metadata, or unverified prose.

        Materialized folder hook event:
        - Append one JSON line to `$HOME/.codex/mapofagents/hook-events.jsonl` on the host where the source thread is running, or call the project helper `script/mapofagents-hook-event.sh folder.created` when available.
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
