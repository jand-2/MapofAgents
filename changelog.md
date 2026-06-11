# Changelog

This changelog documents every commit in the public `MapofAgents` history.
Entries are ordered from oldest to newest.

## d170134 - Initial public release

Date: 2026-05-31

- Published the initial macOS/iOS Swift package and application sources.
- Added the graph canvas, node and edge models, workflow persistence, runtime stores, supervisor services, and Codex App Server client integration.
- Added thread reading, thread creation, workflow activity, machine panels, pairing, iPhone companion views, and remote tunnel foundations.
- Added Apache-2.0 licensing, NOTICE attribution, README documentation, examples, scripts, tests, and public demo media.

## 2399221 - Add remote runtime diagnostics popout

Date: 2026-06-02

- Added a diagnostics popout for remote Codex runtime setup and recovery.
- Improved remote tunnel checks, endpoint verification, identity handling, and supervisor status reporting.
- Added tests for app-server verification and remote route diagnostics.

## b024d3b - Add remote folder picker

Date: 2026-06-02

- Added a remote folder picker UI for browsing project folders on connected machines.
- Extended remote tunnel services to list folders on supported remote hosts.
- Wired folder selection into the canvas and machine panel flows.
- Added route and folder-browser tests.

## 805e1c7 - Refine canvas side panels

Date: 2026-06-02

- Refined the operational rails and side-panel layout on the graph canvas.
- Adjusted thread inbox and panel presentation details for a cleaner workspace UI.

## 8510a61 - Add Windows preview app

Date: 2026-06-09

- Added a native Windows preview app under `windows/` using C#/.NET and WinUI 3.
- Added shared graph and app-server protocol schemas and sample fixtures.
- Added Windows graph models, App Server client code, pairing support, remote tunnel helpers, presentation models, and the main WinUI shell.
- Added Windows tests for graph behavior, pairing, routing, transcript presentation, diagnostics, folder actions, and UI presentation logic.
- Documented the Windows port status and added repository contributor guidance in `AGENTS.md`.

## cf5808d - Document future app installer plan

Date: 2026-06-09

- Added `future_app_installer.md`.
- Captured packaging, signing, update, release, and cross-platform installer considerations for future distribution work.

## efd7769 - Recover Codex remote routes after drops

Date: 2026-06-09

- Improved recovery behavior for Codex remote routes after relay or connection drops.
- Added supervisor logic for staged endpoint attempts and safer route restoration.
- Added tests for route recovery and endpoint replacement behavior.

## c67f655 - Add folder-created workflow materialization

Date: 2026-06-09

- Added `folder.created` workflow events for materializing newly created workspace roots on the canvas.
- Added Codex `PostToolUse` hook support for detecting successful root-folder creation from shell commands.
- Added hook installation scripts and event emission through `script/mapofagents-hook-event.sh`.
- Added graph materialization rules that create folder nodes under the correct machine and ignore descendant/cache folders.
- Updated the Swift app, iPhone surface, activity rail, visibility model, and notifications to understand folder-created events.
- Added tests for hook parsing, event parsing, folder materialization, and descendant-folder filtering.

## 8e5f6db - Add Windows workflow event delivery

Date: 2026-06-09

- Added shared workflow-event schema and a `folder-created` fixture.
- Added Windows workflow event parsing, event-file watching, and folder materialization support.
- Wired Windows workflow events into the WinUI application shell.
- Added Windows tests for workflow events and folder materialization.
- Added shared Swift tests for the shared workflow event fixture.

## 40d6a35 - Add machine dropdown and shared app-server setup

Date: 2026-06-09

- Moved Machines into a toolbar dropdown next to the workflow selector.
- Added local machine setup from the Machines menu so new installs can start or reuse a local Codex App Server.
- Taught remote recovery to reuse authenticated Windows app-data app-server sessions.
- Cleaned PowerShell CLIXML output so Windows recovery errors show readable port/auth details.
- Added Swift and Windows tests for shared app-server token reuse and CLIXML cleanup.

## 5670701 - Start Windows threads through app-server

Date: 2026-06-09

- Added Windows App Server client calls for `thread/start`, `thread/name/set`, and `turn/start`.
- Wired Windows thread creation to create real Codex threads and optionally start the first turn.
- Added automatic local App Server reconnect when creating local Windows threads.
- Increased local App Server initialize patience and improved initialize failure messages.
- Added Windows tests for thread creation, turn start, and best-effort initialize socket shutdown.

## f96bd5a - Show folder contents from canvas nodes

Date: 2026-06-10

- Added a folder-node context-menu action for showing folder contents.
- Opened local folder nodes in Finder on macOS and Explorer on Windows.
- Reused the remote folder browser in a read-only contents mode for remote folder nodes.
- Kept the existing remote project picker behavior for adding folders.

## 2c5f7c5 - Simplify remote diagnostics flow

Date: 2026-06-10

- Removed the Health toolbar menu and moved connection refresh into the Machines popover when a machine needs attention.
- Simplified Codex remote rows so successful remotes stay compact and remote diagnostics appear only for failed or warning states.
- Added a machine-node context-menu action for opening Codex remote diagnostics.
- Shortened the Windows remote app-server start command to avoid PowerShell SSH command-length parsing failures.
- Made restart recovery skip untracked occupied app-server ports and continue through configured port candidates.

## 546cfd0 - Refine Windows machine diagnostics UI

Date: 2026-06-10

- Removed the Windows Health toolbar presentation now that Machines owns connection recovery.
- Added compact Codex remote diagnostics summaries that stay quiet when checks pass and expose Remote Diagnostics only for warning or failed states.
- Added a conditional connection refresh row for local runtime, remote route, and diagnostics attention states.
- Synced local App Server status from graph routes and cleared stale local endpoint registrations when routes are removed.
- Added Windows presentation tests for diagnostics summaries and updated machine action tests.

## 4854d7c - Add thread automation controls

Date: 2026-06-11

- Added local Codex automation discovery for thread-linked automations.
- Added alarm indicators on macOS thread nodes and open thread windows.
- Added an in-canvas automation editor for name, prompt, status, and schedule changes with Daily, Weekly, and Custom RRULE controls.
- Added next-run display and focused Swift tests for automation parsing, scheduling, and saving.

## 4c5a238 - Add Windows thread automation controls

Date: 2026-06-11

- Added Windows Codex automation discovery, scheduling, and TOML update support.
- Added alarm indicators to Windows graph nodes, node context menus, and thread popovers.
- Added a Windows automation editing dialog with matching status, prompt, and schedule controls.
- Added Windows presentation and automation store tests.
