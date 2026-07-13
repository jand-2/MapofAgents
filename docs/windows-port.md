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
endpoint validation, local graph storage, legacy pairing compatibility helpers,
remote tunnel helpers, and Codex App Server clients.
`MapofAgents.Windows` contains the WinUI 3 shell and WebView2 graph renderer.
The shared protocol folder provides schema and fixture contracts that can be
used by both the Swift and C# clients.

## Build And Test On Windows

Install the .NET 8 SDK, the Windows App SDK runtime, and the WebView2 Evergreen
runtime, then run:

```powershell
cd windows
dotnet restore .\MapofAgents.Windows.sln --locked-mode
dotnet test .\tests\MapofAgents.Windows.Tests\MapofAgents.Windows.Tests.csproj -c Release --no-restore
dotnet build .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release -r win-x64 -p:Platform=x64 --no-restore
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
  activity, workflow, subagent, feedback, and reading controls, plus an explicit
  unavailable state for secure device enrollment.
- Presents Mac-aligned operational rails, including machines, activity,
  attention requests, diagnostics, selection details, and the bottom-right
  Thread Inbox dock.
- Supports transcript reading surfaces, transcript filtering, loading states,
  tool/error rows, attachment chrome, composer metadata, and send/stop actions.
- Supports thread inbox summaries, workflow filters, search field styling, row
  actions, unread/live status, warning and empty states, and workflow
  membership presentation.
- Handles App Server endpoint validation, remote tunnel diagnostics, app-server
  readiness checks, and token-redacted diagnostic reports.
- Retains legacy pairing implementation pieces for protocol compatibility and
  test coverage, but deliberately hides the pairing host and import panels.
  Windows does not currently generate or consume secure device enrollment
  codes.
- Persists Windows-side graph and preference state under the user's application
  data folder.

## Continuous Integration

The repository's GitHub Actions workflow restores NuGet dependencies in locked
mode, runs the Windows test project, and builds the WinUI client for Release
`win-x64` on a Windows runner. Repository syntax, shared protocol contracts,
public-safety scanning, Swift coverage, and the iOS Simulator build are gated in
the same workflow. See `.github/workflows/ci.yml`.

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

- Implement the same revocable, short-lived secure device enrollment model used
  by the Apple clients before enabling Windows pairing controls.
- Add signed installer/package generation and publishable release artifacts.
- Run first-install, remote App Server, transcript, diagnostics, update, and
  uninstall QA on clean Windows machines, then add pairing QA once secure
  enrollment is implemented.
