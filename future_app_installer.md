# Future App Installer Plan

MapofAgents should ship platform-specific release artifacts from the same
repository. A Mac user should download only the macOS app and dependencies, and
a Windows user should download only the Windows app and dependencies.

## Release Shape

```text
GitHub release or download page:
  MapofAgents-macOS-universal.dmg
  MapofAgents-Windows-x64.msixbundle
  MapofAgents-Windows-x64.appinstaller
```

Optional future artifacts:

```text
MapofAgents-macOS-arm64.dmg
MapofAgents-macOS-x86_64.dmg
MapofAgents-Windows-arm64.msixbundle
MapofAgents-Windows-x64-Setup.exe
```

## CI Foundation

The first step is a Windows CI workflow that proves the Windows app builds in a
clean environment.

Suggested Windows CI checks:

```powershell
cd windows
dotnet restore .\MapofAgents.Windows.sln
dotnet test .\MapofAgents.Windows.sln
dotnet build .\src\MapofAgents.Windows\MapofAgents.Windows.csproj -c Release -r win-x64 -p:Platform=x64
```

The macOS workflow should continue to build and test the SwiftUI/AppKit app on a
macOS runner. CI should verify both platforms, but it should not publish release
artifacts on every pull request.

## Release Pipeline

A tag-based release workflow can publish signed platform artifacts:

```text
tag vX.Y.Z
  macOS runner:
    build SwiftUI/AppKit app
    sign app bundle
    notarize with Apple
    package as DMG or ZIP
    upload macOS artifact

  Windows runner:
    restore, test, and build WinUI 3 app
    package as MSIX/MSIXBundle
    sign package
    generate or update .appinstaller metadata
    upload Windows artifacts
```

## Windows Packaging Work

The current Windows app is an unpackaged desktop app:

```xml
<WindowsPackageType>None</WindowsPackageType>
```

That is fine for local development and private alpha validation. Public or broad
private Windows distribution needs:

- MSIX/MSIXBundle packaging for the WinUI 3 app.
- Package identity, publisher, version, icon, and capability metadata.
- A Windows code-signing certificate.
- Timestamped signing for package and installer artifacts.
- A decision between framework-dependent and self-contained Windows App SDK
  deployment.
- WebView2 runtime handling, either by relying on Evergreen runtime availability
  or by documenting/bootstraping installation.
- An update path, such as App Installer for non-Store distribution or Microsoft
  Store packaging for Store distribution.

## Download Experience

The public download page can either auto-detect the user's operating system or
show explicit platform buttons:

```text
Download for macOS
Download for Windows
```

Each button should link to the matching platform artifact only. The repository
can contain both app implementations, but release artifacts should remain
platform-specific.

## Private Alpha Minimum

For a private Windows alpha, the minimum useful package is:

- Passing Windows CI.
- A signed Windows x64 MSIX/MSIXBundle or signed installer.
- A short install note covering Windows App SDK and WebView2 expectations.
- A clean-machine smoke test covering first install, pairing, transcript loading,
  Thread Inbox, diagnostics, restart, and uninstall.
