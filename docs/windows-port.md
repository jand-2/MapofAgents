# Windows Port

MapofAgents has an in-repo native Windows client under `windows/`. The Windows
app uses a WinUI 3 desktop shell for the window, command surface, rails, and
native controls, with a WebView2 renderer for the graph canvas. It targets
`.NET 8` and talks to Codex App Server through the same WebSocket JSON-RPC
boundary as the Swift app.

For day-to-day Windows build notes, see `windows/README.md`.

## Repository Layout

```text
windows/
  MapofAgents.Windows.sln
  src/MapofAgents.Core/
  src/MapofAgents.Windows/
  tests/MapofAgents.Windows.Tests/
shared/
  protocol/
    app-server.schema.json
    graph.schema.json
    fixtures/
```

`MapofAgents.Core` contains portable Windows-side models, presentation metrics,
endpoint validation, local graph storage, pairing, remote tunnel helpers, and
Codex App Server clients. `MapofAgents.Windows` contains the WinUI 3 shell and
WebView2 graph renderer. The shared protocol folder provides schema and fixture
contracts that can be used by both the Swift and C# clients.

## Build And Test On Windows

Install the .NET 8 SDK, the Windows App SDK runtime, and the WebView2 Evergreen
runtime, then run:

```powershell
cd windows
dotnet restore .\MapofAgents.Windows.sln
dotnet test .\MapofAgents.Windows.sln
dotnet build .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release -r win-x64 -p:Platform=x64
dotnet run --project .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release
```

The app stores its local graph at:

```text
%APPDATA%\MapofAgents\control-room.json
```

## Current Scope

- Renders the MapofAgents canvas through WebView2, including nodes, semantic
  edges, selection state, manual link source state, and dark-grid presentation.
- Provides a WinUI 3 command surface with creation, search, arrange, health,
  pairing, activity, workflow, subagent, feedback, and reading controls.
- Presents Mac-aligned operational rails, including machines, activity,
  attention requests, diagnostics, selection details, and the bottom-right
  Thread Inbox dock.
- Supports transcript reading surfaces, transcript filtering, loading states,
  tool/error rows, attachment chrome, composer metadata, and send/stop actions.
- Supports thread inbox summaries, workflow filters, search field styling, row
  actions, unread/live status, warning and empty states, and workflow
  membership presentation.
- Handles App Server endpoint validation, local and remote pairing payloads,
  signed bearer pairing, remote tunnel diagnostics, app-server readiness checks,
  and token-redacted diagnostic reports.
- Persists Windows-side graph and preference state under the user's application
  data folder.

## Packaging Status

The current Windows app is still built as an unpackaged desktop app:

```xml
<WindowsPackageType>None</WindowsPackageType>
```

That is acceptable for local development and private alpha validation, but it is
not the final distribution shape. Public or broad private distribution still
needs MSIX/MSIXBundle packaging, code signing, timestamping, release artifacts,
and an update path such as App Installer or Microsoft Store distribution.

## Release Readiness

The Windows client is now a real native companion app rather than a proof of
life. Before a public Windows launch, the remaining release work is:

- Wire Windows CI for restore, test, Release x64 build, and sensitive-string
  scans.
- Add signed installer/package generation and publishable release artifacts.
- Run first-install, pairing, remote App Server, transcript, diagnostics,
  update, and uninstall QA on clean Windows machines.
