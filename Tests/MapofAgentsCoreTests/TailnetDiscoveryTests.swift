import Foundation
import Testing
@testable import MapofAgentsCore

@Test
func tailnetDiscoveryParsesTailscaleStatusPeers() throws {
    let data = Data(
        """
        {
          "Peer": {
            "nodekey:abc": {
              "ID": "n1",
              "PublicKey": "nodekey:abc",
              "HostName": "desktop",
              "DNSName": "desktop.example.ts.net.",
              "OS": "windows",
              "TailscaleIPs": ["100.64.0.10", "fd7a:115c:a1e0::10"],
              "Online": true,
              "LastSeen": "2026-05-21T05:45:12.123456789Z"
            },
            "nodekey:def": {
              "ID": "n2",
              "HostName": "laptop",
              "OS": "macOS",
              "TailscaleIPs": ["100.64.0.11"],
              "Online": false
            }
          }
        }
        """.utf8
    )

    let machines = try TailnetDiscoveryService.machines(from: data)

    #expect(machines.map(\.name) == ["desktop", "laptop"])
    #expect(machines.first?.dnsName == "desktop.example.ts.net")
    #expect(machines.first?.platform == .windows)
    #expect(machines.first?.isOnline == true)
    #expect(machines.first?.suggestedWebSocketEndpoint() == "wss://desktop.example.ts.net:18945")
    #expect(machines.last?.platform == .macOS)
    #expect(machines.last?.isOnline == false)
}

@Test
func boundedProcessRunnerDrainsStdoutAndStderrConcurrently() async throws {
    let script = """
    i=0
    while [ "$i" -lt 5000 ]; do
      printf 'stdout-%04d\\n' "$i"
      printf 'stderr-%04d\\n' "$i" >&2
      i=$((i + 1))
    done
    """

    let result = try await BoundedProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", script],
        timeout: 5,
        maxOutputBytes: 4_096
    )

    #expect(result.terminationStatus == 0)
    #expect(result.stdout.wasTruncated)
    #expect(result.stderr.wasTruncated)
    #expect(result.stdout.stringValue.contains("stdout-0000"))
    #expect(result.stderr.stringValue.contains("stderr-0000"))
}
