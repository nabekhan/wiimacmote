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
    let gamepadState: VirtualGamepadState
    let acceleration: WiimoteAcceleration?
    let extensionAcceleration: WiimoteAcceleration?
    let motionPlusGyroscope: WiimoteMotionPlusGyroscope?
    let reportsPerSecond: Int
    let reportID: UInt8?
    let extensionConnected: Bool
    let extensionName: String?
    let extensionDetail: String?
    let extensionIdentifier: [UInt8]?
    let extensionIdentifierHex: String?
    let extensionInputSignature: String?
    let irPointCount: Int
    let irPoints: [WiimoteIRPoint]
    let balanceWeightKilograms: Double?
    let virtualGamepadActive: Bool
    let virtualGamepadIdentity: String?
    let virtualGamepadBackend: String?
    let virtualGamepadError: String?
}

struct WiimoteHIDSettings: Equatable {
    var virtualGamepadEnabled: Bool
    var virtualGamepadIdentity: VirtualGamepadIdentity
    var virtualGamepadBackendPreference: VirtualGamepadBackendPreference
    var profile: ControllerProfile
    var motionRightStickEnabled: Bool
    var motionInputSource: MotionInputSource
    var motionPlusEnabled: Bool
    var irCameraEnabled: Bool
    var diagnosticsDSUEnabled: Bool
    var exclusiveHIDAccessEnabled: Bool
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

/// Owns all IOHID work on one high-priority serial queue. This intentionally
/// mirrors the Bluetooth/HID flow from the ccaed81 reference build: normal
/// IOHIDManager matching only, no attached-device polling, and no exclusive
/// device seizure.
final class WiimoteHIDController {
    var onSnapshotsChanged: (([ConnectedWiimoteSnapshot]) -> Void)?
    var onConnectionCountChanged: ((Int) -> Void)?
    var logHandler: ((_ icon: String, _ message: String) -> Void)?

    private let queue = DispatchQueue(
        label: "dev.wiimacmote.hid",
        qos: .userInteractive
    )
    private let queueKey = DispatchSpecificKey<Void>()

    private var manager: IOHIDManager?
    private var callbackContext: HIDCallbackContext?
    private var sessions: [UInt64: Session] = [:]
    private var settings: WiimoteHIDSettings
    private var uiTimer: DispatchSourceTimer?
    private var rateTimer: DispatchSourceTimer?
    private var snapshotsDirty = false

    init(settings: WiimoteHIDSettings) {
        self.settings = settings
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

    func updateSettings(_ newSettings: WiimoteHIDSettings) {
        queue.async { [weak self] in
            guard let self else { return }
            let previous = self.settings
            self.settings = newSettings

            for session in self.sessions.values {
                let virtualDeviceConfigurationChanged =
                    previous.virtualGamepadEnabled != newSettings.virtualGamepadEnabled ||
                    previous.virtualGamepadIdentity != newSettings.virtualGamepadIdentity ||
                    previous.virtualGamepadBackendPreference != newSettings.virtualGamepadBackendPreference

                if virtualDeviceConfigurationChanged {
                    if session.virtualGamepad != nil {
                        session.virtualGamepad?.reset()
                        session.virtualGamepad = nil
                    }
                    self.configureVirtualGamepad(for: session)
                }

                if previous.motionRightStickEnabled != newSettings.motionRightStickEnabled {
                    session.motionFilter.resetCalibration()
                    self.setReportMode(for: session)
                }

                self.updateVirtualOutput(for: session)
            }
            self.markSnapshotsDirty()
        }
    }

    func setRumble(id: UInt64, enabled: Bool) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            session.rumbleEnabled = enabled
            self.sendLEDState(for: session)
        }
    }

    func requestStatus(id: UInt64) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            self.sendStatusRequest(for: session)
        }
    }

    func refreshAttachedDevices() {
        // The reference Bluetooth build relied only on IOHIDManager callbacks.
    }

    func calibrateMotion(id: UInt64) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            session.motionFilter.calibrate(using: session.acceleration)
            self.log("🎯", "Calibrated motion center for P\(session.playerIndex).")
        }
    }

    func disconnect(id: UInt64) {
        queue.async { [weak self] in
            guard let self, let session = self.sessions[id] else { return }
            session.rumbleEnabled = false
            self.sendOutputReport(to: session, reportID: 0x11, payload: [0x00])
            self.sendOutputReport(to: session, reportID: 0x10, payload: [0x00])
            self.removeSession(id: id, reason: "P\(session.playerIndex) disconnect requested.")
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

        let vendorID = 0x057E
        let matchOriginal: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: 0x0306
        ]
        let matchTR: [String: Any] = [
            kIOHIDVendorIDKey as String: vendorID,
            kIOHIDProductIDKey as String: 0x0330
        ]
        IOHIDManagerSetDeviceMatchingMultiple(
            created,
            [matchOriginal as CFDictionary, matchTR as CFDictionary] as CFArray
        )

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
            log("❌", "Unable to open IOHIDManager (\(hex(openResult))).")
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
        log("👀", "HID service is ready on its dedicated dispatch queue.")
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
            session.virtualGamepad?.reset()
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
        guard sessions.count < 4 else {
            log("⚠️", "Ignoring an additional Wii Remote because four are already active.")
            return
        }

        let name = stringProperty(device, key: kIOHIDProductKey) ?? "Nintendo Wii Remote"
        if name.localizedCaseInsensitiveContains("RVL-WBC") {
            log("⚠️", "A Wii Balance Board was detected, but balance data is not implemented yet.")
            return
        }

        let productID = intProperty(device, key: kIOHIDProductIDKey) ?? 0
        let playerIndex = firstAvailablePlayerIndex()
        let session = Session(
            id: id,
            device: device,
            playerIndex: playerIndex,
            name: name,
            address: stringProperty(device, key: kIOHIDSerialNumberKey),
            productID: productID
        )
        sessions[id] = session

        configureVirtualGamepad(for: session)
        sendLEDState(for: session)
        setReportMode(for: session)

        // Dolphin similarly allows the new report mode to settle before asking
        // for status; this avoids racing two output transactions at connect.
        queue.asyncAfter(deadline: .now() + .milliseconds(200)) { [weak self, weak session] in
            guard let self, let session, self.sessions[session.id] != nil else { return }
            self.sendStatusRequest(for: session)
        }

        log("✅", "Connected \(name) as P\(playerIndex).")
        publishConnectionChanges()
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        let id = deviceIdentifier(device)
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.virtualGamepad?.reset()

        // The manager owns report delivery. Its callbacks are serialized on
        // this queue, so no session-owned callback buffer needs a drain period.

        log("🔌", "P\(session.playerIndex) disconnected.")
        publishConnectionChanges()
    }

    private func removeSession(id: UInt64, reason: String?) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        session.virtualGamepad?.reset()
        log("🔌", reason ?? "P\(session.playerIndex) disconnected.")
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
            log("⚠️", "HID input callback returned \(hex(result)).")
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
            session.acceleration = input.acceleration
            session.lastReportID = input.reportID
            updateVirtualOutput(for: session)
            markSnapshotsDirty()

        case .status(let status):
            let extensionStateChanged = session.hasReceivedStatus &&
                session.extensionConnected != status.extensionConnected
            session.hasReceivedStatus = true
            session.buttons = status.buttons
            session.batteryPercent = status.batteryPercent
            session.extensionConnected = status.extensionConnected
            session.lastReportID = 0x20
            sendLEDState(for: session)

            // A spontaneous extension connect/disconnect status disables data
            // reporting on the Wii Remote. Restore the selected report mode.
            if extensionStateChanged {
                setReportMode(for: session)
                log("ℹ️", "P\(session.playerIndex) extension state changed; report mode restored.")
            }
            markSnapshotsDirty()

        case .acknowledgment(let acknowledgedReport, let error):
            if error != 0 {
                log(
                    "⚠️",
                    String(format: "P%d rejected output report 0x%02X with error 0x%02X.",
                           session.playerIndex, acknowledgedReport, error)
                )
            }

        case .readData, .ignored:
            break
        }
    }

    private func updateVirtualOutput(for session: Session) {
        let motionStick: (x: Int8, y: Int8)?
        if settings.motionRightStickEnabled, let acceleration = session.acceleration {
            motionStick = session.motionFilter.stick(
                for: acceleration,
                profile: settings.profile
            )
        } else {
            motionStick = nil
        }

        let state = GamepadMapper.map(
            buttons: session.buttons,
            profile: settings.profile,
            motionRightStick: motionStick
        )
        session.gamepadState = state

        guard settings.virtualGamepadEnabled, let gamepad = session.virtualGamepad else { return }
        gamepad.update(state)
    }

    private func configureVirtualGamepad(for session: Session) {
        if settings.virtualGamepadEnabled {
            guard session.virtualGamepad == nil else { return }
            do {
                let gamepad = try VirtualGamepad(
                    playerIndex: session.playerIndex,
                    identity: settings.virtualGamepadIdentity,
                    backendPreference: settings.virtualGamepadBackendPreference
                )
                session.virtualGamepad = gamepad
                session.virtualGamepadError = nil
                log(
                    "🎮",
                    "P\(session.playerIndex) virtual output: \(gamepad.identity.shortTitle) via \(gamepad.backendKind.rawValue)."
                )
            } catch {
                session.virtualGamepadError = error.localizedDescription
                log("❌", "Virtual output failed for P\(session.playerIndex): \(error.localizedDescription)")
            }
        } else {
            session.virtualGamepad?.reset()
            session.virtualGamepad = nil
            session.virtualGamepadError = nil
        }
    }

    // MARK: - Output reports

    private func setReportMode(for session: Session) {
        let mode: UInt8 = settings.motionRightStickEnabled ? 0x31 : 0x30
        sendOutputReport(
            to: session,
            reportID: 0x12,
            payload: [session.rumbleEnabled ? 0x05 : 0x04, mode]
        )
    }

    private func sendStatusRequest(for session: Session) {
        sendOutputReport(
            to: session,
            reportID: 0x15,
            payload: [session.rumbleEnabled ? 0x01 : 0x00]
        )
    }

    private func sendLEDState(for session: Session) {
        let ledMask = UInt8(0x10 << (session.playerIndex - 1))
        let value = ledMask | (session.rumbleEnabled ? 0x01 : 0x00)
        sendOutputReport(to: session, reportID: 0x11, payload: [value])
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
                "⚠️",
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
                    gamepadState: session.gamepadState,
                    acceleration: session.acceleration,
                    extensionAcceleration: nil,
                    motionPlusGyroscope: nil,
                    reportsPerSecond: session.reportsPerSecond,
                    reportID: session.lastReportID,
                    extensionConnected: session.extensionConnected,
                    extensionName: nil,
                    extensionDetail: nil,
                    extensionIdentifier: nil,
                    extensionIdentifierHex: nil,
                    extensionInputSignature: nil,
                    irPointCount: 0,
                    irPoints: [],
                    balanceWeightKilograms: nil,
                    virtualGamepadActive: session.virtualGamepad != nil,
                    virtualGamepadIdentity: session.virtualGamepad?.identity.shortTitle,
                    virtualGamepadBackend: session.virtualGamepad?.backendKind.rawValue,
                    virtualGamepadError: session.virtualGamepadError
                )
            }

        DispatchQueue.main.async { [weak self] in
            self?.onSnapshotsChanged?(snapshots)
        }
    }

    // MARK: - Helpers

    private func log(_ icon: String, _ message: String) {
        logHandler?(icon, message)
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

private final class Session {
    let id: UInt64
    let device: IOHIDDevice
    let playerIndex: Int
    let name: String
    let address: String?
    let productID: Int
    let remoteKind: WiimoteRemoteKind
    let motionPlusCapability: WiimoteMotionPlusCapability
    let motionFilter = MotionStickFilter()

    var virtualGamepad: VirtualGamepad?
    var virtualGamepadError: String?
    var batteryPercent: Int?
    var buttons: WiimoteButtons = []
    var gamepadState = VirtualGamepadState.neutral
    var acceleration: WiimoteAcceleration?
    var reportsPerSecond = 0
    var reportCounter = 0
    var lastReportID: UInt8?
    var hasReceivedStatus = false
    var extensionConnected = false
    var rumbleEnabled = false

    init(
        id: UInt64,
        device: IOHIDDevice,
        playerIndex: Int,
        name: String,
        address: String?,
        productID: Int
    ) {
        self.id = id
        self.device = device
        self.playerIndex = playerIndex
        self.name = name
        self.address = address
        self.productID = productID
        self.remoteKind = WiimoteRemoteKind(name: name, productID: productID)
        self.motionPlusCapability = WiimoteMotionPlusCapability(remoteKind: remoteKind)
    }
}

private final class MotionStickFilter {
    private var baselineX: Double?
    private var baselineY: Double?
    private var filteredX: Double?
    private var filteredY: Double?

    func resetCalibration() {
        baselineX = nil
        baselineY = nil
        filteredX = nil
        filteredY = nil
    }

    func calibrate(using acceleration: WiimoteAcceleration?) {
        guard let acceleration else {
            resetCalibration()
            return
        }
        baselineX = acceleration.xG
        baselineY = acceleration.yG
        filteredX = acceleration.xG
        filteredY = acceleration.yG
    }

    func stick(
        for acceleration: WiimoteAcceleration,
        profile: ControllerProfile
    ) -> (x: Int8, y: Int8) {
        if baselineX == nil || baselineY == nil {
            calibrate(using: acceleration)
        }

        let alpha = 0.18
        filteredX = lowPass(previous: filteredX, next: acceleration.xG, alpha: alpha)
        filteredY = lowPass(previous: filteredY, next: acceleration.yG, alpha: alpha)

        let xDelta = (filteredX ?? acceleration.xG) - (baselineX ?? acceleration.xG)
        let yDelta = (filteredY ?? acceleration.yG) - (baselineY ?? acceleration.yG)

        let oriented: (Double, Double)
        switch profile {
        case .upright:
            oriented = (xDelta, yDelta)
        case .sideways:
            oriented = (yDelta, -xDelta)
        }

        return (
            axisValue(oriented.0),
            axisValue(oriented.1)
        )
    }

    private func lowPass(previous: Double?, next: Double, alpha: Double) -> Double {
        guard let previous else { return next }
        return previous + alpha * (next - previous)
    }

    private func axisValue(_ value: Double) -> Int8 {
        let deadZone = 0.08
        guard abs(value) > deadZone else { return 0 }
        let adjusted = value - (value.sign == .minus ? -deadZone : deadZone)
        let scaled = Int((adjusted * 150.0).rounded())
        return Int8(clamping: min(max(scaled, -127), 127))
    }
}
