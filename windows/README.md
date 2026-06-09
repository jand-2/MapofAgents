# MapofAgents Windows

This folder contains the Windows-native MapofAgents client. The app uses a
WinUI 3 shell for the Windows window, command surface, rails, and native
controls, with a WebView2 graph renderer for the map canvas.

## Build

Install the .NET 8 SDK, the Windows App SDK runtime, and the WebView2 Evergreen
runtime, then run from this folder:

```powershell
dotnet restore .\MapofAgents.Windows.sln
dotnet test .\MapofAgents.Windows.sln -c Release
dotnet build .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release -r win-x64 -p:Platform=x64
dotnet run --project .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release
```

The current app project targets `win-x64` so the WebView2 native loader is
copied next to the executable. The WebView2 Evergreen runtime must be installed
on the Windows machine.

## Shape

- `src/MapofAgents.Core`: portable graph models, persistence, endpoint
  validation, pairing, remote tunnel helpers, presentation metrics, and Codex
  App Server clients.
- `src/MapofAgents.Windows`: WinUI 3 desktop shell and WebView2 graph renderer.
- `tests/MapofAgents.Windows.Tests`: portable tests for core Windows behavior.

The app stores local graph state at:

```text
%APPDATA%\MapofAgents\control-room.json
```
