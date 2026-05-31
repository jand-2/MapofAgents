import Foundation

public enum SupervisorMachineStatus: String, Codable, Sendable {
    case connected
    case connecting
    case disconnected
    case failed
}

public struct SupervisorMachine: Codable, Identifiable, Hashable, Sendable {
    public var id: HostID
    public var name: String
    public var endpointDescription: String
    public var status: SupervisorMachineStatus
    public var platform: HostPlatform
    public var codexHome: String?
    public var lastEventAt: Date?
    public var lastError: String?

    public init(
        id: HostID,
        name: String,
        endpointDescription: String,
        status: SupervisorMachineStatus = .disconnected,
        platform: HostPlatform = .unknown,
        codexHome: String? = nil,
        lastEventAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.endpointDescription = endpointDescription
        self.status = status
        self.platform = platform
        self.codexHome = codexHome
        self.lastEventAt = lastEventAt
        self.lastError = lastError
    }
}

public struct SupervisorEventEnvelope: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var machineID: HostID
    public var event: WorkflowEvent
    public var receivedAt: Date

    public init(
        id: String = UUID().uuidString,
        machineID: HostID,
        event: WorkflowEvent,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.machineID = machineID
        self.event = event
        self.receivedAt = receivedAt
    }
}

public actor WorkflowSupervisor {
    private var machines: [HostID: SupervisorMachine] = [:]
    private var envelopes: [SupervisorEventEnvelope] = []
    private var seenEventIDs: Set<String> = []
    private var explicitlyDisconnectedMachineIDs: Set<HostID> = []

    public init() {}

    public func upsertMachine(_ machine: SupervisorMachine) {
        machines[machine.id] = machine
        if machine.status != .disconnected {
            explicitlyDisconnectedMachineIDs.remove(machine.id)
        }
    }

    public func updateMachineStatus(_ machineID: HostID, status: SupervisorMachineStatus) {
        guard var machine = machines[machineID] else { return }
        machine.status = status
        if status != .failed {
            machine.lastError = nil
        }
        machines[machineID] = machine
        if status == .disconnected {
            explicitlyDisconnectedMachineIDs.insert(machineID)
        } else {
            explicitlyDisconnectedMachineIDs.remove(machineID)
        }
    }

    public func updateMachineFailure(_ machineID: HostID, message: String) {
        guard var machine = machines[machineID] else { return }
        machine.status = .failed
        machine.lastError = message
        machines[machineID] = machine
        explicitlyDisconnectedMachineIDs.remove(machineID)
    }

    @discardableResult
    public func ingest(_ event: WorkflowEvent, from machineID: HostID) -> SupervisorEventEnvelope? {
        var normalizedEvent = event
        normalizedEvent.hostID = normalizedEvent.hostID ?? machineID
        if let dedupeKey = normalizedEvent.semanticDedupeKey {
            guard seenEventIDs.insert(dedupeKey).inserted else {
                return nil
            }
        }

        let envelope = SupervisorEventEnvelope(machineID: machineID, event: normalizedEvent)
        envelopes.insert(envelope, at: 0)
        envelopes = Array(envelopes.prefix(300))
        seenEventIDs = Set(envelopes.compactMap(\.event.semanticDedupeKey))

        if var machine = machines[machineID] {
            if !explicitlyDisconnectedMachineIDs.contains(machineID) {
                machine.status = .connected
            }
            machine.lastEventAt = envelope.receivedAt
            machine.lastError = nil
            machines[machineID] = machine
        }

        return envelope
    }

    public func machineSnapshot() -> [SupervisorMachine] {
        machines.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func recentEvents(limit: Int = 100) -> [SupervisorEventEnvelope] {
        Array(envelopes.prefix(limit))
    }
}
