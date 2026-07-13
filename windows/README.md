# MapofAgents Windows

This folder contains the Windows-native MapofAgents client. The app uses a
WinUI 3 shell for the Windows window, command surface, rails, and native
controls, with a WebView2 graph renderer for the map canvas.

## Build

Install the .NET 8 SDK, the Windows App SDK runtime, and the WebView2 Evergreen
runtime, then run from this folder:

```powershell
dotnet restore .\MapofAgents.Windows.sln --locked-mode
dotnet test .\tests\MapofAgents.Windows.Tests\MapofAgents.Windows.Tests.csproj -c Release --no-restore
dotnet build .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release -r win-x64 -p:Platform=x64 --no-restore
dotnet run --project .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release
```

The current app project targets `win-x64` so the WebView2 native loader is
copied next to the executable. The WebView2 Evergreen runtime must be installed
on the Windows machine.

## Shape

- `src/MapofAgents.Core`: portable graph models, persistence, endpoint
  validation, legacy pairing compatibility helpers, remote tunnel helpers,
  presentation metrics, and Codex App Server clients.
- `src/MapofAgents.Windows`: WinUI 3 desktop shell and WebView2 graph renderer.
- `tests/MapofAgents.Windows.Tests`: portable tests for core Windows behavior.

The app stores local graph state at:

```text
%APPDATA%\MapofAgents\control-room.json
```

## Secure Enrollment Status

Secure device enrollment is not yet available in the Windows client. The UI
shows an unavailable state and hides the legacy pairing host and import panels;
legacy pairing-related code in `MapofAgents.Core` is retained for compatibility
and test coverage. Do not treat it as a supported pairing path.

The macOS/iOS implementation uses one-time enrollment over private Tailscale
Serve HTTPS, a revocable refresh credential stored in Keychain, and access
tokens that last at most five minutes. Windows pairing must adopt an equivalent
model before its controls are enabled.

## Continuous Integration

`.github/workflows/ci.yml` restores this solution in locked mode, runs the
Windows tests, and builds the WinUI project for Release `win-x64` on a Windows
runner. Local macOS development cannot replace that native WinUI build check.
