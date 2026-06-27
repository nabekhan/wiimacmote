import Foundation
import Network

struct DiagnosticDSURumbleCommand {
    let slot: Int
    let intensity: UInt8
}

final class DiagnosticDSUServer {
    var onRumble: ((DiagnosticDSURumbleCommand) -> Void)?
    var onStateChanged: ((_ isRunning: Bool, _ clientCount: Int, _ error: String?) -> Void)?

    private enum MessageType {
        static let protocolVersion: UInt32 = 0x100000
        static let controllerInfo: UInt32 = 0x100001
        static let controllerData: UInt32 = 0x100002
        static let motorInfo: UInt32 = 0x110001
        static let rumble: UInt32 = 0x110002
    }

    private enum Subscription: Hashable {
        case all
        case slot(Int)
        case mac([UInt8])
    }

    private struct ParsedPacket {
        let messageType: UInt32
        let payload: [UInt8]
    }

    private struct ClientState {
        let connection: NWConnection
        var subscriptions = Set<Subscription>()
        var packetCounter: UInt32 = 0
        var lastSeen = Date()
        var rumbleDeadlines: [Int: Date] = [:]
    }

    private let port: UInt16
    private let serverID = UInt32.random(in: 1...UInt32.max)
    private let queue = DispatchQueue(label: "dev.wiimacmote.diagnostics.dsu")
    private var listener: NWListener?
    private var clients: [UUID: ClientState] = [:]
    private var controllers: [Int: ControllerRuntimeSnapshot] = [:]
    private var isRunning = false
    private var sendTimer: DispatchSourceTimer?

    init(port: UInt16) {
        self.port = port
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    func updateControllers(_ snapshots: [ControllerRuntimeSnapshot]) {
        queue.async { [weak self] in
            self?.controllers = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.slot, $0) })
        }
    }

    private func startOnQueue() {
        guard listener == nil else {
            notifyState(error: nil)
            return
        }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            notifyState(isRunning: false, error: "Invalid DSU port \(port).")
            return
        }

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        do {
            let listener = try NWListener(using: parameters, on: endpointPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                self?.handleListenerState(state)
            }
            self.listener = listener
            listener.start(queue: queue)
            startSendTimer()
        } catch {
            notifyState(isRunning: false, error: error.localizedDescription)
        }
    }

    private func stopOnQueue() {
        sendTimer?.cancel()
        sendTimer = nil
        listener?.cancel()
        listener = nil
        for client in clients.values {
            client.connection.cancel()
        }
        clients.removeAll()
        isRunning = false
        notifyState(isRunning: false, error: nil)
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            isRunning = true
            notifyState(error: nil)
        case .failed(let error):
            isRunning = false
            listener = nil
            notifyState(isRunning: false, error: error.localizedDescription)
        case .cancelled:
            isRunning = false
            notifyState(isRunning: false, error: nil)
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard isLoopback(connection.endpoint) else {
            connection.cancel()
            return
        }

        let id = UUID()
        clients[id] = ClientState(connection: connection)
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionState(state, id: id)
        }
        connection.start(queue: queue)
        receive(from: connection, id: id)
        notifyState(error: nil)
    }

    private func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return address == .loopback
        case .ipv6(let address):
            return address == .loopback
        case .name(let name, _):
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "localhost"
        @unknown default:
            return false
        }
    }

    private func handleConnectionState(_ state: NWConnection.State, id: UUID) {
        switch state {
        case .failed, .cancelled:
            clients[id] = nil
            notifyState(error: nil)
        default:
            break
        }
    }

    private func receive(from connection: NWConnection, id: UUID) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, let packet = self.parsePacket(data) {
                self.clients[id]?.lastSeen = Date()
                self.handle(packet, from: id)
            }

            if error == nil, self.clients[id] != nil {
                self.receive(from: connection, id: id)
            } else {
                self.clients[id] = nil
                self.notifyState(error: nil)
            }
        }
    }

    private func handle(_ packet: ParsedPacket, from clientID: UUID) {
        switch packet.messageType {
        case MessageType.protocolVersion:
            sendPacket(messageType: packet.messageType, payload: littleEndian(UInt16(1001)), to: clientID)

        case MessageType.controllerInfo:
            let slots = requestedInfoSlots(packet.payload)
            for slot in slots {
                sendPacket(messageType: packet.messageType, payload: controllerInfoPayload(slot: slot), to: clientID)
            }

        case MessageType.controllerData:
            subscribe(clientID: clientID, payload: packet.payload)
            sendSubscribedControllerData(to: clientID)

        case MessageType.motorInfo:
            for slot in targetSlots(fromIdentifierPayload: packet.payload) {
                sendPacket(messageType: packet.messageType, payload: motorInfoPayload(slot: slot), to: clientID)
            }

        case MessageType.rumble:
            handleRumble(packet.payload, from: clientID)

        default:
            break
        }
    }

    private func requestedInfoSlots(_ payload: [UInt8]) -> [Int] {
        guard payload.count >= 4 else { return Array(0..<4) }
        let count = min(max(Int(int32LE(payload, offset: 0) ?? 4), 0), 4)
        let slots = payload.dropFirst(4).prefix(count).map(Int.init).filter { (0..<4).contains($0) }
        return slots.isEmpty ? Array(0..<4) : slots
    }

    private func subscribe(clientID: UUID, payload: [UInt8]) {
        guard var client = clients[clientID] else { return }
        client.subscriptions.insert(subscription(fromIdentifierPayload: payload))
        client.lastSeen = Date()
        clients[clientID] = client
        notifyState(error: nil)
    }

    private func subscription(fromIdentifierPayload payload: [UInt8]) -> Subscription {
        guard let flags = payload.first else { return .all }
        if (flags & 0x01) != 0, payload.count >= 2 {
            return .slot(Int(payload[1]).clamped(to: 0...3))
        }
        if (flags & 0x02) != 0, payload.count >= 8 {
            return .mac(Array(payload[2..<8]))
        }
        return .all
    }

    private func targetSlots(fromIdentifierPayload payload: [UInt8]) -> [Int] {
        switch subscription(fromIdentifierPayload: payload) {
        case .all:
            return controllers.keys.sorted()
        case .slot(let slot):
            return controllers[slot] == nil ? [] : [slot]
        case .mac(let mac):
            return controllers.values
                .filter { macBytes(for: $0) == mac }
                .map(\.slot)
                .sorted()
        }
    }

    private func handleRumble(_ payload: [UInt8], from clientID: UUID) {
        guard payload.count >= 10 else { return }
        let intensity = payload[9]
        let slots = targetSlots(fromIdentifierPayload: Array(payload.prefix(8)))
        guard !slots.isEmpty else { return }

        if var client = clients[clientID] {
            let deadline = Date().addingTimeInterval(5)
            for slot in slots {
                client.rumbleDeadlines[slot] = intensity == 0 ? nil : deadline
            }
            clients[clientID] = client
        }

        for slot in slots {
            DispatchQueue.main.async { [weak self] in
                self?.onRumble?(DiagnosticDSURumbleCommand(slot: slot, intensity: intensity))
            }
        }
    }

    private func startSendTimer() {
        sendTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(8), repeating: .milliseconds(8), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.sendTick()
        }
        timer.resume()
        sendTimer = timer
    }

    private func sendTick() {
        let now = Date()
        for id in Array(clients.keys) {
            guard var client = clients[id] else { continue }
            if now.timeIntervalSince(client.lastSeen) > 5 {
                for slot in client.rumbleDeadlines.keys {
                    DispatchQueue.main.async { [weak self] in
                        self?.onRumble?(DiagnosticDSURumbleCommand(slot: slot, intensity: 0))
                    }
                }
                client.connection.cancel()
                clients[id] = nil
                continue
            }

            for (slot, deadline) in client.rumbleDeadlines where deadline <= now {
                client.rumbleDeadlines[slot] = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onRumble?(DiagnosticDSURumbleCommand(slot: slot, intensity: 0))
                }
            }

            clients[id] = client
            sendSubscribedControllerData(to: id)
        }
    }

    private func sendSubscribedControllerData(to clientID: UUID) {
        guard var client = clients[clientID], !client.subscriptions.isEmpty else { return }
        let slots = subscribedSlots(for: client)
        for slot in slots {
            guard let controller = controllers[slot] else { continue }
            let payload = controllerDataPayload(controller, packetCounter: client.packetCounter)
            client.packetCounter &+= 1
            sendPacket(messageType: MessageType.controllerData, payload: payload, to: clientID)
        }
        clients[clientID] = client
    }

    private func subscribedSlots(for client: ClientState) -> [Int] {
        var slots = Set<Int>()
        for subscription in client.subscriptions {
            switch subscription {
            case .all:
                slots.formUnion(controllers.keys)
            case .slot(let slot):
                if controllers[slot] != nil { slots.insert(slot) }
            case .mac(let mac):
                for controller in controllers.values where macBytes(for: controller) == mac {
                    slots.insert(controller.slot)
                }
            }
        }
        return slots.sorted()
    }

    private func controllerInfoPayload(slot: Int) -> [UInt8] {
        guard let controller = controllers[slot] else { return Array(repeating: 0, count: 12) }
        var payload = sharedControllerHeader(controller)
        payload.append(0)
        return payload
    }

    private func motorInfoPayload(slot: Int) -> [UInt8] {
        guard let controller = controllers[slot] else { return Array(repeating: 0, count: 12) }
        var payload = sharedControllerHeader(controller)
        payload.append(1)
        return payload
    }

    func controllerDataPayload(_ controller: ControllerRuntimeSnapshot, packetCounter: UInt32) -> [UInt8] {
        var payload = sharedControllerHeader(controller)
        payload.append(1)
        payload.append(contentsOf: littleEndian(packetCounter))

        let dpad = dpadDirections(controller.gamepadState.hat)
        let buttons = controller.gamepadState.buttons

        var buttons1: UInt8 = 0
        if dpad.left { buttons1 |= 0x80 }
        if dpad.down { buttons1 |= 0x40 }
        if dpad.right { buttons1 |= 0x20 }
        if dpad.up { buttons1 |= 0x10 }
        if contains(.start, in: buttons) { buttons1 |= 0x08 }
        if contains(.rightStick, in: buttons) { buttons1 |= 0x04 }
        if contains(.leftStick, in: buttons) { buttons1 |= 0x02 }
        if contains(.select, in: buttons) { buttons1 |= 0x01 }

        var buttons2: UInt8 = 0
        if contains(.north, in: buttons) { buttons2 |= 0x80 }
        if contains(.east, in: buttons) { buttons2 |= 0x40 }
        if contains(.south, in: buttons) { buttons2 |= 0x20 }
        if contains(.west, in: buttons) { buttons2 |= 0x10 }
        if contains(.rightShoulder, in: buttons) { buttons2 |= 0x08 }
        if contains(.leftShoulder, in: buttons) { buttons2 |= 0x04 }
        if contains(.rightTrigger, in: buttons) { buttons2 |= 0x02 }
        if contains(.leftTrigger, in: buttons) { buttons2 |= 0x01 }

        payload.append(buttons1)
        payload.append(buttons2)
        payload.append(contains(.home, in: buttons) ? 1 : 0)
        payload.append(0)
        payload.append(dsuStickAxis(controller.gamepadState.leftX))
        payload.append(dsuStickYAxis(controller.gamepadState.leftY))
        payload.append(dsuStickAxis(controller.gamepadState.rightX))
        payload.append(dsuStickYAxis(controller.gamepadState.rightY))
        payload.append(dpad.left ? 255 : 0)
        payload.append(dpad.down ? 255 : 0)
        payload.append(dpad.right ? 255 : 0)
        payload.append(dpad.up ? 255 : 0)
        payload.append(contains(.north, in: buttons) ? 255 : 0)
        payload.append(contains(.east, in: buttons) ? 255 : 0)
        payload.append(contains(.south, in: buttons) ? 255 : 0)
        payload.append(contains(.west, in: buttons) ? 255 : 0)
        payload.append(contains(.rightShoulder, in: buttons) ? 255 : 0)
        payload.append(contains(.leftShoulder, in: buttons) ? 255 : 0)
        payload.append(contains(.rightTrigger, in: buttons) ? 255 : 0)
        payload.append(contains(.leftTrigger, in: buttons) ? 255 : 0)
        payload.append(contentsOf: Array(repeating: 0, count: 12))
        payload.append(contentsOf: littleEndian(currentMicroseconds()))
        payload.append(contentsOf: littleEndian(Float(controller.motion.accelerationXG)))
        payload.append(contentsOf: littleEndian(Float(controller.motion.accelerationYG)))
        payload.append(contentsOf: littleEndian(Float(controller.motion.accelerationZG)))
        payload.append(contentsOf: littleEndian(Float(controller.motion.gyroPitchDegreesPerSecond)))
        payload.append(contentsOf: littleEndian(Float(controller.motion.gyroYawDegreesPerSecond)))
        payload.append(contentsOf: littleEndian(Float(controller.motion.gyroRollDegreesPerSecond)))
        return payload
    }

    private func sharedControllerHeader(_ controller: ControllerRuntimeSnapshot) -> [UInt8] {
        var payload: [UInt8] = [
            UInt8(controller.slot.clamped(to: 0...3)),
            2,
            controller.hasFullGyro ? 2 : 1,
            connectionTypeByte(controller.transport)
        ]
        payload.append(contentsOf: macBytes(for: controller))
        payload.append(batteryByte(controller.batteryPercent))
        return payload
    }

    private func sendPacket(messageType: UInt32, payload: [UInt8], to clientID: UUID) {
        guard let client = clients[clientID] else { return }
        let packet = buildPacket(messageType: messageType, payload: payload)
        client.connection.send(content: packet, completion: .contentProcessed { _ in })
    }

    func buildPacket(messageType: UInt32, payload: [UInt8]) -> Data {
        var bytes = Array("DSUS".utf8)
        bytes.append(contentsOf: littleEndian(UInt16(1001)))
        bytes.append(contentsOf: littleEndian(UInt16(4 + payload.count)))
        bytes.append(contentsOf: littleEndian(UInt32(0)))
        bytes.append(contentsOf: littleEndian(serverID))
        bytes.append(contentsOf: littleEndian(messageType))
        bytes.append(contentsOf: payload)
        let crc = CRC32.checksum(bytes)
        writeLittleEndian(crc, into: &bytes, at: 8)
        return Data(bytes)
    }

    private func parsePacket(_ data: Data) -> ParsedPacket? {
        var bytes = Array(data)
        guard bytes.count >= 20,
              bytes[0] == UInt8(ascii: "D"),
              bytes[1] == UInt8(ascii: "S"),
              bytes[2] == UInt8(ascii: "U"),
              bytes[3] == UInt8(ascii: "C"),
              uint16LE(bytes, offset: 4) == 1001,
              let length = uint16LE(bytes, offset: 6),
              length >= 4 else {
            return nil
        }

        let packetLength = 16 + Int(length)
        guard bytes.count >= packetLength else { return nil }
        bytes = Array(bytes.prefix(packetLength))
        let expectedCRC = uint32LE(bytes, offset: 8) ?? 0
        if expectedCRC != 0 {
            var checkBytes = bytes
            writeLittleEndian(UInt32(0), into: &checkBytes, at: 8)
            guard CRC32.checksum(checkBytes) == expectedCRC else { return nil }
        }

        guard let messageType = uint32LE(bytes, offset: 16) else { return nil }
        return ParsedPacket(messageType: messageType, payload: Array(bytes[20..<packetLength]))
    }

    private func notifyState(error: String?) {
        notifyState(isRunning: isRunning, error: error)
    }

    private func notifyState(isRunning: Bool, error: String?) {
        let clientCount = clients.count
        DispatchQueue.main.async { [weak self] in
            self?.onStateChanged?(isRunning, clientCount, error)
        }
    }
}

private func connectionTypeByte(_ transport: ControllerTransportKind) -> UInt8 {
    switch transport {
    case .unknown: return 0
    case .usb: return 1
    case .bluetooth: return 2
    }
}

private func batteryByte(_ percent: Int?) -> UInt8 {
    guard let percent else { return 0x00 }
    switch percent {
    case ..<6: return 0x01
    case ..<26: return 0x02
    case ..<61: return 0x03
    case ..<91: return 0x04
    default: return 0x05
    }
}

private func macBytes(for controller: ControllerRuntimeSnapshot) -> [UInt8] {
    if let address = controller.address {
        let parts = address
            .replacingOccurrences(of: "-", with: ":")
            .split(separator: ":")
            .compactMap { UInt8($0, radix: 16) }
        if parts.count == 6 {
            return parts
        }
    }

    return stride(from: 0, to: 6, by: 1).map { offset in
        UInt8((controller.id >> UInt64(offset * 8)) & 0xFF)
    }
}

private func contains(_ button: VirtualGamepadButton, in mask: UInt16) -> Bool {
    (mask & button.mask) != 0
}

private func dpadDirections(_ hat: UInt8) -> (up: Bool, down: Bool, left: Bool, right: Bool) {
    switch hat {
    case 0: return (true, false, false, false)
    case 1: return (true, false, false, true)
    case 2: return (false, false, false, true)
    case 3: return (false, true, false, true)
    case 4: return (false, true, false, false)
    case 5: return (false, true, true, false)
    case 6: return (false, false, true, false)
    case 7: return (true, false, true, false)
    default: return (false, false, false, false)
    }
}

private func dsuStickAxis(_ value: Int8) -> UInt8 {
    UInt8(clamping: Int(value) + 128)
}

private func dsuStickYAxis(_ value: Int8) -> UInt8 {
    UInt8(clamping: 128 - Int(value))
}

private func currentMicroseconds() -> UInt64 {
    UInt64(Date().timeIntervalSince1970 * 1_000_000)
}

private func int32LE(_ bytes: [UInt8], offset: Int) -> Int32? {
    uint32LE(bytes, offset: offset).map { Int32(bitPattern: $0) }
}

private func uint16LE(_ bytes: [UInt8], offset: Int) -> UInt16? {
    guard bytes.count >= offset + 2 else { return nil }
    return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
}

private func uint32LE(_ bytes: [UInt8], offset: Int) -> UInt32? {
    guard bytes.count >= offset + 4 else { return nil }
    return UInt32(bytes[offset]) |
        (UInt32(bytes[offset + 1]) << 8) |
        (UInt32(bytes[offset + 2]) << 16) |
        (UInt32(bytes[offset + 3]) << 24)
}

private func littleEndian(_ value: UInt16) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
}

private func littleEndian(_ value: UInt32) -> [UInt8] {
    [
        UInt8(value & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 24) & 0xFF)
    ]
}

private func littleEndian(_ value: UInt64) -> [UInt8] {
    (0..<8).map { UInt8((value >> UInt64($0 * 8)) & 0xFF) }
}

private func littleEndian(_ value: Float) -> [UInt8] {
    littleEndian(value.bitPattern)
}

private func writeLittleEndian(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
    let encoded = littleEndian(value)
    guard bytes.count >= offset + encoded.count else { return }
    for index in 0..<encoded.count {
        bytes[offset + index] = encoded[index]
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 {
            if (crc & 1) != 0 {
                crc = 0xEDB88320 ^ (crc >> 1)
            } else {
                crc >>= 1
            }
        }
        return crc
    }

    static func checksum(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
