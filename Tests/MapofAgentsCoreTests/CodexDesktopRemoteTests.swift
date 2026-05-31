import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func codexDesktopRemoteDiscoveryParsesManagedConnections() throws {
    let json = """
    {
      "version": 1,
      "codex-managed-remote-connections": [
        {
          "alias": null,
          "displayName": "Windows DESKTOP-EXAMPLE",
          "hostId": "remote-ssh-codex-managed:Windows%20DESKTOP-EXAMPLE",
          "hostname": "User@windows.example.ts.net",
          "identity": "/Users/example/.ssh/codex_example",
          "source": "codex-managed",
          "sshPort": 22
        },
        {
          "alias": "windows-erp",
          "displayName": "windows-erp",
          "hostId": "remote-ssh-discovered:windows-erp",
          "hostname": null,
          "identity": null,
          "source": "discovered",
          "sshPort": null
        }
      ]
    }
    """.data(using: .utf8)!

    let remotes = try CodexDesktopRemoteService.remotes(from: json)
    let managedRemote = try #require(remotes.first)

    #expect(managedRemote.displayName == "Windows DESKTOP-EXAMPLE")
    #expect(managedRemote.hostname == "User@windows.example.ts.net")
    #expect(managedRemote.identityPath == "/Users/example/.ssh/codex_example")
    #expect(managedRemote.sshPort == 22)
    #expect(managedRemote.source == "codex-managed")
    #expect(managedRemote.platform == .windows)
    #expect(managedRemote.isConnectable)
    #expect(remotes.last?.isConnectable == false)
}

@Test
func codexDesktopRemoteDiscoveryRejectsUnsafeSSHTargets() throws {
    let json = """
    {
      "codex-managed-remote-connections": [
        {
          "displayName": "Unsafe",
          "hostId": "remote-ssh-codex-managed:Unsafe",
          "hostname": "-oProxyCommand=touch /tmp/nope",
          "identity": null,
          "source": "codex-managed",
          "sshPort": 22
        }
      ]
    }
    """.data(using: .utf8)!

    let remotes = try CodexDesktopRemoteService.remotes(from: json)

    #expect(remotes.first?.hostname == nil)
    #expect(remotes.first?.isConnectable == false)
    #expect(CodexDesktopRemoteService.isValidSSHTarget("User@windows.example.ts.net"))
    #expect(CodexDesktopRemoteService.isValidSSHTarget("User@windows.example.ts.net -oProxyCommand=nope") == false)
}
