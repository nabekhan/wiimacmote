import Darwin
import Foundation

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

    private struct ClientKey: Hashable {
        let address: UInt32
        let port: UInt16
    }

    private struct ClientState {
        let address: sockaddr_in
        var subscriptions = Set<Subscription>()
        var packetCounter: UInt32 = 0
        var lastSeen = Date()
        var rumbleDeadlines: [Int: Date] = [:]
    }

    private let port: UInt16
    private let serverID = UInt32.random(in: 1...UInt32.max)
    private let queue = DispatchQueue(label: "dev.wiimacmote.diagnostics.dsu")
    private var socketFD: Int32 = -1
    private var readSource: DispatchSourceRead?
    private var clients: [ClientKey: ClientState] = [:]
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
        guard socketFD < 0 else {
            notifyState(error: nil)
            return
        }

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            notifyState(isRunning: false, error: socketError("socket"))
            return
        }

        var reuse: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let error = socketError("bind")
            Darwin.close(fd)
            notifyState(isRunning: false, error: error)
            return
        }

        socketFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.receiveAvailableDatagrams()
        }
        readSource = source
        source.resume()

        isRunning = true
        notifyState(error: nil)
        startSendTimer()
    }

    private func stopOnQueue() {
        sendTimer?.cancel()
        sendTimer = nil

        readSource?.cancel()
        readSource = nil
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }

        clients.removeAll()
        isRunning = false
        notifyState(isRunning: false, error: nil)
    }

    private func receiveAvailableDatagrams() {
        guard socketFD >= 0 else { return }

        while true {
            var buffer = [UInt8](repeating: 0, count: 2048)
            var storage = sockaddr_storage()
            var storageLength = socklen_t(MemoryLayout<sockaddr_storage>.size)

            let count = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return withUnsafeMutablePointer(to: &storage) { storagePointer in
                    storagePointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                        Darwin.recvfrom(socketFD, baseAddress, rawBuffer.count, 0, sockaddrPointer, &storageLength)
                    }
                }
            }

            if count > 0 {
                handleDatagram(Array(buffer.prefix(count)), from: storage)
            } else if count == 0 {
                return
            } else {
                let errorCode = errno
                if errorCode == EWOULDBLOCK || errorCode == EAGAIN {
                    return
                }
                notifyState(error: socketError("recvfrom", code: errorCode))
                return
            }
        }
    }

    private func handleDatagram(_ data: [UInt8], from storage: sockaddr_storage) {
        guard let (key, address) = clientEndpoint(from: storage),
              let packet = parsePacket(Data(data)) else {
            return
        }

        if clients[key] == nil {
            clients[key] = ClientState(address: address)
            notifyState(error: nil)
        }
        clients[key]?.lastSeen = Date()
        handle(packet, from: key)
    }

    private func clientEndpoint(from storage: sockaddr_storage) -> (ClientKey, sockaddr_in)? {
        var storage = storage
        return withUnsafePointer(to: &storage) { storagePointer in
            storagePointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { addressPointer -> (ClientKey, sockaddr_in)? in
                let address = addressPointer.pointee
                guard Int32(address.sin_family) == AF_INET else { return nil }
                let hostAddress = UInt32(bigEndian: address.sin_addr.s_addr)
                guard (hostAddress & 0xFF00_0000) == 0x7F00_0000 else { return nil }
                return (
                    ClientKey(address: address.sin_addr.s_addr, port: UInt16(bigEndian: address.sin_port)),
                    address
                )
            }
        }
    }

    private func handle(_ packet: ParsedPacket, from clientKey: ClientKey) {
        switch packet.messageType {
        case MessageType.protocolVersion:
            sendPacket(
                messageType: packet.messageType,
                payload: littleEndian(UInt16(1001)) + [0, 0],
                to: clientKey
            )

        case MessageType.controllerInfo:
            let slots = requestedInfoSlots(packet.payload)
            for slot in slots {
                sendPacket(messageType: packet.messageType, payload: controllerInfoPayload(slot: slot), to: clientKey)
            }

        case MessageType.controllerData:
            subscribe(clientKey: clientKey, payload: packet.payload)
            sendSubscribedControllerData(to: clientKey)

        case MessageType.motorInfo:
            for slot in targetSlots(fromIdentifierPayload: packet.payload) {
                sendPacket(messageType: packet.messageType, payload: motorInfoPayload(slot: slot), to: clientKey)
            }

        case MessageType.rumble:
            handleRumble(packet.payload, from: clientKey)

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

    private func subscribe(clientKey: ClientKey, payload: [UInt8]) {
        guard var client = clients[clientKey] else { return }
        client.subscriptions.insert(subscription(fromIdentifierPayload: payload))
        client.lastSeen = Date()
        clients[clientKey] = client
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

    private func handleRumble(_ payload: [UInt8], from clientKey: ClientKey) {
        guard payload.count >= 10 else { return }
        let intensity = payload[9]
        let slots = targetSlots(fromIdentifierPayload: Array(payload.prefix(8)))
        guard !slots.isEmpty else { return }

        if var client = clients[clientKey] {
            let deadline = Date().addingTimeInterval(5)
            for slot in slots {
                client.rumbleDeadlines[slot] = intensity == 0 ? nil : deadline
            }
            clients[clientKey] = client
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
        for key in Array(clients.keys) {
            guard var client = clients[key] else { continue }
            if now.timeIntervalSince(client.lastSeen) > 5 {
                for slot in client.rumbleDeadlines.keys {
                    DispatchQueue.main.async { [weak self] in
                        self?.onRumble?(DiagnosticDSURumbleCommand(slot: slot, intensity: 0))
                    }
                }
                clients[key] = nil
                notifyState(error: nil)
                continue
            }

            for (slot, deadline) in client.rumbleDeadlines where deadline <= now {
                client.rumbleDeadlines[slot] = nil
                DispatchQueue.main.async { [weak self] in
                    self?.onRumble?(DiagnosticDSURumbleCommand(slot: slot, intensity: 0))
                }
            }

            clients[key] = client
            sendSubscribedControllerData(to: key)
        }
    }

    private func sendSubscribedControllerData(to clientKey: ClientKey) {
        guard var client = clients[clientKey], !client.subscriptions.isEmpty else { return }
        let slots = subscribedSlots(for: client)
        for slot in slots {
            guard let controller = controllers[slot] else { continue }
            let payload = controllerDataPayload(controller, packetCounter: client.packetCounter)
            client.packetCounter &+= 1
            sendPacket(messageType: MessageType.controllerData, payload: payload, to: clientKey)
        }
        clients[clientKey] = client
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
        guard let controller = controllers[slot] else { return disconnectedControllerHeader(slot: slot) + [0] }
        var payload = sharedControllerHeader(controller)
        payload.append(0)
        return payload
    }

    private func motorInfoPayload(slot: Int) -> [UInt8] {
        guard let controller = controllers[slot] else { return disconnectedControllerHeader(slot: slot) + [0] }
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
        payload.append(contains(.west, in: buttons) ? 255 : 0)
        payload.append(contains(.south, in: buttons) ? 255 : 0)
        payload.append(contains(.east, in: buttons) ? 255 : 0)
        payload.append(contains(.north, in: buttons) ? 255 : 0)
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

    private func disconnectedControllerHeader(slot: Int) -> [UInt8] {
        [UInt8(slot.clamped(to: 0...3)), 0, 0, 0] + Array(repeating: 0, count: 7)
    }

    private func sendPacket(messageType: UInt32, payload: [UInt8], to clientKey: ClientKey) {
        guard socketFD >= 0, var address = clients[clientKey]?.address else { return }
        let packet = buildPacket(messageType: messageType, payload: payload)
        let result = packet.withUnsafeBytes { rawBuffer -> Int in
            guard let baseAddress = rawBuffer.baseAddress else { return -1 }
            return withUnsafePointer(to: &address) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.sendto(
                        socketFD,
                        baseAddress,
                        rawBuffer.count,
                        0,
                        sockaddrPointer,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        if result < 0 {
            notifyState(error: socketError("sendto"))
        }
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
              (uint16LE(bytes, offset: 4) ?? 0) <= 1001,
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

    private func socketError(_ operation: String, code: Int32 = errno) -> String {
        "DSU UDP \(operation) failed: \(String(cString: strerror(code)))."
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
