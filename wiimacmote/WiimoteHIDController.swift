import Foundation
import IOKit
import IOKit.hid

struct ConnectedWiimoteSnapshot: Identifiable, Equatable {
    let id: UInt64
    let playerIndex: Int
    let name: String
    let address: String?
    let productID: Int
    let remoteKind: WiimoteRemoteKind
    let motionPlusCapability: WiimoteMotionPlusCapability
    let batteryPercent: Int?
    let buttons: [String]
    let reportsPerSecond: Int
    let extensionConnected: Bool
    let extensionName: String?
    let extensionDetail: String?
    let extensionIdentifier: [UInt8]?
    let extensionIdentifierHex: String?
    let balanceWeightKilograms: Double?
}

/// Gives C callbacks a stable object whose weak owner can be invalidated
/// before an asynchronous IOHIDManager cancellation has fully drained.
private final class HIDCallbackContext {
    weak var owner: WiimoteHIDController?

    init(owner: WiimoteHIDController) {
        self.owner = owner
    }
}

/// Keeps the dispatch-backed manager and its callback context alive until
/// IOKit has drained its queue and invoked the cancellation handler.
private final class HIDManagerLifetime {
    var manager: IOHIDManager?
    let callbackContext: HIDCallbackContext

    init(manager: IOHIDManager, callbackContext: HIDCallbackContext) {
        self.manager = manager
        self.callbackContext = callbackContext
    }
}

/// Owns all IOHID work on one high-priority serial queue. Input packets are
/// translated immediately, while SwiftUI snapshots are coalesced to 30 Hz.
final class WiimoteHIDController {
    var onSnapshotsChanged: (([ConnectedWiimoteSnapshot]) -> Void)?
    var onConnectionCountChanged: ((Int) -> Void)?
    var logHandler: ((_ level: String, _ message: String) -> Void)?

    private let queue = DispatchQueue(
        label: "dev.wiimacmote.hid",
        qos: .userInteractive
    )
    private let queueKey = DispatchSpecificKey<Void>()

    private var manager: IOHIDManager?
    private var callbackContext: HIDCallbackContext?
    private var sessions: [UInt64: Session] = [:]
    private var uiTimer: DispatchSourceTimer?
    private var rateTimer: DispatchSourceTimer?
    private var snapshotsDirty = false

    init() {
        queue.setSpecific(key: queueKey, value: ())
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            tearDown()
        } else {
            queue.sync { tearDown() }
        }
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.tearDown()
        }
    }

    func setRumble(id: UInt64, enabled: Bool) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            session.rumbleEnabled = enabled
            self.sendLEDState(for: session)
        }
    }

    func disconnect(id: UInt64) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            self.quietAndClose(session, reason: "P\(session.playerIndex) disconnect requested.")
        }
    }

    // MARK: - Setup

    private func startOnQueue() {
        guard manager == nil else { return }

        let created = IOHIDManagerCreate(
            kCFAllocatorDefault,
            IOOptionBits(kIOHIDOptionsTypeNone)
        )
        manager = created

        let matchNintendo: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x057E
        ]
        IOHIDManagerSetDeviceMatching(created, matchNintendo as CFDictionary)

        let callbackContext = HIDCallbackContext(owner: self)
        self.callbackContext = callbackContext
        let context = Unmanaged.passUnretained(callbackContext).toOpaque()

        IOHIDManagerRegisterDeviceMatchingCallback(
            created,
            { context, _, _, device in
                guard let context else { return }
                let callbackContext = Unmanaged<HIDCallbackContext>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                callbackContext.owner?.deviceMatched(device)
            },
            context
        )
        IOHIDManagerRegisterDeviceRemovalCallback(
            created,
            { context, _, _, device in
                guard let context else { return }
                let callbackContext = Unmanaged<HIDCallbackContext>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                callbackContext.owner?.deviceRemoved(device)
            },
            context
        )
        IOHIDManagerRegisterInputReportCallback(
            created,
            { context, result, sender, _, reportID, report, reportLength in
                // With a dispatch-backed IOHIDManager, all callbacks must be
                // registered before activation. The manager-level report
                // callback also avoids mutating an already activated device.
                guard let context, let sender else { return }
                let callbackContext = Unmanaged<HIDCallbackContext>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                guard let owner = callbackContext.owner else { return }
                let source = Unmanaged<IOHIDDevice>
                    .fromOpaque(sender)
                    .takeUnretainedValue()
                owner.receivedReport(
                    from: source,
                    result: result,
                    reportID: reportID,
                    report: report,
                    length: reportLength
                )
            },
            context
        )

        let openResult = IOHIDManagerOpen(created, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess else {
            log("error", "Unable to open IOHIDManager (\(hex(openResult))).")
            callbackContext.owner = nil
            self.callbackContext = nil
            manager = nil
            return
        }

        let lifetime = HIDManagerLifetime(
            manager: created,
            callbackContext: callbackContext
        )
        IOHIDManagerSetDispatchQueue(created, queue)
        IOHIDManagerSetCancelHandler(created) { [lifetime] in
            lifetime.callbackContext.owner = nil
            lifetime.manager = nil
        }
        IOHIDManagerActivate(created)
        startTimers()
        log("info", "HID service is ready on its dedicated dispatch queue.")
    }

    private func tearDown() {
        uiTimer?.cancel()
        uiTimer = nil
        rateTimer?.cancel()
        rateTimer = nil

        // Invalidate the old generation before cancellation. Any callback that
        // was already queued will safely no-op, including during stop/start.
        callbackContext?.owner = nil
        callbackContext = nil

        // Input reports and device access are owned by the manager. Avoid any
        // per-device close or callback mutation while a device may be vanishing.
        for session in sessions.values {
            quietRemote(for: session)
        }
        sessions.removeAll()

        if let manager {
            _ = IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            self.manager = nil
            IOHIDManagerCancel(manager)
        }
    }

    private func startTimers() {
        let uiTimer = DispatchSource.makeTimerSource(queue: queue)
        uiTimer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        uiTimer.setEventHandler { [weak self] in
            guard let self, self.snapshotsDirty else { return }
            self.snapshotsDirty = false
            self.publishSnapshots()
        }
        uiTimer.resume()
        self.uiTimer = uiTimer

        let rateTimer = DispatchSource.makeTimerSource(queue: queue)
        rateTimer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        rateTimer.setEventHandler { [weak self] in
            guard let self else { return }
            for session in self.sessions.values {
                session.reportsPerSecond = session.reportCounter
                session.reportCounter = 0
            }
            self.markSnapshotsDirty()
        }
        rateTimer.resume()
        self.rateTimer = rateTimer
    }

    // MARK: - Device lifecycle

    private func deviceMatched(_ device: IOHIDDevice) {
        let id = deviceIdentifier(device)
        guard sessions[id] == nil else { return }
        let name = stringProperty(device, key: kIOHIDProductKey) ?? "Nintendo Wii Remote"
        let productID = intProperty(device, key: kIOHIDProductIDKey) ?? 0
        let remoteKind = WiimoteRemoteKind(name: name, productID: productID)
        guard remoteKind != .unknown else { return }
        guard sessions.count < 4 else {
            log("info", "Ignoring an additional Wii controller because four are already active.")
            return
        }

        let playerIndex = firstAvailablePlayerIndex()
        let session = Session(
            id: id,
            device: device,
            playerIndex: playerIndex,
            name: name,
            address: stringProperty(device, key: kIOHIDSerialNumberKey),
            productID: productID,
            remoteKind: remoteKind
        )
        if remoteKind == .balanceBoard {
            session.extensionKind = .balanceBoard
            session.extensionConnected = true
        }
        sessions[id] = session

        if session.extensionKind == .balanceBoard {
            initializeExtension(for: session)
        }
        sendLEDState(for: session)
        setReportMode(for: session)

        // Dolphin similarly allows the new report mode to settle before asking
        // for status; this avoids racing two output transactions at connect.
        queue.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            self.sendStatusRequest(for: session)
            self.probeMotionPlusIfNeeded(for: session)
        }

        log("connection", "Connected \(name) as P\(playerIndex).")
        publishConnectionChanges()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = deviceIdentifier(device)
        removeSession(id: id, reason: nil)
    }

    private func removeSession(id: UInt64, reason: String?) {
        guard let session = sessions.removeValue(forKey: id) else { return }

        // The manager owns report delivery. Its callbacks are serialized on
        // this queue, so no session-owned callback buffer needs a drain period.

        log("connection", reason ?? "P\(session.playerIndex) disconnected.")
        publishConnectionChanges()
    }

    private func firstAvailablePlayerIndex() -> Int {
        for candidate in 1...4 where !sessions.values.contains(where: { $0.playerIndex == candidate }) {
            return candidate
        }
        return 1
    }

    // MARK: - Reports

    private func receivedReport(
        from device: IOHIDDevice,
        result: IOReturn,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        length: CFIndex
    ) {
        guard result == kIOReturnSuccess else {
            log("warning", "HID input callback returned \(hex(result)).")
            return
        }
        guard length > 0, let session = sessions[deviceIdentifier(device)] else { return }

        let buffer = UnsafeBufferPointer(start: report, count: length)
        let packet: WiimotePacket?
        if buffer.first == UInt8(truncatingIfNeeded: reportID) || reportID == 0 {
            packet = WiimoteReportParser.parse(buffer)
        } else {
            var normalized = [UInt8(truncatingIfNeeded: reportID)]
            normalized.append(contentsOf: buffer)
            packet = WiimoteReportParser.parse(Data(normalized))
        }

        guard let packet else { return }
        session.reportCounter += 1

        switch packet {
        case .input(let input):
            session.buttons = input.buttons
            if !input.extensionData.isEmpty {
                session.extensionConnected = true
                let decoded = WiimoteExtensionInput.decode(
                    input.extensionData,
                    kind: session.extensionKind
                )
                session.extensionInput = decoded
            }
            markSnapshotsDirty()

        case .status(let status):
            let extensionStateChanged = session.hasReceivedStatus &&
                session.extensionConnected != status.extensionConnected
            session.hasReceivedStatus = true
            session.buttons = status.buttons
            session.batteryPercent = status.batteryPercent
            session.extensionConnected = status.extensionConnected
            sendLEDState(for: session)

            // A spontaneous extension connect/disconnect status disables data
            // reporting on the Wii Remote. Restore the selected report mode.
            if extensionStateChanged {
                if status.extensionConnected {
                    initializeExtension(for: session)
                } else {
                    session.extensionKind = nil
                    session.extensionIdentifier = nil
                    session.extensionInput = nil
                    session.balanceBoardCalibration = nil
                    session.extensionInitializationRequested = false
                    session.extensionIdentifierRetryCount = 0
                    session.motionPlusProbeRequested = false
                    session.pendingRead = nil
                }
                setReportMode(for: session)
                log("info", "P\(session.playerIndex) extension state changed; report mode restored.")
            } else if status.extensionConnected,
                      session.extensionKind == nil ||
                      (session.extensionKind == .balanceBoard && session.balanceBoardCalibration == nil) {
                initializeExtension(for: session)
            }
            probeMotionPlusIfNeeded(for: session)
            markSnapshotsDirty()

        case .readData(let read):
            handleReadData(read, for: session)
            markSnapshotsDirty()

        case .acknowledgment(let acknowledgedReport, let error):
            if error != 0 {
                log(
                    "warning",
                    String(format: "P%d rejected output report 0x%02X with error 0x%02X.",
                           session.playerIndex, acknowledgedReport, error)
                )
            }

        case .ignored:
            break
        }
    }

    // MARK: - Output reports

    private func setReportMode(for session: Session) {
        let report = WiimoteOutputReports.reportMode(
            reportMode(for: session),
            continuous: true,
            rumble: session.rumbleEnabled
        )
        sendOutputReport(report, to: session)
    }

    private func reportMode(for session: Session) -> WiimoteReportMode {
        if session.extensionKind == .balanceBoard {
            return .buttonsExtension19
        }

        let hasExtensionData = session.extensionConnected || session.extensionKind != nil
        if hasExtensionData {
            return .buttonsExtension8
        }
        return .buttons
    }

    private func sendStatusRequest(for session: Session) {
        sendOutputReport(WiimoteOutputReports.statusRequest(rumble: session.rumbleEnabled), to: session)
    }

    private func sendLEDState(for session: Session) {
        let ledMask = UInt8(0x10 << (session.playerIndex - 1))
        sendOutputReport(WiimoteOutputReports.leds(mask: ledMask, rumble: session.rumbleEnabled), to: session)
    }

    private func initializeExtension(for session: Session) {
        guard !session.extensionInitializationRequested else { return }
        session.extensionInitializationRequested = true

        sendOutputReports(WiimoteOutputReports.extensionInitializationSequence(), to: session, interval: 0.05)

        queue.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            self.sendReadMemory(
                for: session,
                kind: .extensionIdentifier,
                addressSpace: .register,
                address: WiimoteProtocolCodes.Register.extensionIdentifier,
                length: 6
            )
        }
    }

    private func probeMotionPlusIfNeeded(for session: Session) {
        if let kind = session.extensionKind {
            if kind.isMotionPlus {
                return
            }
        }
        guard !session.motionPlusProbeRequested else { return }
        session.motionPlusProbeRequested = true
        sendReadMemory(
            for: session,
            kind: .motionPlusIdentifier,
            addressSpace: .register,
            address: WiimoteProtocolCodes.Register.motionPlusIdentifier,
            length: 6
        )
    }

    private func sendReadMemory(
        for session: Session,
        kind: PendingReadKind,
        addressSpace: WiimoteAddressSpace,
        address: UInt32,
        length: UInt16
    ) {
        guard session.pendingRead == nil else {
            queue.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self, weak session] in
                guard let self, let session, self.sessions[session.id] != nil else { return }
                self.sendReadMemory(
                    for: session,
                    kind: kind,
                    addressSpace: addressSpace,
                    address: address,
                    length: length
                )
            }
            return
        }

        guard let report = WiimoteOutputReports.readMemory(
            addressSpace: addressSpace,
            address: address,
            length: length,
            rumble: session.rumbleEnabled
        ) else { return }

        session.pendingRead = PendingRead(
            kind: kind,
            address: address,
            length: Int(length),
            data: []
        )
        sendOutputReport(report, to: session)
    }

    private func handleReadData(_ read: WiimoteReadData, for session: Session) {
        guard var pending = session.pendingRead else { return }
        if read.error != 0 {
            if pending.kind == .motionPlusIdentifier {
                if session.remoteKind != .motionPlusInside {
                    session.motionPlusCapability = .absent
                }
            } else {
                log(
                    "warning",
                    String(format: "P%d memory read at 0x%06X failed with error 0x%02X.",
                           session.playerIndex, pending.address, read.error)
                )
            }
            session.pendingRead = nil
            return
        }

        pending.data.append(contentsOf: read.data)
        session.pendingRead = pending
        guard pending.data.count >= pending.length else { return }

        let data = Array(pending.data.prefix(pending.length))
        session.pendingRead = nil

        switch pending.kind {
        case .extensionIdentifier:
            let identifier = Array(data.prefix(6))
            if WiimoteExtensionKind.identifierLooksInvalid(identifier), session.extensionIdentifierRetryCount < 3 {
                session.extensionIdentifierRetryCount += 1
                session.extensionInitializationRequested = false
                log("warning", "P\(session.playerIndex) extension identifier was not stable; retrying handshake.")
                queue.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self, weak session] in
                    guard let self, let session, self.sessions[session.id] === session else { return }
                    self.initializeExtension(for: session)
                }
                return
            }

            session.extensionIdentifierRetryCount = 0
            session.extensionIdentifier = identifier
            let kind = WiimoteExtensionKind(identifier: identifier)
            log("extension", "P\(session.playerIndex) detected \(kind.displayName).")
            if let capability = WiimoteMotionPlusCapability(identifier: identifier, remoteKind: session.remoteKind) {
                session.motionPlusCapability = capability
            }
            if kind.isMotionPlus {
                session.extensionConnected = false
                session.extensionKind = nil
                setReportMode(for: session)
                return
            }

            session.extensionKind = kind
            setReportMode(for: session)
            if kind == .balanceBoard {
                sendReadMemory(
                    for: session,
                    kind: .balanceBoardCalibration,
                    addressSpace: .register,
                    address: WiimoteProtocolCodes.Register.extensionCalibration,
                    length: 32
                )
            }

        case .motionPlusIdentifier:
            let identifier = Array(data.prefix(6))
            let kind = WiimoteExtensionKind(identifier: identifier)
            if let capability = WiimoteMotionPlusCapability(identifier: identifier, remoteKind: session.remoteKind) {
                session.motionPlusCapability = capability
            }
            if kind.isMotionPlus {
                session.extensionIdentifier = identifier
                log("extension", "P\(session.playerIndex) detected \(kind.displayName).")
                setReportMode(for: session)
            }

        case .balanceBoardCalibration:
            if let calibration = WiimoteBalanceBoardCalibration(bytes: data) {
                session.balanceBoardCalibration = calibration
                log("success", "P\(session.playerIndex) Balance Board calibration loaded.")
            }
        }
    }

    private func quietAndClose(_ session: Session, reason: String) {
        quietRemote(for: session)

        queue.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            let result = IOHIDDeviceClose(session.device, IOOptionBits(kIOHIDOptionsTypeNone))
            if result != kIOReturnSuccess {
                self.log("warning", "P\(session.playerIndex) HID close returned \(self.hex(result)).")
            }
            self.removeSession(id: session.id, reason: reason)
        }
    }

    private func quietRemote(for session: Session) {
        session.rumbleEnabled = false

        // There is no public Wii Remote power-off report. The closest safe
        // shutdown sequence is to stop speaker/IR output, blank LEDs, and force
        // rumble off before closing the Bluetooth HID connection.
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.speakerMute, payload: [WiimoteProtocolCodes.OutputFlag.enable])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.speakerEnable, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.irEnable, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.irEnable2, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.leds, payload: [0x00])
        sendOutputReport(to: session, reportID: WiimoteProtocolCodes.OutputReport.rumble, payload: [0x00])
    }

    private func sendOutputReport(_ report: WiimoteOutputReport, to session: Session) {
        sendOutputReport(to: session, reportID: report.reportID, payload: report.payload)
    }

    private func sendOutputReports(
        _ reports: [WiimoteOutputReport],
        to session: Session,
        interval: TimeInterval
    ) {
        for (index, report) in reports.enumerated() {
            queue.asyncAfter(deadline: .now() + interval * Double(index)) { [weak self, weak session] in
                guard let self,
                      let session,
                      self.sessions[session.id] === session
                else {
                    return
                }
                self.sendOutputReport(report, to: session)
            }
        }
    }

    private func sendOutputReport(
        to session: Session,
        reportID: UInt8,
        payload: [UInt8]
    ) {
        // IOHID uses the report ID as a separate argument, but Bluetooth HID
        // still expects that same ID as the first byte in the report buffer.
        var bytes = [reportID]
        bytes.append(contentsOf: payload)

        let result = bytes.withUnsafeBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress else {
                return kIOReturnBadArgument
            }
            return IOHIDDeviceSetReport(
                session.device,
                kIOHIDReportTypeOutput,
                CFIndex(reportID),
                baseAddress.assumingMemoryBound(to: UInt8.self),
                bytes.count
            )
        }

        if result != kIOReturnSuccess {
            log(
                "warning",
                String(format: "P%d output report 0x%02X failed (%@).",
                       session.playerIndex, reportID, hex(result))
            )
        }
    }

    // MARK: - Snapshot publication

    private func markSnapshotsDirty() {
        snapshotsDirty = true
    }

    private func publishConnectionChanges() {
        markSnapshotsDirty()
        let count = sessions.count
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionCountChanged?(count)
        }
    }

    private func publishSnapshots() {
        let snapshots = sessions.values
            .sorted { $0.playerIndex < $1.playerIndex }
            .map { session in
                ConnectedWiimoteSnapshot(
                    id: session.id,
                    playerIndex: session.playerIndex,
                    name: session.name,
                    address: session.address,
                    productID: session.productID,
                    remoteKind: session.remoteKind,
                    motionPlusCapability: session.motionPlusCapability,
                    batteryPercent: session.batteryPercent,
                    buttons: session.buttons.labels,
                    reportsPerSecond: session.reportsPerSecond,
                    extensionConnected: session.extensionConnected,
                    extensionName: session.extensionKind?.displayName,
                    extensionDetail: session.extensionDetail,
                    extensionIdentifier: session.extensionIdentifier,
                    extensionIdentifierHex: session.extensionIdentifier.map(WiimoteIdentifierFormatter.hexString),
                    balanceWeightKilograms: session.balanceWeightKilograms
                )
            }

        DispatchQueue.main.async { [weak self] in
            self?.onSnapshotsChanged?(snapshots)
        }
    }

    // MARK: - Helpers

    private func log(_ level: String, _ message: String) {
        logHandler?(level, message)
    }

    private func deviceIdentifier(_ device: IOHIDDevice) -> UInt64 {
        UInt64(CFHash(device))
    }

    private func property(_ device: IOHIDDevice, key: String) -> CFTypeRef? {
        let cfKey = key.withCString { pointer in
            CFStringCreateWithCString(
                kCFAllocatorDefault,
                pointer,
                CFStringBuiltInEncodings.UTF8.rawValue
            )
        }
        guard let cfKey else { return nil }
        return IOHIDDeviceGetProperty(device, cfKey)
    }

    private func stringProperty(_ device: IOHIDDevice, key: String) -> String? {
        property(device, key: key) as? String
    }

    private func intProperty(_ device: IOHIDDevice, key: String) -> Int? {
        (property(device, key: key) as? NSNumber)?.intValue
    }

    private func hex(_ value: IOReturn) -> String {
        String(format: "0x%08X", UInt32(bitPattern: value))
    }
}

private enum PendingReadKind: Equatable {
    case extensionIdentifier
    case motionPlusIdentifier
    case balanceBoardCalibration
}

private struct PendingRead {
    let kind: PendingReadKind
    let address: UInt32
    let length: Int
    var data: [UInt8]
}

private final class Session {
    let id: UInt64
    let device: IOHIDDevice
    let playerIndex: Int
    let name: String
    let address: String?
    let productID: Int
    let remoteKind: WiimoteRemoteKind

    var batteryPercent: Int?
    var buttons: WiimoteButtons = []
    var reportsPerSecond = 0
    var reportCounter = 0
    var hasReceivedStatus = false
    var extensionConnected = false
    var extensionKind: WiimoteExtensionKind?
    var extensionIdentifier: [UInt8]?
    var extensionInput: WiimoteExtensionInput?
    var extensionInitializationRequested = false
    var extensionIdentifierRetryCount = 0
    var motionPlusCapability: WiimoteMotionPlusCapability
    var motionPlusProbeRequested = false
    var balanceBoardCalibration: WiimoteBalanceBoardCalibration?
    var pendingRead: PendingRead?
    var rumbleEnabled = false

    var extensionDetail: String? {
        extensionInput?.summary
    }

    var balanceWeightKilograms: Double? {
        guard case .balanceBoard(let input) = extensionInput,
              let calibration = balanceBoardCalibration
        else {
            return nil
        }
        return calibration.weight(for: input).totalKilograms
    }

    init(
        id: UInt64,
        device: IOHIDDevice,
        playerIndex: Int,
        name: String,
        address: String?,
        productID: Int,
        remoteKind: WiimoteRemoteKind
    ) {
        self.id = id
        self.device = device
        self.playerIndex = playerIndex
        self.name = name
        self.address = address
        self.productID = productID
        self.remoteKind = remoteKind
        self.motionPlusCapability = WiimoteMotionPlusCapability(remoteKind: remoteKind)
    }
}
